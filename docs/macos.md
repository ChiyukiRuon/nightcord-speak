# macOS

macOS 端的第一个平台目录（`apps/client/macos/`），以及它跑在哪台机器上。

在此之前仓库只有 `windows/`，所以本文同时是「macOS 特有的东西有哪些」和
「怎么在这台 Mac 上构建」两份记录。

---

## 1. 构建节点

macOS 的构建与验证**不在这台 Windows 机器上做**，而是在局域网内一台 Mac 上：

| 项 | 值 |
| --- | --- |
| SSH | `agent@192.168.31.33`（密钥，免交互） |
| 机型 / 系统 | Apple M4 / macOS 27.0.1 |
| Xcode | 27.0，`xcode-select` 已指向 `/Applications/Xcode.app/Contents/Developer` |
| 仓库 | `~/workspace/nightcord-speak` |
| Flutter | 3.47.5（按 tag 浅克隆，与 Windows 那台**逐位相同**：framework revision 与 engine hash 都一致） |
| Rust | rustup 默认 1.99.0；仓库里由 `rust-toolchain.toml` 钉到 **1.98.0**，首次 `cargo` 时自动安装 |
| cmake | 4.4.3（Homebrew） |
| CocoaPods | 1.17.0（Homebrew） |

**IP 不是长久的**：连不上时先确认这台机器的当前局域网地址，不要照抄上面的数字。

### `~/.zshenv`

非交互式 SSH（`ssh host '命令'`）拿到的 `PATH` 只有 `/usr/bin:/bin:/usr/sbin:/sbin`——
没有 Homebrew，也没有 cargo。所以那台机器上写了：

```sh
export PATH="$HOME/.cargo/bin:$HOME/flutter/bin:/opt/homebrew/bin:$PATH"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
```

zsh 对非交互 shell 也读 `.zshenv`，所以写完就不必给每条命令加前缀。`LANG` 那条是
CocoaPods 自己要的（它没看到 UTF-8 locale 会警告），而这个项目的字符串里有 CJK。

### 两个 Windows 上的坑，在这台机器上不适用

- **`CMAKE_GENERATOR` 不用设**：那条是给「最新 VS 没装 C++ 工具链」的机器绕路的
  （见 `AGENTS.md` §3.2）。macOS 上 cmake 默认就用 Xcode。
- **CMake 4 与 Opus 1.3 的不兼容仍然存在**（Homebrew 的 cmake 也是 4.x），但仓库里
  `.cargo/config.toml` 的 `CMAKE_POLICY_VERSION_MINIMUM` 是跨平台的，直接挡住了——
  首次 `cargo build` 没有报错。

## 2. `macos/` 里不能照模板原样留着的东西

`flutter create --platforms=macos` 生成的目录能编译，但**跑起来不能连、也不能说话**。
以下是逐条改掉的地方，按「不改会怎样」排序。

### 2.1 沙箱权限（`Runner/*.entitlements`）

模板给 Debug 的权限是 `app-sandbox` + `allow-jit` + `network.server`，给 Release 的
**只有 `app-sandbox`**。缺的两条：

| 键 | 缺了会怎样 |
| --- | --- |
| `com.apple.security.network.client` | `connect(2)` 返回 `Operation not permitted`。症状与「服务器连不上」**完全一样**，日志里看不出区别 |
| `com.apple.security.device.audio-input` | 音频 HAL 层被拒。**没有对话框**，就是没有声音 |

两条都同时加进 Debug 与 Release。Release 那份尤其要紧：那是没人挂调试器在跑的版本。

> 这是从 Windows 移植过来时最容易漏的一处——Windows 上没有对应的东西，
> 而 macOS 上它是「静默失败」而不是「报错」。

### 2.2 `NSMicrophoneUsageDescription`（`Runner/Info.plist`）

缺了它不是「麦克风打不开」，是 **TCC 直接把进程杀掉**。所以这句话必须在第一次
推麦之前就存在。

