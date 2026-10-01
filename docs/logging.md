# 日志（Milestone 0.6）

## 为什么有它

bug ③（启动语音前按静音弹红错）当时查不动，原因不是代码难，是**线索会消失**：
错误只以 SnackBar 出现，几秒后自动隐藏，之后就什么都没有了。当时只能靠把文字
抄下来。

底层有两个独立的缺口，缺一不可：

1. **没有 subscriber。** `ts-ffi` 里早就有 14 处 `tracing::` 调用，但 Flutter 通过
   cdylib 加载时没人安装 subscriber，宏全部被丢弃。CLI 自己装了 stderr subscriber，
   所以命令行下反而看不出问题——这个缺口只在 GUI 里存在。
2. **UI 可见的失败不落日志。** 命令失败只走 `FfiEvent::failed(...)` → JSON → Dart
   → SnackBar，Rust 侧一行日志都没有。

现在的规则是一句话：**用户能看到的每一个错误，日志里都必须有。**

---

## 日志落在哪

```text
<应用数据目录>/logs/nightcord.YYYY-MM-DD.log

Windows   %APPDATA%\Nightcord Speak\logs\
macOS     ~/Library/Application Support/Nightcord Speak/logs/
Linux     $XDG_CONFIG_HOME/nightcord-speak/logs/（或 ~/.config/…）
```

- **每日轮转，保留 7 份**，最旧的自动删除。上限存在的原因很简单：无上限的日志
  最终会变成用户的问题，而有用的部分永远在最近那一端。
- 日期在中间、`.log` 在最后，是因为 `tracing-appender` 把日期**追加在 prefix 之后**。
  传给它 `"nightcord.log"` 会得到 `nightcord.log.2026-09-30`——日期成了扩展名，文件
  在文件管理器和所有日志查看器眼里是"没有扩展名"。所以 stem 和扩展名分开传
  （`filename_prefix` + `filename_suffix`）。
- 目录由 `ts_identity::app_data_root()` 给出——身份存在它下面的 `identity/`，
  日志在 `logs/`，设置在 `settings.json`，书签在 `bookmarks.json`。平台路径的知识只有
  这一份——见 [`docs/settings.md`](settings.md) 与 [`docs/bookmarks.md`](bookmarks.md)。
- 文件里**不写 ANSI 转义**：它是给人用编辑器打开的，不是给终端渲染的。

### 环境变量

| 变量 | 作用 |
| --- | --- |
| `NIGHTCORD_LOG` | 日志级别，如 `debug`、`ts_protocol_tsclient=trace`。优先于 `RUST_LOG` |
| `NIGHTCORD_LOG_DIR` | 覆盖日志目录。**设为空字符串**表示「不落文件，只写 stderr」 |

两者对 CLI 与 Flutter 客户端**同时生效**——filter 只有一份定义
（`ts_logging::DEFAULT_FILTER`），CLI 只是写到终端而不是文件。

默认 filter 沿用 CLI 早就验证过的那串：

```text
info,tsclientlib=warn,tsproto=warn,tsproto_packets=warn,ts_bookkeeping=warn
```

供应商库在 info 级会**按包刷屏**——`tsclientlib/src/lib.rs:1384` 在用户处于耳聋状态时
每收到一个音频包（20 毫秒一个）就写一行 info。终端里可以靠人眼略过，文件里不行：
它会把我们自己的行埋掉。所以要写死这个基线，而不是「跟着默认走」。

---

## 不变式：UI 可见 ⇒ 必落日志

收口点在 `FfiEvent::failed(...)`（`crates/ts-ffi/src/event.rs`）：

```text
report()  ─┐
report_failure() ─┼─▶ FfiEvent::failed(command, session, error)
reject()  ─┘        │
                    ├─▶ 记一条 error 日志   ← 这里
                    └─▶ 返回 CommandResult 给 Dart
```

`report`、`report_failure`、`reject` 三者覆盖了 ABI 接受的**每一个**命令，所以在
构造处记录，等于让这条规则成为**类型的性质**，而不是十几个调用点各自要记住的约定
——将来加一个命令，不可能悄悄绕过它。

`FfiEvent::lagged`（事件被丢弃）同样记录：前端「画着一棵过期的树」这件事，用户
事后只会描述成「人显示不对」，没有这行日志就查不出是什么时候开始的。

回归测试盯着这条不变式：
`crates/ts-ffi/src/event.rs` 的 `a_failed_command_is_logged_and_not_only_shown`。

**不重复记录。** `ClientEvent::Error`（握手失败、掉线等核心主动报的错误）已经在
`actor.rs:350` 先 `warn!` 再 publish，所以转发路径上不再记一遍。

### 安全（§4.5，§44）

- `Command` 的 `Debug` 是**手工打的码**：chat 正文、服务器密码、频道密码都不出现。
  所以日志里写 `command = ?command` 是安全的；**不要**把 `text` 单独取出来记。
- `Identity` 与 `ConnectionConfig` 的 `Debug` 同样打码，私钥不会进日志。

