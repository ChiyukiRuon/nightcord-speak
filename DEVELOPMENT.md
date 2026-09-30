# 第三方 TeamSpeak 3/6 跨平台客户端

## 技术设计与开发实施文档

**项目代号：** `Nightcord Speak`
**项目类型：** 第三方 TeamSpeak 客户端
**目标协议：** TeamSpeak 3 / TeamSpeak 6
**核心语言：** Rust
**客户端框架：** Flutter
**目标平台：**

* Windows
* Linux
* macOS
* Android
* iOS

**后续平台：**

* Web
* 其他桌面平台

---

后端参考项目 webspeak3，可直接访问 D:\CodeProject\Reference\webspeak3 查看项目的仓库开源代码

# 1. 项目目标

本项目目标是实现一个独立的 TeamSpeak 第三方客户端。

核心目标：

1. 支持 TeamSpeak 3 Server
2. 支持 TeamSpeak 6 Server
3. 支持多个服务器同时连接
4. 支持文字聊天
5. 支持频道树
6. 支持用户状态
7. 支持频道切换
8. 支持权限相关信息读取
9. 支持语音发送
10. 支持语音接收
11. 支持 Opus
12. 支持持久化客户端身份
13. 支持自动重连
14. 支持跨平台音频设备
15. Rust 核心与 UI 解耦
16. 后续可以接入 Web 前端
17. TS3 与 TS6 协议实现互相隔离

后续支持 GreenTeaSpeak & TeaSpeak (参考 webspeak3)

---

# 2. 总体架构

最终架构：

```text
                         ┌──────────────────────┐
                         │      Flutter UI      │
                         │                      │
                         │ Windows/macOS/Linux  │
                         │ Android/iOS          │
                         └──────────┬───────────┘
                                    │
                              FFI / Bridge
                                    │
                         ┌──────────▼───────────┐
                         │    Rust Client Core  │
                         │                      │
                         │ Session Manager      │
                         │ State Manager        │
                         │ Event System         │
                         │ Audio Engine          │
                         │ Identity Manager     │
                         └──────────┬───────────┘
                                    │
                         ┌──────────▼───────────┐
                         │ Protocol Abstraction │
                         └──────────┬───────────┘
                                    │
                       ┌────────────┴────────────┐
                       │                         │
                ┌──────▼──────┐           ┌─────▼─────┐
                │ TS3 Backend │           │ TS6 Backend│
                └──────┬──────┘           └─────┬─────┘
                       │                         │
                       ▼                         ▼
                  TS3 Server                TS6 Server
```

核心原则：

> Flutter 不直接实现 TeamSpeak 协议。

> TeamSpeak 协议不直接操作 Flutter UI。

> Rust 是整个客户端的核心。

---

# 3. 为什么选择 Rust + Flutter

## 3.1 Rust

Rust 负责：

* TCP/UDP
* TeamSpeak 协议
* 加密
* 数据包解析
* 状态同步
* Opus
* 音频处理
* 身份
* 重连
* 多服务器连接
* 后台任务
* 网络线程

这样 TS3/TS6 协议代码不会受到 UI 框架影响。

---

# 4. Flutter

Flutter 负责：

* 窗口
* 页面
* 频道树
* 用户列表
* 聊天
* 设置
* 服务器列表
* 音频设备选择
* 麦克风按钮
* UI 动画
* 输入框
* 快捷键

Flutter 不应该知道：

```text
TS3 packet
TS6 packet
UDP packet
Opus packet
RSA
协议编码
```

Flutter 只知道：

```text
Server
Channel
Client
Message
VoiceState
ConnectionState
```

---

# 5. 项目目录

建议直接采用：

```text
Nightcord Speak/
│
├── Cargo.toml
├── rust-toolchain.toml
├── README.md
├── LICENSE
│
├── crates/
│   │
│   ├── ts-core/
│   │
│   ├── ts-protocol/
│   │
│   ├── ts-protocol-ts3/
│   │
│   ├── ts-protocol-ts6/
│   │
│   ├── ts-audio/
│   │
│   ├── ts-identity/
│   │
│   ├── ts-model/
│   │
│   ├── ts-session/
│   │
│   ├── ts-events/
│   │
│   └── ts-ffi/
│
├── apps/
│   │
│   └── client/
│       ├── lib/
│       ├── android/
│       ├── ios/
│       ├── linux/
│       ├── macos/
│       └── windows/
│
├── tests/
│
└── docs/
    ├── architecture.md
    ├── protocol.md
    ├── audio.md
    ├── ts3.md
    ├── ts6.md
    └── ffi.md
```

---

# 6. Rust Crate 设计

## 6.1 ts-model

定义所有 UI 能理解的数据。

例如：

