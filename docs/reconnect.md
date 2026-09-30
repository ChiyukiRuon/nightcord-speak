# 重连（Milestone 0.6）

## 要求

设计文档 §35：

```text
Connected → Network Error → Reconnecting → 1s → 2s → 4s → 8s → 16s →（上限 30s）→ Connected
```

§36 补一条硬要求：**重连必须复用原 Identity**，否则服务器把用户当成新客户端，权限全丢。
现状满足：`ConnectionConfig` 持有 identity，`ts-identity` 只在磁盘上没有时才生成。

---

## 摸出来的三个事实

**① tsclientlib 自己会重连，但延迟写死。**

```rust
// vendor/tsclientlib/tsclientlib/src/lib.rs:486-494（补丁前）
/// If `is_reconnect` is `true`, wait 10 seconds before sending the first packet.
async fn connect(options: ConnectOptions, is_reconnect: bool) -> ... {
    if is_reconnect { tokio::time::sleep(Duration::from_secs(10)).await; }
```

`ConnectOptions` 里没有对应字段，不改源码无从调整。

**② actor 有个状态机 bug。** `refresh` 把 `Connected` 转换关在
`if let Some(ready) = ready.take()` 里。`ready` 是首次 `connect()` 的一次性 oneshot，
之后恒为 `None`——所以库重连成功后状态**永远停在 `Reconnecting`**，而连接其实已经好了：
`server_info`、权限、diff 事件都在正常更新。前端于是把一台活着的服务器一直画成灰色，
还拒发消息。

修法是把两件事拆开：

```rust
// 每次握手成功都要转换，包括库重建连接的那一次
if context.connection_state() != ConnectionState::Connected { ... }

// ready 只表示「首次 connect() 可以返回了」，与状态无关
if let Some(ready) = ready.take() { let _ = ready.send(Ok(())); }
```

**③ 库只在 `TsProto::Timeout` 时重试。** 连接阶段若错误不是 timeout（ECONNREFUSED、
DNS 失败），直接 `Err` 返回 → actor 发 `Failed` 然后退出，**没有任何东西再重试**。
这正是「服务器还没起来」的场景。

---

## 职责边界：actor 独占重连策略

三种事实合起来说明：库的自带重连只覆盖一小段（已建立的连接抖了一下），而真正需要长时间
重试的场景（服务器没起来）它会直接放弃。**两套退避同时工作会互相抢控制权**：

```text
actor 1s → 库 10s → actor 2s → actor 4s → ...     ← 谁也不清楚下一次是什么时候
```

所以策略只有一个所有者：

```text
tsclientlib        协议、连接、编解码、TS3/TS6 基础行为
                   └─ 不再自己等待/重试（ReconnectMode::External）

Nightcord actor    ConnectionState、backoff、重试次数、session 生命周期、UI 事件
                   └─ 唯一的重连策略实现，Flutter / CLI / 以后的 Web Gateway 共用
```

---

## fork 补丁：把控制权交出来

仓库 `ChiyukiRuon/tsclientlib`，分支 `nightcord`，commit `c5cc287`。

新增 `ReconnectMode { Automatic, External }`（`Automatic` 是默认，**上游行为完全不变**），
`ConnectOptions` 加一个字段与 builder 方法。`External` 时库在两处改变行为：

| 位置 | `Automatic` | `External` |
| --- | --- | --- |
| 已建立连接超时（`lib.rs` 的 Connected 分支） | 构造 `connect(..., true)` 自己重连 | 报 `DisconnectedTemporarily`，然后**结束流** |
| 服务器重启（Serverstop 分支） | 同上 | 同上 |
| 连接阶段的 timeout 重试 | 重试 | 不重试（多一层模式判断，让不变式在源码里显式可见） |

结束流靠新增的 `finished: bool`——**在取完 `stream_items` 之后**检查，所以那条解释
「为什么连接没了」的事件一定先送达，流才静默。

**不改**的三处，都写了注释说明原因：

- 初始连接用 `Connecting(fut, false)`，本来就不重试——首连失败必须报给用户，
  密码错了不能悄悄重试。
- identity level 提升后的重连是**主动**升级身份，不是故障恢复。
- `ConnectOptions` 的默认值仍是 `Automatic`。

---

## actor 的重连循环

```text
run()
 ├─ serve()              跑一个连接，直到它结束
 │    └─ 返回 Ended::Done（用户断开 / 干净结束）
 │       或 Ended::Dropped(错误)
 ├─ rebuild()            按 §35 退避，等 → 重建 → 再 serve
 └─ 尾部                  发布 Disconnected，唤醒还在等的 ready
```

- **`ReconnectSchedule`**（`ReconnectSchedule::next`）是纯逻辑，与循环分开，
  所以 §35 的调度表能脱离服务器、socket 和时钟被单测。
  它用现成的 `ClientError::is_retryable()` 与 `ReconnectPolicy::delay_for_attempt`
  ——两者早就在 `ts-model` 里写好并测过，只是从未有人调用。
