# Flutter 客户端（Milestone 0.3）

## 已完成并验证

| 项 | 状态 |
| --- | --- |
| `crates/ts-ffi` — C ABI + JSON | ✅ 18 个导出函数，41 个 Rust 测试 |
| dart:ffi 绑定与生命周期管理 | ✅ 9 个 Dart 测试（`ffi_test.dart`，加载的是真实动态库，不是 stub） |
| 原生库打包（CMake 钩子） | ✅ `flutter run -d windows` 单命令可用，DLL 自动就位 |
| 事件流 → Riverpod store | ✅ 移植了 CLI 的 `view.rs` 规则，27 个测试对等（`server_view_test.dart`） |
| 连接真实服务器 | ✅ 连上 `192.168.31.128:9987` |
| 频道树 / 用户列表 / 离线区 | ✅ 实测确认 |
| 聊天（消息列表 + 输入框） | ✅ 实测确认 |
| 语音控制栏（静音 / 耳聋 / 设备） | ✅ 实测确认 |
| 主题（紫色暗色） | ✅ 按效果图配色 |
| **150% 显示缩放下渲染** | ✅ 实测确认，无裁剪 |

实测截图确认可渲染：服务器名（来自握手）、频道树（含选中高亮）、我们自己的
用户、**离线区**（上一轮断开的会话被正确归入「离线 — 1」）、聊天头部、
空状态、底部输入框与语音控制栏。

---

## 多会话（Milestone 0.5）

**实测通过**：同时连上 `192.168.31.128:9987`（TS3）与 `:9988`（TS6），
左上角切换器列出两台且均显示「已连接」，切换后各自渲染自己的频道树。

架构上本来就是多会话的（`SessionManager` 是 `HashMap`，事件带 `SessionId`），
但此前**从未有两个真实服务器同时在线跑过**——所以第一次跑就暴露了两个 bug。

### 抓到的两个 bug

**① 前端从不认为自己已连接**

`ConnectedEvent` 只设置 `server` 与 `info`，没有设置 `connection`；而唯一设置
`connection` 的 `ConnectionStateChanged` 事件，backend 之前**只在重连时**发。

后果：`ServerView.isConnected` 恒为 false。切换器把两台在线服务器都标成
「未连接」，输入框也一直禁用。

修在两处——两层都要对：
- 前端：`connected` 事件本身就意味着已连接，直接置位
- 后端：`set_connection()` 改成**状态变更与事件发布绑在一起**，
  这样五处状态转换不可能再漏发

**② 权限提示缺失被当成「拒绝」**

TS3 的 permission hints 是服务器**可选**下发的。原实现把「没有提示」当作
`empty()`，即全部拒绝。测试服务器恰好不下发 hints，于是输入框被禁用——
而实际上发消息完全正常（CLI 早就验证过）。

改成 **缺失 = 未知 = 放行**：服务器仍是权威，它会用明确的错误拒绝，而错误会
传到用户；把用户本来能做的事灰掉，等于让他没有办法发现。

### 开发用：多地址

`NIGHTCORD_AUTO_CONNECT` 现在接受**逗号分隔的多个地址**，这是让多会话真正可被
演练的前提——一个地址时切换器和多会话 store 都没有意义。

```bash
NIGHTCORD_AUTO_CONNECT="192.168.31.128:9987,192.168.31.128:9988"
```

### Bug ③：启动语音前按静音按钮会报错

**（用户指出）**在点「开始语音」之前点麦克风或耳机按钮，会弹红色错误
SnackBar，文案是 `没有可用的输入设备`。

**原因**（`crates/ts-ffi/src/client.rs` 的 `set_muted`）：

```rust
let Some(active) = voice.as_mut() else {
    events.push(FfiEvent::failed(name, None, ClientError::Audio(AudioError::NoInputDevice)));
    return;
};
```

两个问题叠在一起：

1. **根本不该报错**——启动语音前先静音是「偏好」，不是失败
2. **解释是错的**——设备没任何问题，用户只是还没开机

**修法：把改动记成 *intent***，与引擎是否存在无关：

- worker 里新增 `voice_intent: VoiceState`，静音 / 耳聋 / 传输方式先写进它
- 有引擎就同时应用并告知服务器；没有就只记录，**返回 ok**
- `start_voice` 建好引擎后把 intent 应用上去，所以先按的静音不会丢

实测：启动语音前点麦克风 → 按钮变红（已静音）、**无错误提示**、
输入框仍显示「发送消息」。

回归测试：`muting_before_voice_starts_succeeds`、
`choosing_a_mode_before_voice_starts_succeeds`（`crates/ts-ffi`）。

### 已补上：错误不再只走 UI

上面那个 bug 之所以难查，是因为**应用的错误只以 SnackBar 出现，不写日志**。
SnackBar 几秒后自动消失，线索随之消失——我当时就是这样丢掉它的。

这一项已经做完（Milestone 0.6 的第一项）。现在：

- 每个**用户可见的失败**都会落到 `<应用数据目录>/logs/nightcord.<日期>.log`，
  收口点在 `FfiEvent::failed`，所以新加命令不可能绕过；
- 错误 SnackBar **直接显示日志路径**并带「打开日志」按钮（10 秒）；
- 语音栏 ⚙ → 设置 → 日志一节可以随时打开日志文件夹；
- `NIGHTCORD_LOG=debug` 可以临时提高详细程度。