```rust
pub struct Server {
    pub id: ServerId,
    pub name: String,
    pub address: String,
    pub protocol: ProtocolKind,
}

pub struct Channel {
    pub id: ChannelId,
    pub name: String,
    pub parent_id: Option<ChannelId>,
    pub order: i64,
}

pub struct Client {
    pub id: ClientId,
    pub name: String,
    pub channel_id: ChannelId,
    pub status: ClientStatus,
}
```

---

# 7. ProtocolKind

```rust
pub enum ProtocolKind {
    Ts3,
    Ts6,
}
```

以后可以继续增加：

```rust
pub enum ProtocolKind {
    Ts3,
    Ts6,
    TeaSpeak,
    GreenTeaSpeak,
}
```

但第一阶段不要扩展。

---

# 8. Client 状态

```rust
pub enum ClientStatus {
    Online,
    Away,
    Muted,
    Deafened,
    Recording,
}
```

实际实现时不要简单依赖一个 enum。

建议：

```rust
pub struct ClientFlags {
    pub away: bool,
    pub input_muted: bool,
    pub output_muted: bool,
    pub recording: bool,
    pub channel_commander: bool,
}
```

因为多个状态可以同时存在。

---

# 9. Protocol Trait

TS3 和 TS6 必须通过统一接口连接。

```rust
#[async_trait]
pub trait TsProtocol {
    async fn connect(
        &mut self,
        config: ConnectionConfig,
    ) -> Result<(), ProtocolError>;

    async fn disconnect(&mut self)
        -> Result<(), ProtocolError>;

    async fn send_text(
        &mut self,
        target: MessageTarget,
        text: &str,
    ) -> Result<(), ProtocolError>;

    async fn join_channel(
        &mut self,
        channel_id: ChannelId,
    ) -> Result<(), ProtocolError>;

    async fn send_voice(
        &mut self,
        packet: VoicePacket,
    ) -> Result<(), ProtocolError>;
}
```

---

# 10. 不要让 Trait 过度抽象

不要写成：

```rust
trait TeamSpeakEverything {
    fn do_everything();
}
```

应该根据功能拆分。

例如：

```rust
trait Connection
trait ChannelOperations
trait ClientOperations
trait Messaging
trait Voice
trait FileTransfer
trait Permissions
```

然后：

```rust
pub struct Ts3Client {
    connection: Ts3Connection,
    channel: Ts3ChannelApi,
    voice: Ts3Voice,
}
```

TS6：

```rust
pub struct Ts6Client {
    connection: Ts6Connection,
    channel: Ts6ChannelApi,
    voice: Ts6Voice,
}
```

这样 TS6 出现不同能力时不会污染 TS3。

---

# 11. TS3 Backend

TS3 第一阶段可以大量参考/复用 `ReSpeak/tsclientlib`。

该项目本身就是 Rust TeamSpeak client/bot library，并且已经把低层协议 `tsproto` 与高层 `tsclientlib` 分开；其 `tsdeclarations` 项目还提供机器可读的命令、权限、枚举、状态映射等定义。

建议：

```text
ts3/
├── connection.rs
├── protocol.rs
├── command.rs
├── event.rs
├── channel.rs
├── client.rs
├── chat.rs
├── voice.rs
└── identity.rs
```

---

# 12. TS3 协议层

TS3 的低层通信应该独立：

```text
TCP
 │
 ├── packet framing
 ├── encryption
 ├── command
 └── response
```

UDP：

```text
UDP
 │
 ├── voice
 ├── ping
 ├── packet acknowledgement
 └── voice encryption
```

不要让 UI 知道这些东西。

---

# 13. TS3 Command Layer

例如：

```rust
pub enum Ts3Command {
    ClientList,
    ChannelList,
    WhoAmI,
    ClientMove {
        client_id: ClientId,
        channel_id: ChannelId,
    },
    SendText {
        target: MessageTarget,
        message: String,
    },
}
```

底层再编码成 TS3 command。

---

# 14. TS6 Backend

TS6 单独成一个 crate——**这是隔离，不是从零实现协议**：

```text
ts-protocol-ts6/
├── connection.rs
├── packet.rs
├── command.rs
├── event.rs
├── state.rs
├── channel.rs
├── client.rs
├── chat.rs
├── voice.rs
└── stream.rs
```

> **修订（2026-09-29）：上面这张文件表不代表要把网络协议重写一遍。**
> TS6 Server 的基础连接（频道、用户、语音）仍然走 TeamSpeak 的既有兼容路径，
> 真正新增的只有 `stream` 系列命令；`tsclientlib` 的 `webspeak3` 分支已经提供
> 未知命令透传，而那六条命令在上游是**用 `OutCommand` 公开 API 手写**的。
> 所以本 crate 里多数文件会非常薄，重点只有 `stream.rs`。
> 落地顺序见 [`docs/ts6.md`](docs/ts6.md)。

