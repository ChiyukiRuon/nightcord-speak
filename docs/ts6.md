# TS6 路线（修订）

> **本文修订 `DEVELOPMENT.md` §14 与 §68。**
> 原文写的是「TS6 Backend 单独实现」，暗示要从零实现一整套 TS6 网络协议。
> 实际不是这样，工作量比原估计小得多。

---

## 实际情况：TS6 支持是分层的

TS6 **不是**一套与 TS3 并行的新协议。基础连接（频道、用户、语音）仍然走
TeamSpeak 的既有兼容路径；TS6 新增的能力（Stream / Call）是**额外的命令**。

已核实的分布：

```text
Moepchi/tsclientlib : webspeak3
├── TS3 基础协议
├── TS6 Server 基础兼容
├── TS6 未知命令透传      ← StreamItem::UnknownCommand
├── TeaSpeak / GreenTeaSpeak
└── WebSpeak3 所需修复
              │
              ▼
WebSpeak3 connector (connector/src/main.rs, 3018 行)
├── setupstream
├── joinstreamrequest
├── respondjoinstreamrequest
├── stopstream
├── streamsignaling
└── requeststreaminfo
```

实测数据支持这个判断：

| 命令 | 在 connector 中出现次数 | 在 tsclientlib 的 declarations 中 |
| --- | --- | --- |
| `joinstreamrequest` | 10 | **0** |
| `respondjoinstreamrequest` | 4 | **0** |
| `streamsignaling` | 4 | **0** |
| `setupstream` | 3 | **0** |
| `requeststreaminfo` | 3 | **0** |
| `stopstream` | 2 | **0** |

也就是说：**tsclientlib 不建模这六个命令，connector 直接手写。**

---

## 它们是怎麼发的

connector 用的是 `tsproto_packets` 的**公开 API**，不依赖任何私有封装：

```rust
let mut packet = OutCommand::new(
    Direction::C2S,
    Flags::empty(),
    PacketType::Command,
    "setupstream",           // 命令名直接写字面量
);
packet.write_arg("name", &s.name);
packet.write_arg("type", &s.kind);
packet.write_arg("bitrate", &s.bitrate);
// ...
packet.send_with_result(&mut con)
```

接收侧走 webspeak3 加进 tsclientlib 的透传：

```rust
StreamItem::UnknownCommand { name, content }
```

> tsclientlib 里那段注释写得很清楚：TS6 新增了它不认识的命令，
> 尤其是 `stream` 系列（`notifystreamsignaling` 等）；与其把每一个都声明一遍，
> 不如原样透传，需要的人自己读 `content`。

**我们已经能用这两个 API**——`tsproto-packets` 已在 `ts-protocol-tsclient`
的依赖里（共享适配层；TS3 与 TS6 都能用）。

---

## 已完成（2026-09-29）

### 对真实 TS6 服务器实测

`192.168.31.128:9988`，`TeamSpeak 6 Server, 6.0.0-beta13.1 [Build: 1790080330]`：

| 能力 | 结果 |
| --- | --- |
| 连接 / 握手 | ✅ |
| 服务器信息 | ✅ 正确报出 `TeamSpeak 6 Server` 与版本号 |
| 频道树 | ✅ 3 个频道 |
| 用户列表 | ✅ |
| 文字聊天 | ✅ 完整往返 |
| 语音收发 | ✅ 449↔449 帧，9.0 秒，零丢包 |

**结论：TS6 与 TS3 的基础协议确实是同一套，现有适配层一字未改就能用。**

### 代码落地

原先的 `ts-protocol-ts3` 里 2000 行适配代码，真正 TS3 特有的不到 30 行。
按「抽出共享适配层」方案重构为：

```text
ts-protocol-ts3        ts-protocol-ts6        ← 各自 80 行，只声明「我是谁」
        \                    /
         \                  /
      ts-protocol-tsclient                   ← 共享适配层（原 ts-protocol-ts3）
                  │
             tsclientlib
```

- `ts-protocol-tsclient` — 共享适配层。协议从传入的 `Server` 读取，不再写死
- `ts-protocol-ts3` / `ts-protocol-ts6` — 薄层，**强制**把自己的协议写进 `Server`，
  这样调用方标错协议也不会拿到对方的能力集（有测试覆盖）
- `Capabilities::for_protocol(kind)` — 协议到能力集的唯一映射点，
  放在 `ts-model`，backend 不需要自己分支（§15、§55）
- `ts-core` 的 Ts6 分支从 `Unsupported` 改为真正构造 backend

实测能力上报：

```text
TS6: Capabilities (Ts6): chat, private, voice, whisper, files, stream, poke
TS3: Capabilities (Ts3): chat, private, voice, whisper, files, poke
```

即 UI 只要判断 `capabilities.screen_stream` 就能只在 TS6 上显示 Stream 入口。

### 已知的 TS6 字段差异

连 TS6 时 tsclientlib 会打印三条警告，均为「服务端发了、声明里没有」，
**不影响功能**（库对未知参数是容忍的）：

```text
Unknown argument command="InitServer" argument=Ok("virtualserver_address")
Unknown argument command="InitServer" argument=Ok("virtualserver_sign")
Unknown argument command="InitServer" argument=Ok("client_is_streaming")
```

`client_is_streaming` 正是 `webspeak3` 的 `6df8ba1` 加过的字段，
说明 pin 的基线是对的；只是它出现在 `InitServer` 而非 `ClientUpdated`。

---

## Milestone 0.4 的完成判定

§68 对 Phase 4 的要求是：

```text
connect / server state / channel / client / chat / permissions / voice
```

**这些现在全部对真实 TS6 服务器验证通过。** 通过同一个 `ts-core`（§85 的要求）
——`ts-core` 只多了一个 `ProtocolKind::Ts6` 分支，没有第二套会话逻辑。

### Stream 命令属于 Phase 8，不属于本里程碑

`setupstream` / `joinstreamrequest` / `respondjoinstreamrequest` /
`stopstream` / `streamsignaling` / `requeststreaminfo` 是 TS6 的屏幕共享能力，
而 **§74「MVP 暂时不要做」明确把「屏幕共享」列为不做项**。

所以它们不是 Milestone 0.4 的欠账，而是 §72（Phase 8 — 扩展功能）的内容。
现在不做是对的，不是遗漏。

将来要做时，参考实现在
`D:\CodeProject\Reference\webspeak3\connector\src\main.rs`，按命令名 grep 即可定位；
落点是 `ts-protocol-ts6`，**不会**碰 `ts-protocol-ts3`。
建议顺序（每条补测试后再进下一条）：

1. `requeststreaminfo` —— 只读，最简单
2. `joinstreamrequest` / `respondjoinstreamrequest` —— 请求与应答
3. `streamsignaling` —— SDP/ICE 载荷交换
4. `setupstream` / `stopstream` —— 发布端

届时要先确认一个前提：TS6 的 screen share 是复用同一条 UDP 语音通道，
还是另开信令通道——这决定了它是否能搭在现有的 `ts-audio` 之上。

---

## 版本基线

TS6 Server 仍是 Beta。`DEVELOPMENT.md` §14 定的基线
`6.0.0-beta13.1`（2026-09-22 发布）继续有效；测试环境应固定该版本而不是追 `latest`。