**不走 `l10n`**：Info.plist 的字符串由系统在 Flutter 起来之前解析，要翻译就得另配
一套 `InfoPlist.strings`，等于在应用自己的翻译体系旁边再建一套。应用是多语言的，
但这句用户在系统弹窗里只读一次的话，就跟随构建语言。

### 2.3 产品名（`Runner/Configs/AppInfo.xcconfig`）

`PRODUCT_NAME = Nightcord Speak`。这一个设置同时是窗口标题（`MainMenu.xib` 的
`APP_NAME` 占位符）、菜单栏标题、Dock 与访达里显示的名字、以及 bundle 里可执行
文件的名字——所以它写的是品牌，和 Windows 的 `Runner.rc` 拼写一致。

改它要同时改三处硬编码产品名的地方：`project.pbxproj` 里的 `PBXFileReference` 与
两个 `TEST_HOST`，以及 `xcshareddata/xcschemes/Runner.xcscheme` 里的 `BuildableName`。
**Flutter 自己的工具链不用动**——`macos_assemble.sh embed` 会把构建出的名字写进
`Flutter/ephemeral/.app_filename`，`flutter run` 靠那个文件找 bundle，不管它叫什么。

Bundle identifier 是 `com.chiyukiruon.nightcordClient`，机器面，保持项目名的拼写。

### 2.4 Rust 核心的构建阶段（`project.pbxproj`）

一个 `Build Nightcord Rust core` 的 Run Script 阶段，位置在 `Bundle Framework` 与
Flutter 自己的 embed 阶段之后。它 `cargo build -p ts-ffi`，再把
`libnightcord_ffi.dylib` 拷进 `$BUILT_PRODUCTS_DIR/$PRODUCT_NAME.app/Contents/Frameworks/`。

与 `apps/client/windows/CMakeLists.txt` 里那段 CMake 钩子**是同一件事的两种写法**，
两份注释互相指着。要的效果也一样：`flutter run -d macos` 是一条命令，且核心
永远不会相对调用它的 Dart 过期。

几个非显然的点：

- **profile 跟 Flutter 的构建模式走**（Debug→`dev`，其余→`release`），debug 跑起来
  链的是 debug 核心。cargo 的 `dev` profile 输出目录叫 `target/debug`，不是
  `target/dev`。
- **PATH 要自己补**：Xcode 交给脚本阶段的环境里没有 `~/.cargo/bin`。
- **脚本沙箱是关的**（模板里 `ENABLE_USER_SCRIPT_SANDBOXING = NO`），cargo 才能
  往 target/ 写东西。
- **`PRODUCT_NAME` 里有空格**，脚本里凡是用到它的地方都加引号。

### 2.5 窗口下限（`Runner/MainFlutterWindow.swift`）

`contentMinSize = 960x640`，与 Windows `win32_window.cpp` 的 `kMinWindowWidth`
同一个数、同一个理由（低于它聊天头部会溢出成黄黑条纹）。

用 `contentMinSize` 而不是 `minSize`：它量的是 Flutter 绘制的区域，标题栏不算在里面。
point 本身就是逻辑单位，所以 Retina 屏与 1x 屏拿到的是同一个窗口——这正是 Windows
那边要手动按 DPI 缩放才有的性质。

### 2.6 图标

`macos/Runner/Assets.xcassets/AppIcon.appiconset/` 下 7 个 PNG，由
`scripts/make-app-icon.py` 和 Windows 的 `.ico` 一起生成（同一个脚本、同一处标记
定义，见该脚本头部）。`Contents.json` 是模板的，没有改——它本来就正好列出这七个
文件在十个槽位里。

### 2.7 通知：插件在 macOS 上是个空壳，换成了自己的通道

`local_notifier` 0.1.6 的 macOS 原生实现整个建在**已废弃的 `NSUserNotificationCenter`**
上（`LocalNotifierPlugin.swift`），一行 `UNUserNotificationCenter` 都没有。更麻烦的是
它**把失败也报成成功**：