---

## 为什么写入是非阻塞的（重要）

**有些日志行是从实时音频线程发出来的。** `crates/ts-audio/src/capture.rs` 里
`assembler.push(data)` 就是 cpal 的数据回调，它最终会走到：

```rust
tracing::warn!("capture is ahead of the engine; dropping audio");
```

装文件 subscriber 之后，这一行如果在 RT 线程上做分配、加锁、等磁盘 I/O，就是经典
的实时危险：优先级反转 → xrun → 产生**更多**日志行 → 更严重。

所以用 `tracing_appender::non_blocking`，并且**显式**写 `lossy(true)`：

```rust
NonBlockingBuilder::default().lossy(true).finish(appender);
```

- 记录进有界 channel，由单独的 writer 线程落盘；
- channel 满时**丢行**而不是阻塞调用方。

丢一行日志，好过丢音频。

`WorkerGuard` 必须活到进程结束（drop 它会停掉 writer 线程、丢掉队列里剩下的行），
所以在 `ts_logging::init` 里被放进 `static`——调用方没有理由、也没有责任去保管它。

---

## 为什么单独一个 crate

`crates/ts-logging` **不依赖任何内部 crate**：目录由调用方传进来。

- 它可以被 CLI（写 stderr）和 Flutter 客户端（写文件）同时复用，默认 filter 与
  「谁能吵谁不能吵」的判断因此只有一份，不会漂移。
- 层 1，只依赖 `tracing` / `tracing-subscriber` / `tracing-appender`。

装了新 crate 记得往 `scripts/fmt.sh` 的 `PACKAGES` 里加一行——那个列表是手工维护的，
漏了它不会被格式化，而门禁照样报绿（`ts-audio` 与 `ts-ffi` 就这样漏过很久）。

---

## 从 Dart 转发

Dart 侧有自己的失败：widget 构建时抛异常、事件批次解析不了。这些核心看不到，
但恰恰是用户会来报的那类。

- `nightcord_log(level, message)` —— **不需要 handle**，因为要能在「核心没起来」
  那条路径上也能用。未知 level 按 `info` 记而不是丢弃：调用方是我们自己的代码，
  调用方式的笔误不该把消息一起弄丢。null 消息是唯一被忽略的情况——那时没有东西可记。
- `main.dart` 挂了 `FlutterError.onError` 与 `PlatformDispatcher.onError`。
  两者都**保留原有的控制台输出**（先调用 `previous`），并且 `onError` 返回 `false`
  不吞掉错误——是否改变崩溃策略是另一件事，本次只做记录。

**不**从 `LastErrorNotifier.report` 转发命令失败：Rust 已经记过了，再记一遍就是同
一件事两行日志。

---

## 用户怎么找到它

| 场景 | 入口 |
| --- | --- |
| 出错 | 错误 SnackBar 里直接显示路径，并带「打开日志」按钮（10 秒，够按下按钮） |
| 正常使用 | 语音栏 ⚙ → **设置** → 日志一节显示路径 + 「打开日志文件夹」 |
| 核心起不来 | 启动失败页显示路径 + 按钮 |
| 手机 | 无路径：Android / iOS 的沙箱路径只有宿主应用知道，此时只写 stderr |

设置界面原本是音频专用的 `_AudioSettingsDialog`，现在是应用设置页
（`lib/features/settings/settings_page.dart`，左栏导航、右侧一节），音频与日志是并列的
两节。以后加设备管理、快捷键，都往这里加。

打开文件夹用 `dart:io` 的 `Process.run`，不加依赖。**注意 Windows 上
`explorer.exe` 成功时也返回退出码 1**，所以不能拿退出码判成败——`revealDirectory`
因此不检查退出码，只报告「打不开器进程」这一种失败。

---

## 已知取舍

- **多行消息（如 Dart 调用栈）会占多行**，续行没有时间戳和 target。这是日志系统的
  通行行为，强行转义成一行会让栈没法读。记录边界仍然清楚：下一条带时间戳的行开始
  一条新记录。
- **只按时间轮转，不按大小**。默认 `info` 且供应商库压到 warn 之后单日文件很小；
  用 `NIGHTCORD_LOG=debug` 做长时间排查时才需要留意体积。
- **移动端没有文件日志**，与身份存储的限制相同，等宿主应用传入沙箱路径。
- 崩溃上报（§87 的 Crash reporting）是**另一项**，已完成——见
  [`docs/crash.md`](crash.md)。本次的日志是它的基础，也是它生成的报告里最有用的
  那部分（报告会带上日志尾部；崩溃时刻本身的证据走同步直写，不走这里的队列）。

---

## 相关

- `crates/ts-logging` —— subscriber 本身
- `crates/ts-ffi/src/logging.rs` —— 目录从哪来
- `crates/ts-ffi/src/event.rs` —— UI 可见即落日志的收口点
- [`docs/client.md`](client.md) —— bug ③ 与三条「前端对 core 的认知与实际不符」
- [`docs/architecture.md`](architecture.md) —— crate 分层