完整说明见 [`docs/logging.md`](logging.md)。

另外**顺带修掉**一处相关的缺陷：核心主动报的 `ErrorEvent`（握手失败、掉线、重连）
此前在 `server_view.dart` 被归入「不参与渲染」直接 `break`，既没有提示也没进 SnackBar
——频道树就那么僵着。现在它同样走 `lastErrorProvider`，于是自动获得提示与日志。

> 遗留的观感问题（未修）：可重试错误（如网络类）用 Material 3 的默认 SnackBar 底色，
> 在深色主题下是**浅色**的，看起来有点像 bug。这是改动之前就有的行为，本次没动。

---

## 曾经的「底部被裁掉」：不是 bug，是我的测量方法错了

**结论：项目代码没有问题，Flutter 也没有问题。问题出在截图/测量用的进程是
DPI-unaware 的。**

### 发生了什麼

调试期间截图上语音栏和输入框一直"消失"，看起来像窗口底部被裁掉。
这个现象**只在我这套截图中存在**，换 DPI-aware 的方式测量就完全正常。

### 真正的数值（150% 缩放，DPI-aware 测量）

| 来源 | 值 |
| --- | --- |
| Flutter `MediaQuery.size` | `1265.3 × 682.7`（逻辑） |
| Flutter `devicePixelRatio` | `1.5` |
| `GetClientRect`（**DPI-aware**） | `1898 × 1024`（物理） |
| `GetClientRect`（**DPI-unaware**，之前用的） | `1265 × 682` ← 虚拟化后的值 |
| `GetDpiForWindow` | `144` |

Flutter 的值是**完全自洽**的：`1265.3 × 1.5 = 1898`，`682.7 × 1.5 = 1024`
—— 正好等于窗口的物理客户区。没有任何裁剪。

### 误导是怎么产生的

Windows PowerShell 默认是 DPI-unaware，被系统虚拟化到 96 DPI：

- `GetClientRect` 返回的是**虚拟化后的尺寸**（真值 ÷ 1.5）
- `CopyFromScreen` 按虚拟化坐标截屏，于是只截到了窗口左上角约 2/3

100% 缩放时虚拟化 == 物理，我的坐标碰巧是对的 —— 所以那次"100% 正常"的
对照实验看起来像是印证了 DPI 假设，实际是**假阳性**。150% 下同样的方法
必然截不全，这才是"底部消失"的全部原因。

### 结论

- 应用在 150% 缩放下**渲染完全正常**，语音栏与输入框都在（数字见上表）
- 之前记录的"Flutter Windows embedder 尺寸不同步"**是错的，已作废**
- 曾经排到的 `FlutterDesktopGetDpiForMonitor` 与 `GetDpiForHWND` 的区别
  在这个 Flutter 版本下**不构成问题**：实测两者都返回 144

### 教训

**测 Windows DPI 相关的东西，测量进程本身必须先 `SetProcessDpiAwarenessContext`
设为 PerMonitorV2。** 否则拿到的是虚拟化数值，会得出完全错误的结论。
本次排查在这个坑上花了很长时间。

---

## 私聊与未读

在此之前**私聊消息收得到、存在视图里，但没有任何界面能打开它**——`ChatPanel` 只渲染
「当前频道」或「服务器」两个线程之一，`ConversationKey.client(id)` 永远不是「正在看的」那个。

现在：**点频道树里的某个人就打开与他的私聊**，聊天面板头部显示对方名字和一个返回箭头；
在那个线程里发出去的消息 `target` 是 `ClientTarget`，走的是同一个 `sendMessage`。

未读是 `ServerView` 上的一个集合（纯 Dart，可测）：有东西到达且不在正在看的线程里就加一个，
打开那个线程或走进那个频道就清掉。频道树与服务器切换器各有一个小圆点。
私聊的未读会显示在**对方所在的频道行**上——那是一眼找到「是谁找我」的方式。

规则本身在 [`docs/notifications.md`](notifications.md)。

---

## 开发用环境变量

`AppShell` 启动时会读取（仅用于自动化，不是用户功能）：

| 变量 | 作用 |
| --- | --- |
| `NIGHTCORD_AUTO_CONNECT` | 启动即连接。**逗号分隔多个地址**可一次连上多台，用于演练多会话 |
| `NIGHTCORD_NICKNAME` | 连接用的昵称 |
| `NIGHTCORD_PROFILE` | 身份档名。TS3 会拒绝同一身份的第二条连接，所以脚本化重跑必须换档名 |
| `NIGHTCORD_LOG` | 日志级别（如 `debug`）。优先于 `RUST_LOG` |
| `NIGHTCORD_LOG_DIR` | 覆盖日志目录；设为空字符串则只写 stderr 不落文件，便于测试不污染 `%APPDATA%` |

后两个对 CLI 同样生效，见 [`docs/logging.md`](logging.md)。

局域网地址不需要任何环境变量——`nightcord` 分支已把私有地址设为默认允许
（见 [`docs/tsclientlib-fork.md`](tsclientlib-fork.md)）。

---

## 与效果图的差异

- **多服务器**：按确认结论使用左上角下拉切换，而非 §21/§22 的顶部 tabs
- **文件消息**：§39 把它放在第二阶段。`Attachment` 模型与文件卡片已就位，
  但没有数据来源，下载按钮明确禁用并带说明
- **窗口装饰**：效果图是 macOS 风格，实际使用各平台原生窗口
