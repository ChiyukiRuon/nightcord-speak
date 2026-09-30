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
屏幕共享、自定义 Profile Server、Web。

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
| `ts-settings`          | 用户偏好：结构、存储、默认值          | 决定谁读它（由 core 应用）      |
| `ts-audio`             | 设备、采集、编码、播放、VAD           | 依赖协议库                      |
| `ts-protocol-tsclient` | **唯一**允许知道 `tsclientlib` 的地方 | 出现具体协议判断                |
| `ts-protocol-ts3/ts6`  | 声明协议、承载各自扩展                | 复制适配层                      |
| `ts-core`              | facade + 后端选择                     | 泄漏协议概念                    |
| `ts-ffi`               | C ABI + JSON，句柄而非指针            | 阻塞 Dart UI 线程               |

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

**本机特有**：CMake 会挑最新 VS，但必须选装了 C++ 工具链的那个。本机
VS 2022 Community 未装，VS 2019 BuildTools 装了，所以：

```bash
export CMAKE_GENERATOR="Visual Studio 16 2019"
```

> 这一步**刻意没写进仓库配置**——生成器取决于哪台机器装了 C++ 工具链，
> 写死会让 CI（windows-latest 预装完整 VS 2022）出错。
> 给 VS 2022 装上「使用 C++ 的桌面开发」后就不需要了。

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
cd apps/client && flutter run -d windows
```

### 3.5 门禁：提交前必须全绿

```bash
bash scripts/fmt.sh --check                                        # 格式
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test  --workspace --all-features                             # 281 个
cd apps/client && flutter analyze && flutter test                  # 57 个
```

> `cargo fmt --all` **不能用**：它也会格式化 path 依赖，会把 `vendor/tsclientlib`
> 按我们的风格改写。用 `scripts/fmt.sh`（内部是 `-p` 逐个列出的）。

**坑**：`scripts/fmt.sh` 的包列表是手工维护的，**加了新 crate 必须同步加进去**，
否则它不会被格式化，而且门禁照样报绿。`ts-audio` 与 `ts-ffi` 就这样漏了很久，
直到 2026-09-30 补上时已攒下 15 个文件、101 处漂移（已一次性格式化清零）。

**顺序很重要**：先 `flutter analyze` 再 `flutter build`。跳过 analyze 直接 build，
会把编译错误当成运行时问题查（犯过一次）。

### 3.6 提交

- 一次提交只做一件事；提交信息说清 **为什么**，不只是改了什么。
- 改动 API、修 bug、定决策，同步更新本文档对应小节。
- 未经要求不要提交/推送。

---

## 4. 开发规范

### 4.1 语言

- **代码注释、文档注释、提交信息用英文**（Rust 生态惯例）。
- **与用户交流、本文档、`docs/` 用中文。**

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

---

## 5. 当前进度

**最后更新：2026-09-30**

### 5.1 里程碑

| 里程碑   | 内容                            | 状态        |
|----------|---------------------------------|-------------|
| Phase 0  | workspace / CI / tracing / 文档 | ✅          |
| **M0.1** | TS3 Headless Client             | ✅ **实测** |
| **M0.2** | TS3 Voice                       | ✅ **实测** |
| **M0.3** | Flutter Client                  | ✅ **实测** |
| **M0.4** | TS6                             | ✅ **实测** |
| **M0.5** | Multi Session                   | ✅ **实测** |
| M0.6     | Production Client               | 🚧 logging / 重连 / 设置界面 已完成 |
| Phase 7  | Web Gateway                     | ⏳ 未开始   |

§90 的实际顺序：

```text
① Rust Workspace ✅  ② ts-model ✅  ③ ts-events ✅  ④ ts-session ✅
⑤ TS3 Backend ✅     ⑥ TS3 Headless CLI ✅  ⑦ TS3 Voice ✅
⑧ Flutter FFI ✅     ⑨ Flutter UI ✅
⑩ TS6 Backend ✅     ⑪ Multi Session ✅
⑫ Web Gateway ⏳     ⑬ Web Client ⏳        ⑭ 扩展功能 ⏳
```

### 5.2 规模

|      | 数量                           |
|------|--------------------------------|
| Rust | **15,172 行**，13 crates + CLI |
| Dart | **5,619 行**，26 文件          |
| 测试 | **281 Rust + 57 Dart**，全绿   |

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
| 换频道            | ⚠️ 命令往返与错误映射已验证；**成功换频道未验证**（服务器只有一个频道） |

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
| 日志落盘                    | ✅ `%APPDATA%\Nightcord Speak\logs\nightcord.log.<日期>`，每日轮转保留 7 份 |
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

### 5.4 未验证

- **音质**：只验证了帧数 / 时长 / 电平，**从未用耳朵听过**。
- TS3 成功换频道（测试服务器只有一个频道）。
- Android / iOS / Web：完全未动。
- **重连循环没有跑通过一次真实掉线**。原计划用本机 TCP 中继制造掉线，但在这台机器上
  做不到：`nightcord-cli.exe` 连不上任何本机监听（3ms 内被 RST；同一时刻、同一次调用里
  一个普通 Rust 探针却能连上），而放在项目目录之外的二进制又连不出去。这是环境的
  按进程网络策略，不是代码问题——但它意味着「库报掉线 → 退避重试 → 恢复」这条路径
  目前只有编译期与单元级的保证。
  要真正确认：连上之后停掉 TS3 服务器（或拔网线），看提示条出现、倒计时走秒、日志里
  出现 attempt 序列，再把服务器起回来确认自动恢复、频道树与聊天记录都还在且无重复。

---

## 6. 过程中修掉的真 bug

四个都是「**前端对 core 的认知与实际不符**」，都只有真正跑起来才暴露——
单元测试全绿、CLI 也正常。

| # | 症状                           | 根因                                                    | 修法                                                          |
|---|--------------------------------|---------------------------------------------------------|---------------------------------------------------------------|
| ① | 两台在线服务器都显示「未连接」 | `ConnectedEvent` 不设连接状态；后端只在重连时发状态事件 | 前端由 `connected` 事件置位；后端把状态变更与事件发布**绑定** |
| ② | 聊天输入框始终禁用             | 权限提示缺失被当成「拒绝」（hints 是**可选**的）        | 缺失 = 未知 = 放行；服务器仍是权威                            |
| ③ | 启动语音前按静音弹红错         | 无引擎时报 `NoInputDevice`——既不该报错，解释也是错的    | 记成 **intent**，`start_voice` 时应用                         |
| ④ | 核心主动报的错误**完全不显示** | `ErrorEvent` 被 `server_view.dart` 归入「不参与渲染」而 `break` 掉，既没提示也没 SnackBar——握手失败、掉线、重连拒绝时频道树就那么僵着。日志里有，用户看不到 | `providers.dart` 里让它也走 `lastErrorProvider`，于是自动获得提示与日志（做 logging 时顺带发现） |

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
- [ ] 书签 / 服务器列表
- [ ] 通知
- [ ] 设备管理（设置对话框里已有雏形）
- [ ] 快捷键（目前 PTT 用 `Focus`，非全局）
- [ ] 本地化
- [ ] 崩溃上报

### 其他

- [ ] TS3 成功换频道的验证（需要多频道服务器）
- [ ] `Session::poke()` —— trait、事件、权限位都在，只缺这个方法
- [ ] kick / ban 同上
- [ ] 音质人耳确认
- [ ] 未连接时够不到设置：语音栏只存在于服务器页，所以「打开日志文件夹」在连接页
      无处可点（出错时仍有 SnackBar 按钮兜底）。若要补，落点是 `AppShell`——
      两个分支唯一共同经过的地方。
- [ ] 可重试错误的 SnackBar 底色：`backgroundColor` 对 `isRetryable` 传 `null`，
      于是走 Material 3 的 `inverseSurface`，在深色主题下是**浅色**的，看着像 bug。
      改动前就有的行为，做 logging 时注意到但没动。
- [ ] **CI 缺 Flutter job**：`.github/workflows/ci.yml` 只跑 Rust，`flutter analyze`
      与 `flutter test` 没进 CI。注意 Dart 测试会加载真实的 Rust 动态库，
      所以这个 job 必须先 `cargo build` 并把 DLL 放到测试能找到的位置。
- [ ] `.gitignore` 忽略了 `pubspec.lock`。Flutter **应用**（非库）应当提交
      lockfile 以固定依赖，待确认后改。

### 明确不做（§74）

登录、云同步、头像、好友、社交、插件市场、屏幕共享、Web。

> TS6 的 `stream` 命令族属于**屏幕共享**，因此是 §72（Phase 8），
> 不是 M0.4 的欠账。见 [`docs/ts6.md`](docs/ts6.md)。

---

## 8. 文档索引

| 文件                       | 内容                                                       |
|----------------------------|------------------------------------------------------------|
| **`AGENTS.md`**            | **本文件。开发进度、规范、流程、待办——开发相关只更新这里** |
| `README.md`                | 项目说明：这是什么、怎么构建、怎么用                       |
| `DEVELOPMENT.md`           | 最初的设计文档，保持原样；被修正处在本文注明               |
| `docs/architecture.md`     | crate 分层与依赖、关键实现决策、与 `DEVELOPMENT.md` 的差异 |
| `docs/ts3.md`              | TS3 backend：actor 模式、快照 diff、权限、局限             |
| `docs/ts6.md`              | TS6：实测结论、共享适配层、`stream` 归 Phase 8             |
| `docs/audio.md`            | 音频管线、线程模型、收发格式差异、已知取舍                 |
| `docs/logging.md`          | 日志：位置、轮转、环境变量、「UI 可见即落日志」的不变式     |
| `docs/reconnect.md`        | 重连：职责边界、fork 补丁、退避表、为什么首连失败不重试     |
| `docs/settings.md`         | 设置：文件格式、谁读它、损坏文件为什么与身份文件处理不同     |
| `docs/client.md`           | Flutter 客户端：多会话、三个 bug、开发用环境变量           |
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

### 构建结果要验真

`cargo build | tail -N` 的退出码是 `tail` 的，不是 cargo 的——**早期因此两次把失败的
构建当成成功**。跑构建/测试要看真实退出码或抓错误行。

### 先 analyze 再 build

跳过 `flutter analyze` 直接 build，会把编译错误当成运行时问题查（犯过一次）。

### 不确定就问，不要猜

遇到真正影响架构、且文档没写清的选择（TS6 架构、命名、依赖方案），
停下来问，不要替用户决定。