TS6 当前仍然是 Beta，因此这里必须避免把 TS6 的具体行为泄漏到 `ts-core`。官方 TS6 Server 仓库目前仍明确标注 Beta，且说明部分功能仍在开发中。

截至本文编写时，官方最新 Server release 是：

```text
6.0.0-beta13.1
```

因此建议开发环境固定测试版本，而不是永远追踪 `latest`。

---

# 15. TS6 Capability

TS6 不应该假设与 TS3 完全一致。

设计：

```rust
pub struct Capabilities {
    pub text_chat: bool,
    pub private_chat: bool,
    pub voice: bool,
    pub whisper: bool,
    pub file_transfer: bool,
    pub screen_stream: bool,
    pub poke: bool,
}
```

UI：

```dart
if (capabilities.whisper) {
    showWhisperButton();
}
```

而不是：

```dart
if (serverType == TS6) {
    ...
}
```

---

# 16. Session Manager

客户端需要允许多个服务器同时连接。

例如：

```text
SessionManager

├── Session A
│   └── TS3 Server
│
├── Session B
│   └── TS6 Server
│
└── Session C
    └── TS6 Server
```

Rust：

```rust
pub struct SessionManager {
    sessions: HashMap<SessionId, Session>,
}
```

---

# 17. Session

```rust
pub struct Session {
    pub id: SessionId,
    pub protocol: ProtocolKind,
    pub state: ConnectionState,
    pub server: Server,
}
```

状态：

```rust
pub enum ConnectionState {
    Disconnected,
    Connecting,
    Connected,
    Reconnecting,
    Disconnecting,
    Failed,
}
```

---

# 18. Event System

Rust 不应该主动控制 Flutter 页面。

Rust 产生 Event：

```rust
pub enum ClientEvent {
    Connected(Server),
    Disconnected,
    ChannelCreated(Channel),
    ChannelRemoved(ChannelId),
    ClientJoined(Client),
    ClientLeft(ClientId),
    ClientMoved {
        client_id: ClientId,
        channel_id: ChannelId,
    },
    MessageReceived(Message),
    VoiceStateChanged(VoiceState),
    Error(ClientError),
}
```

Flutter 监听：

```text
Rust Event
     ↓
FFI
     ↓
Dart Stream
     ↓
Bloc/Riverpod
     ↓
Widget
```

---

# 19. 推荐 Flutter 状态管理

建议：

```text
Riverpod
```

结构：

```text
providers/
├── session_provider.dart
├── server_provider.dart
├── channel_provider.dart
├── client_provider.dart
├── chat_provider.dart
├── audio_provider.dart
└── settings_provider.dart
```

---

# 20. Flutter UI

推荐：

```text
lib/
├── main.dart
│
├── app/
│
├── core/
│
├── features/
│   ├── server_list/
│   ├── server_view/
│   ├── channel_tree/
│   ├── chat/
│   ├── voice/
│   ├── settings/
│   └── permissions/
│
├── models/
│
└── ffi/
```

---

# 21. 主界面

桌面端：

```text
┌──────────────────────────────────────────────┐
│ Server Tabs                                  │
├───────────────┬──────────────────────────────┤
│               │                              │
│ Channel Tree  │       Chat / Server View     │
│               │                              │
│ ▼ Lobby       │                              │
│   Alice       │                              │
│   Bob         │                              │
│               │                              │
│ ▼ Gaming      │                              │
│   Charlie     │                              │
│               │                              │
├───────────────┴──────────────────────────────┤
│ 🔇  🎙  🔊    Channel        User            │
└──────────────────────────────────────────────┘
```

---

# 22. Server Tab

每个服务器一个 Session：

```text
[TS3 Server] [TS6 Server] [TS6 Test]
```

切换 Tab 不断开其他服务器。

---

# 23. Channel Tree

数据结构：

```rust
pub struct Channel {
    pub id: ChannelId,
    pub parent_id: Option<ChannelId>,
    pub name: String,
    pub order: i64,
    pub clients: Vec<ClientId>,
}
```

Flutter 根据 `parent_id` 构造树。

不要直接让 Rust 返回 Widget 所需要的树结构。

---

# 24. Chat

统一：

```rust
pub enum MessageTarget {
    Server,
    Channel(ChannelId),
    Client(ClientId),
}
```

消息：

```rust
pub struct Message {
    pub id: MessageId,
    pub sender: Option<ClientId>,
    pub target: MessageTarget,
    pub content: String,
    pub timestamp: i64,
}
```

这样 UI 不关心 TS3/TS6。

---

# 25. Voice Engine

这是整个项目最重要的模块之一。

建议：

```text
Microphone
    ↓
Audio Capture
    ↓
Resample
    ↓
Voice Processing
    ↓
Opus Encoder
    ↓
TS Voice Packet
    ↓
UDP
```

接收：

