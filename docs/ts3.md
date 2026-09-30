# TS3 Backend 设计

`crates/ts-protocol-ts3` 是 TS3 backend 的声明与扩展点。**wire 层与 `tsclientlib`
的接触面全部在 `ts-protocol-tsclient`**（唯一允许依赖 `tsclientlib` 的 crate），
本文讲的 actor、快照 diff、权限映射都实现在那里，TS3 与 TS6 共用。

---

## 1. 为什么不把 `Connection` 放在锁后面

`tsclientlib` 有两条约束，决定了整个 backend 的形状：

> **连接是单所有者的。** `Connection` 需要 `&mut` 才能发送命令。
>
> **不 poll 事件流，连接就什么都不做。** 官方文档原话：
> *"The connection will not do anything unless the event stream is polled.
> Even sending packets will only happen while polling."*

也就是说：发送本身也依赖轮询。把 `Connection` 放进 `Mutex` 并不能解决问题——
一个持锁的发送者如果在 await 期间不 poll，命令就永远发不出去。

所以采用 **actor**：

```text
Ts3Client ──mpsc::Sender<Command>──▶ actor 任务
    ▲                                   │
    └────────── oneshot reply ──────────┘
                                        │
                                        └──▶ EventBus ──▶ front-end
```

连接被 move 进后台任务，其他部分只通过命令通道与它通信。

### select 循环的写法不是偶然

```rust
loop {
    let mut stream = connection.events();   // 可变借用 connection
    let outcome = tokio::select! {
        item    = stream.next()      => Outcome::Stream(item),
        command = commands.recv()    => Outcome::Command(command),
    };
    drop(stream);                            // 释放借用
    match outcome { /* 这里才能再可变使用 connection */ }
}
```

每次迭代**重建**事件流，拿到一个**拥有数据**的 `Outcome`，然后 `drop(stream)`
释放借用，之后才能在 `match` 里发送命令。

丢弃流是安全的：`EventStream::poll_next` 每次只取出一个 item 就返回，
不会有已取出但未交付的事件滞留在流内部。

---

## 2. 事件翻译：快照 + diff，而不是逐个属性

`tsclientlib` 把服务器状态维护在一本 "book" 里，变更以
`PropertyAdded/PropertyChanged/PropertyRemoved { id: PropertyId, .. }` 的形式推送，
而 `PropertyId` 有约 200 个变体（`ChannelName(..)`、`ClientNickname(..)`…）。

backend **不**逐变体翻译，而是：

```text
BookEvents 到达
      ↓
从 book 重建完整 ServerState（convert::snapshot）
      ↓
与上一份快照 diff（diff::between）
      ↓
得出 ClientEvent 列表
```

优点：实现小、不可能与 book 失步、新属性自动覆盖。
代价：每批更新走一次全量。

> 这是 Milestone 0.1 的刻意取舍。若 profiling 显示瓶颈，再把热点属性改为增量——
> 但那时应该有真实数据支撑，而不是先验猜测。

diff 的一个细节：客户端换频道报 `ClientMoved` 而**不是** `ClientUpdated`，
因为只有前者能让频道树知道要重新挂载节点。

---

## 3. 命令的成败在服务器应答时才算数

`send_with_result(con)` 只把包排进队列，真正的结果以
`StreamItem::MessageResult(handle, result)` 异步回来。因此：

- 命令携带一个 `oneshot::Sender`；
- 发送成功后把 `handle → reply` 存进 `pending` 表；
- 收到 `MessageResult` 时取出并回填。

这样 `send_text(..).await` 返回 `Ok` 就意味着服务器确实接受了。

actor 退出时 `pending.clear()`：sender 被丢弃会让所有等待中的
`oneshot::Receiver` 立刻收到错误，而不是永远挂起。

`CommandError` 里如果带 `missing_permission`，会映射成
`ClientError::Permission` 而不是 `Protocol`——UI 应该隐藏按钮，而不是报一个传输错误。

---

## 4. 权限来自 permission hints

`Permissions` 由 book 的 `ChannelPermissionHint` / `ClientPermissionHint` 位标志推导：

| 领域字段 | 来源 |
| --- | --- |
| `can_join_channel` | `ChannelPermissionHint::JOIN` |
| `can_send_channel_message` | `ChannelPermissionHint::SUBSCRIBE`（最接近的提示） |
| `can_send_private_message` | `ClientPermissionHint::PRIVATE_MESSAGE` |
| `can_move_clients` | `ClientPermissionHint::MOVE_CLIENT` |
| `can_kick` | `KICK_SERVER \| KICK_CHANNEL` |
| `can_ban` | `ClientPermissionHint::BAN` |

