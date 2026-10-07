# Web 网关（§71）

## 架构与设备边界

Flutter Native 通过 FFI、Flutter Web 通过 WebSocket 使用同一套 Rust Core。
网关负责握手、设备隔离、事件快照、扇出和语音桥，不包含 TS3/TS6 协议实现。
本文采用 `AGENTS.md` 的每设备独立身份约定，取代最初的单网关共享身份设计；
`DEVELOPMENT.md` 的原始设计保持不变，以 `AGENTS.md` 修订为准。

```text
设备 A 的标签页 ─ WebSocket ─ Core A ─ TS 服务器
设备 B 的标签页 ─ WebSocket ─ Core B ─ TS 服务器
                              ↑
                   同一个 nightcord-gateway 进程
```

每设备隔离身份、设置、书签、会话、事件与语音。同设备标签页共用一个 Core，
命令结果和音频会发送到这个设备的所有标签页；不同设备不能控制对方的会话。
浏览器发送 `shutdown` 会被拒绝，网关退出由进程管理。

Web 的设备边界是浏览器个人资料、页面 Origin 与网关 URL。localStorage 保存
随机公开编号与随机恢复密钥，不保存 TS 私钥，不使用硬件指纹。
换浏览器、清除网站数据、无痕窗口或换站点/网关地址都会创建新设备身份。
浏览器存储不可用时退化为当前页面的内存，无法保证跨刷新恢复。

存储布局为 `<data-dir>/devices/<公开编号>/`，其中保存 `access.key`、身份、
`settings.json` 与 `bookmarks.json`。恢复凭据形式为两个 32 位小写十六进制段，
以点分隔；公开编号不能代替密钥。恢复时校验服务端密钥，路径只使用公开编号。
Token 与设备凭据都不进入日志、Debug 或 URL；Unix 下新建 `access.key` 权限为 0600。
旧版共享身份文件保留，新设备建立新身份，服务器权限需按新身份分配。

最后一个标签页关闭后释放 PTT，保留 Core 30 秒供刷新恢复；每 5 秒清理，
因此约 30–35 秒后断开无人访问的 TS 会话。身份与设置继续落盘，聊天历史不重放。
最多同时保留 64 个设备 Core；清理旧 Core 完成后才允许重建同一设备。

## 分层

| crate | 职责 |
| --- | --- |
| `ts-wire` | 命令与事件 JSON 词汇，与 FFI 共用 |
| `ts-gateway` | WebSocket、设备 Core 注册表、快照、语音与诊断页 |
| `nightcord-gateway` | 参数、日志、退出信号与退出码 |

## WebSocket 协议

服务器首先发送 protocol 1 的 hello：

```json
{"kind":"hello","protocol":1,"auth":"none","device":"required"}
```

客户端须在 10 秒内发送第一帧。免 Token 网关使用：

```json
{"kind":"attach","device":"<公开编号>.<恢复密钥>"}
```

启用 Token 时，hello 的 `auth` 为 `required`，客户端使用：

```json
{"kind":"auth","token":"<网关 Token>","device":"<公开编号>.<恢复密钥>"}
```

device 可缺省，由服务器生成并在 welcome 返回；产品浏览器在连接前生成、保存凭据，
便于其他标签页复用。鉴权和设备校验成功后返回 `welcome`（含 device），再逐帧发送
设备会话快照。Worker 内原子订阅与取快照，避免刷新时丢失中间事件。
旧版免 Token 客户端若没有设备 attach，将无法连接新版网关；应同时更新前后端。

| 层 | 方向 | 格式 |
| --- | --- | --- |
| 控制 | 双向 | `kind` 信封：hello / auth / attach / welcome / error |
| 命令 | 浏览器 → 网关 | `{"command": "…", "payload": …}` |
| 事件与结果 | 网关 → 浏览器 | `ts-wire::FfiEvent`，与 FFI 同形 |
| 音频 | 双向 | 二进制，tag 1 为上行 PCM，tag 2 为下行 PCM |

设备内广播队列容量 1024；落后连接收到 `lagged` 标记，过期事件丢弃。