```text
UDP
 ↓
TS Voice Packet
 ↓
Decrypt
 ↓
Opus Decoder
 ↓
Jitter Buffer
 ↓
Mixer
 ↓
Audio Output
```

---

# 26. Audio Engine

独立 crate：

```text
ts-audio/
├── capture.rs
├── playback.rs
├── device.rs
├── mixer.rs
├── resampler.rs
├── encoder.rs
├── decoder.rs
├── jitter.rs
└── vad.rs
```

---

# 27. Audio Backend

Rust 端建议抽象：

```rust
trait AudioBackend {
    fn input_devices(&self) -> Vec<AudioDevice>;
    fn output_devices(&self) -> Vec<AudioDevice>;

    fn start_input(&mut self);
    fn start_output(&mut self);
}
```

具体实现可以根据平台选择成熟音频库。

核心目标：

> Flutter 不直接处理实时 PCM。

---

# 28. Opus

语音编码：

```text
PCM
 ↓
Opus
 ↓
TS voice packet
```

接收：

```text
TS voice packet
 ↓
Opus
 ↓
PCM
```

Opus 编解码应该完全放在 Rust。

WebSpeak3 当前也是 Rust connector + Opus voice 的架构，可以作为实现和测试参考。

---

# 29. Voice Activation

提供：

```text
Push To Talk
Voice Activation
Continuous
Muted
```

Voice Activation：

```text
Microphone
 ↓
RMS / VAD
 ↓
Threshold
 ↓
Transmit
```

设置：

```text
Sensitivity
Attack
Release
```

---

# 30. PTT

Flutter 监听：

```text
Keyboard Down
     ↓
Rust.start_transmitting()
```

释放：

```text
Keyboard Up
     ↓
Rust.stop_transmitting()
```

不要由 Dart 自己编码语音。

---

# 31. Identity

第一阶段不做登录。

但是 TS 客户端本身仍需要持久化 TeamSpeak Client Identity。

设计：

```text
IdentityManager
```

```rust
pub struct Identity {
    pub unique_id: String,
    pub identity_blob: Vec<u8>,
}
```

保存：

```text
Application Data
└── identity/
    └── default.identity
```

不要每次启动重新生成。

否则服务器会认为用户是不同客户端。

---

# 32. Identity Storage

建议：

```text
Windows
%APPDATA%/Nightcord Speak/

Linux
~/.config/Nightcord Speak/

macOS
~/Library/Application Support/Nightcord Speak/

Android
Application Documents

iOS
Application Support
```

敏感数据以后使用系统 Keychain / Credential Manager。

---

# 33. Connection Flow

连接过程：

```text
用户输入 Server Address
        ↓
解析地址
        ↓
创建 Session
        ↓
检测 TS3 / TS6
        ↓
建立控制连接
        ↓
协议握手
        ↓
建立身份
        ↓
获取 Server 信息
        ↓
获取 Channel
        ↓
获取 Client
        ↓
建立 Voice
        ↓
Connected
```

---

# 34. Server Detection

不要单纯：

```text
port == xxxx
```

判断协议。

应该：

```text
connect
 ↓
protocol handshake
 ↓
detect server dialect
 ↓
instantiate backend
```

WebSpeak3 目前也是在 Rust connector 中处理 TS3/TS6 等服务器方言，并支持自动检测或强制指定 server type。

---

# 35. Reconnect

断线：

```text
Connected
    ↓
Network Error
    ↓
Reconnecting
    ↓
1s
    ↓
2s
    ↓
4s
    ↓
8s
    ↓
16s
```

最大：

```text
30s
```

成功：

```text
Connected
```

---

# 36. Reconnect 时不要重新生成 Identity

必须：

```text
Session
 ↓
Reconnect
 ↓
原 Identity
```

而不是：

```text
Reconnect
 ↓
New Identity
```

---

# 37. Error System

统一：

```rust
pub enum ClientError {
    Network(NetworkError),
    Protocol(ProtocolError),
    Authentication(AuthError),
    Voice(VoiceError),
    Audio(AudioError),
    Permission(PermissionError),
    Timeout,
    Unsupported,
}
```

Flutter 只接收统一 Error。

---

# 38. Permission

权限必须进入 Model：

```rust
pub struct Permissions {
    pub can_join_channel: bool,
    pub can_move_clients: bool,
    pub can_send_channel_message: bool,
    pub can_send_private_message: bool,
    pub can_kick: bool,
    pub can_ban: bool,
}
```

UI 根据权限决定是否显示按钮。

---

# 39. File Transfer

第一阶段可以延后。

第二阶段：

```text
ts-file-transfer/
├── upload.rs
├── download.rs
├── progress.rs
└── transfer.rs
```

UI：

```text
Upload
██████████░░░░ 72%
```

---

# 40. Server Bookmarks

本地保存：

```json
{
  "name": "My Server",
  "host": "example.com",
  "port": 9987,
  "nickname": "Player"
}
```

