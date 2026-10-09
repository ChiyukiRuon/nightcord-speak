# 架构说明

本文档记录 `DEVELOPMENT.md` 之外的实现决策，以及实现过程中发现的约束。

---

## 1. Crate 依赖

分层（数字是依赖层级，**箭头只能向下**）：

| 层 | crate | 依赖 | 职责 |
| --- | --- | --- | --- |
| 0 | `ts-model` | **无** | 领域模型、地址解析、统一错误。整个项目的契约 |
| 1 | `ts-events` | model | 事件与 `EventBus` |
| 1 | `ts-identity` | model | 身份持久化（不碰密码学）；应用数据目录 |
| 1 | `ts-logging` | **无**（仅外部 tracing 三件套） | 进程级 subscriber：文件、轮转、filter |
| 1 | `ts-crash` | **无**（仅 `crash-handler` + `backtrace`） | 崩溃笔记、运行标记、报告打包。目录由调用方传入，与 `ts-logging` 同型 |
| 2 | `ts-settings` | model, identity | 用户偏好与已存服务器：结构、存储 |
| 2 | `ts-protocol` | model, identity | 能力拆分的 trait + `Backend` |
| 3 | `ts-session` | model, events, protocol | `Session` / `SessionManager` |
| 3 | `ts-audio` | model, protocol | 设备、采集、编码、播放、VAD |
| 4 | `ts-protocol-tsclient` | model, events, identity, protocol, **tsclientlib** | 唯一知道 `tsclientlib` 的地方 |
| 5 | `ts-protocol-ts3` / `ts-protocol-ts6` | model, events, identity, protocol, tsclient | 声明「我是谁」+ 各自扩展 |
| 6 | `ts-core` | model, events, identity, protocol, ts3, ts6, session | facade + 后端选择 |
| 7 | `ts-ffi` | core, session, audio, identity, logging, settings, crash, model, events, protocol | C ABI / JSON / 日志 / 设置 / 崩溃证据出口 |
| 7 | `apps/cli` | core, session, audio, identity, model, events, protocol | 无头客户端 |

`ts-audio` 与 `ts-session` 同层：都只依赖 model + protocol，**互不依赖**。
音频不是协议的一部分——两者之间唯一的接缝是 `ts_protocol::AudioSink`。

`ts-core` **不**依赖 `ts-audio`：把音频接到会话上是出口（`ts-ffi` / CLI）的事，
不是 facade 的事。

三条硬规则：

- `ts-model` 不依赖任何东西。它是整个项目的契约。
- `ts-protocol` 不出现 `ts3` / `ts6` 字样。
- 反向依赖（例如让 `ts-model` 认识 `TsClient`）一律禁止。

**`ts-protocol-ts3` / `ts-protocol-ts6` 为什么这么薄**：实测证实 TS6 与 TS3
共用同一套基础协议，两者真正不同的只有能力集与 TS6 的 `stream` 家族。所以
wire 处理放在 `ts-protocol-tsclient`，上面两个 crate 各自只声明「我是谁」，
并作为各自协议以后扩展（TS6 的 stream 命令）的落点。§14 要保护的「隔离」
是 crate 边界，不是行数——把适配层复制两份只会让它们漂移。

`ts-identity` 只依赖 `ts-model`；它把身份当作「生命周期与存储」问题，不碰密码学，
所以不依赖任何协议库。

**重连策略归 actor，不归 `tsclientlib`。** 库自带的内部重连延迟写死、且只在连接超时时
生效，外层要按 §35 的退避表接管就必须能关掉它（fork 的 `ReconnectMode::External`）。
两层各有一套退避会互相抢控制权——只有一层能告诉用户「还有几秒」。
细节见 [`docs/reconnect.md`](reconnect.md)。

**`ts-identity` 为什么连应用数据目录一起管**：`app_data_root()` 是全项目唯一知道
「本应用的每用户目录在哪」的地方（Windows 的 `%APPDATA%`、macOS 的
`Application Support`、Linux 的 XDG 各家不同）。身份是最先需要它的使用者，日志随后，
设置与书签以后。让它公开，是为了避免出现第二份平台路径逻辑——加 Android 时只改一处。

