# 崩溃上报

M0.6 的最后一项。`docs/logging.md` 回答「运行中发生了什么」；本文的系统回答
「进程死掉时发生了什么」——两者是互补的，`logging.md` 里早已划界，本文件兑现。

---

## 1. 三类信号

| 信号 | 由谁写 | 何时 | 解决什么 |
| --- | --- | --- | --- |
| **运行标记** `crashes/last-run.<pid>` | `nightcord_create` | 每个进程启动时写、干净退出时删 | 「上次没有干净退出」——包括被 `taskkill /F` 杀掉这种日志什么都记不到的情况 |
| **崩溃笔记** `crashes/crash-<纳秒>-<pid>-<kind>.txt` | panic hook / `crash-handler` 回调 | 同步直写，在进程死掉之前 | panic 的消息与源码位置；SEH 异常的异常码与地址；两者的**帧地址**回溯 |
| **报告** `crashes/nightcord-report-<ts>.txt` | 用户点「生成报告」 | 按需 | 一份可提交的文本：头部信息 + 全部笔记 + 全部标记 + 日志尾部（≤256 KB）+ 隐私说明 |

为什么笔记不能走日志：`ts-logging` 是有界异步队列（满了会**丢**记录），而崩溃时刻
最值钱的恰恰是最后几条。笔记用 `std::fs` 同步直写，不碰队列。

## 2. 标记的语义

- **按 pid 一个文件**，而不是一个共享文件：两个实例不会互相覆盖证据、也不会互相
  清掉对方的标记。`status` 扫描 `last-run.*`，**只有 pid 已不存活**的才算异常
  （Windows 用 `OpenProcess`，其余平台对 `/proc` 可用性保守处理）。
- **写标记在 FFI 导出层（`nightcord_create`）而不是 `NightcordClient::new`**：
  cargo 测试直接构造客户端，因此既不装全进程的 hook，也不会往真实目录丢东西。
- **笔记只在本进程的标记存在时写**（`our_run_is_live`）：测试进程 panic 不产生
  用户目录里的垃圾文件。代价是标记写入失败时笔记也不写，方向是保守的。
- **「干净退出」有两个来源**：`nightcord_mark_clean_exit`（Dart 在关窗时调，
  见 §4）与 `shutdown`（worker 正常结束才算）。**worker panic 后关窗，标记保留**——
  那不是干净退出，下次启动应当说出来。
- 生成报告会**消费**（删除）死进程的标记：证据已在报告里。`忽略` 不消费，
  下次启动还会提醒。「活」标记永远不动。

## 3. 回调用 `backtrace` crate 且**不解析符号**

笔记里每帧一行指令指针（`0x7ffb...`），没有函数名。三个原因，都是踩出来的：

1. **地址永远在**。发布版不含符号，用户机也没有匹配的 PDB——地址 + 本仓库留档的
   同版本 PDB 才能事后符号化（见 §7）。
2. **没有 PDB 时解析器不会失败，它会答错**：把帧归给「最近的导出」，于是我们的
   帧被标成了 Flutter 引擎的导出名。自信的错名字比「unknown」更糟。
3. 符号化会加载 dbghelp 并分配内存。这运行在 panic hook 与异常回调里——进程正在
   解体时最不该做的事；实测那条路径上解析也确实返回了空。

## 4. Dart 侧

- **启动时**问一次 `nightcord_crash_status`（无句柄同步导出，worker 死了也能答），
  异常则显示顶部横幅：「上次会话异常结束 / 有 N 份崩溃记录」+ 生成报告 / 打开文件夹 / 忽略。
- **关窗时**：`AppLifecycleListener(onExitRequested)` 在返回响应**之前**同步调
  `nightcord_mark_clean_exit`——之后不再有 Dart 代码运行。这条路径必须存在：
  ProviderScope 从不销毁，`client.dispose()` 在正常退出时根本不会执行，
  没有它每次正常关窗都会被下一次启动报成崩溃。
- **worker 半死**（任务 panic、进程活着）也被照亮了：`send()` 发现通道关闭时
  只报**一次** `core_gone` 错误给 UI（`AtomicBool` 去重），同时 Rust 侧记
  `ERROR`。在此之前这是静默冻结——用户面对一个永远不回应的界面。

## 5. 已知边界

- **没有 minidump**。原生崩溃只有异常码 + 地址 + 尽力而为的回溯，没有内存转储。
  升级路径：`minidumper` + 一个 sidecar 进程（Embark 的 out-of-process 方案），
  连同 zip 打包一起做。
- **Dart↔FFI 调用上的原生崩溃可能漏**：UEF 类捕获器在 UI 线程的 Dart FFI 调用中
  有已知盲区（[dart-lang/sdk#51726](https://github.com/dart-lang/sdk/issues/51726)）。
  **panic 笔记与运行标记是承重信号**，SEH 笔记按「尽力而为」理解。
- **一次 abort 两条笔记**：原始 panic 一条，abort 机制自身（"a function that cannot
  unwind"）往往再来一条。文件名到纳秒，两条都留下——毫秒粒度时第二条曾把第一条
  （真正的原因）覆盖掉。
- **`taskkill /f` 与 `exit(0)` 不算干净退出**——设计如此，这就是「异常结束」的定义。
- **CLI 不覆盖**：`apps/cli` 直接用 ts-core、不走 ts-ffi，崩溃在终端里可见。
- **按 pid 的标记有 pid 复用假阴性**：旧 pid 恰好被新进程复用会漏报，概率低且方向安全
  （漏报好于误报）。
- 崩溃笔记与报告的保留数是各 10 份（仿 `ts-logging` 的 `KEEP_FILES`）。

## 6. 开发时的触发法

`NIGHTCORD_TEST_PANIC`（与 `NIGHTCORD_AUTO_CONNECT` 同类的开发工具，release 也带）：

| 值 | 效果 | 验证的路径 |
| --- | --- | --- |
| `ffi` | `nightcord_create` 里 panic → 跨 FFI 边界 → **abort，进程真死** | 笔记（消息/位置/地址）+ 标记保留 + 下次启动横幅 |
| `worker` | worker 任务 panic，进程存活 | `core_gone` 错误进 UI + 日志；关窗后标记保留，下次启动横幅 |

```bash
# 例：真死亡路径
powershell -Command '$env:NIGHTCORD_TEST_PANIC="ffi"; Start-Process <exe>'
```

**注意**：跑 `flutter build windows` 之前先关掉正在运行的应用——安装步骤会因
exe/DLL 被占用而失败（`error MSB3073`）。

## 7. 符号化

发布版 `[profile.release] strip = true` 剥掉符号，但链接器产出的 PDB
（`target/release/nightcord_ffi.pdb`）仍在本地。它**不随安装包发布**（
`windows/CMakeLists.txt` 只装 DLL）：每条发布都留好对应的 PDB，用户报告里的
地址就能事后符号化；用户机上则只有地址，没有名字。

## 8. 相关

- `crates/ts-crash` —— 标记、笔记、报告；**不**依赖任何内部 crate（目录由调用方传入，
  与 `ts-logging` 同型）
- `crates/ts-ffi/src/crash.rs` —— 目录解析（`NIGHTCORD_CRASH_DIR` 覆盖，语义与
  `NIGHTCORD_LOG_DIR` 相同：它是崩溃目录本身）、三个导出、启动/退出钩子
- `apps/client/lib/features/crash/crash_banner.dart` —— 横幅
- `apps/client/lib/models/crash.dart` —— 状态模型
- [`docs/logging.md`](logging.md) —— 「UI 可见 ⇒ 必落日志」；本文是它的另一半