注意：

**Bookmark 不等于账号。**

---

# 41. Settings

建议：

```text
settings/
├── audio
├── appearance
├── behavior
├── notifications
├── connection
└── shortcuts
```

---

# 42. Shortcut

例如：

```text
Ctrl + Shift + M
    ↓
Mute

Ctrl + Shift + D
    ↓
Deafen

Ctrl + Shift + P
    ↓
PTT
```

快捷键系统应该独立。

---

# 43. Notification

事件：

```text
Someone joined
Someone left
Private message
Channel message
Poke
Connection lost
Connection restored
```

由 Rust Event 产生。

Flutter 决定怎么显示。

---

# 44. Logging

Rust 使用：

```text
tracing
```

例如：

```rust
tracing::info!(
    session = %session_id,
    "connected"
);
```

生产环境：

```text
ERROR
WARN
INFO
```

开发：

```text
DEBUG
TRACE
```

绝对不要默认打印：

* 密钥
* Identity 私密数据
* 原始语音
* 密码
* 敏感 Token

---

# 45. FFI

Flutter ↔ Rust 建议不要直接暴露大量 Rust struct。

推荐：

```text
Flutter
   │
   │ JSON / C ABI
   ▼
Rust FFI
   │
   ▼
Rust Core
```

例如：

```text
connect()
disconnect()
send_message()
join_channel()
set_microphone()
set_output_device()
start_voice()
stop_voice()
```

---

# 46. FFI API

概念 API：

```text
client_create()
client_destroy()

session_connect()
session_disconnect()

session_send_message()
session_join_channel()

audio_get_input_devices()
audio_get_output_devices()

audio_set_input_device()
audio_set_output_device()

voice_start()
voice_stop()
```

事件：

```text
event_poll()
```

或者使用 callback / stream。

---

# 47. 不要把整个 Rust 对象暴露给 Dart

错误：

```text
Dart → Rust Object Pointer → 随便调用
```

更推荐：

```text
Dart
 ↓
Handle
 ↓
Rust SessionManager
```

例如：

```text
session_id = 42
```

Rust 内部：

```rust
HashMap<SessionId, Session>
```

---

# 48. Web 支持

第二阶段再做。

架构：

```text
React
  │
WebSocket
  │
Rust Web Gateway
  │
Rust Client Core
  │
TS3 / TS6
```

不要把 TS3/TS6 协议重新用 TypeScript 实现一遍。

---

# 49. Web Gateway

可以借鉴 WebSpeak3 的架构。

WebSpeak3 当前：

```text
Browser
   │
WebSocket
   │
Gateway
   │
Rust Connector
   │
TS3/TS6
```

并且它已经提供 TS3/TS6 实际服务器连接、文字聊天、频道树和 Opus 语音等完整参考实现。

但我们的最终目标不是简单复制它，而是：

```text
                    Rust Core
                   /         \
              Flutter       Gateway
                 │              │
                 │           WebSocket
                 │              │
                 │            React
```

这样 Native 和 Web 共用协议核心。

---

# 50. Web 音频

Web：

```text
Browser Microphone
        ↓
Web Audio / WebRTC
        ↓
Gateway
        ↓
Rust Audio
        ↓
TS Voice
```

接收：

```text
TS Voice
   ↓
Rust
   ↓
Gateway
   ↓
Browser
```

不要把 TS 原始 UDP 协议暴露给浏览器。

---

# 51. Web Gateway 与 Native Core

目标：

```text
libtsclient.so
libtsclient.dll
libtsclient.dylib
```

Native：

```text
Flutter → Rust library
```

Web：

```text
React → WebSocket → Rust Gateway → Rust library
```

---

# 52. Web 与 Native 功能统一

最终：

```text
Feature                Native       Web

Connect                  ✓            ✓
Channel                  ✓            ✓
Chat                     ✓            ✓
Private Message          ✓            ✓
Voice                    ✓            ✓
Whisper                  ✓            ✓
File Transfer            ✓            ✓
Bookmarks                ✓            ✓
Settings                 ✓            ✓
```

但是 Web 受到浏览器能力限制。

---

# 53. 数据模型原则

不要：

```text
TS3Client
TS6Client
FlutterTS3Client
FlutterTS6Client
WebTS3Client
WebTS6Client
```

堆大量重复模型。

应该：

```text
Domain Model
      │
 ┌────┴────┐
 TS3      TS6
```

---

# 54. Domain Model

核心：

```text
Server
Channel
Client
Message
Permission
VoiceState
ConnectionState
Capabilities
```

协议实现：

```text
TS3 → Domain Model
TS6 → Domain Model
```

UI：

```text
Domain Model → Flutter
```

---

# 55. TS3 / TS6 差异处理

例如 TS6 支持某个功能：

```rust
Capabilities {
    screen_stream: true,
}
```