**`ts-logging` 为什么不依赖任何内部 crate**：日志目录是**参数**，由调用方（`ts-ffi`）
用 `app_data_root()` 算好传进来。这样它保持叶子身份，CLI（写 stderr）和 Flutter 客户端
（写文件）能共用同一份默认 filter 与「供应商库压到 warn」的判断，而不会各存一份慢慢漂移。
细节见 [`docs/logging.md`](logging.md)。

**`Bookmark` 为什么从 `ts-protocol` 搬到了 `ts-settings`**：它在那里躺了三个里程碑，
定义好、导出好、从没被构造过。搬家的原因不是口味——`ts-settings` 与 `ts-protocol`
**同在层 2**，而同层互不依赖是本文件上面那条规则，所以留在原处就没人能存它。
用户数据不是协议。

**`ts-settings` 为什么反过来依赖 `ts-identity`**：设置只有一个固定的文件位置，
`SettingsStore::platform_default()` 得回答「在哪」，而这正是 `app_data_root()` 唯一知道的事。
把目录当参数传（像 `ts-logging` 那样）在这里只会让每个调用方各自去拼路径。
细节见 [`docs/settings.md`](settings.md)。

---

## 2. 协议实现：为什么是 submodule 而不是 Cargo 依赖

这是实现期最重要的一个发现，已实测验证。

`tsclientlib` 的 crate **无法**通过 Cargo git 依赖引入：

- 它的 `utils/tsproto-structs` 在**编译期**用
  `include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/declarations/Versions.csv"))`
  读取声明文件。
- `declarations/` 是一个嵌套 submodule（现为自建 fork
  `ChiyukiRuon/tsdeclarations@nightcord`，理由见
  [`tsclientlib-fork.md`](tsclientlib-fork.md)）。
- **Cargo 不会为 git 依赖拉取 submodule**，因此构建必定失败于
  `couldn't read .../declarations/Versions.csv`。

而且没有绕过办法：`CARGO_MANIFEST_DIR` 指向 Cargo 自己的 checkout，
无法从外部重定向这个路径。

因此采用与参考项目 WebSpeak3 相同的方案：

```text
.gitmodules
└── vendor/tsclientlib  →  ChiyukiRuon/tsclientlib @ nightcord
    └── utils/tsproto-structs/declarations  →  ChiyukiRuon/tsdeclarations @ nightcord
```

版本由 submodule 记录的 commit 固定（可复现）。升级方式：

```bash
cd vendor/tsclientlib
git fetch && git checkout <rev>
cd ../.. && git add vendor/tsclientlib
```

Cargo 侧用 `path` 依赖，并在 workspace 里 `exclude = ["vendor"]`，
确保第三方 crate 不会变成我们的 workspace 成员。

> `crates.io` 上的 `tsclientlib` 停留在 2021 年的 `0.2.0`，远远落后于上游，不可用。

---

## 3. 能力拆分，而不是一个大 trait

`DEVELOPMENT.md` §10 要求不要把接口写成一个 `do_everything()`。实现方式：

`ts-protocol` 定义 6 个窄接口：

```rust
Connection           // 连接生命周期
ChannelOperations    // 频道
ClientOperations     // 对他人操作
Messaging            // 发消息
Voice                // 语音
PermissionsReport    // 权限读取
```

`ts-protocol::Backend` 把它们**组合**起来，每个能力各自一个 trait object：

```rust
pub struct Backend {
    kind: ProtocolKind,
    connection:  Box<dyn Connection>,
    channels:    Box<dyn ChannelOperations>,
    clients:     Box<dyn ClientOperations>,
    presence:    Box<dyn Presence>,
    messaging:   Box<dyn Messaging>,
    voice:       Box<dyn Voice>,
    permissions: Box<dyn PermissionsReport>,
}
```

调用方要发消息就取 `.messaging()`，**拿不到**移动客户端或发语音的能力。

尚未实现的能力用 `NoVoice` 这类显式占位实现，返回
`ClientError::Unsupported`，而不是静默吞掉调用。

`ts-protocol::testing`（`testing` feature）提供了一个内存版 backend，
既用于测试，也是这套组合方式的活文档。

---

## 4. 事件流