未连接时一律返回 `Permissions::none()`：宁可不显示按钮，也不要提供一个必然失败的操作。

---

## 5. 身份在升级后会被写回

`tsclientlib` 会自行提升身份的 hashcash 难度，并推送
`StreamItem::IdentityLevelIncreased`。此时 backend 会把新身份
**重新持久化**，否则下次启动会退回较弱的身份并重做计算。

这是 §36 的一个推论：身份一旦存在，就只能被更新，不能被替换。

---

## 6. 局域网地址（已解决）

> **状态（2026-09-29）：已解决。** 改动落在自建 fork 的 `nightcord` 分支
> （`df38c87`），本仓库的 submodule 已指向它。**不需要任何环境变量。**
> 完整说明见 [`docs/tsclientlib-fork.md`](tsclientlib-fork.md)。
> 下面保留问题本身的记录。

`tsclientlib` 上游带了一层 **SSRF 防护**：

```rust
// vendor/tsclientlib/tsclientlib/src/resolver.rs
pub fn is_allowed_target(ip: &IpAddr) -> bool {
    std::env::var("ALLOW_PRIVATE_TARGETS").is_ok_and(|v| v == "1") || is_public_addr(ip)
}
```

`connect()` 里对每个解析结果都做这个检查，所以**任何**局域网地址
（`192.168.*`、`10.*`、`172.16-31.*`、回环等）都会被拒绝：

```text
Failed to connect to server at "192.168.31.128:9987":
[ResolveAddress(BlockedTarget(192.168.31.128))]
```

这对 WebSpeak3 是正确的——浏览器提交的地址不能拿来探测服务器内网。
但**对原生客户端是错的**：连局域网服务器是完全正常的用法。

**解决办法**：把默认反过来——私有地址默认允许，`BLOCK_PRIVATE_TARGETS=1`
才恢复上游行为。该改动只存在于本项目的 `nightcord` 分支，`webspeak3`
保持原样，所以以后从上游拉更新仍是一次快进。

### 为什么不直接用上游 ReSpeak/tsclientlib

已实测对比（2026-09-29）：

```text
merge-base(fork webspeak3, upstream master) == upstream master 的 HEAD
```

也就是说 **fork 是上游的严格超集**：领先 14 个 commit，落后 0 个。上游并不陈旧，
fork 是叠在它之上的。这 14 个 commit 中与我们相关的：

| commit | 作用 |
| --- | --- |
| `Surface unknown commands instead of dropping them` | **TS6** 的 `stream` 系列命令透传（上游 `UnknownCommand` 出现 0 次） |
| `Bump declarations: add client_is_streaming` | **TS6** 字段 |
| `Fix SSRF via filetransfer address and OOB panic in license parsing` | 安全：恶意服务器可把 filetransfer 指向客户端内网 |
| `Block connections to private/internal addresses` | ← 就是本节的问题 |
| poke 处理、乱序队列上限、resolver 修复 | 健壮性 |

所以换成上游能直接消除局域网拦截，但会**同时失去 TS6 支持**
（`DEVELOPMENT.md` §85 的 Milestone 0.4）以及上述安全修复。

子模块差异：上游指向 `ReSpeak/tsdeclarations`，fork 指向 `Moepchi/tsdeclarations@webspeak3`。

### 结论（2026-09-29）：已解决

采用**自建 fork**方案。完整说明、核实过的调用点，
以及需要在你 fork 里执行的步骤见 **[`docs/tsclientlib-fork.md`](tsclientlib-fork.md)**。

一句话版本：`ChiyukiRuon/tsclientlib` 的 `webspeak3` 分支
（= 我们现在 pin 的 `2e77949`）上，把 `is_allowed_target` 的默认反过来即可。

在此之前，`vendor/tsclientlib` 的工作区已应用该补丁，本仓库现在就能连局域网。

---

## 7. 已知局限

| 项 | 说明 |
| --- | --- |
| 频道排序 | `Channel.order` 存的是 TS3 的 `channel_order` 原始值。该字段语义是「排在哪个频道之后」的链表指针，不是可比较的序号，因此严格排序需要走链。目前 CLI 按该值排序，树结构（`parent_id`）是正确的。 |
| `ClientType` | book 不报告查询客户端类型，一律标为 `Voice`。目前无代码依赖它。 |
| 语音 | ✅ 已实现（M0.2 实测）。收发链路见 [`audio.md`](audio.md)——抖动、解码、混音由 `tsclientlib` 负责，`ts-audio` 只经 `AudioSink` 接播放。 |
| 服务器 uptime | 来自 server-variables 查询，Milestone 0.1 不发该查询，故为 `None`。 |