TS3：

```rust
Capabilities {
    screen_stream: false,
}
```

Flutter：

```text
if supported:
    显示按钮
else:
    不显示
```

不要：

```text
if ts6:
```

---

# 56. 测试架构

测试必须分四层。

## Unit Test

测试：

```text
packet parser
encoder
decoder
state
identity
audio
```

---

# 57. Protocol Test

测试：

```text
TS3 Server
     ↑
Test Client
```

以及：

```text
TS6 Server
     ↑
Test Client
```

---

# 58. Integration Test

测试：

```text
Connect
 ↓
Channel List
 ↓
Client List
 ↓
Join
 ↓
Chat
 ↓
Voice
 ↓
Disconnect
```

---

# 59. Voice Test

至少测试：

```text
Input Device
 ↓
Capture
 ↓
Opus Encode
 ↓
Network
 ↓
Opus Decode
 ↓
Output
```

测试：

* 延迟
* 丢包
* 重连
* 设备切换
* 采样率
* 音量
* 静音
* PTT

---

# 60. Server Matrix

测试环境：

```text
TS3
 ├── Linux
 ├── Windows
 └── Docker

TS6
 ├── Linux
 ├── Windows
 └── Docker
```

TS6 测试环境应固定具体 beta 版本。

目前可以把：

```text
6.0.0-beta13.1
```

作为当前开发基线，同时保留升级测试。官方仓库显示 beta13.1 于 2026-09-22 发布。

---

# 61. CI

GitHub Actions：

```text
push
 ↓
cargo fmt
 ↓
cargo clippy
 ↓
cargo test
 ↓
flutter analyze
 ↓
flutter test
 ↓
build
```

---

# 62. Build Matrix

```text
Windows
Linux
macOS
Android
iOS
```

Web：

```text
Flutter Web
```

如果最终采用 React Web：

```text
React
```

---

# 63. Release

版本：

```text
0.1.0
0.2.0
0.3.0
...
1.0.0
```

不要在协议仍不稳定时直接：

```text
1.0.0
```

---

# 64. 开发阶段

## Phase 0 — 项目初始化

目标：

```text
Rust
Flutter
FFI
```

完成：

* Workspace
* Flutter Project
* Rust Library
* FFI
* CI
* Logging

---

# 65. Phase 1 — TS3 基础连接

完成：

```text
TS3 TCP
TS3 command
TS3 response
Identity
Server info
Channel list
Client list
```

最终效果：

```text
输入服务器
      ↓
Connect
      ↓
看到频道树
      ↓
看到用户
```

这一阶段不做语音。

---

# 66. Phase 2 — TS3 Chat

完成：

```text
Channel Chat
Private Chat
Server Chat
Poke
```

---

# 67. Phase 3 — TS3 Voice

完成：

```text
Microphone
Opus
UDP
Playback
Mute
Deafen
PTT
Voice Activation
```

这是第一个真正可用的 Alpha。

---

# 68. Phase 4 — TS6

建立：

```text
ts-protocol-ts6
```

完成：

```text
connect
server state
channel
client
chat
permissions
voice
```

TS6 不应该直接修改 TS3 backend。

> **修订（2026-09-29）：** 本节已完成。上面七项全部对真实 TS6 服务器
> （`6.0.0-beta13.1`）实测通过：连接、服务器信息、频道树、用户列表、聊天、
> 语音收发（449↔449 帧、零丢包）。TS6 与 TS3 共用基础协议，因此用的是同一个
> `ts-core`，没有第二套会话逻辑。
>
> TS6 独有的六条 `stream` 命令（`setupstream` 等）属于**屏幕共享**，而 §74
> 已把「屏幕共享」列为 MVP 不做项——它们归 §72（Phase 8），不是本里程碑的欠账。
> 见 [`docs/ts6.md`](docs/ts6.md)。

---

# 69. Phase 5 — Multi Session

完成：

```text
Server A
Server B
Server C
```

可以同时连接。

---

# 70. Phase 6 — Native Polish

完成：

```text
Settings
Device selection
Notifications
Shortcuts
Reconnect
Bookmarks
Theme
Localization
```

---

# 71. Phase 7 — Web

建立：

```text
web-gateway
```

然后：

```text
React
 ↓
WebSocket
 ↓
Rust
```

---

# 72. Phase 8 — 扩展功能

此阶段才考虑：

```text
Profile
Avatar
Friends
Custom Status
Badges
Themes
Plugins
```

---

# 73. MVP

真正的 MVP 不需要一次完成所有功能。

建议 MVP：

```text
✓ TS3 Connect
✓ TS6 Connect
✓ Identity
✓ Server Info
✓ Channel Tree
✓ Client List
✓ Channel Join
✓ Text Chat
✓ Private Chat
✓ Voice
✓ Mute
✓ Deafen
✓ PTT
✓ Reconnect
✓ Multi Server
```

