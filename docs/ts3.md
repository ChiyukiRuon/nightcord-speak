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

子模块差异：上游指向 `ReSpeak/tsdeclarations`，fork 随后指向
`Moepchi/tsdeclarations@webspeak3`；2026-10-09 起本仓库的 fork 链再改指
`ChiyukiRuon/tsdeclarations@nightcord`（多一个 `client_myteamspeak_avatar` 字段）。

### 结论（2026-09-29）：已解决

采用**自建 fork**方案。完整说明、核实过的调用点，
以及需要在你 fork 里执行的步骤见 **[`docs/tsclientlib-fork.md`](tsclientlib-fork.md)**。

一句话版本：`ChiyukiRuon/tsclientlib` 的 **`nightcord`** 分支上（`webspeak3` 是它分叉
自的上游分支，保持不动），把 `is_allowed_target` 的默认反过来即可。这两处补丁
落在提交 `df38c87`（私有地址）与 `c5cc287`（重连策略），`vendor/tsclientlib`
现在 pin 的就是后者。

在此之前，`vendor/tsclientlib` 的工作区已应用该补丁，本仓库现在就能连局域网。

---

## 7. 已知局限

| 项 | 说明 |
| --- | --- |
| 频道排序 | `Channel.order` 存的是 TS3 的 `channel_order` 原始值。该字段语义是「排在哪个频道之后」的链表指针，不是可比较的序号，因此严格排序需要走链。目前 CLI 按该值排序，树结构（`parent_id`）是正确的。 |
| `ClientType` | book 不报告查询客户端类型，一律标为 `Voice`。目前无代码依赖它。 |
| 语音 | ✅ 已实现（M0.2 实测）。收发链路见 [`audio.md`](audio.md)——抖动、解码、混音由 `tsclientlib` 负责，`ts-audio` 只经 `AudioSink` 接播放。 |
| 服务器 uptime | 来自 server-variables 查询，Milestone 0.1 不发该查询，故为 `None`。 |

---

## 8. 必须 `channelsubscribeall`，否则「换频道」看起来像「下线」

**症状**：别人只是换了个频道，树里那个人就消失了；等你走进那个频道，他又出现了。

**原因**：TS3 的服务器**只推送你订阅了的频道的事件**。订阅的时机是「你进入某个频道」
（`ClientMoved` 规则里的 `SubscribeChannelFun`）。所以别人从你所在的频道搬到别处时，
服务器给你发的是 `notifyclientleftview`——语义是「这个人离开了*你的视野*」，而
`MessagesToBook.toml` 里那条规则是**无条件 `remove`**：

```toml
[[rule]]
from = "ClientLeftView"
to = "Client"
operation = "remove"
```

于是 book 把人删掉，我们的快照 diff 报 `ClientLeft`，前端画成「人没了」。而此后你再也
收不到他的任何消息，因为他所在的频道你没订阅——直到你走进去，服务器补发一整套
`notifycliententerview`。

**修法**：握手后、以及**每次权限快照变化后**，发一条 `channelsubscribeall`
（`Server::set_subscribed(true)`）。权限变化要重发，是因为之前看不见的频道不会主动推
给你。

这条是从 `D:\CodeProject\Reference\webspeak3` 学来的——它的 connector 里有这么一行：

```rust
// Subscribe to all channels so we actually receive the full channel/client list.
con.get_state()?.server.set_subscribed(true).send(&mut con)?;
```

它还在自己所在的 server group 变化后重发一次（TeaSpeak 只在权限变化时暴露新频道）。
我们的判据更粗一档：**整个权限快照变了就重发**，覆盖同一类情形而不用盯着 server group。

**为什么这是我们的 bug 而不是库的**：库提供的是「按消息更新 book」的原语，订阅与否是
调用方的选择。官方客户端订阅全部；我们一开始没订。

---

## 9. 在线人数：先问服务器，再把 query 连接减掉

服务器的 `virtualserver_clientsonline` **把 server-query 连接也算作 client**，所以直接显示
它会把 `serveradmin` 算进「N 在线」。而直接数我们自己的客户端列表又会**少算**——看不见的
频道里的人、被权限挡住的人，都是真人却不在列表里。

所以两个数一起用（这套做法照 `webspeak3/connector/src/main.rs` 的 `snapshot()`）：

```text
在线 = (服务器自报数 − query 数).max(我们看得见的非 query 数)
```

`max` 不是保险，是必需的：`notifyserverupdated` 只在被问到时才推，可选数据可能已经过时，
一个比屏幕上还小的数就是明显错的。

**但服务器不会主动给**：book 里那份 `OptionalServerData` 的文档写着「Get by
`notifyserverupdated` **after requested by `servergetvariables`**」。所以要发一条裸命令：

```rust
OutCommand::new(Direction::C2S, Flags::empty(), PacketType::Command, "servergetvariables")
```