- Dart 层的 `setup()` 在 macOS 上根本不发原生调用（插件里那个分支只对 Windows 生效），
  直接 `_isInitialized = true`
- 原生 `deliver` 是 fire-and-forget，**无条件 `result(true)`**
- 应用与插件都没有申请过通知权限

三个方向全静默：`_ready` 是 `true`、不会记「已丢弃」的日志、原生不抛错——**连日志都没有**。
所以「通知没出现」和「通知正常工作」在那条路径上完全无法区分。

现在是 `MainFlutterWindow.swift` 里一个 `nightcord/notifications` 通道，走
`UNUserNotificationCenter`：

- **权限在第一次真要发通知时申请**，不在启动时——弹窗因此带着理由出现
- 回给 Dart 的是**「显示了没有」**，不是「调用成功了没有」。用户拒绝权限会被记一行
- 设了 `UNUserNotificationCenterDelegate`，`willPresent` 返回 `.banner`

> **撤回过一次，又装回来了。** 用户报「通知正常」之后按指示整体撤销，撤销完通知立刻
> 不工作——**那次实测跑在含新通道的构建上**。要判断一个替代实现是否必要，必须拿
> **不含它**的构建去测。经过见 [`docs/notifications.md`](notifications.md)。

Windows 不动，仍走 `local_notifier`（WinToast，含 AppUserModelID 与开始菜单快捷方式）。
分支在 `lib/util/system_notifications.dart` 这一个文件里。

### 2.8 快捷键：默认修饰键与显示

两处按平台分：

- **默认值**：macOS 是 **⌘⇧M / ⌘⇧D / ⌘⇧P**，其余平台是 Ctrl+Shift+…。Mac 键盘在那个
  位置上是 Command，用 Control 能work但手感是错的。默认值由 `ts-settings` 拥有
  （serde 补齐后总会把三个键都序列化出去），所以**改 Rust 那一处就够**
- **显示**：`Chord.format()` 在 macOS 上拼 `Cmd` / `Option` 而不是 `Meta` / `Alt`；
  `MainMenu.xib` 里模板自带一个 `Preferences…`（`keyEquivalent=","`，即 ⌘,）但**没有
  action 也没有 target，是个死的**——`MainFlutterWindow` 按 key equivalent 找到它接上，
  经 `nightcord/shell` 通道让 Dart 打开设置页。不要求全局热键，也不动菜单项的标题与位置

注册路径本身**不需要改**：`uni_platform` 的扩展在 macOS 上会把 Flutter 的 HID usage
查 `kMacOsToPhysicalKey` 换成正的 Carbon 虚拟键码，`hotkey_manager_macos` 才把它交给
`Key(carbonKeyCode:)`。这一段读插件源码确认过——不确认的话很容易误以为是错键。

### 2.9 两个只在「跨机器构建」时才出现的坑

这条走廊是：**Windows 上改代码 → 打包 → Mac 上编译 → 复制给控制台用户**。
两个坑都在中间那一步。

#### ① 从 Windows 同步过去的源码会被 cargo 认为「没变过」

`tar` 保留文件时间戳。Windows 上的 mtime 常常**早于** Mac 上的构建产物，于是
`cargo` 判定源码是新鲜的、直接跳过重编——**构建报成功，产物里却没有这次的改动**。

实测撞上过一次：改了一条日志文案，构建「成功」，`cargo` 只花了 0.10 秒；用
`strings` 去产物里找那句话，**不在**。差一点就把一个不含改动的二进制交出去了。

**修法**：解包之后把源码 `touch` 一遍。

```bash
tar xzf - && find crates apps -name "*.rs" -exec touch {} +
```

**并且**：怀疑构建没生效时，用 `strings` 去产物里找一句**这次的**新字符串——
这比看构建日志可靠，因为日志只说「成功」。

#### ② 签名封条在增量构建后会过期