- **重建用的是同一份 `ConnectionConfig`**（`open()` 把它 clone 一份交给 actor，
  重建走同一个 `open_connection()`）。两条路径分开写的话，某天有人只改了其中一条，
  重连就会丢掉频道密码或 token，把用户送到别的地方去。
- **等待可以被命令打断**：`Command::Disconnect` 立刻结束，而不是让用户干等 30 秒。
  其它命令当场以 `not_connected()` 答复——连接不存在，答案已知，没必要让调用方等完退避。
- **`ready` 还在等时（首连没完成）不重连**。首连失败的错误属于那个正在 `await` 的调用方，
  `open()` 会直接把它返回；actor 再发一个事件就会让同一个失败在屏幕上出现两次
  （一次提示条，一次用户点「连接」的结果）。

### 事件的克制

| 场合 | 发什么 |
| --- | --- |
| 每次尝试 | `tracing::warn!`（进日志）+ `ClientEvent::ReconnectScheduled`（进 UI，带倒计时） |
| 放弃 | `ClientEvent::Error` + `Failed`，然后照旧 `Disconnected` |
| 重试期间 | **不发 `Disconnected`** |

最后一条是硬性的：`ClientEvent::Disconnected` 的文档是「No further events will follow」
且 `is_terminal()`，CLI 正是靠它退出循环——重试期间发它会让 CLI 直接收摊。

不发 `Error` 是因为它会变成一个 10 秒的 SnackBar 并写一行 `ERROR`：服务器断一小时就是
每三十秒一次的横幅和一大片重复日志。`ReconnectScheduled` 说的是界面需要知道的，
`warn!` 说的是事后读日志的人需要知道的。

---

## UI

| 状态 | 界面 |
| --- | --- |
| `reconnecting` | 顶部提示条：「连接已断开，N 秒后重试（第 N 次）」，每秒走秒，带「断开」按钮 |
| 提示条之下 | **频道树、用户列表、聊天记录全部保留** |
| 恢复后 | 服务器重放整棵树，`ServerView.apply` 幂等，所以是补齐而不是重复（已有测试锁住） |

保留画面是刻意的：会话并没有结束，核心正在把它接回来；清空用户正在看的东西会让一次抖动
看起来像一次崩溃。

两处配套修正：

- 输入框禁用时的提示语不再说「加入频道后才能发言」——重连中用户**就在**频道里，
  那句话把唯一没出问题的事情当成了原因。现在按连接状态说话。
- 「断开」按钮是**必须**的：重试可以永远进行（`max_attempts: None`），前提是用户能停下来。
  这是全应用第一次真正调用 `RustClient.disconnect`——在此之前它没有任何界面入口。

---

## 与 §35 的差异

§35 只给了退避表，没写**谁**拥有策略。本轮的决定是 **actor 独占**，
并为此改了自己的 fork——理由是上面那条：两套退避互相抢控制权比任何一套单独工作都糟。

策略值本身（1/2/4/8/16→30）与 §35 一致。让它可配置需要把 `ReconnectPolicy` 串进
`ConnectionConfig`，那是 §41 设置项的事，本轮没做。

---

## 验证状态

**已验证（自动化）**：`ReconnectSchedule` 的六个单测——§35 的调度表、
首次重试编号为 1、不可重试错误不消耗预算、网络错误照常重试、恢复后重新计数、
`max_attempts` 生效；Dart 侧七个——`reconnect_scheduled` 记录 attempt/delay、
断线期间频道树与消息不被清掉、`connected`/`disconnected` 清空倒计时、
后来的尝试覆盖先前的、没有调度时不编造倒计时、倒计时不为负。

**已验证（手工）**：`External` 模式下正常路径完全未变——真实服务器 `192.168.31.128:9987`
连接、服务器信息、能力集、干净断开全部与补丁前一致。

**未验证**：重连循环本身（`serve` → `rebuild` → `refresh`）**没有跑通过一次真实的掉线**。
原计划用本机 TCP 中继制造掉线，但在这台机器上做不到：`nightcord-cli.exe` 连不上任何
本机监听（3ms 内被 RST，同一时刻同一次调用里一个普通 Rust 探针却能连上），
而放在项目外的二进制又连不出去。这是环境的按进程网络策略，不是代码问题，但它意味着
**「库报掉线 → 退避重试 → 恢复」这条路径目前只有编译期和单元级的保证**。

要真正确认，需要在能控制服务器的环境里做一次：连上之后停掉 TS3 服务器（或拔网线），
看提示条出现、倒计时走秒、日志里出现 attempt 序列，再把服务器起回来确认自动恢复、
频道树与聊天记录都还在且没有重复项。
