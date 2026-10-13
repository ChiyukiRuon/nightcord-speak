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

每设备隔离身份、设置、会话、事件与语音。同设备标签页共用一个 Core，
命令结果和音频会发送到这个设备的所有标签页；不同设备不能控制对方的会话。
浏览器发送 `shutdown` 会被拒绝，网关退出由进程管理。

Web 的设备边界是浏览器个人资料、页面 Origin 与网关 URL。localStorage 保存
随机公开编号与随机恢复密钥，不保存 TS 私钥，不使用硬件指纹。
换浏览器、清除网站数据、无痕窗口或换站点/网关地址都会创建新设备身份。
浏览器存储不可用时退化为当前页面的内存，无法保证跨刷新恢复。

存储布局为 `<data-dir>/devices/<公开编号>/`，其中保存 `access.key`、身份、
`settings.json`；旧版的 `bookmarks.json` 保留供迁移。新版 Flutter Web 的服务器书签
保存在页面 Origin 的 localStorage（`nightcord.bookmarks.v1`），不按网关地址分开。
首次连接每个网关会将旧设备书签合并到浏览器，保留本地同地址条目，并记录迁移完成，
避免删除后再次导入。迁移不会删除服务器旧文件。恢复凭据形式为两个 32 位小写十六进制段，
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

网页版保存／编辑书签使用 `bookmark_prepare`：payload 包含随机前缀的 `request_id`
及 `bookmark`（`NewBookmark`）。网关复用 Rust 地址解析，返回相同请求编号、归一化
书签及被替换地址；成功与失败均携带编号，只由发起标签页处理，不写设备书签文件。
原有书签读写命令保留兼容旧客户端；新版只在迁移时读取旧列表。

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
| `--profile <NAME>` | `web` | 连接请求未指定档名时的默认身份档名；网页在设置里自选，网关不再强制 |
| `--data-dir <DIR>` | 应用数据目录 | 设备数据保存在其 devices 子目录 |
| `--web-root <DIR>` | 内嵌诊断页 | 只覆盖诊断页，不提供 Flutter 静态托管 |

网关只提供 `/ws`、`/`、`/index.html` 与 `/pcm-worklet.js`。
诊断页位于 `crates/ts-gateway/web/`；产品 UI 位于 `apps/client/`。
Cloudflare Pages 上传 Flutter 的 `apps/client/build/web/`，两者不是同一份页面。

产品使用、Pages 配置与临时 HTTPS 见 [Web 客户端使用与部署](web-client.md)。

## Docker Compose 部署

部署文件为仓库根目录的 `docker-compose.yaml`，`docker compose` 会自动读取。

镜像运行 Rust 网关，提供 `/ws` 与内嵌诊断页；Flutter 产品网页继续独立构建和托管。
镜像支持 Linux `amd64`、`arm64`。Docker 容器不需要访问宿主机声卡，浏览器负责
采集和播放音频；无需挂载 `/dev/snd` 或开启特权模式。

### 从源码构建

先确认已递归初始化 `vendor/tsclientlib` 及其 declarations 子模块，再在仓库根目录执行：

```bash
git submodule update --init --recursive vendor/tsclientlib
cp .env.example .env
docker compose up -d --build --pull never
docker compose ps
```

第一次编译会下载 Rust 基础镜像和依赖；编译器版本与 `rust-toolchain.toml` 当前的
`1.98.0` 一致。镜像不需要 Flutter SDK 或 UI 字体。Dockerfile 的 `RUST_VERSION`
默认值随工具链升级一起更新；CI 自动从工具链文件读取版本并传入构建。

启动后，诊断页为 `http://localhost:8787/`，WebSocket 为 `ws://localhost:8787/ws`。
`docker compose ps` 显示 `healthy` 代表网关 HTTP 入口可用，不表示已连接 TS 服务器。

### 使用自动构建镜像

GitHub workflow 首次发布镜像后执行：

```bash
docker compose pull
docker compose up -d --no-build
```

默认镜像为 `ghcr.io/chiyukiruon/nightcord-speak-gateway:main`。GHCR 包首次发布后，
如果需要免登录拉取，在 GitHub 的包设置中将可见性设为 Public；私有包需先
`docker login ghcr.io`。本地源码构建不依赖 GHCR 包已发布。

| 标签 | 来源 |
| --- | --- |
| `main` | 主分支最新通过容器验证的版本 |
| `0.3.0` 等完整版本 | 对应的 `v0.3.0` Git 标签 |
| `0.3.1-beta.1` 等预览版本 | 对应的 alpha／beta／rc 标签，不更新 `latest` |
| `latest` | 最近一次发布的无 alpha／beta／rc 后缀版本 |
| `sha-<完整提交哈希>` | 对应源码提交，适合固定部署版本 |

