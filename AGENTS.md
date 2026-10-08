# AGENTS.md — 开发工作文档

> **这个文件是开发工作的唯一入口。**
>
> - **所有与开发有关的更新都写在这里**：进度、决策、约定、踩过的坑、待办。
> - `README.md` 只写项目说明（这是什么、怎么用），不写开发过程。
> - `DEVELOPMENT.md` 是最初的设计文档，**保持原样**；它被本文或 `docs/` 修正的地方，
>   在对应小节里注明。

---

## 1. 项目目标

做一个**独立的第三方 TeamSpeak 客户端**，支持 TS3 与 TS6，跨 Windows / Linux /
macOS / Android / iOS。

一句话架构：

> **Rust Core 是真正的产品，Flutter 只是它的一个 UI。**

完整目标见 `DEVELOPMENT.md` §1。核心诉求：

| #  | 目标                                    |
|----|-----------------------------------------|
| 1  | 支持 TS3 Server                         |
| 2  | 支持 TS6 Server                         |
| 3  | 多服务器同时连接                        |
| 4  | 文字聊天 / 频道树 / 用户状态 / 频道切换 |
| 5  | 语音收发（Opus）                        |
| 6  | 权限信息读取                            |
| 7  | 持久化客户端身份                        |
| 8  | 自动重连                                |
| 9  | 跨平台音频设备                          |
| 10 | Rust core 与 UI 解耦，后续可接 Web 前端 |
| 11 | TS3 与 TS6 协议实现互相隔离             |

**非目标（§74，MVP 阶段不做）**：登录、云同步、头像、好友、社交系统、插件市场、
自定义 Profile Server。Web 原属 MVP 非目标，现已进入 Phase 7；**TS6 的屏幕共享
（Stream）已于 2026-10-07 实现**，见 [`docs/screen-sharing.md`](docs/screen-sharing.md)。

---

## 2. 架构与不可违反的规则

```text
                    ┌─────────────────┐        ┌──────────────┐
                    │   Flutter App   │        │  Web Gateway │
                    └────────┬────────┘        └──────┬───────┘
                             │ FFI                    │ WebSocket
                    ┌────────▼────────────────────────▼───────┐
                    │            TS Client Core               │
                    └────────────────────┬────────────────────┘
                                         │
              ┌──────────────────────────▼──────────────────────────┐
              │                  ts-protocol                        │
              │        （不出现 ts3 / ts6 字样）                     │
              └────────┬───────────────────────────────┬────────────┘
                  ┌────▼─────┐                   ┌────▼─────┐
                  │ TS3      │                   │ TS6      │
                  └────┬─────┘                   └────┬─────┘
                       │                              │
              ┌────────▼──────────────────────────────▼────────┐
              │           ts-protocol-tsclient                  │
              │      （TS3/TS6 共用的基础协议，实测同一套）        │
              └────────────────────┬───────────────────────────┘
                                   │
                              tsclientlib
```

### 依赖方向只能向下

`ts-model` 不依赖任何东西；反向依赖（让 `ts-model` 认识 `TsClient`）一律禁止。

### 五条硬规则

1. **UI 永远不直接依赖 TS3/TS6 协议。** Flutter 只知道
   `Server` / `Channel` / `Client` / `Message` / `VoiceState` / `ConnectionState`。
2. **TS3 与 TS6 是两个独立 Backend**——指 crate 隔离，**不是**把协议重写一遍。
   两者的基础协议实测是同一套，共享代码放 `ts-protocol-tsclient`，
   各自只保留「我是谁」和各自的扩展。
3. **Domain Model 与 Protocol Model 分离。** 协议形状的值不许越过 `ts-model`。
4. **音频尽量留在 Rust。** 实时 PCM 永远不跨 FFI；Flutter 只发控制命令。
5. **TS6 必须允许协议变化**（仍是 Beta），其特有实现不许渗进 `ts-core`。

### 分层职责

| crate                  | 职责                                  | 不许做                          |
|------------------------|---------------------------------------|---------------------------------|
| `ts-model`             | 领域模型、地址解析、统一错误          | 依赖任何东西                    |
| `ts-events`            | 事件与 `EventBus`                     | 知道协议                        |
| `ts-protocol`          | 能力拆分的 trait + `Backend`          | 出现 `ts3`/`ts6` 字样           |
| `ts-session`           | `Session` / `SessionManager`          | 知道具体协议                    |
| `ts-identity`          | 身份持久化、应用数据目录              | 碰密码学（由 backend 提供生成） |
| `ts-logging`           | 进程级 subscriber：文件、轮转、filter | 自己找目录（由调用方传入）      |
| `ts-crash`             | 崩溃笔记、运行标记、报告              | 依赖任何内部 crate              |
| `ts-settings`          | 用户偏好与已存服务器：结构、存储      | 决定谁读它（由 core 应用）      |
| `ts-audio`             | 设备、采集、编码、播放、VAD           | 依赖协议库                      |
| `ts-protocol-tsclient` | **唯一**允许知道 `tsclientlib` 的地方 | 出现具体协议判断                |
| `ts-protocol-ts3/ts6`  | 声明协议、承载各自扩展                | 复制适配层                      |
| `ts-core`              | facade + 后端选择                     | 泄漏协议概念                    |
| `ts-ffi`               | C ABI + JSON，句柄而非指针            | 阻塞 Dart UI 线程               |
| `ts-wire`              | 命令与事件的 JSON 词汇（前端唯一一份） | 承载任何行为/传输              |
| `ts-gateway`           | WebSocket 前端：每设备独立 core  | 复制 core（与桌面共用同一套）    |

### 前端架构：Flutter 六端一致（2026-09-30 定）

**取代 `DEVELOPMENT.md` §48/§79 的「React Web + Flutter Native」**——见该节修订注。

> **原则（用户拍板）**：Flutter 统一承担所有平台 UI。共享 Design System、业务组件、
> 状态管理、Models 与交互逻辑；Desktop/Mobile 仅通过 Adaptive Shell 做布局差异。
> 平台相关能力通过 Capability/Backend 接口隔离。Native 使用 FFI，Web 使用 WebSocket
> Gateway。Rust Core、TS3/TS6 Protocol 与 Session 层**完全不因 UI 平台而复制**。
> Web 语音的 PCM-over-WebSocket 仅作为第一阶段可验证实现，**不作为最终传输格式**。

不是「100% 全等」，是**最大化复用**：共享组件与行为模型；允许按形态调整布局，不追求逐
widget 全等。

**两个产品族**——按 viewport / 输入能力判定 `LayoutClass`，**不按 OS 判断**（iPad 横屏、
Windows 窄窗口都不该被操作系统粗暴分类）：

| 族 | 平台 | Shell |
| --- | --- | --- |
| Desktop | Windows / macOS / Desktop Web | `DesktopShell`：侧栏 + 聊天 + 底部语音栏 |
| Mobile | iOS / Android / Mobile Web | `MobileShell`：频道树主页 / 聊天详情；设置分类 / 设置详情 |

两族继续共享：Design System、业务组件、状态层、Models、l10n。

**三层 UI**（差异只允许出现在第三层）：

1. `design/`——tokens、theme、通用控件；**六端全共享**。
2. `features/`——业务组件（频道树、聊天、用户列表……）；**共享**，禁止散落
   `Platform.isX` / `kIsWeb` 分支。
3. `layout/`——`DesktopShell` / `MobileShell` / `adaptive_shell.dart`；布局差异在这里。

**平台能力 = 接口 + 各平台实现**，UI 不感知：

| 接口 | Native | Web |
| --- | --- | --- |
| `ClientTransport`（命令与事件） | `EmbeddedTransport`（FFI ↔ 内嵌 core） | `RemoteTransport`（WebSocket ↔ 网关） |
| `VoiceBackend` | Rust 引擎（cpal） | Web Audio worklet ↔ 网关 |
| `NotificationBackend` | `local_notifier` | Notification API |
| `SecureStorage` | 文件(0600) / Keychain / Keystore | 浏览器存储（弱一档） |
| `HotkeyBackend` | 系统级热键 | 不支持（降级为页面内快捷键） |

**Transport 不绑平台**：命名按能力（内嵌 / 远程）而不是按 OS——将来桌面连远程网关
（NAS、云端）同属 `RemoteTransport`。`ClientTransport` 是 providers 之下的**唯一协议
边界**；UI 与状态层不知道下面是 FFI 还是 WebSocket。

**网关不得复制 Core**（现状即是）：桌面与网关共用同一套 `ts-core`/`ts-session`/
`ts-protocol`/`ts-audio`；TS3/TS6 的行为永远只修一遍。

**目标目录**（渐进到位，不搞一次性大搬家）：

```text
apps/client/lib/
├── app/
├── core/{transport, voice, state}      # ClientTransport / VoiceBackend / 共享状态
├── design/{tokens, theme, components}  # 全平台共享
├── features/*                          # 业务组件，共享
└── layout/{desktop_shell, mobile_shell, adaptive_shell}.dart
tools/web-debug/                        # 现调试页迁入：诊断/协议验证，不做产品 UI
```

**路线**：① `ClientTransport` 抽象（已接入内嵌/远程）→ ② 浏览器 `VoiceBackend`（已实现）→ ③
`flutter build web` + Cloudflare Pages → ④ 移动平台脚手架 + `MobileShell` → ⑤
三条一致性要求逐项走查。

**层 1 已经建起来了**（2026-09-30）：`lib/design/{tokens,theme,components}`，
按 `docs/UI设计与配色规范.md` 与 `docs/UI字体规范.md` 落地。布局那一层：`MobileShell`
已于 2026-10-05 落地；**Server Rail 与独立成员栏不做**（用户拍板、多次重申，2026-10-08
再次确认）——不要再列进任何待办。见 [`docs/ui.md`](docs/ui.md)。

---

## 3. 开发流程

### 3.1 首次准备

```bash
git clone --recurse-submodules <repo>     # 子模块必须初始化
```

**为什么必须用 submodule**：`tsclientlib` 的 `tsproto-structs` 在编译期用
`include_str!` 读 `declarations/Versions.csv`，而该目录是嵌套 submodule。
**Cargo 不为 git 依赖拉取 submodule**，所以 `git = "..."` 必然编译失败（已实测）。

`vendor/tsclientlib` 指向自建 fork 的 `nightcord` 分支——见
[`docs/tsclientlib-fork.md`](docs/tsclientlib-fork.md)。

### 3.2 环境前提

| 项            | 要求                                                                                        |
|---------------|---------------------------------------------------------------------------------------------|
| Rust          | `rust-toolchain.toml` 固定 `1.98.0`，rustup 自动安装                                        |
| cmake         | **必须**。`audiopus_sys` 用它从源码编译 libopus。装：`winget install --id Kitware.CMake -e` |
| Visual Studio | 需要**装了 C++ 工作负载**的版本（见下）                                                     |
| Flutter       | 3.47.5+（本机 3.47.5 / Dart 3.13.4），做客户端时必需                                        |
| UI 字体       | **必须**先跑 `bash scripts/fetch-fonts.sh`（见下）                                          |

**字体不进仓库**：`apps/client/assets/fonts/` 被 `.gitignore` 忽略，
`scripts/fetch-fonts.sh` 从 jsDelivr 取 Noto Sans / Noto Sans SC 的可变字体
（约 20 MB，校验 sha256），另一处来源是 `raw.githubusercontent.com` 作兜底。
理由是体积与不可变性——一个永远不变的二进制没必要跟着每一次 clone 走。

**代价要知道**：`pubspec.yaml` 声明了这些文件，所以**缺字体时
`flutter analyze` 与 `flutter test` 都会失败**，报 `unable to locate asset
entry`（analyze 对 `.txt` 那份报 `asset_does_not_exist`）。这是刻意的：另一种
做法（不声明）会让每个页面默默用系统字体渲染，而那正是这份规范要消灭的
平台差异。`--check` 只校验不下载，CI 可以用它给一句人话。

**本机特有**：CMake 会挑最新 VS，但必须选装了 C++ 工具链的那个。本机
VS 2022 Community 未装，VS 2019 BuildTools 装了，所以：

```bash
export CMAKE_GENERATOR="Visual Studio 16 2019"
```

> 这一步**刻意没写进仓库配置**——生成器取决于哪台机器装了 C++ 工具链，
> 写死会让 CI（windows-latest 预装完整 VS 2022）出错。
> 给 VS 2022 装上「使用 C++ 的桌面开发」后就不需要了。

**macOS 侧**——构建**不在这台 Windows 上做**，在局域网内一台 Mac 上做，细节见
[`docs/macos.md`](docs/macos.md)。Rust、cmake、UI 字体三条与上面的要求相同，
另有两样 Windows 不需要的：

| 项 | 为什么 |
| --- | --- |
| Xcode | 27.0。`xcode-select -p` 要指向 `/Applications/Xcode.app/Contents/Developer` |
| CocoaPods | `flutter build macos` 靠它链接带原生代码的插件（`local_notifier`、`hotkey_manager`）。装：`brew install cocoapods` |

`CMAKE_GENERATOR` 那条**在 macOS 上不适用**（cmake 默认就用 Xcode）；CMake 4 与
Opus 1.3 的问题照旧由 `.cargo/config.toml` 挡住，跨平台。

### 3.3 语音构建踩过的两个坑（已由仓库配置绕过，记录备查）

都不需要手动做，但如果哪天在别的机器/CI 上看到这两条错误，答案在这里：

**① CMake 4 与 Opus 1.3 不兼容**

CMake 4 移除了对 `cmake_minimum_required(VERSION < 3.5)` 的兼容，而
audiopus_sys 自带的 Opus 1.3 仍声明旧的版本下限：

```text
CMake Error at CMakeLists.txt:1 (cmake_minimum_required):
  Compatibility with CMake < 3.5 has been removed from CMake.
```

解法：`.cargo/config.toml` 设 `CMAKE_POLICY_VERSION_MINIMUM = "3.5"`。

**② MSVC 运行库不匹配**

cmake-rs 在 cargo `opt-level = 0` 时会选 CMake 的 `Debug` 配置，而 MSVC 的
Debug 配置链接**调试版 CRT**（`/MDd`），Rust 始终链接发布版 CRT：

```text
libaudiopus_sys.rlib(opus_encoder.obj) :
  error LNK2001: unresolved external symbol __imp__CrtDbgReportW
```

解法：`Cargo.toml` 设 `[profile.dev.package.audiopus_sys] opt-level = 1`，
让 cmake-rs 改用 `RelWithDebInfo`，且只影响这一个包。

### 3.4 日常命令

```bash
cargo build --workspace
cargo test  --workspace --all-features
cargo run -p nightcord-cli -- --address <host> --nickname <name>

# Flutter（需要 CMAKE_GENERATOR，见上）
bash scripts/fetch-fonts.sh                # 克隆后一次；analyze / test 都要它
cd apps/client && flutter run -d windows

# 改了 apps/client/lib/l10n/*.arb 之后：重新生成并一起提交。
# build/run 会自动生成，analyze/test 不会——所以生成文件必须进仓库，
# 详见 docs/localization.md。
cd apps/client && flutter gen-l10n
```

> `flutter build windows` **之前先关掉正在运行的应用**：安装步骤要覆盖
> exe/DLL，文件被占用时构建以 `error MSB3073`（cmake_install 失败）告终，
> 报错信息不会直说原因。冒烟测试时踩到过一次。

> **改了用到新图标的地方，release 构建要额外删一次字体子集**——
> 图标字体在 release 下按 kernel 裁成子集，而**这个目标不会因为 kernel 变化
> 重跑**：新加的 `Icons.*` 会不在字体里，界面上一片空白（见 §6 ㉖）。要么
> `flutter clean`，要么只删这一个文件再 build：
>
> ```bash
> rm -f apps/client/build/flutter_assets/fonts/MaterialIcons-Regular.otf
> ```
>
> debug 构建与 `flutter test` 不做 tree-shake，**它们看不见这个问题**。

**macOS（在 Mac 构建节点上，见 [`docs/macos.md`](docs/macos.md)）**：

```bash
ssh agent@192.168.31.33                     # 先连上去，其余命令都在那边跑
cd ~/workspace/nightcord-speak/apps/client
git pull
flutter build macos --debug                 # 会连着 cargo build -p ts-ffi 一起跑
```

`flutter run -d macos` 也支持，但**从 SSH 启动会失败**：构建账号没有图形会话
（`docs/macos.md` §4）。看界面得把 `.app` 复制到 `/Users/Shared/` 再在访达里打开。

### 3.5 门禁：提交前必须全绿

```bash
bash scripts/fmt.sh --check                                        # 格式
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test  --workspace --all-features                             # 422 个
cd apps/client && flutter analyze && flutter test                  # 293 个
```

> `cargo fmt --all` **不能用**：它也会格式化 path 依赖，会把 `vendor/tsclientlib`
> 按我们的风格改写。用 `scripts/fmt.sh`（内部是 `-p` 逐个列出的）。

**坑**：`scripts/fmt.sh` 的包列表是手工维护的，**加了新 crate 必须同步加进去**，
否则它不会被格式化，而且门禁照样报绿。`ts-audio` 与 `ts-ffi` 就这样漏了很久，
直到 2026-09-30 补上时已攒下 15 个文件、101 处漂移（已一次性格式化清零）。

**顺序很重要**：先 `flutter analyze` 再 `flutter build`。跳过 analyze 直接 build，
会把编译错误当成运行时问题查（犯过一次）。

**字体是 Flutter 侧门禁的前提**：`apps/client/assets/fonts/` 为空时
`flutter analyze` 与 `flutter test` 都会失败（见 §3.2）。克隆后先跑一次
`bash scripts/fetch-fonts.sh`。

### 3.6 提交