---

# 74. MVP 暂时不要做

```text
✗ 登录
✗ 云同步
✗ 头像
✗ 好友
✗ 社交系统
✗ 插件市场
✗ 屏幕共享
✗ 自定义 Profile Server
✗ Web
```

这些都应该放到后面。

---

# 75. 开发顺序非常重要

不要一开始就：

```text
Flutter UI
+
TS3
+
TS6
+
Voice
+
Web
+
Login
```

这样非常容易失控。

正确顺序：

```text
Rust
 ↓
TS3
 ↓
TS3 State
 ↓
TS3 Chat
 ↓
TS3 Voice
 ↓
Flutter
 ↓
TS6
 ↓
Multi Session
 ↓
Web
 ↓
Extensions
```

---

# 76. 第一阶段具体任务

第一周：

```text
[ ] 创建 Rust workspace
[ ] 创建 Flutter app
[ ] 创建 FFI
[ ] 建立 CI
[ ] 建立 tracing
[ ] 创建 ts-model
[ ] 创建 ts-events
[ ] 创建 ts-session
```

第二阶段：

```text
[ ] 引入/整理 tsclientlib
[ ] 建立 TS3 backend
[ ] Connect
[ ] Disconnect
[ ] Identity
[ ] Server info
```

第三阶段：

```text
[ ] Channel List
[ ] Client List
[ ] Join Channel
[ ] Leave Channel
[ ] Text Chat
```

第四阶段：

```text
[ ] Audio Capture
[ ] Opus
[ ] UDP
[ ] Playback
[ ] PTT
```

第五阶段：

```text
[ ] TS6 backend
[ ] TS6 connection
[ ] TS6 state
[ ] TS6 chat
[ ] TS6 voice
```

---

# 77. tsclientlib 的定位

`ReSpeak/tsclientlib` 可以作为 TS3 协议实现的基础，而不是整个项目架构。

它目前仍是 Rust TeamSpeak client library，并且仓库在 2026 年仍有更新；但其 README 也明确说明项目仍属于 work in progress。

所以：

```text
错误：

Flutter
 ↓
tsclientlib
 ↓
TS Server
```

更推荐：

```text
Flutter
 ↓
你的 FFI
 ↓
你的 ts-core
 ↓
你的 TS3 adapter
 ↓
tsclientlib / 你的协议代码
 ↓
TS3
```

这样以后替换协议实现不会影响 Flutter。

---

# 78. WebSpeak3 的定位

WebSpeak3 不应该成为最终架构的核心依赖。

它更适合作为：

```text
参考实现
```

尤其值得参考：

```text
TS3/TS6 connector
Gateway
WebSocket protocol
Voice
Opus
Multi-session
Browser limitation
```

它目前的实际架构就是：

```text
React
 ↓
WebSocket
 ↓
Node Gateway
 ↓
Rust Connector
 ↓
tsclientlib
 ↓
TS Server
```

并且可以关闭静态 Web 前端，只运行 Gateway，这对后续替换前端很有帮助。

---

# 79. 最终架构

最终希望达到：

```text
                         ┌─────────────────┐
                         │   Flutter App   │
                         └────────┬────────┘
                                  │
                                  │ FFI
                                  │
                    ┌─────────────▼─────────────┐
                    │       TS Client Core      │
                    │                           │
                    │ Session Manager            │
                    │ Domain State               │
                    │ Event System               │
                    │ Identity                   │
                    │ Audio                      │
                    └─────────────┬─────────────┘
                                  │
                    ┌─────────────▼─────────────┐
                    │    Protocol Abstraction    │
                    └─────────────┬─────────────┘
                                  │
                         ┌────────┴────────┐
                         │                 │
                    ┌────▼─────┐      ┌────▼─────┐
                    │   TS3    │      │   TS6    │
                    │ Backend  │      │ Backend  │
                    └────┬─────┘      └────┬─────┘
                         │                 │
                         ▼                 ▼
                     TS3 Server        TS6 Server
```

Web：

```text
                  React
                    │
                WebSocket
                    │
             Rust Web Gateway
                    │
                    ▼
             TS Client Core
              /           \
            TS3           TS6
```

---

# 80. 最重要的设计原则

### 原则 1

**UI 永远不要直接依赖 TS3/TS6 协议。**

---

### 原则 2

**TS3 和 TS6 必须是两个独立 Backend。**

> **修订（2026-09-29）：** 「独立」指的是**代码隔离**——TS6 的行为不许渗进
> `ts-core` 或 TS3 的路径，两者可以各自演进、各自被替换。
> 它**不**意味着从零重写一遍网络协议：TS6 的基础连接沿用同一套兼容底座，
> 独立的是 crate 边界，不是协议实现。

---

### 原则 3

**Rust Core 才是项目主体，Flutter 只是 UI。**