生产部署可将 `.env` 的 `NIGHTCORD_GATEWAY_IMAGE` 改成完整版本标签或镜像 digest。
主分支推送仅在网关、Rust 依赖、容器配置或 workflow 变动时触发；版本标签与手动运行
也会构建。PR 只构建和验证，不登录 GHCR、不发布。手动运行仅在 `main` 或版本标签上
发布，其他分支用于构建验证。

两种架构在各自原生 runner 上编译并执行 Compose 冒烟验证；成功后上传架构 digest，
两端全部通过才生成带上述标签的多架构 manifest。使用仓库默认 `GITHUB_TOKEN`，
无需新增 PAT；工作流发布 job 需要 `packages: write`。已有桌面发布和普通 CI 的
触发规则保持不变。

### 环境配置

Compose 自动读取根目录 `.env`；该文件被 Git 和 Docker 构建上下文排除。不要把
实际 Token 写到 `.env.example` 或构建参数中。Token 只在容器运行时注入。

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `NIGHTCORD_GATEWAY_IMAGE` | 上述 `:main` 镜像 | 选择镜像版本 |
| `NIGHTCORD_GATEWAY_HOST` | `127.0.0.1` | 宿主机端口绑定地址；局域网访问可设为 `0.0.0.0` |
| `NIGHTCORD_GATEWAY_PORT` | `8787` | 宿主机端口；容器内固定使用 8787 |
| `NIGHTCORD_GATEWAY_ORIGINS` | 空 | 逗号分隔的网页 Origin，不加空格；空值沿用本机来源策略 |
| `NIGHTCORD_GATEWAY_TOKEN` | 空 | 非空时启用 Token 鉴权 |
| `NIGHTCORD_GATEWAY_PROFILE` | `web` | 未指定档名的连接使用的默认身份档名 |
| `NIGHTCORD_GATEWAY_LOG` | `info` | Rust 日志过滤条件 |
| `NIGHTCORD_GATEWAY_TZ` | `Asia/Hong_Kong` | 日志日期与轮转时区 |

例如，网页部署在 `https://speak.example.com` 时，将允许来源设为该 Origin；
多站点可设为 `https://speak.example.com,https://preview.example.com`。
网页构建环境的 `NIGHTCORD_GATEWAY_URL` 使用浏览器实际可访问的 WSS 地址，
不能使用 Compose 内的服务名 `gateway`；若启用了 Token，网页构建也需传入相同 Token。
配置了地址的网页在连接失败时只显示状态与重试按钮，不显示地址填写页。

HTTPS 页面需要 WSS。可在宿主机反向代理或隧道中终止 TLS，并将 WebSocket 流量
转发至 `127.0.0.1:8787/ws`；代理需要保留 `Origin` 并支持 WebSocket Upgrade。
反向代理若运行于其他容器，需连接同一个 Compose 网络并转发到 `gateway:8787`。
调整 `.env` 后重新执行 `docker compose up -d --no-build`，让 Compose 重建服务应用配置。

### 数据、更新与停止

具名卷 `gateway-data` 挂载在 `/data`，默认完整名称为
`nightcord-gateway_gateway-data`。设备数据位于 `/data/devices/`，日志位于
`/data/config/nightcord-speak/logs/`。该卷在容器重建后保留设备恢复密钥、TS 身份和设置。
更新和普通停止不会删除它：

```bash
docker compose pull
docker compose up -d --no-build
docker compose logs --tail 100 -f gateway
docker compose down
```

`docker compose down --volumes` 会删除身份和设置，只有确定不再需要数据时才使用。
备份前先停止服务，再备份具名卷；恢复到其他主机时保留文件所有者 UID/GID 10001。
推荐具名卷；改成宿主机目录挂载时，该目录也必须允许 10001:10001 写入。

容器以非 root 用户运行，根文件系统只读，临时文件写入 `/tmp`。
Docker 通过 SIGINT 请求网关关闭，最长等待 30 秒，复用既有设备 worker 的退出流程。
镜像也可直接运行 `docker run --rm <镜像> --version`；显式 CLI 参数会替换环境默认
启动参数，此时需自行提供 `--bind` 和 `--data-dir`。

### 容器验证

本地构建后可运行与 CI 相同的测试，无需真实 TS 服务器：

```bash
docker build -f apps/gateway/Dockerfile -t nightcord-gateway:local .
python scripts/gateway-docker-smoke.py --image nightcord-gateway:local
```

测试创建独立的随机 Compose 项目和卷，验证健康检查、非 root／只读根目录、网页来源
与 Token 鉴权、设备恢复凭据、设置落盘和正常停止后重启恢复，结束时删除该测试项目。
不会启动真实服务器连接，也不会修改正常部署的数据卷。

开发进度、实测结果与待办统一记录于 [AGENTS.md](../AGENTS.md)。