- 一次提交只做一件事；提交信息说清 **为什么**，不只是改了什么。
- 格式用 [Conventional Commits](https://www.conventionalcommits.org/)：
  `type(scope): 简述`。`type` 取 `feat` / `fix` / `refactor` / `docs` / `test` /
  `chore`；`scope` 写受影响的那一块（`gateway`、`client`、`audio`、`ffi`、
  `logging`……）。**语言用中文**（§4.1）。
- 改动 API、修 bug、定决策，同步更新本文档对应小节。
- 未经要求不要提交/推送。
- 提交的信息应当简洁明了，不要长篇大论。

---

## 4. 开发规范

### 4.1 语言

- **代码注释、文档注释用英文**（Rust 生态惯例）。
- **与用户交流、本文档、`docs/`、提交信息用中文。**

> 提交信息这条曾写着「用英文」，但仓库从 `Initial commit` 起就是这么写的：
> 十条提交全是中文。规则与实际不一致时，改的是规则——除非打算把历史也重写一遍。
> 格式见 §3.6。

### 4.2 注释

- 文档注释解释 **为什么**，不是 **是什么**。`/// Returns the name` 没有价值，
  `/// Falls back to the address when the server has not named itself yet` 才有。
- 反直觉的地方必须写清原因，尤其是「看起来可以简化但不能」的地方。
- 不写 `// TODO`，要么现在做，要么记进本文档的待办。

### 4.3 测试

- **每个 bug 修复都要配回归测试**，测试注释里写清原本的症状。
- 协议边界、错误路径、状态机边界必须有覆盖。
- 测试要能独立运行，不依赖执行顺序。
- 涉及真实服务器的验证放进本文档的进度表，**不进单元测试**。

### 4.4 错误处理

- 库代码不 panic；返回 `Result`。
- 所有错误归一到 `ts-model` 的 `ClientError`（§37），前端只见这一套词汇。
- 错误信息要能让人行动。「permission denied」不够，
  「missing permission #218」才有用。
- 未知不等于拒绝：缺少信息时**不要**默认禁止（见 §6 的 Bug ②）。

### 4.5 安全

- 身份私钥、密码、Token **绝不**进日志、`Debug`、FFI。
  `Identity` 与 `ConnectionConfig` 的 `Debug` 已打码，不要绕开。
- 日志里不放聊天内容原样（用户内容）。
- `ts-ffi` 只暴露**句柄**（`u32` id），不暴露 Rust 对象指针（§47）。

### 4.6 依赖

- 新增依赖前先问：标准库或已有依赖能否解决。
- 记录**为什么**选它，必要时写进 `docs/`。
- 版本在 workspace 根统一声明，子 crate 用 `workspace = true`。

> `time` 是唯一的例外情况记录在案：它进 `ts-protocol-tsclient` 只为一件事——
> `OutBanClientPart` 的 `time` 字段类型是 `time::SignedDuration`，而 `tsclientlib`
> 没有 re-export 它。它本来就在依赖树里（vendored 库用的同一份），所以没有新增编译量。

---

## 5. 当前进度

**最后更新：2026-10-08**

### 5.1 里程碑

| 里程碑   | 内容                            | 状态        |
|----------|---------------------------------|-------------|
| Phase 0  | workspace / CI / tracing / 文档 | ✅          |
| **M0.1** | TS3 Headless Client             | ✅ **实测** |
| **M0.2** | TS3 Voice                       | ✅ **实测** |
| **M0.3** | Flutter Client                  | ✅ **实测** |
| **M0.4** | TS6                             | ✅ **实测** |
| **M0.5** | Multi Session                   | ✅ **实测** |
| M0.6     | Production Client               | ✅ **全部完成** |
| Phase 7  | Web Gateway                     | 🚧 进行中   |
| Phase 8  | 扩展功能（§72）                 | 🚧 屏幕共享已做 |

§90 的实际顺序：

```text
① Rust Workspace ✅  ② ts-model ✅  ③ ts-events ✅  ④ ts-session ✅
⑤ TS3 Backend ✅     ⑥ TS3 Headless CLI ✅  ⑦ TS3 Voice ✅
⑧ Flutter FFI ✅     ⑨ Flutter UI ✅
⑩ TS6 Backend ✅     ⑪ Multi Session ✅
⑫ Web Gateway 🚧     ⑬ Web Client 🚧        ⑭ 扩展功能 🚧（屏幕共享）
```

**Phase 7 当前到哪**（详细设计见 [`docs/gateway.md`](docs/gateway.md)）：

- [x] `ts-wire` —— 命令与事件词汇从 `ts-ffi` 搬出，两个前端共用一份
- [x] `ts-gateway` + `nightcord-gateway` —— 鉴权、扇出、语音桥、内嵌调试页
- [x] `ClientTransport` 接口 + `ConnectRequest` 搬进 `models/`
- [x] 桌面侧的功能补齐（poke / kick / ban / 权限面板 / 编码档位 / 音量）——见 §5.3 末
- [x] 浏览器 `VoiceBackend`、`RemoteTransport`、Flutter Web 发布构建与自适应 Desktop / Mobile Shell
- [ ] HTTPS/WSS 部署、手机浏览器真机语音验收；Android / iOS 原生脚手架仍未建立

> Phase 7 的本轮验证记录见 §5.3「Web 客户端第一阶段」，未验证项仍留在 §5.4。

### 5.2 规模

|      | 数量                           |
|------|--------------------------------|
| Rust | **25,968 行**，16 crates + CLI + gateway（不含 vendor） |
| Dart | **25,210 行**，`apps/client/lib/` 下 107 文件（含 l10n 生成文件，不含测试） |
| 测试 | **422 Rust + 354 Dart + 5 启动脚本测试**；macOS 上一轮为 399 Rust + 272 Dart（差的是 SEH 那条，本轮尚未重跑） |

> macOS 少的那一个是 `a_simulated_exception_writes_a_note`——SEH 是 Windows 专有的
> 异常机制，那条测试本来就带平台门控。**不是回归**，数的时候别把它当成丢了一个。

### 5.3 实测验证过什么

**TS3**（`192.168.31.128:9987`）

| 项                | 结果                                                                    |
|-------------------|-------------------------------------------------------------------------|
| 连接 / 断开       | ✅ 干净断开后可立即用同一身份重连                                       |
| 身份持久化        | ✅ 两次运行 `unique_id` 一致（§36）                                     |
| 服务器信息        | ✅ 名称 / 欢迎语 / 平台 / 版本 / 槽位 / 在线数                          |
| 频道树 / 用户列表 | ✅ 含 `(you)` 标记                                                      |
| 聊天收发          | ✅ 服务器回显经事件路径到达                                             |
| 语音              | ✅ **499↔499 帧，10.0 秒，双向零丢包**，峰值 0.316                      |
| 换频道            | ✅ 用户于 2026-10-05 确认频道切换已完成并测试无误 |

**TS6**（`192.168.31.128:9988`，`TeamSpeak 6 Server 6.0.0-beta13.1`）

| 项                | 结果                              |
|-------------------|-----------------------------------|
| 连接 / 服务器信息 | ✅ 正确报出 TS6 与版本号          |
| 频道树 / 用户列表 | ✅ 3 个频道                       |
| 聊天              | ✅ 完整往返                       |
| 语音              | ✅ **449↔449 帧，9.0 秒，零丢包** |
| 能力集            | ✅ TS6 报 `stream`，TS3 不报      |

**Flutter 客户端**

| 项                              | 结果                                          |
|---------------------------------|-----------------------------------------------|
| 连接真实服务器                  | ✅ TS3 与 TS6 均可                            |
| 频道树 / 离线区 / 聊天 / 语音栏 | ✅                                            |
| 音频设置对话框                  | ✅ 设备与传输方式下拉                         |
| **多会话**                      | ✅ TS3 + TS6 同时在线，切换器均显示「已连接」 |
| 150% 显示缩放                   | ✅ 渲染正常                                   |

**Logging（M0.6 第一项）**

| 项                          | 结果                                                                       |
|-----------------------------|----------------------------------------------------------------------------|
| 日志落盘                    | ✅ `%APPDATA%\Nightcord Speak\logs\nightcord.<日期>.log`，每日轮转保留 7 份 |
| **「UI 可见 ⇒ 必落日志」**  | ✅ 实测：连 `127.0.0.1:9` 失败，SnackBar 里那句话与日志里那行是同一个错误    |
| 错误 SnackBar 显示路径+按钮 | ✅ 截图确认（路径 + 「打开日志」）                                          |
| 设置对话框（音频 + 日志）   | ✅ 截图确认，路径为真实目录，「打开日志文件夹」按钮就位                        |
| Dart 错误经 FFI 转发        | ✅ `dart-forwarded-…` 以 `ERROR nightcord_ui` 落盘（也是 Dart 集成测试）     |
| 未知 level / 空消息 / 中文  | ✅ 按 info 记或不记，均不 panic                                             |
| CLI 行为不变                | ✅ 仍写 stderr；`RUST_LOG` 生效，`NIGHTCORD_LOG` 优先级更高                  |

**重连（M0.6 第二项）**

| 项 | 结果 |
| --- | --- |
| fork 补丁 `ReconnectMode::External` | ✅ 已推送 `c5cc287`；本仓库 pin 已在 `dcf2509` 提交，编译通过 |
| 正常路径未受影响 | ✅ 真实服务器连接 / 服务器信息 / 能力集 / 干净断开，与补丁前一致 |
| actor 的 `Reconnecting → Connected` bug | ✅ 已修（`refresh` 不再拿一次性 `ready` 当状态开关） |
| §35 退避表 | ✅ 6 个单测：1/2/4/8/16→30 封顶、首次编号为 1、不可重试错误不消耗预算、恢复后重新计数 |
| Dart 侧断线保留上下文与倒计时 | ✅ 7 个测试 |
| **重连循环本身** | ❌ **未跑通过一次真实掉线** —— 见 §5.4 |

**设置界面（M0.6 第三项）**

| 项 | 结果 |
| --- | --- |
| 设置落盘 | ✅ `<应用数据目录>/settings.json`，字段可读、可手改 |
| **关掉对话框后值还在** | ✅ 截图确认对话框从设置渲染（不再是 widget state） |
| **跨进程往返** | ✅ Dart 写入 → 经 FFI → core → 文件 → 读回一致（Dart 集成测试，收尾恢复原值） |
| Rust 侧往返 | ✅ `settings_update` → `settings` 同一份值（真实 DLL，收尾恢复原值） |
| 坏文件不阻塞启动 | ✅ 实测：写成 `{ this is not json`，应用照常启动并连上服务器，日志一条 `warn` 带原因与路径，**文件原样保留** |
| 无 `.tmp` 残留 | ✅ 原子写入的回归测试 + 实测 |
| 部分/未知字段 | ✅ 删掉一行只重置那一项；未知字段被忽略而不是报错 |
| 策略真的进了配置 | ✅ 两个测试：`Some(0)` 一次都不重试；没动过的配置照旧重试 |

**书签 / 服务器列表（M0.6 第四项）**

| 项 | 结果 |
| --- | --- |
| 模型搬家 + 改名 | ✅ `ts-protocol` 里那份死代码已删；`Server` 撞名的两处（Dart 与 `ts-model`）一跑 analyze 就暴露，改回 `Bookmark` |
| 文件与设置分开 | ✅ `bookmarks.json` 与 `settings.json` 并列，互不干扰 |
| 跨进程往返 | ✅ Dart 存入 → core 解析地址并归一化 → 文件 → 读回一致（含收尾恢复） |
| 地址归一化 | ✅ `ts3://example.com:9999` → `host`+`port`；裸地址取默认端口 9987 |
| 拒绝连不上的地址 | ✅ `https://example.com/server` 被拒，错误里点明 scheme，**且什么都没写** |
| 密码不进 `Debug` | ✅ 单测盯着（`<set>` / `<unset>`） |
| 坏文件不阻塞启动 | ✅ 实测：一条 `warn`、**消息里带文件名**、文件原样保留、照常连上服务器 |
| 无 `.tmp` 残留 | ✅ 两个 store 各有一条回归测试（共用同一份原子写） |

**通知（M0.6 第五项）**

| 项 | 结果 |
| --- | --- |
| 应用内浮层 | ✅ 实测截图：第二个人加入时右下角出现「同事二号 / 加入了服务器」 |
| **不打扰正在看的线程** | ✅ 同一次实测里，频道消息**没有**弹——用户正看着那个频道 |
| **握手重放被压住** | ✅ 应用连接时服务器上已有的人没有产生任何通知 |
| **系统通知（我标为风险的那项）** | ✅ 实测：窗口最小化时，桌面右下角弹出 Windows toast。插件首次运行时自己补了缺的 `.lnk` |
| 开关真的落盘 | ✅ FFI 往返测试断言新节存在且只关掉指定的那一个 |
| 规则本身 | ✅ 19 条纯 Dart 测试：每个开关、正在看的线程、自己的消息、2 秒静默窗、重连重放、离场者名字、语言切换 |
| **未读点** | ⚠️ 只有单测——测试服务器只有一个频道，而 CLI 没有发私聊的参数，端到端制造不出「没在看的线程」 |

**设备管理（M0.6 第六项）**

| 项 | 结果 |
| --- | --- |
| 「正在使用」哪一个设备 | ✅ 实测截图：**「正在使用：麦克风（ROG CARNYX）」**——引擎报出实际打开的那个 |
| 麦克风电平表 | ✅ 实测截图：播放声音时电平条有读数，且标着「低于阈值，未传输」 |
| 阈值线 | ✅ 截图里可见（紫色竖线在 5% 处），滑块因此不再盲调 |
| 测试扬声器按钮的状态 | ✅ 两张截图对比：没引擎时**灰**，开始语音后**可用** |
| 未开始语音时不报错 | ✅ 实测：显示「尚未开始语音…」而不是错误 |
| 电平在四种模式下都被记录 | ✅ 单测（PTT / 持续 / 静音三种会让闸门短路，是易错处） |
| `voice_status` 无引擎时的回答 | ✅ 单测：回「都不可用」而不是失败 |
| **设备被拔掉时的提示** | ⚠️ 只有代码路径——没有真的拔过设备 |

**快捷键（M0.6 第七项）**

| 项 | 结果 |
| --- | --- |
| **系统级热键**（本轮重点） | ✅ 实测截图：切到**记事本**后发 Ctrl+Shift+M，切回来麦克风图标是红的——窗口不在前台也生效 |
| 插件与当前 Flutter 兼容 | ✅ `flutter build windows` 通过（该包最后发布于 2024-05，是这一轮唯一的依赖风险） |
| 匹配是精确的 | ✅ 单测：Ctrl+M 不会被 Ctrl+Shift+M 触发，加一个修饰键也不是同一个组合 |
| 清空 ≠ 没设置过 | ✅ 单测：`"mute": null` 保持未绑定，缺这个键才回落到 §42 的默认 |
| 默认值写在模型里 | ✅ 单测：一个写在快捷键存在之前的设置文件读回来是 Ctrl+Shift+M/D/P |
| 按钮与快捷键同一条路 | ✅ 两者都调 `SessionsNotifier.toggleInputMuted` / `toggleOutputMuted` |
| **旧 PTT 的卡住 bug** | ✅ 机制上消失（插件按注册的组合投递松开事件）——但**没有手工复现过旧行为** |
| 设置里的记录器 | ⚠️ **没能截图确认**（滚动截图两次都不稳定），只有 `flutter analyze` 与代码审查 |
| PTT 的按住/松开 | ⚠️ 未实测（`SendKeys` 无法按住不放） |

**本地化（M0.6 第八项）**

| 项 | 结果 |
| --- | --- |
| **读取与应用（端到端）** | ✅ 实测截图：手改 `settings.json` 的 `ui.language` 为 `"en"` → 启动 → **整页英文**（Saved servers / Server address / Connect）；改 `"zh"` → 整页中文。品牌与用户数据（书签、昵称）两种语言下均不变 |
| 跟随系统 | ✅ 系统 zh-CN + `language: null` 的解析与 `"zh"` 走同一条路；`localeProvider` 单测覆盖五种语义（显式 zh/en、系统 zh、系统 fr→en、未答复、不认识的值） |
| 设置里切换 | ⚠️ 只有单测与 FFI 往返（写入路径 = 对话框下拉 → core → 文件 → 读回）。**连接页够不到设置对话框**（§7 的已知缺口），本机没连服务器，对话框本体没有手工点到 |
| 错误句与时间戳 | ✅ 单测双语断言：`describe` 透传 core 原文 / 结构化 payload / 四种 Dart 侧 kind；`formatTimestamp` 今天 / 昨天 / 同年 / 跨年 |
| 通知文案随语言切换 | ✅ 单测：policy 构造后换 getter 的返回语言，下一句即换（重建 policy 会重置重放窗口，故用 getter） |
| ARB 完整性 | ✅ 单测直接比较两份 ARB 的 key 集合——gen-l10n 对「缺翻译」是**静默回退英文**的，这是唯一守卫 |
| Windows 窗口标题 | ✅ 截图确认已是 `Nightcord Speak`（品牌，不随语言变；`Runner.rc` 同步） |
| **顺带修正**：TS6 分段陈旧 UI | ✅ 截图确认两个分段都可选——原先 `enabled: false` + 「尚未实现」停留在 M0.4 之前，见 §6 ⑤ |
| `flutter gen-l10n` 产物入库 | ✅ 生成文件已提交（`analyze`/`test` 不会自动生成，不提交则克隆后第一次门禁即红） |
| 四门 CJK 语言 | ✅ 简中 / 繁中 / 日 / 韩，各配一个 Noto 字体（构建前多下约 31 MB） |
| `zh_Hant` 的 script 判定 | ✅ 单测：`zh_TW`/`zh_HK`/`zh_MO` 解析到 Hant，`zh`/`zh_CN`/`zh_SG` 到 Hans。**没有这一步的话 `basicLocaleListResolution` 先比语言码，`zh_TW` 会停在我们那个光秃秃的 `zh` 上——简体字形** |
| key 集合守卫改成扫目录 | ✅ **它原本点名比较 en/zh 两份**，所以此后加的每一门语言都不设防，缺 key 只会静默回落英文 |

**崩溃上报（M0.6 第九项）**

| 项 | 结果 |
| --- | --- |
| **硬杀 → 横幅 → 报告（端到端）** | ✅ 实测截图：`taskkill /F` → 重启 → 顶部横幅「上次会话异常结束 / 有 N 份崩溃记录」→ 点「生成报告」（鼠标自动化）→ SnackBar 显示路径、死标记被消费、横幅随之消失；报告含头部、标记（活/死分别标注）、日志尾部与隐私说明 |
| **正常关窗不误报** | ✅ 实测：关窗 → 标记被删 → 重启**无横幅**。这条路径靠 `AppLifecycleListener(onExitRequested)`——ProviderScope 从不销毁，`client.dispose()` 在正常退出时不会执行 |
| **真 panic → 真死亡** | ✅ 实测：`NIGHTCORD_TEST_PANIC=ffi` → 进程 abort → 笔记含 `message: NIGHTCORD_TEST_PANIC=ffi`、源码位置与**帧地址**；重启出现横幅；报告含两条笔记（原始原因 + «cannot unwind»） |
| **worker 半死** | ✅ 实测：`NIGHTCORD_TEST_PANIC=worker` → 进程存活、界面红色「核心已崩溃，请重启应用」（此前是静默冻结）；日志一次性 `ERROR` + 命令级失败；关窗后标记**保留** → 重启横幅 |
| 笔记同名覆盖 | ✅ 回归测试：纳秒命名——毫秒粒度的第一版把「真正的原因」那条覆盖掉了（冒烟抓出） |
| 崩溃目录位置 | ✅ FFI 测试断言它是 `logs/` 的**兄弟**而非子目录——第一版复用了日志助手（会拼 `logs`），冒烟抓出 |
| SEH 路径（模拟） | ✅ 集成测试：`simulate_exception` 走真实回调，笔记含异常码与地址 |
| 标记判定 | ✅ 单测：死 pid 算异常、活 pid 不算；按 pid 分文件（两实例互不干扰）、报告消费死标记、清理上限 |
| **真实原生崩溃（非模拟）** | ⚠️ 未触发过；且 Dart↔FFI 路径上的 UEF 已知盲区（dart-lang/sdk#51726）——SEH 笔记按「尽力而为」理解，承重信号是 panic 笔记与运行标记 |
| minidump | ❌ 明确不做（v1），升级路径写进 [`docs/crash.md`](docs/crash.md) |

**品牌与细节（视觉层这一轮，2026-10-01）**

| 项 | 结果 |
| --- | --- |
| **品牌标记** | ✅ 实机截图：连接页标题行（32px）与服务器头部（24px）画的是 `AppLogo`，`Icons.bubble_chart` 一处不剩 |
| **应用图标** | ✅ `scripts/make-app-icon.py` 生成的 7 个尺寸（16–256）；实机看过浅色标题栏下的 16px，两只眼仍认得出 |
| **底栏名字的位置** | ✅ 屏幕取像素：墨迹中心从偏离底栏中线 **+4.5** 物理像素改到 **−0.5**。前两次改行高都没修对——行高不是那个杠杆，理由写在 `_opticalLift` 的注释里 |
| 已保存服务器的图标边距 | ✅ 屏幕量：图标墨迹 x 663 → **675**，左边框仍在 660，不再贴着 |
| 双击直连 | ✅ 单测两条：单击只填表单（transport 零调用）、双击发出 `connect:192.168.31.128:9987`。单击被押后约 300ms 是双击判定的固有代价，见 §7 |
| 新标记的各尺寸绘制 | ✅ 单测：16 / 24 / 32 / 256 都能画不报错。**画得像不像**只能人眼看——测试字体没有真实字形度量（底栏那轮因此量错过两次） |

**功能补齐与音质（2026-10-01 第二轮）**

用户实测反馈「音质确实有点差」，并澄清是**声音本身的质量**（不是断音 / 爆音 / 卡顿）。
据此做了编码档位、音量、以及几个一直缺的功能。**这一轮的实测全部待做**——下表的
✅ 一律只表示单测与静态检查，不是实机结论。

| 项 | 结果 |
| --- | --- |
| 音质差的根因 | ✅ 定位到：编码器把 `VOICE_BITRATE = 24_000`、单声道、`Application::Voip` 全写死，且客户端**没有任何质量设置**。管线本身是 48 kHz / f32 全链路，采样率没问题——「采样率差」的实质是 Opus 在 24 kbps 下的实际带宽被压低 |
| **编码固定成最高档，没有设置** | ✅ 桌面：立体声 + `Application::Audio` + `CodecType::OpusMusic` + 79,200 bps。网关：单声道 + 45,056 bps（浏览器只送单声道帧）。两个数字都取自 TeamSpeak 公布阶梯的顶端 |
| 声道数是参数不是设置 | ✅ 它是**输入的性质**：桌面采集恒为立体声，浏览器 worklet 只给单声道。把单声道编成立体声等于为一个声道付两次带宽 |
| 中途改过两次主意 | ⚠️ 先做了「Voice/Music 两档 + 1–10 质量滑块」（含 `reconfigure`、两条码率阶梯、设置 UI、l10n），用户看过之后否掉：「官方客户端哪里有选择音质这个选项了……不要设置了」。整套已删除——设置字段、`AudioCodec`、`EncoderConfig`、`reconfigure`、滑块的 Dart 代码与文案。**留档是为了记住这个决定**：编码质量不做成旋钮 |
| 采集恒定立体声 | ✅ 单声道设备复制成双声道、>2 声道取前两路；两个 `Resampler` 实例按声道分开（共享会把左声道的上一个样本灌进右声道，每次回调一次咔哒） |
| 采集回调去分配 | ✅ 顺带修掉：此前每次回调两次 `collect`，现在只剩成帧本身一次——`docs/audio.md` 里那句「唯一的分配是成帧本身」第一次成立 |
| 输出总音量 | ✅ `Playback::set_volume`，一个原子写，回调每帧读一次；换设备用 `open_with_volume`，否则音量会被打回 1.0 |
| 单人音量 | ✅ 后端一张 `HashMap<ClientId, f32>` 覆盖表，在**队列新建时**套用。**不需要改 fork**：`AudioQueue::volume` 是 pub 字段 |
| 单人音量撑过「停说再开口」 | ✅ 回归测试：收包建队列 → 设音量 → `fill_buffer` 到队列被删 → 再收包 → 断言新队列仍是设定值。**这条测试抓到了一个真缺陷**：采纳逻辑原本挂在 `handle_item` 上，与队列创建可分离，已合并进 `Audio::receive` 使二者不可分 |
| poke 的管道 | ✅ trait、actor、事件、通知浮层本来全都在，缺的只有 session → wire → ffi → gateway → UI |
| kick / ban | ✅ `OutClientKickPart` / `OutBanClientPart`；永久封禁在线路上是**字段缺席**而不是 0，`BanDuration` 因此把「永久」做成独立变体 |
| 成员右键菜单 | ✅ 戳一戳 / 移到频道 / 从频道踢出 / 从服务器踢出 / 封禁 / 音量；自己那一行除音量外全灰 |
| 权限门控 | ✅ 单测三条（无权限时灰、有权限时踢出带对的 scope、对自己不可用）。位来自 `ServerView.permissions`，**服务器仍是权威** |
| 「我的权限」面板 | ✅ 服务器切换器里，六个位如实列出——目标 #6 唯一看得见的落点。此前那六个位只有聊天输入框读了其中一个 |
| `voice_status` 报真实档位 | ✅ 多 `codec` 与 `bitrate_bps`，由 core 算。前端的「正在以 Opus Voice 33 kbps 发送」读它，不另抄一张表 |
| 双击直连不再押后单击 | ✅ 单测两条：单击当帧填表（**只 `pump()` 一次**，不再等 400ms）、间隔 500ms 的两次点击不算双击。第一版用 `Stopwatch` 量真实时间，**被测试当场抓出不可测**，改用 `Timer`（走调度器时钟，`flutter_test` 推得动） |
| 未连接时够不到设置 | ✅ `SettingsDialog.session` 改 `int?`，连接页标题行加设置按钮。此前「打开日志文件夹」在连接页无处可点 |

**AFK / 离开状态（2026-10-01 第三轮）**

底栏麦克风左边多了一个离开按钮：点一下在「离开 / 在线」之间切换，**右键（触屏是长按）**
打开「离开消息」对话框，填的那句话写进 `settings.json` 的 `presence.away_message`，
下次打开对话框时预填它。别人的离开消息显示在成员列表里名字后面。**实测待做**，下表全是
单测与静态检查的结论。

> **点击永远不带消息**（用户定，2026-10-01）：存着的那条只是**对话框的预填**，不是按钮的
> 意思。「离开」和「说明为什么离开」是两件事——按钮做前一件，对话框做两件。

| 项 | 结果 |
| --- | --- |
| 三态不许塌成两态 | ✅ `ts-session` 测试：`away: true` 不带消息仍然要标记离开（不是「在线」），而回来时不再带消息 |
| 线路上是 `clientupdate` | ✅ actor 用生成的 `set_away(Option<&str>)`，与设静音同一个 `client_update()` builder；序列化顺序 `client_away` 在 `client_away_message` 之前——这正是库回写 book 时认消息的前提 |
| **不需要乐观更新** | ✅ 库在命令**发出**时就把状态写回自己的 book（`update_on_outgoing_command`），actor 又是「任何 book 事件就重拍快照」，所以按钮亮灭直接读 `ownClient.flags.away` 就是准的。与静音按钮不同，那个的本地副本另有原因 |
| 模型里只有一个真相 | ✅ book 的 `AwayMessage` 即「是否离开」；`ClientFlags.away` 由它派生，消息本身放 `Client.away_message`（空串在 `convert.rs` 塌成 `None`——「离开了没话说」没有可显示的东西） |
| 离开消息持久化 | ✅ 新的 `presence` 节（`ts-settings` + Dart `models/settings.dart`），默认空串；一条测试盯着「写在有这个节之前的文件」读回来是空串。它只喂对话框的预填——按钮从不读它 |
| **点击不带消息** | ✅ 两条测试盯着（store 层与 widget 层）：即使设置里存着「在开会」，点按钮发出去的也是 `away:yes:`（空消息）。带消息只有对话框那条路 |
| 别人的离开消息看得见 | ✅ 成员行的名字用 `Text.rich` 跟一段 ` (消息)`，`bodySmall` + 次级色，整行一次省略号——名字优先占位 |
| 右键/长按出对话框 | ✅ 测试：预填已存消息、确定后发 `away:yes:<新消息>` 并把新消息写回设置。对话框是既有 poke 提示框提升成的 `showTextPrompt`（`design/components/`），没有第二份 |
| 离开按钮的字形 | ✅ 在线 `schedule_outlined` / 离开 `schedule`，与成员列表的离开徽章同一个字形；颜色不是唯一信号 |
| **离开要关掉本地发送闸门** | ✅ `TransmitPolicy` 里 away 与静音、闭麦并列（见 §6 ⑰）。不关的话：帧被库拒绝，界面弹一个「未连接」——用户实测报上来的就是这个 |
| 跨重连清掉这个标志 | ✅ 两处宿主都在 `ConnectionStateChanged(Connected)` 上清引擎的 away：服务器不跨连接记 away，而引擎会活过重连，否则会**静默地永远不发** |
| ABI 与网关 | ✅ `nightcord_set_away`（bool + 消息两个参数，因为「离开但没话说」不是「在线」）；`set_away` 进 `ts-wire`，网关因此自动有；Dart 的 ABI 测试（真实 DLL）里加了这一条 |
| **对真实服务器发过没有** | ❌ 见 §5.4 |

**麦克风增益（2026-10-01 第四轮）**

「我说给服务器多大声」——应用里此前根本没有这个控制（`output_volume` 是**播放**音量）。
现在：设置对话框多了「麦克风增益」，鼠标停在底栏**麦克风按钮**上会弹出同一条滑杆，
两边同一个值。默认 `0 dB`，范围 `-200…+10 dB`，最底端＝静音。
**实测待做**，下表全是单测与静态检查。

| 项 | 结果 |
| --- | --- |
| dB 换算 | ✅ `gain_from_db`：0 dB→1.0、+6 dB≈2.0、-200 dB<1e-9、NaN/∞→0（没有「不是数的分贝」这种意思） |
| 增益在哪一步应用 | ✅ `VoiceEngine::poll` 里 **measure 之后、encode 之前**：门限与电平表必须读麦克风原始电平，否则拧增益会悄悄改掉灵敏度滑杆的阈值。网关的 `RemoteVoice::encode_frame` 同一顺序 |
| +10 dB 的形状 | ✅ 乘完 clamp 到 ±1：削波是「响亮」，不是 NaN。unity 时一个采样都不碰（默认设置与从前逐位相同） |
| 存的是 dB，不是分数 | ✅ 新键 `input_gain_db`，**与旧的 `output_volume` 不同名**——老文件里那个键被忽略、新键落在 0 dB（＝unity，正是它原本的行为）。两条测试盯着：默认值，以及「写在有它之前的文件」读回来是 0 dB |
| 滑杆行程 | ✅ `util/gain.dart`：可听段（-60…+10 dB）铺满整条，0 dB 落在 0.857，**最底端单独是静音**；两个方向互为逆函数（-60 dB 本身即静音位，绕不回来，这是设计） |
| 两处同步 | ✅ 都写 `SettingsNotifier.update` → `settings_update`，两边 `ref.watch` 同一个 provider；不需要新命令 |
| 悬浮面板 | ✅ `OverlayPortal` + `CompositedTransformFollower` 贴在按钮正上方（全仓库第一次用这两个）；指针离开按钮/面板 250ms 后收起，拖动中不收；触摸平台没有 hover，那条路是设置对话框 |
| 底栏那条**竖着**，设置那条横着 | ✅ 面板挂在底边按钮上，行程往上长（那里有空间），不往两边长（那里是聊天）。`Slider` 没有竖向模式，靠 `RotatedBox(quarterTurns: 3)`——这个方向才把静音留在最底端 |
| 面板里没有文字 | ✅ 只有 dB 读数（用户要求）：面板挂在麦克风按钮上，按钮本身已经说明它调的是什么，写个标签只会把面板撑宽到盖住邻居。读数显示 `+6 dB` / `0 dB` / `静音` |

**窗口与图标（2026-10-01 第五轮）**

用户把窗口拖窄时，聊天头部溢出（Flutter 画出黄黑条纹），据此定了窗口下限；同时换掉两个图标。

| 项 | 结果 |
| --- | --- |
| 窗口最小尺寸 | ✅ 两个平台各一份，同一个数、同一个理由（低于它聊天头部溢出）。**Windows** 走 `WM_GETMINMAXINFO`（`windows/runner/win32_window.cpp`），`AdjustWindowRectEx` 把边框加回去所以下限管**客户区**，`FlutterDesktopGetDpiForHWND` 让 150% 缩放下是同一个窗口；**macOS** 走 `MainFlutterWindow.swift` 的 `contentMinSize`，它量的本来就是绘制区、point 本来就是逻辑单位。默认 `1280x720` 仍在其上 |
| 为什么是这个数 | ✅ 溢出的是 `chat_panel.dart` 的头部行：侧栏 288 + 聊天面板里那行固定件（图标 32 + 名称 + 话题分隔 + 在线数）约 300；960 给聊天面板留 671，长一点的频道名和四位在线数都放得下。**没有实测拖到下限**（见 §5.4） |
| 断开图标 | ✅ `Icons.link_off` → `Icons.logout`：门 + 箭头，和登录界面「退出」是同一个记号；断链读起来像「链路坏了」——是故障，不是选择 |
| AFK 图标 | ✅ `Icons.schedule` → `Icons.snooze`（在线 `snooze_outlined`）：闹钟脸里一个大 Z，是全仓库里最接近「zzz」的 Material 字形；成员列表的离开徽章同时换成同一个，两者仍然读作同一件事 |
| 怎么挑的 | ⚠️ 图标字体在 `flutter test` 里不会自动加载（渲染成方框），所以是把 SDK 缓存里的 `materialicons-regular.otf` 用 `FontLoader` 塞进一个临时测试、渲染成 PNG **人眼看过的**；那个临时测试没有留下 |
| 测试 | ✅ **本仓库第一个 hover 测试**：`createGesture(kind: mouse)` 移到麦克风图标 → 面板出现 → 拖滑杆 → 设置里是新值；移开 → 面板消失。设置对话框那条滑杆另有一条测试（含「播放音量没被碰」） |
| **真机听过没有** | ❌ 见 §5.4 |

**设置页（2026-10-01 第六轮）**

用户要求把设置从弹窗改成单独的页面、左右布局。原先是一个 480px 的 `AlertDialog`，
六节摞在一条滚动里；现在是 `SettingsPage`（`lib/features/settings/settings_page.dart`）：
左栏 240px 的分节导航（标题与返回按钮在左栏顶部，导航项带图标），右侧是当前一节，
六节各自一个文件放在 `sections/`。左栏两个选择是用户拍板的（见对话）。
**实测待做**，下表全是单测与静态检查。

| 项 | 结果 |
| --- | --- |
| 弹窗 → 页面 | ✅ `SettingsDialog` 改名 `SettingsPage`（本文更早处的旧名字即指它），文件拆成 `settings_page.dart` + `sections/`；这是本仓库**第一个 `Navigator.push` 的路由**（此前只有 dialog 与 sheet，没有任何路由表）；入口收进 `SettingsPage.open(context, {session})`，语音栏 ⚙ 与连接页 ⚙ 都走它 |
| 左栏 | ✅ `bgSidebar` + 1px `borderSubtle`；行样式照搬频道行（选中 `surface1`、hover `channelHoverBg`、hover/选中的文字都是 `textPrimary`，余者 `textSecondary`），hover 手写 `MouseRegion`——§19 连文字颜色都变，`InkWell` 不管文字 |
| 宽度 240 | ✅ §19 给 240–280 取了下限：标签是一两个词，不跟频道栏的 288 对齐 |
| 分节 | ✅ 六节各自一个文件，只有选中那节被构建，切走即销毁 |
| **轮询只在该跑的时候跑** | ✅ 200ms 状态轮询与 5s 设备枚举搬进 `AudioSection` 的 `State`——别的节显示时不再有定时器（此前只要弹窗开着就一直跑，哪怕人在看日志一节） |
| 内容区要 `Material` | ✅ `Material(bgMain)` + 最大宽 640。**不能是刷底色的 `Container`**：通知一节是 `SwitchListTile`，`ListTile` 把水波纹画在最近的 `Material` 上，垫一层纯色会被 Flutter 断言「ink 会被盖住」——第一次跑测试就撞上 |
| 页面自带 `Scaffold` | ✅ 错误 SnackBar 走 `ScaffoldMessenger`（发给所有注册的 `Scaffold`）；没有它的话，设置页开着时的报错落在被盖住的 shell 上，用户什么也看不到 |
| l10n | ✅ 新增 `backButton`（返回 / Back / 戻る / 뒤로）；删除 `closeButton`——全仓库只剩旧弹窗那个「关闭」按钮在用，改成返回之后就是死键 |
| 测试 | ✅ 4 处改用页面（渲染、连接页入口、增益滑杆、每主题构建）；新增 2 条：左栏切节真的换内容、返回按钮真的回到连接页 |
| **实机看过没有** | ❌ 见 §5.4 |

**macOS 平台（2026-10-01，第一轮）**

细节在 [`docs/macos.md`](docs/macos.md)。**这一轮全部是构建与测试层面的结论，
界面本身没有人看过**——原因见 §5.4 第一条。

| 项 | 结果 |
| --- | --- |
| Rust workspace 在 macOS 上编译 | ✅ arm64，含 libopus。cmake 是 4.4.3（就是 Windows 上出事的那个大版本），`.cargo/config.toml` 的 `CMAKE_POLICY_VERSION_MINIMUM` **跨平台生效**，没报错 |
| `flutter build macos --debug` | ✅ `Nightcord Speak.app`，一条命令 |
| dylib 进了 bundle | ✅ `Contents/Frameworks/libnightcord_ffi.dylib`，arm64，34 个 `nightcord_*` 导出符号 |
| **签名里的权限** | ✅ `codesign -d --entitlements` 实读到 `network.client` 与 `audio-input`——不是只看源文件里的 plist |
| 产品名 | ✅ `CFBundleName` = `Nightcord Speak`；窗口标题与菜单栏同源 |
| 图标 | ✅ 7 个尺寸由 `make-app-icon.py` 生成；**Windows 的 `.ico` 与改动前逐字节相同**（重构没动原产物） |
| `flutter analyze` | ✅ 无问题 |
| Rust 测试 | ✅ 398 全绿（少的那一个是 Windows 专有的 SEH，见 §5.2） |
| Dart 测试 | ✅ 270 全绿 |
| **抓到 1 个真 bug** | ✅ `ts-crash` 的进程存活探测在 macOS 上恒真，见 §6 ⑱ |
| **看界面 / 连服务器 / 语音** | ❌ 见 §5.4（第二轮里前两项补上了，见下） |

**macOS 第二轮（2026-10-01，用户实机反馈后）**

用户双击看了界面，报回四条。逐条查下来，**只有两条是真 bug**：

| 项 | 结果 |
| --- | --- |
| 「检测不到麦克风」 | ✅ **不是 bug**——**这台 Mac mini 没有麦克风**。沙箱外的探针枚举出 0 个输入设备，`system_profiler` 全机只有一个 `Mac mini扬声器`。见 [`docs/macos.md`](docs/macos.md) §5.1 |
| 「播放不出声音」 | ✅ **不是 bug**。用户随后在一台 **MacBook** 上实测：扬声器与麦克风、收发语音全部正常——**macOS 端的语音是通的**，构建节点没有麦克风只是那台机器的硬件现状 |
| 顺带留下两条诊断 | ✅ `pump_audio` 的两条静默返回（没有输出设备 / 队列已满且不排空）加了节流告警，成功路径加一条一次性 `info`。原来这两处是**直接 `return`、一个字都不记**，于是「有人在说话而你听不见」在日志里查不到任何线索。查这轮问题时正是靠它们把范围从「整个音频栈」缩到「混音之后」 |
| **通知不出现** | ✅ **真 bug**，且**三个方向全静默**。`local_notifier` 0.1.6 的 macOS 侧建在废弃的 `NSUserNotificationCenter` 上：Dart 的 `setup()` 在 macOS 上不发原生调用、原生 `deliver` 无条件 `result(true)`、两边都没申请过权限——「坏了」与「正常」在日志里无法区分。换成 `UNUserNotificationCenter` 的方法通道，权限改到第一次真要发通知时申请，回给 Dart 的是「显示了没有」而不是「调用成功了没有」。见 §6 ⑲ 与 [`docs/notifications.md`](notifications.md)。**中间撤回过一次**，见下 |
| **快捷键显示没适配** | ✅ 真 bug 但只是显示：`Chord.format()` 把修饰键写死成 `Ctrl/Shift/Alt/Meta`，在 macOS 上按 ⌘ 显示成 `Meta`、⌥ 显示成 `Alt`。改成按平台拼。**注册路径本身是对的**——`uni_platform` 的扩展会把 Flutter 的 HID usage 查表换成 Carbon 虚拟键码，读插件源码确认过 |
| **默认修饰键改成 Command** | ✅ 用户拍板。macOS 默认改为 ⌘⇧M/D/P，其余平台不变。默认值由 `ts-settings` 拥有，只改 Rust 一处 |
| **⌘, 打开设置** | ✅ 用户拍板走 macOS 惯例而不是全局热键。`MainMenu.xib` 里模板自带的 `Preferences…`（`keyEquivalent=","`）**本来就是个没有 action/target 的死项**，接上即可 |
| 新 Swift 进了产物 | ✅ `strings` 在二进制里找得到 `nightcord/shell` 与 `nightcord/notifications` |
| **快捷键与 ⌘,** | ✅ **用户实测通过**：⌘⇧M/D/P 触发正常，`⌘,` 打开设置正常 |
| **通知** | ✅ **用户实测通过**——但绕了一圈，见下 |

> **通知那一条的弯路值得单独记**：用户报「通知正常」，于是按指示把那套
> `UNUserNotificationCenter` 通道整体撤销。**撤销之后通知立刻不工作**——原来那次
> 「正常」跑在**本身就含新通道的构建**上。
>
> 教训不是「别撤」，是：**判断一个替代实现是否必要，必须拿不含它的构建去测**。
> 拿含它的构建测，测的是替代实现自己。这条对以后任何「我们加了 X 绕过 Y」的改动都成立。
| 编解码往返 | ✅ 新增测试 `a_tone_survives_the_codec_at_its_own_level`（`ts-audio/src/encoder.rs`）：编码一个 0.5 幅度的正弦、再用 libopus 解码、断言电平回来。**两个平台都通过**。这是唯一一处让 `opus_encode_float` 与 `opus_decode_float` 互相验证的地方——`audiopus_sys` 是用当时机器上的 cmake 现场编 libopus 的，而一个「解码恒定为 ±1 LSB」的构建在其他任何测试里都看不出来 |

**Web 客户端第一阶段（2026-10-05）**

- Flutter 复用桌面的状态、频道、聊天、设置与设计系统。浏览器通过 `RemoteTransport` 连接同一套 Rust gateway/core，Native 继续使用 FFI；日志、崩溃、通知与快捷键通过条件导入隔离。
- `AdaptiveShell` 按视口宽度判定：760 及以上使用桌面侧栏，以下使用移动逐级页面导航（用户于 2026-10-05 修订）：主页直接显示频道树，单击频道打开对应频道聊天，单击成员打开私聊；详情通过返回按钮或系统返回回到频道树。设置入口先显示分类列表，再进入具体设置，返回先退回分类。没有隐藏侧栏。本轮 Chromium 真实服务器冒烟验证已确认频道树 → 聊天 → 返回，以及设置分类 → 通知设置 → 返回分类。长按频道切换语音频道，成员长按菜单；移动端提供按住说话按钮并处理松开、取消与失焦。
- 浏览器 Web Audio / AudioWorklet 采集麦克风并播放立体声，PCM 经 WebSocket 交给 Rust 编解码。麦克风权限被拒时可只收听；音频需用户手势启用。设备枚举与选择留在浏览器，总音量与静音同步；未按住 PTT、静音或离开时停止发送本地 PCM。
- 网关维护领域事件快照，新标签页或刷新鉴权后恢复已有会话、频道、成员与状态；订阅和取快照在 worker 内原子完成。聊天历史不重放。修复了设置层提前订阅导致会话层丢失快照的问题，并有回归测试。
- 手动输入的 Token 只在内存与 WebSocket 首帧中使用，不放 URL、浏览器存储或日志。Pages 环境变量注入的 Token 会打包进静态产物，见下方部署约定。每设备独立身份，同设备标签页共享；最后一个标签页关闭后保留 30 秒供刷新恢复，再清理会话。
- 验证：Rust 402 测试、clippy、格式检查；Flutter analyze、292 测试与 `flutter build web --release` 全部通过。窄窗口、频道/成员单击进入聊天与返回、移动设置分类/详情返回、触屏 PTT 取消/失焦及传输边界有测试。Chromium 实测通过网关鉴权、真实 TS3 连接、1280×800 桌面 / 390×844 移动布局切换、刷新恢复同一会话，浏览器无错误。假麦克风捕获和注入立体声播放帧均通过（不等同于人耳或官方客户端的浏览器互通验收）。

本地运行（两个终端）：

```powershell
cargo run -p nightcord-gateway -- --data-dir run/gateway-web
# 默认免 Token；需要鉴权时在服务端设置 NIGHTCORD_GATEWAY_TOKEN。
cd apps/client
flutter run -d chrome
```

自定义网关可在入口填写地址，或用 `?gw=wss://your-host/ws`（不要把 Token 放查询参数）。静态产物位于 `apps/client/build/web/`，CanvasKit 随构建打包。手机访问需 HTTPS 页面 + WSS 网关以取得麦克风；按部署域名配置网关允许的 Origin。尚未部署 Cloudflare Pages，也未验证真实手机 Safari/Chrome 的音频、后台行为和系统通知。浏览器快捷键仅页面内生效，本地日志目录与崩溃报告不适用。PCM-over-WebSocket 仍是第一阶段方案。

**Cloudflare Pages 构建配置与自动连接（2026-10-05）**

- `GatewayConfig.environment()` 读取 Dart 构建定义 `NIGHTCORD_GATEWAY_URL` 与 `NIGHTCORD_GATEWAY_TOKEN`，旧地址名 `NIGHTCORD_GATEWAY` 仍兼容。地址存在时页面自动连接；Token 可不配置。网关 hello.auth 声明 none 时直接接收 welcome；声明 required 时才发送 auth，未提供密钥则显示输入入口。自动连接失败显示可重试表单，不循环重试。
- 浏览器静态应用不能读取部署机器运行时环境变量。`scripts/build-web.py` 将构建进程环境写到临时 JSON，通过 `--dart-define-from-file` 注入 Flutter，结束后删除临时文件；Token 不进入命令参数或脚本日志。改环境变量后必须重新构建部署。
- 配置了 Token 时，`?gw=` 不能覆盖目标地址，避免链接把预置凭据发送给其他网关。**打包的 Token 对站点访问者可见**；Cloudflare 的变量/Secret 标记不能使客户端代码中的值保密。适用于已限制访客的自用部署；每设备独立身份，同设备标签页共享。
- `scripts/build-pages.sh` 在缺少 Flutter 时拉取固定 3.47.5 SDK（可用 `FLUTTER_VERSION` 覆盖），下载字体后调用上述构建脚本。Web 构建不需要 Rust/Opus 工具链。`web/_headers` 令入口和应用脚本重新验证缓存，便于更新配置。

Pages 控制台配置（生产/预览环境各自设置）：

| 项目 | 值 |
| --- | --- |
| Framework preset | None |
| Root directory | 仓库根目录（留空） |
| Build command | `bash scripts/build-pages.sh` |
| Build output directory | `apps/client/build/web` |
| `NIGHTCORD_GATEWAY_URL` | `wss://你的网关域名/ws` |
| `NIGHTCORD_GATEWAY_TOKEN` | 可选；免鉴权部署不用设置，启用时与 Rust 网关相同 |

依据 [Pages 构建配置](https://developers.cloudflare.com/pages/configuration/build-configuration/)：环境变量提供给构建过程，根目录与产物目录独立配置。本项目只将静态 UI 放到 Pages；Rust 网关仍单独运行，由 HTTPS/WSS 反向代理提供访问，并用 `--allow-origin https://你的项目.pages.dev`（及自定义域名/预览域名）允许站点 Origin。构建脚本在 Pages 环境拒绝 `ws://` 配置。

验证：Flutter analyze、292 个测试与环境变量注入的发布构建通过；Chromium 实测无填表自动鉴权、刷新自动鉴权、`?gw=` 不覆盖配置地址通过。构建脚本的 JSON 特殊字符编码、临时文件清理、Pages 强制 WSS 也已检查。尚未在 Pages Linux 构建节点上实际运行安装 SDK 分支。

本地同样可以设置地址环境变量（Token 可选）后运行 `python scripts/build-web.py`。直接 `flutter run/build` 不会自动读取 shell 变量，需要显式 Dart define；推荐使用脚本构建。当前未实际发布 Pages。

**网关鉴权改为可选（2026-10-05，用户决策）**

- 默认 `GatewayConfig.token` 为空，CLI 不再自动生成/打印 Token。未设置服务端 `NIGHTCORD_GATEWAY_TOKEN` 或 `--token` 时免鉴权；配置非空值时启用 Token 校验。空字符串也表示关闭。
- 握手保留协议版本 1：`hello.auth = none` 时浏览器发送设备 `attach` 后接收 `welcome`，不发 auth；`required` 时必须先鉴权，再接收快照与命令。网页默认不显示 Token 字段，服务器要求时才显示。网关内嵌调试页也按 hello 决定是否发 auth。
- Pages 只需 `NIGHTCORD_GATEWAY_URL` 即可自动连接免鉴权网关，不需要在静态产物中放密钥；保留可选预置 Token 兼容自用部署。启用 Token 时，可仅在 Rust 服务端配置，网页连接后由使用者手工输入。
- Origin 白名单、WSS、消息长度与命令边界照旧；是否要求凭据完全由服务端决定。免 Token 的访客仍须自动提交设备凭据，仅能操作该设备的会话。
- **修订 `docs/gateway.md` 中 Token 必填、默认随机生成的旧设计**：本段与实际代码优先，该文保留原轮设计记录。原来的 Pages 构建说明中地址和 Token 都必须存在也已被本段替代。
- 回归验证覆盖免 Token 的真实 WebSocket 命令往返，以及浏览器传输不发送 auth、URL 单独配置即可自动进入应用、受保护网关缺 Token 被拒；已启用模式的正确/错误 Token 测试继续保留。402 个 Rust 测试、292 个 Flutter 测试、clippy、格式与 analyze 通过；Web 发布构建和 Chromium 无 Token 自动连接/刷新实测通过。CLI 启动输出回归测试已改为默认不生成、不打印 Token。

**Web 每设备独立身份（2026-10-05，用户决策）**

- 取代 `docs/gateway.md` 的「一个网关一个共享身份」设计。每设备实例化同一套 Rust Core，隔离身份、设置、书签、会话、事件与语音；同设备标签页共享。没有复制 Core 或协议实现。
- Web 设备边界是浏览器个人资料、站点 Origin 与网关地址。localStorage 保存随机设备编号与恢复凭据，兼容局域网 HTTP；刷新与再次访问复用。清除网站数据、无痕模式或换浏览器会产生新身份，不读取硬件指纹。TS 私钥始终只在服务端。
- 数据位于 `<data-dir>/devices/<设备编号>/`，包含身份、设置、书签和 `access.key`。恢复须匹配随机密钥，知道公开编号不能接管；凭据不进日志、URL 或 Debug。旧共享身份文件保留，新设备创建新身份，服务器权限需按新身份分配。
- protocol 1 新增 `hello.device = required`；免 Token 发送 `attach`，启用 Token 则在 `auth` 中同时携带设备凭据。Token 控制进入网关，设备凭据控制隔离与恢复；前端自动处理，无需用户输入。浏览器不能发送 `shutdown` 关闭网关。
- 最后一个标签页关闭立即释放 PTT，保留 Core 30 秒供刷新，每 5 秒清理，所以约 30–35 秒自动断开 TS；身份与设置持久化。最多保留 64 个活跃设备 Core。清理完成前不重新启动同一身份，避免重复登录。
- 回归覆盖不同设备隔离、同设备共享与恢复、伪造凭据和非法编号拒绝，以及语音帧隔离。405 项 Rust 测试通过。Chromium 两个独立浏览器上下文同时连接真实 TS3，确认不同 client id 与 unique id；刷新 A 恢复原会话，B 保持独立。Flutter analyze、295 项测试和 Web release 构建通过。
- 未停止用户运行中的旧网关。最初根目录 exe 被 Windows 占用，验证构建放在 `run/device-target/debug/nightcord-gateway.exe`；旧进程退出后已成功重新构建 `target/debug/nightcord-gateway.exe`。使用新行为须重新启动网关，同时重启或重新部署 Web 客户端。Rust clippy 全工作区、格式检查与 5 项启动脚本测试通过。

- 用户要求代为启动后，已后台启动网关 `0.0.0.0:8787` 与发布版 Web 静态服务 `0.0.0.0:5173`；保持原 Token，构建时自动注入局域网网关地址及 Token。Chromium 手机视口访问 `http://192.168.31.95:5173` 已确认自动鉴权成功。进程号与日志保存在忽略的 `run/live-*` 文件，未弹出终端窗口。

**手机白屏调查与启动提示（2026-10-05）**

- 用户报告手机访问白屏，尚未提供访问地址、手机系统和浏览器；**实际站点的根因未定位，不能认为已经修复该手机问题**。
- 确认了独立缺口：旧 `index.html` 在 Flutter 首帧之前没有加载状态，bootstrap/CanvasKit 初始化失败只进控制台，用户看到空白。新增不依赖 Flutter 的启动提示、resources/renderer/app 阶段、失败重载入口及 30 秒等待提示；首帧移除提示，不展示原始错误/敏感数据。
- `flutter_bootstrap.js` 显式等待引擎初始化与 runApp 并捕获失败；Pages 对 startup/audio/worklet 脚本补充缓存重新验证。需要重新构建和部署才能在用户访问的站点生效，本轮未部署。
- 本地发布构建通过。Chromium 与 WebKit 26.5（iPhone viewport 模拟）启动通过；模拟阻断 CanvasKit wasm 时，两种引擎均显示 renderer 失败提示。**WebKit 模拟不是 iPhone 真机验收**，且实际页面的网络/缓存/浏览器版本仍待检查。
- 新增 5 个独立 Node 回归测试：脚本加载失败、渲染拒绝与敏感内容隔离、慢加载提示、首帧移除提示、bootstrap 引擎失败。运行 `node --test apps/client/test/web_startup_test.cjs`，全部通过。

**局域网手机启动补充（2026-10-05）**

- 用户确认手机通过电脑局域网地址访问；桌面启动命令为 `flutter run -d chrome --web-port 5173`，网关通过环境 Token 启动现成二进制。不能再把页面问题解释为手机输入 localhost。
- 在本机 LAN HTTP 分别验证：发布版 Chromium/WebKit 启动正常；Flutter 调试版 Chromium 正常，但 WebKit 报 `new window.AudioContext()` 构造失败，堆栈位于 `dart_sdk.js` 的 DDC runtime polyfill，发生在项目代码加载前。SDK 源码 `private/ddc_runtime/runtime.dart` 确有未经能力检查构造 AudioContext 的分支。**这是本地 WebKit 模拟复现，不足以断言用户安卓 Chrome 也是同一错误**；用户手机真实堆栈仍缺。
- 手机联调使用发布模式 web-server：`flutter run -d web-server --release --web-hostname 0.0.0.0 --web-port 5173`，手机打开电脑局域网 IP 的 5173。不修改 SDK 或伪造浏览器音频 API。已在 5174 独立测试同一发布模式命令，Chromium/WebKit 在真实 LAN HTTP Origin 都通过启动；测试服务已结束。293 个 Flutter 测试及 analyze 通过。
- 另有独立连接问题：默认 gateway 只绑定回环，网页原默认 ws://localhost 会指向手机。已修复未配置地址时使用页面 hostname + 8787，显式配置的地址与 Token 目的地不改写，并有回归测试。网关 LAN 访问需要重启时添加 `--bind 0.0.0.0:8787 --allow-origin http://电脑IP:5173`；当前用户运行的网关没有被修改或停止。
- LAN HTTP 可测页面与命令，麦克风仍要求 HTTPS 安全上下文；正式 Pages 部署继续使用 HTTPS + WSS。

**TS6 屏幕共享（2026-10-07）**

用户要求参照 `D:\CodeProject\Reference\webspeak3` 实现 TS6 的屏幕共享收发，
并拍板了媒体层的分工（Rust 管信令、`flutter_webrtc` 管媒体）。设计记录见
[`docs/screen-sharing.md`](docs/screen-sharing.md)，那里有线路词汇、三个坑和
每一项约束的理由。**这一轮全部是单测与静态检查的结论，没有和真实 TS6 服务器
互通过**——下表 ✅ 一律只表示测试通过。

| 项 | 结果 |
| --- | --- |
| 形状 | ✅ 信令走已连接的命令通道，画面走**独立的 P2P WebRTC 连接**。回答了 `docs/ts6.md` 留的那个前提：既不复用 UDP 语音通道，也不是「另开一条信令通道」 |
| 分工 | ✅ `ts-model` 出领域词汇 → `ts-protocol::ScreenSharing` trait → `ts-protocol-ts6` 是**唯一**知道 `setupstream` 等字面量的地方 → FFI/网关原样转发 → Flutter 的 `ScreenController` + `ScreenShareBackend` |
| 为什么是 `flutter_webrtc` | ✅ 六端目标下落地更快；TS6 协议仍完整留在 Rust，换媒体实现的边界就是 `ScreenShareBackend` 这一个接口 |
| 六个命令 | ✅ `requeststreaminfo` / `setupstream` / `stopstream` / `joinstreamrequest` / `respondjoinstreamrequest` / `streamsignaling`，4 条测试盯编码、枚举取值与超长拒绝 |
| **`answer` 的键名不对称** | ✅ 提议用 `args.offer`、应答用 `args.answer`、ICE 用 `args.{sdp,mid,mLine}`。这是对端的期望，测试盯着 |
| **参数值必须 `get_str()`** | ✅ `UnknownCommand` 的 `content` 仍带 TS 转义，而 `CommandArgumentValue` 没有 `Display`——第一版用 `to_string()` 根本没编译过。SDP 里全是空格换行与反斜杠，拿转义形态解析会得到坏 SDP |
| 流 id 由服务器给 | ✅ 客户端不选 id，所以「点了共享」与「拿到 id」是两件事：没拿到就取消时发不出 `stopstream`，等服务器补来 `available` 才补发。**第一版就是在这里漏了一次停止**，有回归测试 |
| 入站命令的透传 | ✅ `StreamItem::UnknownCommand` → `ScreenExtension::decode`，通用层只认领域事件；TS3 后端不装这个扩展，命令回 `Unsupported` |
| 入口按能力位 | ✅ `capabilities.screen_stream`，不是协议版本号。TS3 上整个面板不出现（有 widget 测试）。**这条一开始是坏的**：后端从没发布过 `CapabilitiesChanged`，见 §6 ⑳ |
| 能力位真的会到 | ✅ `refresh` 里紧跟 `Connected` 发布 `CapabilitiesChanged`；两侧的名字各有一条测试钉住 |
| 发布端的码率与降级策略 | ✅ `setLocalDescription` **之后**才读 sender 的 encodings（之前是空的，两个设置都写丢了，见 §6 ㉒）；`degradationPreference` 选 `maintain-framerate`；`setParameters` 的返回值与读回来的参数都进日志 |
| 发布端的读数 | ✅ `getStats()` 每秒轮询显示在浮动小窗标题里（分辨率 · fps · 谁在限制），每 10 秒进一次 `info` 日志；一条控制器测试盯着轮询会随共享起停、同一读数不重复唤醒 |
| 收端不依赖 `msid` | ⚠️ **只有代码路径**：`streams` 为空时自建 `MediaStream`。要真的验，得和一个不带 msid 的发端连一次（TS6 官方客户端就是），`flutter_test` 里做不到 |
| 渲染器真的拿到流 | ✅ `renderer.muted` 整个删掉（它会把 `_init` 打断在 `srcObject` 之前，见 §6 ㉓）。同样是**只有代码路径**——`flutter_test` 里没有 `RTCVideoRenderer` |
| 浮动小窗能拖 | ⚠️ widget 测试（**鼠标**驱动）按在空隙上也要动、指针动多少窗口动多少；但**同一套测试在真机上已经骗过一次**，见 §6 ㉔。拖动走 `Listener`，第一次移动会落一行日志——真机到底有没有拿到指针，看日志 |
| 协议路径的日志 | ✅ 每条命令与事件一行 `info`（只有类型、stream id、client id；SDP/ICE 不进日志，§4.5）。㉓ 就是靠它定位的 |
| SDP / ICE 不进日志 | ✅ 三个领域类型的 `Debug` 手写成 `<redacted>`（§4.5），有测试 |
| 生命周期 | ✅ 8 条控制器测试：先 offer 后 ICE、迟到的采集被关掉、频道切换/断线收摊、观看上限本地拒绝、系统停止共享、被拒绝、订阅者离场 |
| 入口的界面 | ✅ 3 条 widget 测试：按能力位显示且住在底栏里、按钮 → 命令 → 状态往返、从成员行进出一个共享 |
| **界面按「这件事是谁的」分** | ✅ 发起/停止在**底栏 AFK 左边**（是我的状态，和离开、静音同类）；观看/停止观看是**成员行上那个徽章本身**（事实与入口是同一件事的两个视角）；画面是**浮在聊天上的小窗**（可拖、可全屏、可关）。用户定的，第一版是聊天上方常驻的一条 |
| 文件与依赖 | ✅ 新增 `ts-protocol-tsclient/src/extension.rs`、`ts-protocol-ts6/src/screen.rs`、`ts-model/src/screen.rs`、Flutter `core/screen/` 与 `features/screen/`；`flutter_webrtc` 是新依赖，Windows 侧要为它加 `/utf-8`（插件源码的 UTF-8 注释在 `/WX` 下会被 C4819 打成错误） |
| 采集参数可调 | ✅ 预设 / 分辨率 / FPS / 视频与音频码率 / 隐私 / 观众限制 / 连接模式，从 `settings.json` 一路到 `setupstream` 与编码器；越界值在 `ts-protocol-ts6` 被拒（连接模式的「服务器」明确报未实现） |
| 两步向导界面 | ✅ 选择来源（分页 + 缩略图/实时画面）→ 设置（基本 + 可折叠高级）→ 开始直播；设置在点「开始直播」时才写盘 |
| **独立窗口** | ✅ 观看别人的共享时可以「弹出」到自己的系统窗口（Windows；macOS/Linux 未验）。两个窗口是两个引擎，**纹理不能跨引擎**，所以是交棒而不是搬家：新窗口自己开连接、主窗口让开。真实 TS6 上跑通过连续三轮弹出/原生关闭/重新观看，返回小窗也通过 |
| **多引擎的三个插件缺陷** | ✅ 都得打补丁，因为都在 `flutter_webrtc` 的 C++ 里：① 每个引擎析构都调**进程级**的 `LibWebRTC::Terminate()`，关一个子窗口会拆掉别人还在用的运行时；② 事件通道的 messenger 是**全局缓存**的，指向最后注册的引擎，子窗口一关就悬空（第二次弹出必崩）；③ `onTrack` 里 cascade 用错，有远端流时也会调 `addTrack`，原生只查本地表，于是报 `stream is null`。补丁在 `apps/client/windows/cmake/webrtc_multi_engine.cmake`，**在构建树里生成打过补丁的副本，不动 Pub 缓存**，上游一变就构建失败要求重新审查。**仅 Windows** |
| 快速重开会触发服务器限流 | ✅ `ClientIsFlooding`：每轮每个候选单发一条信令，几次开关就耗尽命令预算。改成最多等 2 秒把候选并进 SDP，并对 `0x020c` 做两次延迟重试（策略留在 TS6 crate，core 与 UI 不认协议错误码） |
| 来源选择器的预览 | ✅ 改用插件自带 `getDesktopSourceThumbnail`（异步请求更新、立即返回缓存），**不启动会置前的采集路径**；空缓存有限重试，失败保留选择而不回退到采集 |
| **采窗口会把窗口提到最前** | ✅ **用户 2026-10-08 确认已解决**——仓库里没有对应改动可核对（cmake 补丁、提交、已下载的 DLL 都没有聚焦相关代码），**按实测为准记录**。⚠️ 调查中「它用的是 GDI 采集器、只能自己重写发布端」的推论**已撤回**（从 DLL 符号推出来的，不成立）；完整证据链见 [`docs/screen-sharing.md`](docs/screen-sharing.md) |
| 门禁 | ✅ 422 Rust + 345 Dart、clippy、格式、`flutter analyze`、Windows release 构建、Web release 构建全部通过 |

> **本轮接手时的状态**：上一个 agent 在实现中途停下，留下未格式化的代码和六处
> 被补丁脚本割裂的文档注释（新函数顶了邻居的注释）。接手后跑通全部门禁、补上
> 界面测试、整理文档。**改动的实质内容没有变**，只是补完与收尾。

**屏幕共享的音频与观看授权（2026-10-08）**

上一轮代码审查留下的两项（§6 ㉗㉘）。**全部是单测与静态检查的结论**——真机试听与
真实服务器上的审批走查都还没做（见 §5.4），下表 ✅ 一律只表示测试通过。

| 项 | 结果 |
| --- | --- |
| 音频真的进 offer | ✅ 后端测试：采集产出的视频与音频轨都被加进连接；画面拿 `video_bitrate_kbps` + 降级偏好，声音**只**拿 `audio_bitrate_kbps`——`degradationPreference` 是画面的事 |
| 线上如实报音频 | ✅ 控制器测试：采集有音轨→`audio=1`；没有→`audio=0`。macOS 与 Linux 的插件没有 loopback 采集器（Linux 是返回 `nullptr` 的 stub），开着的开关是一个无法兑现的承诺，如实报 0（参考实现同一规则） |
| 采集侧 | ✅ 原本就对：`capture` 一直带着 `{'audio': options.audio}`。插件的 Windows 实现带 WASAPI loopback，选窗口来源时按该窗口的进程定向——**测试没碰过原生路径** |
| 观看端 | ⚠️ **只有代码路径**：原生由 WebRTC 自动播放（未实机听过）；Web 渲染器把远端音轨接到隐藏的 `<audio>` 自动播放（插件源码核对，非实机） |
| 私密/联系人逐个批准 | ✅ 控制器 7 条：进队列、批准即应答、拒绝即应答且不建连接、撤回作废、停共享清理、离开服务器清理、批准可超过上限；页面 1 条：弹窗出现 → 按「允许」→ `respond` 走的是同一条 `_admit` |
| 授权为什么在客户端 | ✅ **服务器不做守门人**——参考实现在真实服务器上证实：它存下 `accessibility` 与 `viewer_limit`，然后照样转发每个请求。所以 `join_requested` 里「公开放行 / 非公开进队列」就是全部的执行 |
| 满员仍是到达即拒 | ✅ 本地闸门的既有决定保留；**发布者亲手批准可以超过上限**——上限压的是自动放行，人读过名字后说 yes 不是自动（参考实现同此）。两处都写进 [`docs/screen-sharing.md`](docs/screen-sharing.md) |
| 「屏蔽」按钮 | ❌ 不做（参考实现有：拒绝不粘、同一个人能一直问）。TS6 自己的命令预算压着刷屏，真被烦到再加，位置就是这个控制器 |
| 门禁 | ✅ 422 Rust + 354 Dart、clippy、格式、`flutter analyze` 全绿 |

### 5.4 未验证

- ~~macOS 的通知、`⌘,`、快捷键~~ ——**用户实测全部通过**（见 §5.3）。
- ~~macOS 上的真实服务器与语音~~ ——**已由用户在一台 MacBook 上实测通过**：连接、扬声器、
  麦克风、收发语音都正常。构建节点（Mac mini，无输入设备）上听不到声音，是那台机器的
  硬件现状，不是平台限制；[`docs/macos.md`](docs/macos.md) §5.1 记了怎么一眼看出机器
  有没有输入设备。**麦克风那个 TCC 对话框长什么样仍未记录**。
- ~~官方客户端语音互通~~ ——用户于 2026-10-05 确认已完成并测试无误。不同真实立体声源的听感比较尚未记录；本次确认不等同于浏览器端语音验收。
- **音量**：总音量与单人音量的即时性、以及总音量跨进程重启后是否还在，待实机。
- **poke / kick / ban**：命令链与权限门控有单测，**没有对真实服务器发过一次**。
- ~~窗口最小尺寸~~ ——**用户实测确认挡住了**（macOS 侧；Windows 的 `WM_GETMINMAXINFO` 用的是同一个数，机制不同）。150% 缩放那一条仍未单独试过。
- **设置页**：左栏切换、返回、六节各自的观感只有单测与静态检查，**没有人在真机上点过**；
  尤其没试过窗口拖到 960 下限时内容区（960 − 240 = 720）的样子。
- **麦克风增益**：换算、clamp、存储、滑杆曲线、两处 UI 都有单测，**没有人真机听过**
  ——「别人听到多大声」这件事只有耳朵能判断，而且增益在本地没有监听回路（听不到自己）。
  +10 dB 会在本来就响的时候削波，这是刻意的（把麦克风拧大就是这个后果）。
- **恢复默认快捷键**：命令链（`reset_shortcuts` → FFI → transport → settings）有单测与
  FFI 往返测试，按钮「按哪一行问哪一行」有 widget 测试，**但按钮改完还没被人点过**
  （用户报「看不见」时用的是第一版裸图标）。键名表（§6 ㉕）也只有测试与一次离屏渲染
  看过——**没有在新的 release 构建上再确认一次**。
- **离开状态**：命令链、三态折叠、持久化、对话框都有单测，**没有对真实服务器发过一次**。
  要确认的是外部视角：点一下离开，**别人的客户端**（第二个客户端或 CLI）是否看到离开标记
  与那句话；改一条消息重启应用后是否还在；再点回在线标记是否消失。
  另外有一条**已知副作用**（有意保留）：库把 away 当成 mute，离开期间发不出语音
  ——见 [`docs/ts3.md`](docs/ts3.md) §11。
- ~~频道切换、退出清理~~ ——用户于 2026-10-05 确认均已完成并测试无误。
- **屏幕共享**：命令编码、状态机、入口都只有单测。用户 2026-10-07 实测过三轮，报回来
  四条、修掉四个真 bug（§6 ㉑–㉔）；**㉑ ㉒ 与「采窗口会把窗口提到最前」已由用户于
  2026-10-08 确认可用**（置前那条仓库里没有对应改动可核对，按用户实测为准，见 §9 的
  2026-10-08 记录）。第二轮拿到的读数（**发布端自报 `1280x720 5fps (bandwidth)`**，
  被带宽估计卡住而不是 CPU）仍是 `maintain-framerate` 要不要翻过来的依据——设上了却
  仍然这样就该换成限制分辨率（参考实现选的就是保分辨率）；下一轮看小窗标题里
  `limited-by` 写的是 `cpu` 还是 `bandwidth`。
  **仍未验证**的是 2026-10-08 新加的音频与观看授权：Windows loopback 的屏幕声音真响
  不响、macOS/Linux 如实报 `audio=0` 的路径、私密共享的批准弹窗对真实服务器走一遍
  （批准 → 观看者拿到画面；拒绝 → 观看者看到「被拒绝」）。其他没验过的：能不能收到
  官方客户端的共享、跨 NAT、以及那些平台差异（macOS 屏幕录制权限、iOS Broadcast
  Extension、浏览器 `getDisplayMedia` 的手势与安全上下文）。
- Android / iOS 原生脚手架尚未建立。Web 已实现，尚需 iOS Safari / Android Chrome 真机与人耳语音验收；HTTPS/WSS 部署尚未进行。
- **重连循环没有跑通过一次真实掉线**。原计划用本机 TCP 中继制造掉线，但在这台机器上
  做不到：`nightcord-cli.exe` 连不上任何本机监听（3ms 内被 RST；同一时刻、同一次调用里
  一个普通 Rust 探针却能连上），而放在项目目录之外的二进制又连不出去。这是环境的
  按进程网络策略，不是代码问题——但它意味着「库报掉线 → 退避重试 → 恢复」这条路径
  目前只有编译期与单元级的保证。
  要真正确认：连上之后停掉 TS3 服务器（或拔网线），看提示条出现、倒计时走秒、日志里
  出现 attempt 序列，再把服务器起回来确认自动恢复、频道树与聊天记录都还在且无重复。

---

## 6. 过程中修掉的真 bug

前四个都是「**前端对 core 的认知与实际不符**」，都只有真正跑起来才暴露——
单元测试全绿、CLI 也正常。⑤ 是同一类（UI 落后于后端能力），只是这次是在读代码
时撞见的。⑥⑦ 是补功能那轮里新写的代码被抓出来的，抓它们的是刚写下的测试与
`flutter analyze`。⑯ 也是同一路数：长按那条测试刚写下就红了，红得有价值——
它跑在默认的 Android 目标平台上，而长按在那里根本到不了我们的处理器。

⑱ 是另一类，第一次出现：**平台假设从没在另一个平台上跑过**。那段代码在 Windows
上是对的、在 Linux 上也是对的，唯独 macOS 上是错的——而 macOS 是这轮才加的。
抓到它的不是新写的测试，是**把已有的测试换一台机器跑**。

⑲ 是 ⑱ 的同源版本（移植到 macOS），但错在**依赖**而不是我们自己的代码：插件声称支持
macOS，实际那条路径是空壳，而且**把失败报成了成功**。它的教训不是「换个包」，是
**「不可见也不落日志」比「报错」坏得多**——⑲ 直接违反了 M0.6 立下的那条不变式，
所以修法的重点在于让回答变成真的（回「显示了没有」而不是「调用成功了没有」）。

它中间被撤回过一次：用户报「通知正常」，于是按指示整体撤销；**撤销之后通知立刻不工作**
——那次「正常」跑在含新通道的构建上。真正该记的是**怎么测一个替代实现**：
**要拿不含它的构建去测**，否则测的是它自己。这条已经写进 [`docs/notifications.md`](notifications.md)。

㉕ 又是另一类，而且这次的「另一个环境」不是别的系统而是**另一个构建模式**：那段代码在
debug 下对、在测试里也对，唯独 release 下是错的——因为它读的 Flutter API 只在
`assert` 里被填上。**这个仓库的所有测试都跑 debug**，所以这一类没有任何测试能抓到；
能做的只有把它写在文件头，让下一个读代码的人不必先踩一遍。

| ⑳ | **屏幕上根本没有屏幕共享的入口** | `CapabilitiesChanged` **定义了、序列化了、Dart 也处理了，就是没有任何后端发布过它**。`ServerView.capabilities` 因此永远是默认的全 false，而 `server_page.dart` 正是用 `capabilities.screenStream` 决定要不要画那个面板。core 侧只有**拉**的 API（`Session::capabilities()`，CLI 用的是它），前端只有**推**的这条路——两边各自都对，中间没人连线。单元测试全绿：`capabilities()` 本身有两条测试，前端那条测试自己 `new` 一个事件喂进去 | 在 actor 里**紧跟 `Connected`** 发布：能力集是协议的函数（`Capabilities::for_protocol`），而 `Connected` 已经在那个分支里发了，两件事不该有先后（`actor.rs` 的 `refresh`）。回归测试分两半：Rust 侧钉住线路上 `capabilities_changed` + `screen_stream` 这两个名字（`ts-events`），Dart 侧改用 `ClientEvent.fromJson` 解真实载荷而不是手搓事件——**前端测试自己造事件，正是这条 bug 藏了这么久的原因**（同 §6 ⑫ 的教训）。**用户实测报上来的** |

| ㉑ | **收不到别人的共享**，但别人看得到我的 | `onTrack` 里有一句 `if (event.streams.isEmpty) return;`——而**发端没有义务在 offer 里放 `msid`**：TS6 官方客户端就没放，轨道到达时 `streams` 是空的。于是连接建起来了、画面永远不来，**而且一个字都不说**。我们自己发的 offer 带 msid（`addTrack(track, stream)` 会给），所以只有「我们当观看者」这一半是坏的——正好是用户报的那一半 | 按参考实现的做法：`streams` 为空时**用 `event.track` 自己搭一个 `MediaStream`**（它的 `ontrack` 一直就是这么写的，从不依赖 `streams`）。顺带在协议路径上加了逐条 `info` 日志（只记类型与 id，SDP/ICE 一律不进日志），下一次失败至少能看出停在哪一步。**用户实测报上来的** |
| ㉒ | **共享的画面帧率低** | `_Peer.offer` 在 `setLocalDescription` **之前**读 `sender.parameters.encodings`——而 sender 的 encodings **要到设了本地描述之后才存在**，所以那句 `if (encodings != null && encodings.isNotEmpty)` 从来没进去过：码率上限和 `degradationPreference` 都写进了一个空列表，整条流一直跑在 libwebrtc 的默认值上。参考实现专门用一段注释记了这件事 | 把参数搬到 `setLocalDescription` 之后，并补上 `degradationPreference`。选 **`maintain-framerate`**（保帧率、必要时缩分辨率），和参考实现**相反**——它保分辨率是因为共享的多半是文字，而这一版是被「帧率低」报上来的。`setParameters` 的返回值和读回来的参数**都进日志**——原来那个 `catch (_) {}` 会把「没设上」和「设上了」写成同一个样子，这正是它第一次没被发现的原因 |
| ㉓ | **共享的画面在屏幕上永不出现**（两侧都是，包括自己的预览） | `_VideoState._init` 里有一句 `renderer.muted = media.local`。`RTCVideoRenderer.muted` **不是**「别把自己的声音播回来」，而是**拿流的第一个音频轨去静音麦克风**：没有 `srcObject` 时抛、流是远端的也抛、没有音频轨还抛。屏幕采集是 `audio: false`，所以三种情况全中——**异常在设 `srcObject` 之前就中断了 `_init`**，`ready` 永远是 false，渲染器一次都没拿到流。信令全程正常，日志里只有一行 `Can't be muted: The MediaStream is null` | 整句删掉：共享只有视频，本来就没有可以回授的声音。**这是用户报「看不到画面」时，靠新加的协议日志一眼定位的**——那批日志是上一轮为了查 ㉑ 才加的 |
| ㉔ | **浮动小窗拖不动**，鼠标和窗口不同步 | 查了三层，前两层是真的、第三层没定：① `GestureDetector` 用默认的 `deferToChild`，而 `Row` **只在有子控件的地方**参与命中测试——标题、读数、按钮之间的空隙全按不动；② **只有顶上 32px 的标题条能拖**，而那块 320×180、占窗口八成面积的画面拖不动，手最先抓的偏偏是它；③ 用户复测仍报「拖不动/不同步」后，**换 `Listener` 直接拿指针事件**——不参与手势竞技场、不等滑差，并把「收到指针了没有」记进日志。**同时发现一个更大的混淆项：一直在给 debug 构建**，而 debug 的 Flutter 光栅化慢一个数量级，720p 视频纹理 + 调试版 Dart VM 完全可能把「窗口跟不上鼠标」做成真的。改成 release | 拖动覆盖**整个窗口**（两个按钮更深、照样赢走点击）；`_DragArea` 用 `Listener` + `HitTestBehavior.opaque`。第一次移动记一行日志，**只记「指针有没有到」不够，第二次报上来时那行确实出现了**——于是日志升级成把四个数一次写全：`screen: dragged by Δ on state=… bounds=… before -> after`。State 的哈希是给「`_at` 每帧被扔掉」那个假设用的：保留着 `_at` 却不动的窗口，和每帧重置 `_at` 的窗口，从外面看一模一样。同时修掉一处真的钉死：`_clamp` 的房间写成 `(extent - size).clamp(0, ∞)`，面积比窗口小时塌成 0，于是**任何位置都被钳到 0**——没有信息时不该默认禁止（§4.4），改成「没有余地就不夹」。回归测试用**鼠标**驱动（第一版用触摸，测试过了而真机没有），断言按在**空隙**上也要动、指针移多少窗口移多少、以及**面积装不下时仍能动** |
| ㉕ | **release 构建里快捷键显示成 `Ctrl+Shift+0x70010`** | `Chord.format()` 的键名取自 `PhysicalKeyboardKey.debugName`，而 Flutter 把这个 getter 填在 `assert` 里——SDK 自己那行注释就是「will be null in release mode」，`_debugNames` 那张表也是 `kReleaseMode ? {} : {…}`。于是 debug 构建与全部测试读 `Ctrl+Shift+M`，**用户拿到的 release 构建读十六进制**（`0x70010` 就是 `Key M`），启动日志那行 `shortcut mute is …` 同样是它。测试全绿是因为**测试只跑 debug**——这是 §6 ⑱ 的同源版本，只是这次漏掉的是构建模式而不是平台 | 键名表改由我们自己拥有（`lib/util/key_names.dart`）：USB HID usage → 名字，拼写照 Flutter 的（`Arrow Left`、`Audio Volume Mute`），两种构建下一致；表里没有的码仍回落到十六进制，那正是 `settings.json` 里存的东西。函数收 usage 的 `int` 而不是 `PhysicalKeyboardKey`，`debugName` 因此不在伸手可及之处。回归测试钉住一批键名与回落值——**它抓不到这类回归**（依旧只在 debug 跑），所以「为什么不能用 Flutter 的」写在那个文件头上。**用户实测报上来的** |
| ㉖ | **release 构建里新加的图标不显示**——用户看到的「按钮里面一点东西都没有」 | 图标字体在 release 下会被 tree-shake：`build/flutter_assets/fonts/MaterialIcons-Regular.otf` 只有 8 KB，是 `font-subset` 按 **kernel 里出现的 `IconData` 常量**裁出来的子集。那份子集生成于 21:50，而「恢复默认」按钮（22:00 才写）用的 `settings_backup_restore` 不在其中——**22:07 与 22:39 两次 release 构建都没有重新生成它**（文件 mtime 一动不动），于是那个字形在实际交付的构建里根本不存在。核对方式：解出子集的 cmap，与 `lib/` 里用到的 `Icons.*` 逐个比——55 个里只有这一个不在，其余都在（所以不是子集整体过期）。debug 构建不 tree-shake（字体是完整的 1.6 MB），`flutter test` 也不经过它，**这件事在任何测试与调试构建里都看不见** | 删掉 `build/flutter_assets/fonts/MaterialIcons-Regular.otf` 再构建：子集输出缺失，构建系统才会重跑 `font-subset`，重新生成的子集 67 个字形、含 `U+E582`。**「加个图标再 build 一次」是无效的**——kernel 变化不会让这个目标变脏；`flutter clean` 同样有效，代价是一次全量重建。排查手法：用 `fontLoader` 把 SDK 的**完整**字体塞进离屏渲染，量的是完整字体，**与用户手上那份不是一回事**（这一轮就是这么被骗过去的） |
| ㉗ | **「捕获音频」打开了，观看者听不到任何声音，而且一个字都不报** | 设置一路走通——采集请求了音轨（`getDisplayMedia({'audio': true})`）、`setupstream` 的 `audio=1` 也发了——唯独 `offer` 只把 `getVideoTracks()` 加进连接：音频轨道采集出来后就没人管了。两份代码各自都「对」，中间没有人连线（与 ⑳ 同型：定义、序列化、 UI 全在，就是没接上） | offer 改加采集产出的**全部**轨道；音频发送者只设码率上限（`degradationPreference` 是画面的事）；线上 `audio` 改为以「采集真的产出了音轨」为准——macOS 与 Linux 的插件没有 loopback 采集器，开着的开关如实报 0（参考实现同一规则）。三条测试：控制器（wire 跟随采集）、后端（两条轨道各拿各的参数）、向导（选择真的到线上） |
| ㉘ | **「私密」和「联系人」共享与公开没有区别——同频道谁点谁能看** | 两档只作为 `accessibility` 2/3 发给了服务器，而**服务器不做守门人**：它存下设置、把每个观看请求照样转发（参考实现在真实服务器上证实）。客户端这边 `join_requested` 只查观看上限就一律放行——而界面的帮助文案早已写着「联系人按私人处理」，说的是一件不存在的事 | 非公开共享的请求进待批准队列，发布端弹窗逐个允许/拒绝；批准与公开共用同一段 `_admit`。满员仍是到达即拒（本地闸门的既有决定）；**发布者亲手批准可以超过上限**——上限压的是自动放行（参考实现同此）。控制器测试 7 条 + 页面 1 条 |

| # | 症状                           | 根因                                                    | 修法                                                          |
|---|--------------------------------|---------------------------------------------------------|---------------------------------------------------------------|
| ① | 两台在线服务器都显示「未连接」 | `ConnectedEvent` 不设连接状态；后端只在重连时发状态事件 | 前端由 `connected` 事件置位；后端把状态变更与事件发布**绑定** |
| ② | 聊天输入框始终禁用             | 权限提示缺失被当成「拒绝」（hints 是**可选**的）        | 缺失 = 未知 = 放行；服务器仍是权威                            |
| ③ | 启动语音前按静音弹红错         | 无引擎时报 `NoInputDevice`——既不该报错，解释也是错的    | 记成 **intent**，`start_voice` 时应用                         |
| ④ | 核心主动报的错误**完全不显示** | `ErrorEvent` 被 `server_view.dart` 归入「不参与渲染」而 `break` 掉，既没提示也没 SnackBar——握手失败、掉线、重连拒绝时频道树就那么僵着。日志里有，用户看不到 | `providers.dart` 里让它也走 `lastErrorProvider`，于是自动获得提示与日志（做 logging 时顺带发现） |
| ⑤ | TS6 早已可用，连接页却拒绝选择 | 分段按钮的 `enabled: false` 与「TS6 后端尚未实现」停留在 M0.4 之前；M0.4 实测通过后没人回头改 UI | 启用分段、删掉过时提示（做本地化扫荡到该文件时发现）          |
| ⑥ | 单人音量在对方「停说再开口」后丢失 | 采纳逻辑写在 `handle_item` 里，与队列创建**可分离**——而 `tsclientlib` 会在说话人停下时删掉队列 | 合并进 `Audio::receive`，使队列的创建与音量的施回**不可分**。回归测试当场抓出 |
| ⑦ | 连接页标题行溢出 22 像素 | 加了设置按钮之后，`Text` + `Spacer` 的组合在窄窗口下放不下三样东西 | 标题改 `Expanded`（可省略号），按钮留在右边 |
| ⑨ | **关掉软件，服务器那边还挂着** | `NightcordClient::shutdown` 的文档注释**早就写着**「Sessions are disconnected on the way out」——而 worker 收到 `Command::Shutdown` 只是 `break`。更外层：Dart 的退出回调也只调了 `markCleanExit()`，从没叫过 core 停 | worker 收到 Shutdown 先 `disconnect_all()`；Dart 的 `onExitRequested` 改成 `dispose()`（它阻塞到 worker 真的停下，顺带只在干净停止时才标 clean——比原来那个调用更严） |
| ⑮ | **在线人数有人进出也不动** | 上一行那个 `.max(可见数)` 本来是防「服务器数过时偏低」的，副作用是这个数**只增不减**：服务器那份 `client_count` 停在 N 之后，有人离开时 `max(N, 变小)` 仍是 N。而服务器**不会主动推**这个数 | 成员集合一变就重发 `servergetvariables`（`refresh` 现在返回「成员是否变了」，`greet_the_server` 返回「这次是不是刚打过招呼」以免重复发）。**实测验证**：临时探针客户端加入 → `2 在线` 变 `3`；离开 → 回 `2` |
| ⑬ | **在线人数把 serveradmin 算进去了** | `convert.rs` 直接 `book.clients.len()`。服务器自报的 `virtualserver_clientsonline` 也把 query 连接算作 client，而只数我们自己的列表又会**少算**看不见的人 | 照 webspeak3：`(服务器自报数 − query 数).max(可见的非 query 数)`。**但前提是先发 `servergetvariables`**——服务器不会主动给。顺带修好了 `uptime`（一直是 `None`，同一个原因） |
| ⑭ | 重连后不会再订阅频道和取变量 | 我上一轮把「已订阅」的标志挂在 `Context` 上，而 `Context` 跨重连存活 | 标志改为「这条连接打过招呼没有」，在任何离开 `Connected` 的状态迁移里重置（`set_connection` 是唯一入口） |
| ⑫ | 权限错误只显示「permission」 | `PermissionError` 是**枚举套枚举**，serde 把内层也加了标签——`MissingPermission { permission }` 到 Dart 是 `{"missing_permission":{"permission":203}}`，而 `describe` 按**扁平**读 `detail['permission']`，取不到就掉到最后 `return kind`。单测喂的是扁平形状，**测试和 core 的真实形状不一致**，所以两边都「绿」 | 按真实形状取内层；测试改用真实载荷 |
| ⑪ | **别人发来的私聊跑到「和自己」的会话里** | TS3 的私聊消息里 `target` 是**收件人**——别人发给我时那就是**我**。而 `ConversationKey.of` 直接拿 `target` 当会话键，于是消息被存进 `client:<我的 id>`：树里**我自己那一行**冒未读点，而那条消息进了一个打不开的会话（自己那行没有打开入口）。症状是「别人回应我的戳，圆点却在我自己这行」——戳本身不标未读，标它的是紧随的那条私聊 | `ConversationKey.of` 增加 `ownClientId`：私聊的会话属于**对方**，收件人是我时改用 sender |
| ⑩ | 戳一戳的合成 id 会撞 | 第一版用 `-时间戳`，两次戳在同一毫秒就重复，而消息列表按 id 作键 | 视图上一个从 0 单调递减、**先减后取**的计数器（服务器从 1 往上数，两者不会碰面） |
| ⑧ | **别人换频道，看起来像是下线了** | 我们**从没订阅过频道**。TS3 只推你订阅了的频道的事件，所以别人搬走时发来的是 `notifyclientleftview`（语义是「离开你的视野」），而 book 的规则是**无条件 `remove`** | 握手后发 `channelsubscribeall`，并在权限快照变化后重发。见 `docs/ts3.md` §8——**这条是从 webspeak3 学来的** |
| ⑰ | **设为离开后，麦克风一触发就报「未连接」** | away 只发给了服务器，**本地的发送闸门没关**——`TransmitPolicy` 里只有静音与闭麦两扇门。于是门限照常放行、帧被编出来、库以 `can_send_audio()` 拒绝，FFI 把这次拒绝当成 `voice_send` 失败弹了出来。**同一个 bug 在 deafen 上已经修过一次**（`TransmitPolicy::output_muted` 的注释逐字写着同样的症状），away 是把同一件事又做了一遍 | `TransmitPolicy` 加第三扇门 `away`（`ts-audio/src/engine.rs`），两处宿主在 `SetAway` 时顺手关闸；再在 `ConnectionStateChanged(Connected)` 上清掉它——away 是连接状态，服务器不跨连接记它，而引擎会活过重连（麦克风不会重开）。回归测试照 deafen 那条写。**用户实测报上来的** |
| ⑱ | **崩溃报告永远发现不了「上次异常结束」**（macOS） | `ts-crash` 判断留下运行标记的进程是否还活着，非 Windows 分支只认 `/proc`，**没有 `/proc` 就 `return true`**。macOS 与 BSD 都没有 `/proc`，于是每个 pid 都算活着：硬杀留下的标记永远不判异常，报告也永远不消费它们。这个 crate 从没在 macOS 上编译过，所以 Windows 与 Linux 的测试一直是绿的 | 补 `kill(pid, 0)`：0 是活着、`EPERM` 是活着但不是我们的、`ESRCH` 才是没了。**转换要先检查**——负的 `pid_t` 不是进程号而是进程*组*号，`kill` 会对存在的组返回成功，那是个假的「活着」；超出 `pid_t` 的 pid 是这个内核不可能发出的，直接判死（测试里的 `u32::MAX - 3` 正靠这一点）。`libc` 本来就由 `cpal`/`tokio` 带在树里，加进去不增加编译量。见 [`docs/macos.md`](docs/macos.md) §6 |
| ⑯ | **触屏上长按打不开离开消息** | `IconButton` 的 `tooltip` 是它**内部**的一个 `Tooltip`，而 `Tooltip` 在触屏平台认长按。手势竞技场里最深的那层先被命中、先赢，所以长按弹的是提示框——在**唯一没有右键**的那类平台上，功能正好够不到 | 有第二个动作的按钮把 `Tooltip` 挪到最外层、`IconButton` 不再自带，`GestureDetector` 于是成为最深的那层。测试跑在 `flutter_test` 默认的 Android 目标平台上，所以这条路径**是被测过的**，不是「桌面能点就行」 |

③ 由用户指出。**教训**：错误只以 SnackBar 出现、不落日志，线索几秒就没了——
这正是 M0.6 的 logging 要补的。

---

## 7. 待办

### 立刻

- [x] ~~仓库零提交~~ —— 已有 `Initial commit`。

### M0.6 — Production Client（§87）

按建议顺序：

- [x] **logging**（最先做）——见 [`docs/logging.md`](docs/logging.md)。落盘、轮转、
      「UI 可见 ⇒ 必落日志」的不变式、设置里的入口，都已实测。
- [x] **重连** —— actor 成为唯一的策略所有者，fork 加了 `ReconnectMode::External`
      把库的内部重试关掉，§35 的退避表落在 actor。见 [`docs/reconnect.md`](docs/reconnect.md)。
      **欠一次真实掉线的端到端验证**，原因见 §5.4。
- [x] **设置界面** —— `ts-settings` + `settings.json`，音频（设备/传输方式/灵敏度）
      与连接（昵称/身份档/重连次数）两节真的存下来了。见 [`docs/settings.md`](docs/settings.md)。
      设备管理、通知、快捷键、主题、本地化仍是 §70 里的独立项。
- [x] **书签 / 服务器列表** —— `bookmarks.json` + 连接页与切换器两处入口。见
      [`docs/bookmarks.md`](docs/bookmarks.md)。模型从 `ts-protocol` 搬到了 `ts-settings`
      （分层），并改名为 `Bookmark`（`Server` 在两个语言里都已名花有主）。
- [x] **通知** —— 浮层 + 未读点 + 系统通知（桌面 `local_notifier`）。判断规则是纯 Dart、
      可注入时钟与文案表，19 条测试。顺带把**私聊界面**做通了（点频道树里的人即可），
      否则私聊通知点了没地方去。见 [`docs/notifications.md`](docs/notifications.md)。
- [x] **设备管理** —— 电平表、实际在用哪个设备（含失效回退提示）、测试扬声器、
      热插拔轮询，全部走一个新命令 `nightcord_voice_status`。顺带修掉两个真 bug：
      `VoiceStateChanged` 从未被发布过、下拉的 `initialValue` 从不自我纠正。
      见 [`docs/devices.md`](docs/devices.md)。
- [x] **快捷键** —— 三个动作、系统级、可配置。顺带修掉旧 PTT 的一个真 bug
      （先松 Ctrl 会卡在「一直发着」）。见 [`docs/shortcuts.md`](docs/shortcuts.md)。
- [x] **本地化** —— zh + en，官方 `flutter gen-l10n`；语言存 `settings.json` 的
      `ui.language`，默认跟随系统。两处无 BuildContext 的组句（错误句、通知文案）
      改为「状态层存数据、渲染期组句」。顺带修正连接页停滞在 M0.4 之前的 TS6 陈旧 UI。
      见 [`docs/localization.md`](docs/localization.md)。
- [x] **崩溃上报** —— `ts-crash`：按 pid 的运行标记 + 同步直写的崩溃笔记（panic/SEH，
      含帧地址不解析符号）+ 按需生成的单文件报告（无云、无自动上传）。顺带修掉
      「worker panic 后界面静默冻结」与「`shutdown` 把 `JoinError` 当干净结束」。
      见 [`docs/crash.md`](docs/crash.md)。

> **M0.6 至此全部完成。** 下一站是 Phase 7（Web Gateway，§71）。

### 视觉层欠账（见 [`docs/ui.md`](docs/ui.md)）

- **Server Rail + 独立成员栏：不做**（用户拍板、多次重申，2026-10-08 再次确认）。
  这条原先挂在「布局那一层」欠账里，每次列待办都会冒出来一次——**它不是欠账，是不做**，
  所以从欠账里摘出来了（同 §10 自绘标题栏的处理）。移动端 Shell 已于 2026-10-05 落地。
- **§10 的自绘窗口标题栏：不做**（用户定，2026-10-02）。两个平台都用系统标题栏。
- [x] ~~设置的左右布局~~ —— 弹窗改成了页面（左栏导航 + 右侧一节），见 §5.3 第六轮与
      [`docs/ui.md`](docs/ui.md)。**这是布局那一层的第一块**；2026-10-05 已继续加入 Desktop/Mobile 自适应 Shell。
- [x] **§19 的侧栏宽度**：2026-10-05 调整为 280，窄窗口改用频道树主页与详情导航。
- [ ] **§34 的动效**只用到一处（聊天滚到底），其余时长与曲线备好未用。
- [ ] **§36 的完整无障碍走查**：目前只做到「颜色不是唯一信号」。
- [x] ~~繁中 / 日 / 韩字体~~ —— 已加（`docs/localization.md` §7 记了三处一起改的规则，
      以及 `zh_Hant` 为什么要在 `providers.dart` 里手动指路）

### Phase 7 欠账（见 [`docs/gateway.md`](docs/gateway.md)）

- [ ] 网关没有 TLS，也没有每访客身份与会话归属；多标签页同权是写明的 v1 行为
- [ ] 语音是 PCM over WebSocket（第一阶段），最终要换成浏览器侧编解码
- [ ] 调试页（`crates/ts-gateway/web/`）要按目标目录迁进 `tools/web-debug/`，
      产品 UI 已实现为 Flutter Web；调试页迁移仍待做

### macOS（见 [`docs/macos.md`](docs/macos.md)）

`.app` 每次构建后复制到 `/Users/Shared/`，双击即可（构建账号没有图形会话，见该文 §4）。

- [x] ~~验通知、`⌘,`、⌘⇧M/D/P~~ ——**用户实测全部通过**（见 §5.3）。通知那条绕了
      一圈：「正常」是在含新通道的构建上测的，撤销后立刻不工作，已装回
- [x] ~~拖动窗口到 960x640 下限~~ ——**用户实测确认挡住了**
- [x] ~~设置文件的迁移~~ ——macOS 默认值从 Ctrl 改成 ⌘ 之后存量的那份 `settings.json`
      里还是 Ctrl。**用户已自行删掉该文件**，没有写迁移（见 §5.4 的理由）
- [ ] 连真实 TS3 / TS6（服务器地址见 §5.3）——**语音部分用户已在 MacBook 上验过**，
      频道切换也已由用户于 2026-10-05 确认；剩下的是通知与弹窗文案的走查

### 其他

- [x] TS3 成功换频道的验证 ——用户于 2026-10-05 确认通过
- [x] ~~别人换频道被当成下线~~ —— 根因是我们从没 `channelsubscribeall`，见 §6 ⑧
- [x] ~~关掉软件不主动断开~~ —— 见 §6 ⑨
- [x] **第九条的实测**：退出清理已由用户于 2026-10-05 确认通过
- [ ] 订阅全部频道在大服务器上的代价：频道多时会收到更多推送。官方客户端也这么做，
      但没量过；真出问题就在 `subscribe_to_every_channel` 那里收窄
- [x] ~~连接页保存行的单击被押后约 300ms~~ —— 已改为行内自计时（`Timer`，非时间戳，
      理由见 `docs/client.md`）。第一版用 `Stopwatch` 量真实时间，被测试抓出不可测。
- [x] ~~`Session::poke()`~~ —— 连同 kick / ban 一起补完，见 §5.3
- [x] ~~kick / ban~~
- [x] 官方客户端语音互通 ——用户于 2026-10-05 确认通过
- [ ] 不同真实立体声源的听感比较；poke / kick / ban 的真实服务器验证
- [ ] **屏幕共享的复测**：㉑ ㉒ 与置前一条已由用户确认（2026-10-08，见 §5.4）。剩下要看的
      ——能不能收到别人（官方客户端）的共享；小窗标题里 `limited-by` 写的是 `cpu` 还是
      `bandwidth`（**它决定 ㉒ 里 `maintain-framerate` 这个选择要不要翻过来**）；
      以及 2026-10-08 新加的音频与观看授权对真实服务器走一遍（见 §5.4）
- [ ] 成员行的单击要等双击判定，所以点「观看」到命令发出去之间约 300ms
      （与连接页保存行同一个代价，见 §7 更早那条）。要压掉只能用 `onTapDown`，
      代价是拖动列表也会触发——所以先留着
- [ ] 屏幕共享的一个已知取舍，等有实测数据再决定要不要动：
      只用 TeamSpeak 官方的那两条 STUN（参考实现还带了 Google 的第三条，
      跨 NAT 打不通时再补，那是一条要往外发查询的第三方端点）。
      ~~观看上限写在三处~~ 已在参数化那轮收敛到 `ScreenController.viewerLimit` 一处；
      观看上限的行为本身见 §5.3 的 2026-10-08 表（自动到达时强制，亲手批准可超过）
- [x] ~~未连接时够不到设置~~ —— `SettingsDialog.session` 改 `int?`，连接页加按钮
- [x] ~~可重试错误的 SnackBar 底色~~ —— **早已修好**（`app_shell.dart` 用
      `tokens.infoBg` / `tokens.errorBg`），待办是过期的，本轮清理
- [ ] 单人音量不持久化：现在只在会话内有效。要做成官方客户端那样按唯一身份记住
      （`Client.unique_id` 是有的），需要多一个存储和一次 `ClientId → unique_id` 解析
- [ ] **立体声只对真立体声源有意义**：单声道麦克风会被复制成两个一样的声道，听感
      与单声道无异，带宽却翻倍。要不要在界面上说明这件事，或者检测到单声道设备时
      回落到语音档，待定——这是「固定最高档」这个决定的已知代价
- [ ] **CI 缺 Flutter job**：`.github/workflows/ci.yml` 只跑 Rust，`flutter analyze`
      与 `flutter test` 没进 CI。注意 Dart 测试会加载真实的 Rust 动态库，
      所以这个 job 必须先 `cargo build` 并把 DLL 放到测试能找到的位置。
- [ ] `.gitignore` 忽略了 `pubspec.lock`。Flutter **应用**（非库）应当提交
      lockfile 以固定依赖，待确认后改。

### 明确不做（§74）

登录、云同步、头像、好友、社交、插件市场。Web 已按 Phase 7 开始实现。

> **屏幕共享原在这条里**，已于 2026-10-07 实现（TS6 有、TS3 没有），
> 见 [`docs/screen-sharing.md`](docs/screen-sharing.md)。
> 它当时不属于 M0.4 的欠账、而属于 §72（Phase 8）——这个判断没变，
> 只是 Phase 8 的这一项提前做掉了。

---

## 8. 文档索引

| 文件                       | 内容                                                       |
|----------------------------|------------------------------------------------------------|
| **`AGENTS.md`**            | **本文件。开发进度、规范、流程、待办——开发相关只更新这里** |
| `README.md`                | 项目说明：这是什么、怎么构建、怎么用                       |
| `DEVELOPMENT.md`           | 最初的设计文档，保持原样；被修正处在本文注明               |
| `docs/architecture.md`     | crate 分层与依赖、关键实现决策、与 `DEVELOPMENT.md` 的差异 |
| `docs/ts3.md`              | TS3 backend：actor 模式、快照 diff、权限、局限             |
| `docs/ts6.md`              | TS6：实测结论、共享适配层、`stream` 归 Phase 8（已实现）   |
| `docs/screen-sharing.md`   | 屏幕共享：信令与媒体分层、线路词汇、三个坑、约束与安全     |
| `docs/audio.md`            | 音频管线、线程模型、收发格式差异、已知取舍                 |
| `docs/logging.md`          | 日志：位置、轮转、环境变量、「UI 可见即落日志」的不变式     |
| `docs/reconnect.md`        | 重连：职责边界、fork 补丁、退避表、为什么首连失败不重试     |
| `docs/settings.md`         | 设置：文件格式、谁读它、损坏文件为什么与身份文件处理不同     |
| `docs/bookmarks.md`        | 书签：文件格式、明文密码这件事、地址归一化、两处入口的分工   |
| `docs/notifications.md`    | 通知：三种送达方式、两个坑、为什么不打扰正在看的、Windows toast 依赖 |
| `docs/devices.md`          | 设备：状态出口、为什么电平是拉不是推、静音着采集就是麦克风测试 |
| `docs/shortcuts.md`        | 快捷键：为什么系统级、物理键与 HID 码的代价、旧 PTT 的卡住 bug |
| `docs/localization.md`     | 本地化：工具与文件、语言如何决定、无 context 组句、什么不本地化、加语言/加文案 |
| `docs/crash.md`            | 崩溃上报：三类信号、标记语义、为什么不解析符号、Dart 侧的关窗路径、边界与触发法 |
| `docs/gateway.md`          | Web 网关：设备 Core 隔离、握手、安全边界、语音分阶段 |
| `docs/web-client.md`       | Web 使用：局域网、HTTPS/WSS、Pages、可选 Token 与设备身份 |
| `docs/ui.md`               | 视觉层：设计系统住哪、规范没写全或互相打架的地方怎么裁的、字体为什么下载而不是提交 |
| `docs/UI设计与配色规范.md` | UI 设计系统 **v2.0**：颜色 / 字体 / 间距 token 与组件规范（v2 换掉了 v1 的全套颜色） |
| `docs/client.md`           | Flutter 客户端：多会话、三个 bug、开发用环境变量           |
| `docs/macos.md`            | macOS：构建节点、要改的六处模板、沙箱数据目录、启动为什么从 SSH 做不到 |
| `docs/tsclientlib-fork.md` | 为什么用 submodule、fork 的 `nightcord` 分支、局域网改动   |

### 怎么更新本文档

- **进度 / 待办 / 决策**直接改进对应小节；改完同步 §5 顶部的「最后更新」日期。
- **规模数字（§5.2）用命令重新数，不要凭印象**：

```bash
find crates apps -name '*.rs' -not -path '*/target/*' | xargs wc -l | tail -1
find apps/client/lib apps/client/test -name '*.dart' | xargs wc -l | tail -1
cargo test --workspace --all-features 2>&1 | grep '^test result:' | awk '{s+=$4} END {print s}'
cd apps/client && flutter test        # Dart 测试数看最后一行 +N
```

- 正文里出现的「N 个测试」与 §5.2 必须一致，改一处要全改。
- **`docs/` 里出现过的事实若被本文推翻，回去把那份也改掉**——否则两份文档互相矛盾。

---

## 9. 工作约定与教训

### 测量工具必须先可信

**两次**因为自己临时拼的测量工具得出错误结论：

1. **DPI 截图**：PowerShell 默认是 DPI-unaware，`GetClientRect` 与截图都拿的是
   虚拟化坐标，于是「窗口底部被裁掉」这个 bug **根本不存在**——我追了很久。
   测 Windows DPI 相关的东西，测量进程必须先
   `SetProcessDpiAwarenessContext(PerMonitorV2)`。
2. **TCP 探针**：`TcpClient.BeginConnect` + `WaitOne` 在**失败**时也返回 true，
   判断逻辑是错的，导致误报两台服务器都离线。

**约定**：**用已知可用的工具去测**（要测服务器在不在，先用能连上的客户端试一次），
别用临时拼的探针。

**先找一遍仓库里有没有。** 加 macOS 时为了回答「沙箱之外能不能看到音频设备」，又临时
写了一个 example——而 `crates/ts-audio/examples/list_devices.rs` **本来就在仓库里**，
还比临时写的那个更全（默认设备标记、采样率、声道数）。更糟的是收尾时 `rm -rf examples/`
把那个**已提交的文件**一起删了，`git status` 里的 `D` 才暴露出来（已 `git checkout` 恢复）。

两条都是同一个动作能避免的：**写工具之前先 `ls`，删目录之前先看 `git status`**。

### 构建结果要验真

`cargo build | tail -N` 的退出码是 `tail` 的，不是 cargo 的——**早期因此两次把失败的
构建当成成功**。跑构建/测试要看真实退出码或抓错误行。

### 先 analyze 再 build

跳过 `flutter analyze` 直接 build，会把编译错误当成运行时问题查（犯过一次）。

### runner 里的注释只能是 ASCII

`windows/runner/*.cpp` 用 MSVC 编译，且开着「警告即错误」，而源文件是 UTF-8 无 BOM：
一个 em dash（U+2014）就会被读成当前代码页（936）表示不了的字符，C4819 直接升级成硬
错误——**报错指向文件第 1 行**，完全看不出是哪一句。C++ 侧（runner）的注释一律纯 ASCII；
Rust 与 Dart 侧不受影响（§4.1 说注释用英文，这条是同一个方向的硬约束）。

### 带转义的值，别让它穿过 shell

加 macOS 平台时改 `project.pbxproj`，连坏了两次，两次都不是 Xcode 的错：

1. **heredoc 吃掉了一个反斜杠。** `python - <<'PY'` 里的 `"\\n"` 到 Python 手上变成
   了 `"\n"`，于是「把换行转义成 `\n` 两字符」的函数实际是「把换行换成换行」——
   no-op。写进文件的是真换行，再被文本模式的写放大成 CRLF，Xcode 生成出来的脚本
   第一行就成了 `set -e\r`，bash 报 `set: -` + `: invalid option`。
2. **`re.subn` 的替换串会解释转义。** 用函数做替换不会，用字符串会——`\n` 又被
   还原成了换行。

**约定**：

- 要交给 Python 的代码里有反斜杠，就**写成文件**再执行，别走 heredoc。
- 内容本身含转义序列的文件（`.pbxproj`、任何内嵌脚本的工程文件），**用字节读写**，
  并且在源码里用 `chr(92)` 拼反斜杠——源码里一个反斜杠字面量都不留。
- 改完**验字节**，不是看 diff 像不像：数 CR、数转义、`plutil -lint`、最后还要
  `xcodebuild -list` 真的读一遍。前两次「看着没问题」都骗过了人眼。

> 附带一条：`.gitattributes` 是 `* text=auto eol=lf`，而本机 `core.autocrlf=true`，
> 所以**工作区里一堆 CRLF 是正常的**，git 存的是 LF。看到 CRLF 先别当污染去修——
> 先确认它在不在一个值的**内部**。

### 不确定就问，不要猜

遇到真正影响架构、且文档没写清的选择（TS6 架构、命名、依赖方案），
停下来问，不要替用户决定。


### 2026-10-05：临时 HTTPS 验证配置（未完成启用）

- 用户授权使用 Quick Tunnel。已下载官方 cloudflared 2026.9.3 至忽略目录 `run/`，后台启动页面和网关两个隧道，进程及地址日志位于 `run/tunnel-*`。
- 自动审批拒绝在网关启动参数中加入临时公网 Origin，仅返回 `blocked by policy`，未提供具体原因。未绕过；已恢复原局域网网关，并验证 LAN 页面自动鉴权成功。HTTPS/WSS、手机音频尚未完成验收。
- 为用户准备 `run/enable-https.ps1`（未执行）：检查隧道及网关进程，生成新随机 Token、重新构建 Web、以 loopback 监听重启网关并配置精确 Origin，输出手机访问地址。凭据不输出。该脚本须用户手动运行；临时地址依赖当前隧道进程，重启会变化。

- HTTPS 启用脚本修复：Windows PowerShell 5 在 `$ErrorActionPreference = Stop` 下将原生 stderr 重定向变成 `NativeCommandError`，Flutter 的正常 Wasm 提示会中止构建流程。改为 Start-Process 在进程边界分别写 stdout/stderr，并仅按 ExitCode 判断。`run/test-https-build.ps1` 直接提取实际构建函数做回归，确认 stderr 警告 + exit 0 成功、exit 7 正确保留失败码；脚本语法检查通过。仍由用户手动运行 HTTPS 启用脚本，未绕过公网 Origin 的审批拒绝。


### 2026-10-05：Web 改动整理与提交

- 按网关与 Web 客户端两组整理：网关实现可选 Token、设备 Core/数据/语音隔离与刷新快照；客户端实现远程传输、浏览器平台能力、Web 音频、自适应逐级导航、构建变量与启动错误提示。
- docs/gateway.md 更新为当前设备隔离和可选 Token 约定，新增 docs/web-client.md 说明本机/LAN、Pages、Quick Tunnel、HTTPS/WSS 和浏览器身份边界。README 仅补产品使用入口，DEVELOPMENT 保持原样。
- 审查补上 GatewayConfig Debug 的 Token 打码和回归测试。修正 Dart 格式化后暴露的测试样例大括号 lint。
- 用户要求停止后，网关、静态服务、两个隧道均已停止，5173/8787 无监听。临时 run/ 脚本、下载工具、日志、真实身份与凭据不纳入提交；HTTPS/WSS 手机音频仍未完成验收，未部署 Pages。
- 提交前门禁：格式、clippy 全工作区、406 项 Rust 测试、Flutter analyze、295 项 Flutter 测试、5 项启动脚本测试与无凭据预置的 Web release 构建全部通过。规模按当前源码重新统计，Dart 明确仅统计 lib/。


### 2026-10-07：头像两侧发言指示

- 频道成员发言时显示头像左右两段圆弧，替代昵称变色；使用配色规范 §9 的 online token（Nightcord 主题 #8CC9A3），随主题取色。头像预留固定间距，发言切换不改变布局。
- 自身发言读取 VoiceState.transmitting；FFI 与 Gateway 在音频帧驱动的传输状态变化时发送 VoiceStateChanged，停止语音与断开连接清除指示。浏览器停止提供音频帧时重置发言状态。
- 验证：Flutter analyze、完整 Flutter 测试、ts-ffi 与 ts-gateway 库测试通过；新增自身发言状态、头像圆弧颜色与尺寸、浏览器断流清除状态回归测试。尚未进行真实麦克风与服务器界面验收。

- 同日视觉微调：圆弧由 120° 缩短为 90°，线宽由 2.5 增至 3.5；成员行上下内边距由各 2 增至各 4，行高增加 4；自身昵称由 500 增至 600，同步设置可变字体 wght 轴。头像与页面渲染回归测试通过。

### 2026-10-07：设置页关于栏目

- 新增桌面/移动共用的关于栏目，无连接且设置尚未返回时仍可查看：软件名称、pubspec 版本、用途、项目地址、MIT OR Apache-2.0 许可证及开源声明。五种语言同步生成。
- 使用 Flutter LicensePage 浏览许可证；在 Flutter 自动收集的声明之外，注册 Rust Core/网关跨平台生产与构建依赖（排除仅 dev 的依赖）、vendored tsclientlib 及其继承许可、audiopus_sys 内嵌 Opus 许可、Noto 字体与项目许可证。注册只做一次。
- scripts/generate-about.py 从 cargo metadata 与 pubspec 生成 assets/licenses/third_party.json 和 lib/models/app_info.dart；修改版本、Cargo.lock 或依赖后运行 python scripts/generate-about.py。需要本机 Cargo 依赖源码及字体 OFL.txt；资源入仓库，普通客户端构建无需 Python。部分上游包不附带许可正文，保留其 SPDX 标识、作者及仓库地址；脚本输出缺少正文的名单，未宣称完成发行合规审计。
- 验证：Flutter analyze、关于栏目的设置未就绪入口、许可证页面打开、原生依赖与字体声明、重复注册回归测试通过。

- 收尾验证：完整 Flutter 测试与 Windows debug 构建通过，已启动新版客户端。

- 关于说明按用户提供的五种语言游戏名称更新：声明第三方 TeamSpeak 客户端身份、Nightcord 为游戏内虚构语音软件、不主张其名称及图标知识产权，以及与 TeamSpeak、SEGA、Colorful Palette、Nuverse 无隶属关系。补充相关权利归原权利人、无合作或授权关系、不代表公司立场；五种语言生成文件同步。

### 2026-10-07：聊天标题栏布局

- 聊天标题栏间距修复：频道名改用 Flexible 的宽松约束，短名称不再占满半个标题栏，备注紧跟名称与分隔线；长名称仍省略。新增短频道名与备注距离回归测试。

- 聊天标题栏后续修复：名称与备注组成占满可用宽度的分组，在线人数独立留在右端，避免无备注时人数因名称的宽松约束移到中间；覆盖有/无备注两条布局路径。

- 提交前门禁：Rust 格式检查、全工作区 clippy（所有 target/feature）、全工作区 Rust 测试、Flutter analyze 与完整 Flutter 测试通过；Windows debug 构建通过。

### 2026-10-07：TS6 屏幕共享与接手收尾

- 实现 TS6 屏幕共享的发起与观看：Rust 管协议与共享状态，`flutter_webrtc` 管媒体，
  Flutter 管界面。信令走已连接的命令通道，画面走独立的 P2P WebRTC 连接。
  设计记录见 [`docs/screen-sharing.md`](docs/screen-sharing.md)，验证表见 §5.3。
- 门禁：Rust 与 Dart 测试、clippy 全工作区、Rust 格式、`flutter analyze`、
  Windows 与 Web 构建全部通过（数字见 §5.2，后续几轮继续往上加）。
- **用户实测报上来的第一件事：界面上找不到入口。** 根因是 `CapabilitiesChanged`
  从来没有被发布过——整个前端只有 `capabilities.screen_stream` 一处判断，而它恒为
  false。见 §6 ⑳。
- **用户看了之后重排了界面**（第一版是聊天上方常驻的两行）：发起/停止搬到底栏 AFK
  左边，观看/停止观看搬进成员行上那个徽章本身，画面改成一个可拖的浮动小窗（用户从
  三个方案里选的）。见 §5.3 那一行与 [`docs/screen-sharing.md`](docs/screen-sharing.md)。
- 重排时自己踩了一个坑，被同一轮写下的测试当场抓住（和 §6 ⑥ 一样的抓法）：
  `ScreenShareButton` 把 `controller.active` 读在 `ListenableBuilder` **外面**，
  于是按钮图标永远停在按下前的那一面——`ListenableBuilder` 的通知会重跑 builder，
  但不会重跑那个捕获了旧值的闭包。**凡是要随通知变的东西，都得读在 builder 里面。**
- **未做**：与真实 TS6 服务器的互通过一次也没有；macOS / 移动端 / 浏览器的采集与
  权限未验证。见 §5.4。

#### 教训：补丁脚本插代码会割裂文档注释

一次脚本化的批量编辑把新函数/新字段插在**既有声明的文档注释之后、声明本身之前**，
于是那段注释（连同 `# Safety` 段）成了新符号的注释，而原来的符号掉了注释。
本轮一次撞出**六处**：

```text
crates/ts-protocol/src/traits.rs     ScreenSharing 顶了 Backend 的注释
crates/ts-ffi/src/lib.rs             nightcord_screen 顶了 set_away 的注释
crates/ts-session/src/session.rs     Session::screen 顶了 set_away 的注释
apps/client/lib/ffi/bindings.dart    screen 字段顶了 setAway 的注释
apps/client/lib/ffi/rust_client.dart 同上
apps/client/lib/models/events.dart   ScreenEvent 顶了 ConnectedEvent 的注释
```

**编译器不会报，测试不会红，diff 看上去也对**——只有通读新代码才发现。

**约定**：用脚本插符号时，**锚点要么选在文档注释之前，要么把注释一起重写**；
插入之后逐个新符号确认「它的注释说的是不是它」。`nightcord_screen` 那一处还带着
`# Safety` 段——把 unsafe 的调用前提安到另一个函数头上，不只是难看。

### 2026-10-07：屏幕共享的参数化、两步向导与「窗口被提到前台」的调查

- **参数不再写死**：新增 `ScreenOptions`（来源 / 分辨率 / FPS / 视频与音频码率 / 捕获音频 /
  隐私 / 观众限制 / 连接模式），从 `settings.json` 的 `screen` 节一路穿到 `setupstream`
  与编码器。枚举在 `ts-model`，数字映射在 `ts-protocol-ts6`；越界值在那里被拒，
  「服务器」模式明确报未实现而不是发一个连不上的流。
  `contentHint` 在 flutter_webrtc 里没有 API，用 `degradationPreference` 近似——
  「演示」预设保分辨率，其余保帧率。**这一条是与原版的已知差异。**
- **踩到两个真坑，都补了注释**：Windows 抓屏根本不看分辨率约束（分辨率改落在编码器上），
  而帧率要**同时**发标准的 `ideal` 和旧式的 `mandatory`——发一种就有一个平台不生效。
- **界面**：底栏 ⛶ 打开两步向导——先选来源（应用程序 / 屏幕 / 摄像头三页 + 缩略图），
  再进设置（基本 + 可折叠高级）。**设置只在点「开始直播」时写盘**：改了又取消的，
  不该影响明天的共享。观众上限从「写在三处」收敛成 `ScreenController.viewerLimit` 一处。
- **两个探针**（都在 `run/`，仓库忽略）：
  - `run/wgc-probe`：证明这台机器能用 Windows Graphics Capture 抓**别人的**窗口、
    抓得到帧、**而且窗口不动**。
  - `run/source-probe`：证明 `flutter_webrtc` 头文件里那个「自己喂帧」的钩子
    （`CreateCustomVideoSource` + `OnCapturedFrame`）**在预编译 DLL 里没有实现**——
    调用直接段错误。
- **结论**：采窗口会把窗口提到最前，根因在 `libwebrtc.dll` 选用 GDI 采集器（它读不到
  被挡住的窗口，就先翻上来）。四条「便宜的路」逐条查死，唯一的出路是自己拥有发布端。
  用户看过价钱后决定**只记录、不开工**——产品行为改为：选窗口不自动开采集，
  要按「预览」才会，按钮下写明代价。全部证据链见
  [`docs/screen-sharing.md`](docs/screen-sharing.md)。此处关于 GDI 与「唯一路线」的推论已由下节修正。
- 门禁：Rust 与 Dart 全绿、clippy、格式、`flutter analyze`、Windows release 构建通过。

### 2026-10-07：窗口预览复查与生命周期修复

- 当前 libwebrtc 版本源码在启动窗口视频采集时显式调用 `FocusOnSelectedSource()`；
  不能由 DLL 中存在 Raw/GDI 符号推断实际采集路径，也不能由探针崩溃断言 API 未实现。
  自建 Rust 发布端不是已经证明的唯一方案；优先评估原生库聚焦开关与 WGC 配置。
- 桌面预览改用现有缩略图方法，不启动 `getDisplayMedia`；空缓存有限重试，失败不回退
  到视频采集。正式共享的置前行为尚未修复，原生桌面效果仍待真机验收。
- 只预览选中来源，串行打开与释放；修复切页、关闭、重复选择时的迟到结果泄漏。
  切换来源类别清空选择，开始共享前等待清理。摄像头页不再自动打开所有摄像头。
- 新增 5 个回归测试覆盖缩略图调用、空缓存失败、切页、关闭及快速换源。
- 本轮验证：`flutter analyze --no-pub` 无问题；`flutter test --no-pub` 共 326 项通过。
  未重建原生客户端，未进行后台窗口缩略图与真实 TS6 互通验收。
- ~~实现审查待办~~（**已全部收口**）：音频选项接线与私密/联系人授权于 2026-10-08 做完
  （§6 ㉗㉘、§5.3 的表）；无 msid 的远端多轨道合并与 peer 关闭异常路径在随后的独立窗口
  崩溃轮里补齐（onTrack 串行合并、迟到合成流释放，见上面的记录）。

### 2026-10-07：屏幕共享独立窗口失败与重试崩溃

- 日志两次报 `MediaStreamAddTrack() stream is null`，随后崩溃笔记为 `0xc0000005`。
  修复 onTrack cascade 对已有远端流重复 addTrack；音视频事件串行合并、等待原生添加，
  关闭期间释放迟到合成流，远端轨道交给 peer 管理。崩溃笔记无符号，未断言最后崩溃函数。
- 修复 start 发错通道、未等待 handler 注册与事件订阅的握手竞争；每次打开分配独立通道，
  串行打开、失败清理、重复点击保护，关闭子引擎之前释放媒体。
- Windows 构建生成 flutter_webrtc 生命周期补丁：全局初始化一次，移除每个引擎析构时的
  全局 Terminate，避免关闭子引擎破坏主引擎。保持全局环境至进程退出，不修改 Pub 缓存。
  新版本补丁锚点不匹配时构建失败，要求审查；macOS 尚未验证。
- 新增 4 个 Dart 回归测试；原生工具 `apps/client/tool/screen_window_smoke.dart` 连续
  3 轮创建/初始化/销毁子窗口并复验主引擎 peer，通过、退出码 0。
  原生回归不连接真实 TS6 服务器，实际远端画面弹出仍待用户验收。
- 本轮静态分析通过，完整 Flutter 测试 330 项通过；Windows debug 构建通过。

### 2026-10-07：独立窗口修复的 Release 交付核对

- 用户重试仍失败；Windows Application 事件 1000 明确记录崩溃进程路径为
  `apps/client/build/windows/x64/runner/Release/nightcord_client.exe`。
  当时 Release exe 为 18:54:17、媒体插件 DLL 为 16:02:28，上一轮仅更新 Debug，
  所以 19:59 的重试实际没有执行已修复代码。属于构建交付遗漏，不能据此判断修复无效。
- 交付修复时核对用户实际运行的构建目录，同时更新对应模式的 Dart 产物与插件 DLL。
  本轮重新构建 Release；实际 TS6 观看与弹出窗口仍需在新产物上验收。
- Release 构建通过，核对 `data/app.so` 含新轨道错误处理和独立通道逻辑，
  `flutter_webrtc_plugin.dll` 不再导入全局 Terminate。exe 外壳无需重编时其时间戳不会改变，
  不能只检查 exe；修复实际落在 Dart AOT 与媒体插件产物中。

### 2026-10-07：真实 TS6 独立窗口交接与第二次打开崩溃

- 新版仍失败，真实服务器复现发现子窗口 discover 有回答、join 无回答：旧窗口仍占用
  同一客户端的观看连接。改为先 leave 并释放旧 peer，再让子窗口加入；等待远端媒体
  到达才完成弹出，失败清理子窗口并恢复内嵌观看。新增交接顺序与失败恢复回归测试。
- 连续重开复现另一个 `0xc0000005`：插件的全局 `g_host_messenger` 指向已关闭的
  子引擎，主引擎新建事件通道时使用失效指针。项目构建补丁改为每引擎映射，事件通道
  保留自身 messenger 引用，插件析构删除映射，不修改 Pub 缓存。
- 下载并校验锁定版本原始包，SHA256 与 `pubspec.lock` 一致，相关源码与本机缓存
  一致，确认全局指针问题存在于 `flutter_webrtc 1.6.2+hotfix.4` 发布包。
- 真实视频工具 `apps/client/tool/screen_video_smoke.dart` 使用产品子窗口路径。
  20:39–20:40 在真实 TS6 服务器连续两轮内嵌观看、弹出、收到视频、关闭、重新观看
  通过；主窗口与子窗口每轮均记录首帧，进程退出码 0。使用独立身份，不启动麦克风。
- 静态分析通过，最终完整 Flutter 测试 333 项通过；覆盖子窗口连接失败清理。
  Windows 原生诊断 Debug 构建通过，正式 Debug/Release 重新生成。
  macOS 多引擎与实际界面人工验收尚未完成。

### 2026-10-07：独立窗口原生关闭与回到小窗

- 用户标题栏关闭触发 20:52 的 `0xc0000025` 崩溃，上一轮工具只测试主侧主动关闭，
  漏掉原生关闭路径；无符号笔记不足以确定最后的原生函数。
- 子窗口启用关闭拦截与 `WindowListener`；标题栏“×”请求主侧统一清理，先释放观看
  条目、取消信令转发，子侧释放 peer 和画面后回复调用，再发原生关闭。已经销毁的
  窗口通知不再向该引擎重复发送关闭命令，防止关闭期间重入。
- 独立窗口右上角新增“回到小窗”，补齐五种界面语言；释放子窗口观看后，由原会话
  重建同一发布者的内嵌观看。关闭独立窗口只停止观看，不退出主程序。
- 回归覆盖清理后恢复观看、重复返回不重复加入、已销毁窗口不重复关闭。
  `flutter analyze` 通过，完整 Flutter 测试 335 项通过。
- 21:00 真实 TS6 工具验证原生关闭后主进程继续观看/再次弹出，以及返回小窗后
  视频接收恢复，退出码 0。多轮测试间隔 8 秒，避免真实服务器的防刷预算耗尽。
  Windows Debug/Release 正式产物同步更新；macOS 原生关闭仍待验收。

### 2026-10-07：快速重开共享窗口触发服务器限流

- 用户再次重开失败，21:04:48 日志明确报 `ClientIsFlooding`；21:05:08 弹出超时后
  主窗口能重新收画面，没有新崩溃。上一轮工具加 8 秒间隔掩盖了真实连续操作问题。
- ICE 最多收集 2 秒后与 SDP 合并，候选按 mid/媒体索引写入对应媒体段；原生 SDK
  返回的 SDP 缺少候选，需显式补入。未知媒体段及迟到候选仍走 trickle，保留跨网能力。
  完全相同 offer 去重，变化的 offer 仍正常应答。日志不输出 SDP 或候选内容。
- 通用适配器保留服务器错误码，扩展接口提供重试策略；TS6 仅对明确限流拒绝
  `0x020c` 延迟 3/6 秒，最多两次，保持 15 秒总命令期限。不重试权限拒绝、超时
  或不确定送达；具体错误码和策略不进入 core/UI。
- 命令最终失败转发到独立窗口，结束空等并清理；观看就绪还要求本地应答已提交，
  修正 onTrack 先到导致诊断工具过早切换的问题。
- 21:35–21:36 真实 TS6 无额外冷却等待连续三轮弹出/关闭/重新观看通过，最后返回
  小窗也通过；日志确实记录限流后一次 3 秒重试及恢复首帧，共七次首帧、退出码 0。
- 门禁：`flutter analyze` 无问题，完整 Flutter 测试 342 项通过；两项 Rust crate
  测试共 62 项通过，相关 crates clippy 通过。Windows 正式 Debug/Release 同步更新。
  macOS 与跨 NAT 真机验收仍未完成。

### 2026-10-07：恢复默认快捷键（按钮与键名）

- **功能**：设置 → 快捷键 每行一个「恢复默认」按钮。默认值按平台由 `ts-settings` 拥有
  （macOS 是 Command，其余是 Control），所以前端**只负责问**：新命令
  `reset_shortcuts { action }` 走 FFI/网关同一条 `ts-wire` 词汇，回包带着**整个
  settings**（不是裸 `ok`），`SettingsNotifier._collect` 因此也认这个名字。
  一个按钮只管自己那一行——`ShortcutSettings::reset` 与 FFI 测试各钉了一遍。
- **按钮的可见性**（用户报「现在这个配色谁看得见」，随后又报「按钮里面一点东西
  都没有」）：**根因是 §6 ㉖——release 构建的图标字体子集里根本没有那个字形**，
  所以按钮是空的，裸图标那版连边界都没有，看起来就是「什么都没有」。样式也一并
  改了：从 18px 的裸 `IconButton`（主题色 `textSecondary`，一行里没有任何边界）
  改成 §17.2 的 secondary 材质（`OutlinedButton`：`surface1` 底、`borderDefault`
  边框、`textPrimary` 图标），36×36 方形，与同一行里那个输入框同高。**不带文字**：
  每行一个，标签在手机上会挤掉输入框，说明交给 tooltip。回归测试除了「按哪一行问
  哪一行」，还盯着那一行里**确实有个 `OutlinedButton`**——否则改回裸图标不会有人发现。
  **教训**：那一版的离屏渲染是用 `FontLoader` 直接加载 SDK 的完整字体做的，图标
  当然画得出来——量出来的「按钮可见」与用户看到的「按钮是空的」说的不是一件事。
- **`Ctrl+Shift+0x70010`**：见 §6 ㉕。键名表落在 `lib/util/key_names.dart`。
- **文案**：那条 tooltip 按用户要求从「把这一条恢复成默认」改成**「恢复默认」**
  （五种语言同步，`flutter gen-l10n` 产物一起更新）。按钮就在那一行上，不必再解释
  「这一条」是哪一条。
- **两个小顺手**：删掉上一轮遗留在 `pages_render_test.dart` 里的 `PROBE` print；
  §5.2 的测试数按本轮实跑更新（422 Rust + 345 Dart）。
- 门禁：`flutter analyze` 无问题，Rust 全工作区测试、完整 Flutter 测试全绿。
- **未验证**：改完的按钮与新的键名都**没有在真机上再看一次**（§5.4）。

### 2026-10-08：屏幕共享的音频与观看授权

用户点名把上一轮代码审查留下的两项做完：「捕获音频」真正接线（§6 ㉗），私密/联系人
共享真正需要发布者批准（§6 ㉘）。参照实现（webspeak3）两处的行为都核对过，刻意的差异
各自注明（决策表在 §5.3，设计细节补进了 [`docs/screen-sharing.md`](docs/screen-sharing.md)）。

- **音频**：offer 加上采集产出的音频轨；音频发送者只设码率上限；线上 `audio` 以
  「采集真的产出了音轨」为准。插件的 Windows 实现带 WASAPI loopback（选窗口来源时按
  该窗口的进程定向），macOS/Linux 没有 loopback 采集器——那里开着的开关如实报 0。
  观看端不需要写代码：原生由 WebRTC 自动播放（未实机听过），Web 渲染器把远端音轨接到
  隐藏的 `<audio>` 自动播放（插件源码核对）。
- **观看授权**：私密/联系人的 `join_requested` 不再自动放行，进待批准队列；发布端
  模态弹窗逐个允许/拒绝（Esc 可关、不丢请求；请求者超时或离开即自动消失）。**服务器
  不做守门人是参考实现在真实服务器上证实过的**，所以客户端这一句就是全部的执行。
  满员仍是到达即拒；发布者亲手批准可超过上限。参考实现有「屏蔽」，**不做**——TS6 的
  命令预算压着刷屏，真被烦到再加。
- **Server Rail + 独立成员栏**：用户在本轮对话里**再次**拍板不做——从 §2、§7 与
  `docs/ui.md` 的欠账清单里摘除，按「不做」记录，此后不再出现在任何待办里。
- **「采窗口会把窗口提到最前」**：用户 2026-10-08 确认已解决。仓库里查不到对应改动
  （cmake 补丁、提交、已下载的 DLL 都没有聚焦相关代码），**按用户实测为准记录**；
  §7 的待办与 §5.4 的相关段落一并摘除。
- 门禁：Rust 格式、全工作区 clippy、422 项 Rust 测试、`flutter analyze`、354 项
  Flutter 测试全绿。**未做**：真机试听与真实服务器上的批准走查（§5.4）。