库建模了这条消息但没有现成的发送方法。**每一条连接发一次**（从 `Connected` 出去的任何
状态迁移都会重置这个标志），权限变化后重发一次——和 `channelsubscribeall` 同一个时机。
顺带把 `uptime` 也修好了：它之前一直是 `None`，原因正是「M0.1 不发该查询」。

---

## 10. 管理动作：poke / kick / ban

三个都走同一条路：trait → actor 的私有命令 → 直接构造 `Out...Part` →
`send_with_result`。它们的「为什么」值得分开记：

- **poke** 的底层一直是齐的（trait、actor、事件、通知浮层都在），缺的只有
  session → wire → ffi → gateway 这段管道。也就是说「有人戳你」这个事件在补上管道
  之前到不了界面，尽管它一路都被正确翻译了。
- **kick** 用 `OutClientKickPart`，`reasonid` 就是「踢到哪」：`KickChannel` 踢出频道、
  `KickServer` 踢出服务器。同一个命令承载两者，所以菜单里的两个条目只差这一个字段
  ——`ts-wire` 有一条测试专门盯着它们不能序列化成一样的东西。
- **ban** 没有 book 辅助方法可用：`BookToMessages.toml` 里没有通向 `banclient` 的规则，
  所以 `OutBanClientPart` 是手工构造的。**永久封禁在线路上是「字段缺席」而不是 0**
  （`time: Option<SignedDuration>`），`ts-model` 的 `BanDuration` 因此把「永久」做成
  一个独立变体而不是一个很大的秒数。`time` 这个 crate 是 `ts-protocol-tsclient` 的
  直接依赖，只为构造这一个值——生成的类型用的是它，而它没有被 re-export。

**拒绝的形状**：权限不足时服务器回错误码，`command_error`（`actor.rs`）把它认出来
并转成 `ClientError::Permission(PermissionError::MissingPermission { permission })`，
所以前端拿到的是一句能行动的话，而不是「操作失败」。前端的菜单也会按
`Permissions::can_kick` / `can_ban` 灰掉条目，但**服务器始终是权威**——那份快照可能
已经过期，所以被灰掉的条目仍然解释了原因，而被允许却失败的操作会带着缺失的权限号回来。

---

## 11. 离开状态（away）

「离开」不是本地状态，它**发给服务器**：别人在成员列表里看到离开标记和一句消息。
线路上是一条 `clientupdate`，带 `client_away` 与 `client_away_message` 两个属性——
生成代码里 `OutClientUpdatePart::set_away(Option<&str>)` 早就存在，actor 设
`input_muted` 用的是同一个 builder。

前台说的是三态，协议说的是两态，**`ts-session` 是唯一折叠它的地方**：

| `Command::SetAway` | 协议 | 含义 |
| --- | --- | --- |
| `away: false` | `None` | 在线，清掉标记 |
| `away: true`，无消息 | `Some("")` | 离开，没什么要说的 |
| `away: true`，有消息 | `Some(m)` | 离开，并说一句 |

「离开但没话说」和「在线」是两回事，`ts-session` 有一条测试专门盯着它们不许塌成一个。

**两件不需要自己做的事**：

- **不需要乐观更新**。库在命令**发出**时就把状态写回自己的 book
  （`update_on_outgoing_command`），而 actor 是「任何 book 事件就重拍快照」
  （`actor.rs` 里那条注释），所以按钮的亮灭直接读 `ownClient.flags.away` 就是准的。
  这与静音按钮不同：那个的本地副本是为了别的目的，见 `providers.dart`。
- **模型里不需要第二个真相**。book 只有 `AwayMessage: Option<String>`，
  「是否离开」就是 `is_some()`；`ClientFlags.away` 由它派生，消息本身放在
  `Client.away_message` 里。空串在 `convert.rs` 就塌成 `None`——那是「离开了，
  没话说」，没有可显示的东西。

**离开会停掉本地的发送闸门**：库把 away 当成 mute——`can_send_audio()` 在
`away_message.is_some()` 时为 false（`vendor/tsclientlib/tsclientlib/src/lib.rs:1211`），
所以离开了就发不出语音。这与「人不在」的语义一致，是**有意保留**的。

代价是**必须自己把闸门关上**，否则就是第一次实现的样子：本地门限照常放行，帧被编出来、
被库拒绝，FFI 把它当成失败报给界面——「未连接」。一个关于连接的、错误的、且用户按了
按钮就会重复出现的错误。现在 `ts-audio` 的 `TransmitPolicy` 里 away 与闭麦并列，
`SetAway` 在两处宿主都顺手把闸门关上（FFI 与网关各一行）。

**跨重连要清掉这个标志**：away 是连接状态，服务器在新连接上不记得它，而引擎会活过
重连（麦克风不会重开）。所以两处宿主都在看到 `ConnectionStateChanged(Connected)` 时
把引擎的 away 清掉——**否则会静默地永远不发**，那比报错更糟。