**现象**：`codesign --verify --deep` 报某个嵌套组件 `file modified`。
时间戳会指出来龙去脉——内容变了，而 `_CodeSignature/CodeResources` 停在上一轮。

两个来源，都是「有 build phase 往 bundle 里写东西，而这轮 Xcode 没重签」：

- **Flutter 自己的** `Flutter Assemble` target 里那个没有 outputs 的 Run Script 阶段，
  每次都重写 `App.framework`（构建日志里那条
  `Run script build phase 'Run Script' will be run during every build` 就是它）
- **本项目的** `Build Nightcord Rust core` 阶段，每次都重写
  `Contents/Frameworks/libnightcord_ffi.dylib`

**干净构建不会**——`flutter clean` 之后的产物直接通过校验。

**所以**：`codesign --verify --deep` 必须进交付流程，不能省。不过就重做一次干净构建，
别在增量产物上查「看着像 bundle 坏了」的症状（图标变通用、通知注册不上、沙箱异常）。

> 为什么值得写下来：图标那次就是先怀疑了图标资源本身。实际 `Assets.car` 里
> `assetutil --info` 显示七个尺寸一个不少，`CFBundleIconName = AppIcon` 也对——
> 资源从来没坏过，坏的是封条。

### 2.10 把产物交给控制台用户

`~agent` 对其它用户不可读（`drwxr-x---+`），所以 `.app` 必须先复制出去。
用 **`ditto` 而不是 `cp -R`**：`ditto` 是 bundle-aware 的，会带上扩展属性与资源分支。
复制完 `chmod -R a+rX`（否则控制台用户读不了 `~agent` 里来的文件），再
`touch` 一下 bundle 让 Finder 重读它的修改时间。

LaunchServices 认的是**每个用户自己的**数据库，所以它在 `agent` 这边注册得再干净，
也影响不到 `chiyukiruon` 那边的图标缓存。真遇到图标不刷新，要在登录的那个账号里跑：

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "/Users/Shared/Nightcord Speak.app"
killall Finder
```

## 3. 运行时的数据落在哪

`ts-identity` 的 `app_data_root()` 早就写好 macOS 分支：
`$HOME/Library/Application Support/Nightcord Speak`。

**但应用是沙箱化的**，所以那个 `$HOME` 是容器里的家目录，实际路径是：

```text
~/Library/Containers/com.chiyukiruon.nightcordClient/Data/Library/Application Support/Nightcord Speak/
```

日志、身份、设置、书签、崩溃记录都在里面。这是沙箱正确的行为，不是 bug——
但也意味着**它和 Windows 的 `%APPDATA%` 不是同一个位置**，命令行里手改设置文件时
要找对地方。

## 4. 启动：构建账号没有图形会话

**这是这台构建节点目前的限制，不是代码问题。**

Mac 图形界面上登录的是 `chiyukiruon`（uid 501），SSH 账号是 `agent`（uid 502），
两者不是同一个用户。`agent` 没有 Aqua 会话（`launchctl print gui/502` 不存在），
所以从 SSH 执行 `open App.app` 会失败：

```text
OSLaunchdErrorDomain Code=125 "Domain does not support specified action"
```

GUI 程序需要 WindowServer，而 `agent` 没有。**现有做法**：构建完把 `.app` 复制到
`/Users/Shared/`（world-writable，且 `~agent` 对其它用户不可读，必须复制出去），
由控制台上的用户在访达里双击。

脚本化的做法（`launchctl asuser`）需要 sudo，且会让应用以 `chiyukiruon` 的身份运行、
数据落进那个用户的容器——所以没有采用。

## 5. 验证到哪一步

| 项 | 结果 |
| --- | --- |
| Rust workspace 编译 | ✅ macOS arm64，含 libopus（cmake 4 未报错） |
| `flutter build macos --debug` | ✅ `Nightcord Speak.app` |
| dylib 进了 bundle | ✅ `Contents/Frameworks/libnightcord_ffi.dylib`，arm64，34 个 `nightcord_*` 导出符号 |
| 签名里的权限 | ✅ `codesign -d --entitlements` 确认 `network.client` 与 `audio-input` 都在 |
| `flutter analyze` | ✅ 无问题 |
| Rust 测试 | ✅ 全绿（见 `AGENTS.md` §5.2 的数字） |
| Dart 测试 | ✅ 全绿 |
| 播放链路 | ✅ 探针实跑：`play_test_tone` 返回 `queued`，设备是 `Mac mini扬声器` |
| 新 Swift 进了产物 | ✅ `strings` 在二进制里找得到 `nightcord/shell`（菜单通道）；Swift 的改动**必须这样验**，增量构建与同步时间戳都会让 cargo/Xcode 跳过重编（见 §2.9） |
| **界面本身** | ❌ **没有人看过** —— 见 §4，需要人工双击 |
| **连真实服务器** | ❌ 未做 |
| **通知与 ⌘, 菜单项** | ❌ 代码在产物里，但**没有人点过** |
| **语音** | ❌ 见下——这台机器上测不了 |

### 5.1 这台 Mac 没有麦克风

不是「检测不到」，是**物理上没有**。仓库里现成的工具（跑在**沙箱之外**、无图形会话，
所以它同时也是「Rust 音频代码在 macOS 上有没有问题」与「沙箱有没有拦」的对照组）：

```text
$ cargo run -p ts-audio --example list_devices
input: (none found)
output (1):
  Mac mini扬声器 [default] — 48000 Hz, 2 ch
    id: coreaudio:BuiltInSpeakerDevice