---

### 原则 4

**音频永远尽量留在 Rust。**

---

### 原则 5

**Domain Model 与 Protocol Model 分离。**

---

### 原则 6

**TS6 必须允许协议变化。**

当前 TS6 Server 仍处于 Beta，官方仓库明确说明仍存在开发中的功能，因此不要让 TS6 特有实现渗透到通用层。

---

### 原则 7

**先实现一个能连接、能聊天、能语音的 TS3/TS6 客户端，再做高级功能。**

---

# 81. 第一份真正需要写的代码

项目正式开始后，不应该先写 Flutter UI。

第一批代码应该是：

```text
crates/
├── ts-model/
├── ts-events/
├── ts-session/
├── ts-protocol/
└── ts-protocol-ts3/
```

然后实现：

```rust
let client = TsClient::new();

let session = client.connect(
    ConnectionConfig {
        host: "...",
        port: 9987,
        nickname: "...",
    }
).await?;
```

然后：

```text
Connected
    ↓
Server Info
    ↓
Channel List
    ↓
Client List
```

能够稳定完成这条链以后，再接 Flutter。

---

# 82. 项目第一里程碑

定义：

> **Milestone 0.1 — TS3 Headless Client**

要求：

```text
Rust CLI
    ↓
TS3 Server
```

能够：

```text
✓ Connect
✓ Identity
✓ Server Info
✓ Channel List
✓ Client List
✓ Join Channel
✓ Send Message
✓ Receive Message
✓ Disconnect
```

没有 Flutter。

没有 UI。

没有音频。

---

# 83. 第二里程碑

> **Milestone 0.2 — TS3 Voice Client**

增加：

```text
✓ Microphone
✓ Opus Encode
✓ UDP Voice
✓ Opus Decode
✓ Playback
✓ Mute
✓ Deafen
✓ PTT
```

---

# 84. 第三里程碑

> **Milestone 0.3 — Flutter Client**

将：

```text
Rust CLI
```

替换为：

```text
Flutter UI
```

---

# 85. 第四里程碑

> **Milestone 0.4 — TS6**

增加：

```text
TS6 Backend
```

并通过同一个：

```text
ts-core
```

使用。

---

# 86. 第五里程碑

> **Milestone 0.5 — Multi Session**

实现：

```text
TS3 #1
TS3 #2
TS6 #1
TS6 #2
```

同时在线。

---

# 87. 第六里程碑

> **Milestone 0.6 — Production Client**

增加：

```text
Reconnect
Settings
Bookmarks
Notifications
Device management
Localization
Crash reporting
Logging
```

---

# 88. 最终 1.0

```text
Nightcord Speak 1.0

✓ Windows
✓ macOS
✓ Android
✓ iOS

✓ TS3
✓ TS6

✓ Text
✓ Voice
✓ Whisper
✓ Multi Server
✓ Identity
✓ Reconnect
✓ Permissions
✓ File Transfer
✓ Settings
```

然后再开始：

```text
2.0
↓
Web
↓
Profile
↓
Avatar
↓
Custom features
```

---

# 89. 参考项目

核心参考：

* ReSpeak `tsclientlib`：TS3 Rust client library。
* ReSpeak `tsdeclarations`：机器可读的 TS3 协议/命令/权限等定义。
* WebSpeak3：TS3/TS6 Web 客户端、Rust connector、Gateway、WebSocket、Opus 的综合参考实现。
* TeamSpeak 官方 TS6 Server：TS6 当前服务端行为与版本基线。

---

# 90. 结论

这个项目最终应该不是：

```text
Flutter TeamSpeak Client
```

而应该是：

```text
             Nightcord Speak Core
                   │
       ┌───────────┼───────────┐
       │           │           │
      TS3         TS6        Audio
       │           │           │
       └───────────┼───────────┘
                   │
          ┌────────┴────────┐
          │                 │
       Flutter          Web Gateway
          │                 │
       Native            React
```

**Rust Core 是真正的产品。**

Flutter、Web 都只是它的不同 UI。

这样以后无论你：

* 更换 Flutter
* 做 Web
* 做 Android
* 做 iOS
* 修改 TS3
* 修改 TS6
* 增加其他服务器协议
* 重写 UI

都不会把整个项目推倒重来。

**当前实际开发顺序就确定为：**

```text
① Rust Workspace
        ↓
② ts-model
        ↓
③ ts-events
        ↓
④ ts-session
        ↓
⑤ TS3 Backend
        ↓
⑥ TS3 Headless Client
        ↓
⑦ TS3 Voice
        ↓
⑧ Flutter FFI
        ↓
⑨ Flutter UI
        ↓
⑩ TS6 Backend
        ↓
⑪ Multi Session
        ↓
⑫ Web Gateway
        ↓
⑬ Web Client
        ↓
⑭ 扩展功能
```