```text
backend ──publish──▶ EventBus ──┬──▶ apps/cli
                                ├──▶ ts-ffi 队列 ──▶ Dart Stream
                                └──▶ (Phase 7) Web Gateway
```

- `EventBus` 基于 `tokio::sync::broadcast`。
- 慢消费者**丢弃最旧事件**，绝不阻塞网络循环。
- 每个事件都带 `SessionId`（`SessionEvent`），多服务器场景下不会串台。
- 新订阅者不回放历史：状态应该从 `ServerState` 读，而不是靠重放事件重建。

---

## 5. 身份

`ts-identity::IdentityStore` 负责持久化，**不负责生成**——生成需要协议密码学，
由 backend 提供。

三个刻意的设计：

1. `Identity` **不实现 `Serialize`**，且 `Debug` 被打码。私钥不得进入日志或 FFI。
2. `load_or_create` 是重连唯一允许走的入口（§36）：磁盘上已有身份就绝不重新生成，
   否则服务器会认为这是全新客户端，用户权限丢失。
3. 文件损坏时返回 `Malformed` 而**不是**「当作不存在」。把读取失败当作缺失，
   会静默地换掉用户身份。

存储位置（§32）：

| 平台 | 路径 |
| --- | --- |
| Windows | `%APPDATA%\Nightcord Speak\identity\` |
| Linux | `$XDG_CONFIG_HOME/nightcord-speak/identity/` |
| macOS | `~/Library/Application Support/Nightcord Speak/identity/` |
| Android / iOS | **必须由宿主 App 传入**（沙箱路径只有 App 自己知道） |

身份文件写入使用「临时文件 + rename」，避免中断产生半截密钥；
Unix 下权限为 `0600`。

---

## 6. 与 `DEVELOPMENT.md` 的差异

实现时按工程判断做了少量偏离，记录如下。

| 位置 | 文档写法 | 实现 | 原因 |
| --- | --- | --- | --- |
| §8 | `ClientStatus` enum | 只有 `ClientFlags` | 文档自己也说状态可并存；保留 enum 会制造第二个真相来源 |
| §37 | `ClientError` 8 个变体 | 增加 `Identity` / `InvalidAddress` | 两者都是 UI 必须展示的真实错误，无合适归属 |
| §37 | `Unsupported` 无载荷 | `Unsupported(String)` | 无上下文时 UI 无法给出有用提示 |
| §23 | `Channel` 6 字段 | 增加 description / topic / has_password 等 | 频道树渲染需要；均为可选项 |
| §24 | `Message` 5 字段 | 增加 `sender_name` | 发送者可能已断线，届时无法反查昵称 |
| §18 | 事件列表 | 增加 `Poked` | Poke 无回复、无历史、展示方式不同，塞进 `Message` 会丢语义（§66 明确要求支持） |
| §16 | `SessionManager` | 增加 `reserve_id` / `insert` | backend 在构造时就要用 session id 给事件打标，因此 id 必须先于 backend 存在 |
| 命名 | 文档混用 NovaSpeak / Nightcord Speak | 统一 **Nightcord Speak** | 按确认结论 |

`Transport`/`ClientError` 等类型放在 `ts-model` 而不是 `ts-protocol`，
是为了让 `ts-protocol` 与 `ts-session` 共用同一套错误词汇，避免循环依赖。

---

## 7. 构建前置条件（2026-09-30 更新）

早期这里是「缺口」，现在都装上了：

| 项 | 状态 |
| --- | --- |
| Flutter SDK | ✅ 已装 3.47.5（Dart 3.13.4），`apps/client` 已在使用 |
| cmake | ✅ 已装。`audiopus_sys` 用它从源码编译 libopus |
| VS 2022 C++ 工具链 | ❌ **仍未装**（VS 2022 Community 缺 C++ 工作负载）。本机靠 VS 2019 BuildTools，所以构建要带 `CMAKE_GENERATOR` |

`tsclientlib` 的 `audio` feature **已打开**（workspace `Cargo.toml`）——
语音的包传输、分帧与加密都由它提供，关掉就收发不了语音。

具体命令与两个已由仓库配置绕过的坑（CMake 4 版本下限、MSVC 调试版 CRT）
见 `AGENTS.md` §3.2 / §3.3。