```

系统自己的工具是同一个答案：

```text
$ system_profiler SPAudioDataType
    Devices:
        Mac mini扬声器:
          Default Output Device: Yes
          Transport: Built-in
```

Mac mini（Mac16,10 / M4）**不带内置麦克风**。所以：

- 「检测不到麦克风」不是 bug，没有东西可检测
- **要在这台机器上验语音，得插一个 USB 麦克风或耳麦**
- `Mac mini扬声器` 是唯一的输出设备

引擎本身按「**没有麦克风的人也应该能听**」设计（`VoiceEngine::open_devices` 把输入失败
记成警告，不阻断播放），所以没有麦克风时连接与收听都应当是好的。

| 项 | 结果 |
| --- | --- |
| 输入设备枚举 | ✅ `input: (none found)`——与系统工具一致，这台机器确实没有输入设备 |
| 输出设备枚举 | ✅ `coreaudio:BuiltInSpeakerDevice`，48 kHz / 2 ch |
| 播放（`play_test_tone`，沙箱外） | ✅ 打开成功、音频入队 |

> 这两条是用 `cargo run -p ts-audio --example list_devices` 与一段临时探针在**沙箱之外**
> 得到的。写那段探针之前没有先去找现成的例子，结果写了个重复的——`examples/list_devices.rs`
> 本来就在仓库里，而且比探针更全（默认设备标记、采样率、声道数）。找工具之前先找一遍。

> **构建节点有没有麦克风，与 macOS 端能不能语音无关。** 用户在一台 **MacBook** 上实测过
> 完整语音（扬声器与麦克风都正常），所以这一节只是这台构建机的硬件现状，不是平台的
> 限制。`ts-audio` 的 `list_devices` 一眼就能看出某台机器有没有输入设备。

## 6. 顺带修掉的一个真 bug

`ts-crash` 判断「留下运行标记的进程是否还活着」时，非 Windows 分支只认 `/proc`，
没有 `/proc` 就 `return true`。macOS 没有 `/proc`，于是**每个 pid 都算活着**：
硬杀留下的标记永远不被判为异常，崩溃报告也永远不消费它们。

这个 crate 从没在 macOS 上编译过，所以 Windows 与 Linux 的测试一直是绿的。
修法见 `AGENTS.md` §6 的 bug 表。