## 鉴权与部署边界

Token 默认关闭，设置非空 `NIGHTCORD_GATEWAY_TOKEN` 或 `--token` 才启用。
Token 控制进入网关，设备密钥控制状态归属与恢复，两者用途不同。
浏览器不能设置 WebSocket 请求头，因此 Token 放第一帧，不能放查询参数。

网关默认监听 `127.0.0.1:8787` 与 `[::1]:8787`，只允许本机来源的浏览器。
`--allow-origin` 可重复，非空时替换默认列表；当前实现按 scheme 与 host 比较，
端口不参与。无 Origin 的原生/测试客户端可以通过来源检查，但仍须符合 Token 策略。
消息上限 64 KiB，未完成握手的连接超时关闭。

网关不终结 TLS。HTTPS/WSS 由 Tunnel 或反向代理提供，后端可继续使用 loopback HTTP。
手机通过局域网 IP 的 HTTP 页面无法使用麦克风或本项目依赖的 AudioWorklet 播放。
页面启用 HTTPS 时网关地址也必须使用 WSS。

## 语音

浏览器 AudioWorklet 按 48 kHz 时钟采集，每 960 个单声道 f32 样本发送一次。
网关复用 `ts-audio` 的编码器、发送策略与电平计算，编码 Opus 后交给会话；
Rust 协议后端解码收到的语音，通过设备专属 WsAudioSink 返回立体声 PCM。
麦克风、扬声器选择在浏览器；网关不使用本机 cpal 设备。

同设备多个标签页的上行按 tick 混合、平均并按峰值限幅，不同设备不混音。
单人音量、静音与发送策略只作用于所属设备。PTT、静音、离开与关闭扬声器均控制闸门。
浏览器拒绝麦克风权限时可只收听，音频启用仍需用户手势。

PCM-over-WebSocket 是第一阶段传输方式，最终格式应换成浏览器侧编解码。

## 屏幕共享

TS6 的屏幕共享**不经过网关传输画面**。`Command::Screen` 与 `ClientEvent::Screen`
只是 `ts-wire` 里的又一对词汇，网关原样转发，和桌面侧走 FFI 的是同一套 core、
同一套协议实现（§2：网关不复制 Core）。信令从浏览器发出、经网关到 TS6 服务器；
**画面本身是浏览器与对端之间的一条独立 P2P WebRTC 连接**，网关和服务器都不在
这条路径上，也不会看到 SDP 之外的任何内容。

含义有两条：网关不需要为它增加带宽预算；以及**浏览器拿不到共享画面时，
网关侧查不到任何线索**——问题在 NAT 或浏览器的 `getDisplayMedia` 上。
完整设计见 [`screen-sharing.md`](screen-sharing.md)。

## 启动参数

```bash
cargo run -p nightcord-gateway
cargo run -p nightcord-gateway -- --allow-origin https://example.pages.dev
```

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `--bind <ADDR>` | 两个 loopback 地址，端口 8787 | 可重复 |
| `--token <TOKEN>` | 无 | 推荐通过 `NIGHTCORD_GATEWAY_TOKEN` 设置，避免命令行暴露 |
| `--allow-origin <ORIGIN>` | 本机页面 | 可重复，替换默认列表 |
| `--profile <NAME>` | `web` | 各设备独立存储内的身份档名 |
| `--data-dir <DIR>` | 应用数据目录 | 设备数据保存在其 devices 子目录 |
| `--web-root <DIR>` | 内嵌诊断页 | 只覆盖诊断页，不提供 Flutter 静态托管 |

网关只提供 `/ws`、`/`、`/index.html` 与 `/pcm-worklet.js`。
诊断页位于 `crates/ts-gateway/web/`；产品 UI 位于 `apps/client/`。
Cloudflare Pages 上传 Flutter 的 `apps/client/build/web/`，两者不是同一份页面。

产品使用、Pages 配置与临时 HTTPS 见 [Web 客户端使用与部署](web-client.md)。
开发进度、实测结果与待办统一记录于 [AGENTS.md](../AGENTS.md)。
