# 屏幕共享（TS6 Stream）

> **本文修订 `DEVELOPMENT.md` §74 与 `docs/ts6.md`。**
> 前者把「屏幕共享」列在 MVP 不做项里，后者把 TS6 的六条 `stream` 命令归到
> §72（Phase 8）。两者都已完成：TS6 的屏幕共享**已实现**，TS3 没有对应能力，
> 因此它是**能力**上的差异而不是里程碑上的欠账。

---

## 形状：信令走命令通道，画面走 WebRTC

`docs/ts6.md` 留过一个待确认的前提：

> TS6 的 screen share 是复用同一条 UDP 语音通道，还是另开信令通道
> ——这决定了它是否能搭在现有的 `ts-audio` 之上。

**两个都不是。** 答案是第三条路：

```text
        ┌──────────── 已连接的 TS6 命令通道 ────────────┐
        │  setupstream / joinstreamrequest / …          │
        │  streamsignaling（SDP、ICE，JSON 塞在一个参数里）│
        └───────────────────────────────────────────────┘
                             │ 换到 stream_id 与对端之后
                             ▼
        ┌──────────── 独立的 WebRTC 连接（P2P）──────────┐
        │  视频：采集端 → 观看端，一对一                │
        └───────────────────────────────────────────────┘
```

所以它**搭不到 `ts-audio` 上**，也**不应该**搭上去：语音是「所有人到所有人的
Opus 帧」，共享是「一个发布者到每个观看者的一条实时视频连接」。两条管线除了
共用同一条命令连接来交换参数之外没有共同点。

**核心因此不碰像素。** 实时画面永远不跨 FFI、不过网关、不进 Rust 内存。这一条
和 §2 硬规则 4（「音频尽量留在 Rust」）方向一致：能留在 Rust 的是**协议与状态**，
真正需要平台编解码和渲染的那部分交给有现成实现的层。

---

## 分工

| 层 | 负责 | 不负责 |
| --- | --- | --- |
| `ts-model` | `ScreenCommand` / `ScreenEvent` / `ScreenSignal`——传输无关的领域词汇 | 知道 TS6 的字段名 |
| `ts-protocol` | `ScreenSharing` trait + `Backend::with_screen` | 知道 WebRTC |
| `ts-protocol-ts6` | 六个命令的编码与解码（**唯一**知道 `setupstream` 等字面量的地方） | 碰媒体 |
| `ts-protocol-tsclient` | `UnknownCommand` 透传、`ScreenExtension` 钩子、`Command::Extension` 发送 | 判断命令语义 |
| `ts-ffi` / `ts-gateway` | `screen` 命令的原样转发 | 解析 |
| Flutter `core/screen/` | `ScreenController`（谁在共享、谁在看、什么时候收摊） | 调用平台 API |
| Flutter `ScreenShareBackend` | 采集、编解码、播放、ICE——`flutter_webrtc` 提供的部分 | 决定状态 |

`ScreenShareBackend` 是**媒体层唯一的接口**。将来要做纯 Rust 媒体（§72 的方向），
换的是这一个实现，`ScreenController` 以上一行都不用改。

### 为什么是 `flutter_webrtc` 而不是 Rust 媒体

用户拍板前比较过两条路（本次实现的直接依据）：

| 比较项 | Flutter + `flutter_webrtc` | Rust 管理媒体 |
| --- | --- | --- |
| 桌面 | 采集/收发/渲染已集成 | 要选并整合采集、编解码、渲染三套方案 |
| Android / iOS | 已有平台适配（仍需权限与 iOS 的 Broadcast Extension） | 需要大量原生桥接 |
| Web | 直接接浏览器 WebRTC | 仍要补一整套浏览器媒体实现 |
| 脱离 Flutter | 需要另接媒体实现 | 有优势 |
| 性能 | 取决于底层引擎与硬件编码 | 用 Rust 本身不保证更低延迟或更低占用 |

结论：**六端目标下 `flutter_webrtc` 落地更快**，而 TS6 协议仍然完整留在 Rust——
换媒体实现的边界就是 `ScreenShareBackend`。

> 「Flutter 管理媒体」不等于用 Dart 逐帧编码：Dart 只调接口，编解码在底层
> WebRTC。所以这一条**不能**按「Rust 比 Dart 快」来比较。

---

## 线路词汇

六条命令，全部来自 webspeak3（`connector/src/main.rs`）——tsclientlib 的
declarations 里一条都没有：

| 领域命令 | TS6 命令 | 关键参数 |
| --- | --- | --- |
| `Discover` | `requeststreaminfo` | `clid` |
| `Start` | `setupstream` | `type` 2=屏幕 / 3=窗口、`accessibility` 1/2/3、`mode`=1（P2P）、`bitrate`（视频）、`viewer_limit`、`audio`（0/1）——全部来自 `ScreenOptions`，行为约束见下面「界面上的约束」 |
| `Stop` | `stopstream` | `id`、`reason` |
| `Join` / `Leave` | `joinstreamrequest` | `is_remove` 0 / 1 |
| `Respond` | `respondjoinstreamrequest` | `decision` 1 / 0、`offer` |
| `Signal` | `streamsignaling` | `json`（`{cmd, args}` 的 JSON 字符串） |

三个枚举取自 TS6 自己的 UI bundle（webspeak3 `publish.ts` 注明来自
`ts6-re/findings §10`），不是猜的：`type` 2=SCREEN 3=WINDOW，
`accessibility` 1=PUBLIC，`mode` 1=P2P。

**`streamsignaling` 的键名是不对称的，必须照抄。** 提议用 `args.offer`，应答用
`args.answer`，ICE 用 `args.{sdp, mid, mLine}`——同一个「SDP」在三个地方叫三个
名字。参考实现在这里注明了它**实测过**：写成 `{sdp: "<sdp>"}` 或直接给一个字符串，
**服务器照样接受，然后被客户端静默丢掉**——没有报错，只有握手就此停住。
所以 `ts-protocol-ts6/src/screen.rs` 里有一条测试专门盯着这个键名。

### 怎么知道谁在共享

两条路，各管一半：

- **`client_is_streaming` 跟着成员数据一起来**（`ClientEnterView` / `ClientUpdated`，
  声明里都是可选字段），所以「谁在共享」不需要额外查询——它就在
  `ClientFlags.streaming` 里，面板上的「观看 · 名字」直接由它生成。
  这也是 TS6 唯一一处**服务器主动推**的共享状态。
- **`requeststreaminfo` 只用来把 client id 换成 stream id。** 点是「观看」之后才发，
  回来的 `notifystreaminfo` 带 `id` 和 `name`，才是后续 `join` 与信令要用的那个 id。

> `docs/ts6.md` 记过 M0.4 时看到的一条警告：`InitServer` 里带了
> `client_is_streaming` 而声明里没有。那是**另一条命令**，无碍——
> `ClientUpdated` 声明了它，所以开关共享时这个标志会真的变。

### 两个必须记住的坑

**① 参数值是转义过的，只有 `get_str()` 会解开。**
`StreamItem::UnknownCommand` 交出来的 `content` 是**收到的原始命令行，仍然带着
TS 转义**（库自己的文档注释就是这么写的）。而 `CommandArgumentValue` 没有
`Display`，`get_raw()` 给的也是转义后的字节。SDP 里全是空格、换行和 `\`，
拿转义形态去解析会得到一段坏掉的 SDP。所以 `actor.rs` 里读参数一律走
`get_str()`，读不出来（非 UTF-8）就**跳过这一个参数**而不是整条丢掉。

**② 流的 id 是服务器给的，客户端不选。**
`setupstream` 不带 id，服务器用 `notifystreamstarted` 广播它分配的那个。所以
「点了共享」和「拿到 id」是两件事：

- 还没拿到 id 就取消 → 发不出 `stopstream`（没有 id 可发）。
- 服务器随后补来 `available`（`client_id` 是自己）→ 才知道该补一条 `stopstream`。

这条路径有回归测试（`late server acknowledgement after stop is stopped immediately`），
因为第一版就是在这里漏掉了一次停止。

---

## 界面住在哪

三个动作，三个地方，**按「这件事是谁的」分**，而不是按功能分：

| 动作 | 位置 | 为什么在这里 |
| --- | --- | --- |
| **发起 / 停止共享** | 底栏，AFK 按钮左边 | 和「离开」「静音」同类：**我**往服务器上发的一个状态，底栏就是放这类东西的地方。放在聊天上方单独占一条，等于把「我的状态」寄存在「别人的内容」那边 |
| **观看 / 停止观看** | 成员列表里那个人**自己的行**上，同一个徽章 | 「某某在共享」这个事实和「我要看」这个动作是**同一件事的两个视角**，拆成「徽章」+「按钮」会让一行里出现两个说的是同一件事的东西。徽章用 §9 的 online 色——共享是服务器在替对方承载画面，不是警告，recorded 那种红会说反 |
| **画面** | 浮在聊天上的小窗（可拖、可全屏、可关） | 共享是**一边看着一边说**的东西。在聊天上方占一条，正好在最需要看消息的时候把它们挤出去 |

徽章同时也是**我们自己那一行**的：`client_is_streaming` 对谁都一样，所以共享时自己的行上
也有一个，只是没有点击动作（看不了自己）。

错误（采集失败、被拒、超时、连接失败）走 **SnackBar**，不再有一条常驻的红字。

> **已知代价**：成员行的单击要等双击判定（那一行双击是开私聊），所以点「观看」到
> `discover` 发出去之间约 300ms。和连接页的保存行是同一个代价（`AGENTS.md` §7）。
> 用 `onTapDown` 可以绕开，但那样拖动列表也会触发。

## 界面上的约束，以及为什么

| 约束 | 为什么 |
| --- | --- |
| **只有 TS6 显示入口** | 判断的是 `capabilities.screen_stream`（§15 的能力位），不是协议版本号。TS3 后端没有 `ScreenSharing`，命令会得到 `Unsupported`——给一个必然失败的按钮比不给更糟 |
| **同频道** | 面板只列自己频道里标了 `streaming` 的成员；发布端也只接受同频道成员的 `join_requested`。跨频道要先换频道 |
| **观看上限只管自动放行** | 到达即满员时直接回 `decision=0`（发不出去的 offer 不如不发）；**发布者亲手批准的那一个可以超过它**——人读过名字之后说 yes 已经不是自动（参考实现同此） |
| **屏幕声音要自己打开，而且不是每个平台都有** | 「捕获音频」默认关。开启后走采集端自己的音轨：Windows 是 WASAPI loopback（窗口来源按该窗口的进程定向、屏幕来源是全系统）、浏览器是标签页音频；**macOS 与 Linux 的插件没有 loopback 采集器**，那里线上如实报 `audio=0`——不让观看者对着一个永远不响的控件。详见下面「屏幕声音」 |
| **隐私三档，只有公开是自动的** | `accessibility` 1=公开 / 2=联系人 / 3=私密。服务器不做守门人，私密与联系人由**发布端逐个批准**；联系人按私密处理——本客户端没有可核对的好友名单。详见下面「观看授权」 |

> 设置向导里每条的帮助文案写在选择旁边（`screenSetupHelp*`）：影响别人能看到什么
> 的事实在**按下之前**说清楚，比事后解释有用。

---

## 屏幕声音（2026-10-08）

一条音轨，加不加由发布者决定：

- **采集**：`getDisplayMedia({'audio': options.audio, …})`。插件的 Windows 实现拿它当
  WASAPI loopback 的开关——选窗口来源时按该窗口的进程定向（只有那个应用的声音），
  `source_id` 对不上或是屏幕来源时退回到全系统。浏览器把它交给自己的选择器
  （「共享标签页音频」）。
- **上行**：`offer` 把采集产出的**全部**轨道加进连接。此前只加 `getVideoTracks()`，
  于是设置一路走到了采集和服务器，唯独没进 offer——观看者永远听不到声音，而且
  一个字都不报（`AGENTS.md` §6 ㉗，与 ⑳ 同型）。音频发送者**只设码率上限**：
  `degradationPreference` 和分辨率缩放都是画面的事。
- **如实上报**：线上 `audio` 以「采集真的产出了音轨」为准，而不是以用户点没点开关
  为准。macOS 没有 loopback 实现、Linux 是返回 `nullptr` 的 stub（`loopback_capturer.h`
  的平台分支），那里开着的开关是一个无法兑现的承诺——线上一律报 0。参考实现同一规则。
- **下行**：观看端不需要写代码。桌面/移动的原生 WebRTC 把收到的音频自动从默认输出
  设备播放；Web 端插件的渲染器把远端音轨接到一个隐藏的 `<audio>` 元素自动播放
  （只有本地流静音，防回授）。**两处都只有源码依据，没有实机听过**。

## 观看授权（2026-10-08）

私密与联系人共享**逐个批准**观看者。界面是发布端的一张模态弹窗：一行一个请求
（「某某 想观看你的共享」+ 拒绝/允许）。Esc 关掉不回答任何事——请求留在队列里，
下一个到达会再弹；请求者自己放弃（观看端约 25 秒超时）或离开服务器时，那一行随之消失。

**为什么归客户端管**：服务器不做守门人。参考实现在真实服务器上证实过——它存下
`accessibility` 与 `viewer_limit`，然后把每个请求原样转发；一个标着私密、上限 1 的流
照样把两位观看者都报给了发布端。所以 `screen_controller.dart` 的 `join_requested` 里
「公开放行 / 非公开进队列」这一句就是全部的执行；批准后与公开走同一段 `_admit`
（开 peer、发 offer、`decision=1` 带 sdp）。

几个刻意的取舍：

- **满员在到达时就拒绝，不进队列。** 参考实现在满员时也会去问发布者，这里保留本地
  闸门的既有决定（「发不出去的 offer 不如不发」）——上限压的是自动放行。
- **发布者亲手批准可以超过上限。** 人读过名字之后说 yes，已经不是自动。参考实现同此。
- **没有「屏蔽」。** 参考实现允许把某个人记进本场屏蔽名单——拒绝并不粘，服务器不
  记仇，同一个人可以一直问。TS6 自己的命令预算压着刷屏，真被烦到再加；加的位置
  就是这个控制器。

## 独立窗口（2026-10-07）

把画面送到自己的系统窗口去。两个窗口是两个 Flutter 引擎，而**一个引擎用不了另一个
引擎的纹理**，所以这不是「把画面搬过去」，是交棒：新窗口自己开一条连接，主窗口让开。

### 做的时候踩到的东西

用户日志在本地时间 19:10:58、19:11:17 两次观看时均记录
`MediaStreamAddTrack() stream is null`；19:11:19 的崩溃笔记记录 `0xc0000005`
访问违规。崩溃笔记没有模块符号，不能仅凭地址确定最后触发崩溃的 C++ 函数。

已确认并修复的路径：

- 真实 TS6 复现确认：主窗口仍占用同一客户端的观看连接时，子窗口重复加入没有
  `join_answered`。交接改为先发送 leave、关闭旧 peer，再创建并加入独立窗口。
  弹出操作等待远端媒体到达，连接失败或超时则关闭子窗口并恢复内嵌观看。
- `flutter_webrtc 1.6.2+hotfix.4` 用全局 `g_host_messenger` 指向最近注册的引擎。
  子窗口关闭后该指针失效；随后主窗口创建新的事件通道会使用失效指针，第二次弹出
  前复现 `0xc0000005`。构建补丁改为按 `BinaryMessenger*` 查找所属引擎的原生
  messenger，事件通道保留自身引用，插件析构移除映射。已下载锁定版本的原始包，
  包 SHA256 与 lockfile 一致，确认此问题存在于发布包，无须修改 Pub 缓存。
- `onTrack` 的条件表达式后使用 cascade，导致**有远端 stream 时也调用 addTrack**。
  原生插件该方法只查本地 stream 表，远端 stream 不在其中，因此报空。改为复用远端流，
  不重复调用原生 addTrack；无 stream 时才创建合成流，并等待加入轨道完成。
  音视频事件串行处理、去重并合并，迟到的合成流会释放；远端轨道由 peer 管理，
  不当作本地采集轨道再次停止。
- “start” 原来发到 `WindowController` 通道，子窗口却在配对信令通道等待。
  统一通道；双方等待 handler 注册完成；主窗口订阅事件后再允许子窗口 discover。
- 每次打开使用独立通道；打开请求串行；失败清理窗口与订阅；重复点击被拦截。
  向子窗口发出的关闭命令先释放 peer，再销毁引擎。
- Windows 插件每个引擎都有一个 `FlutterWebRTCBase`，析构却调用进程全局
  `LibWebRTC::Terminate()`。关闭一个子窗口会清理其他引擎仍在用的 SSL/线程环境。
  构建时生成一个补丁编译单元：进程全局初始化只执行一次，全局环境保留至进程退出，
  每个引擎的 peer/factory 仍按自身生命周期释放。补丁在
  `apps/client/windows/cmake/webrtc_multi_engine.cmake`，不改 Pub 缓存；上游代码改变时
  构建明确失败，要求重新审查。此补丁仅用于 Windows，macOS 尚未验证。

原生回归工具 `apps/client/tool/screen_window_smoke.dart`：主引擎保持 WebRTC peer 存活，
连续创建、初始化、销毁 3 个子引擎，每次销毁后验证主引擎与新 peer 仍能创建 offer。

新增 `apps/client/tool/screen_video_smoke.dart` 使用产品的独立窗口和真实视频轨道；
默认本机视频，`NIGHTCORD_SCREEN_SMOKE_REAL=1` 使用单独测试身份接收真实 TS6 共享。
2026-10-07 本地时间 20:39–20:40，在 `192.168.31.128:9988` 连续两轮
内嵌观看 → 弹出 → 视频接收 → 关闭 → 重新观看通过，四次渲染均记录首帧，退出码 0。
这一测试覆盖真实发布端，补足此前只验证子引擎初始化/销毁的不足；macOS 尚未验收。

**标题栏关闭与返回小窗**：20:52 用户关闭独立窗口时产生新的 `0xc0000025` 崩溃笔记。
此前测试只调用主窗口的主动关闭方法，漏掉原生标题栏“×”的直接销毁路径。
子窗口现在拦截原生关闭，交由主窗口释放观众条目、取消转发，再清理子窗口 peer；
等待当前画面卸载、回复关闭调用后才执行原生关闭。窗口已经被销毁的通知只清理主侧
记录，不再向销毁中的引擎重复发关闭命令。崩溃笔记缺少符号，未断言最后崩溃函数。

独立窗口右上角新增“回到小窗”（含全部界面语言）；它先完成上述清理，再由原会话
重新观看同一发布者。标题栏“×”停止本次观看；两者均不停止主程序或发布者的共享。
21:00 真实 TS6 验证通过：原生关闭后主窗口继续观看并再次弹出，返回小窗后重新收到
视频，进程退出码 0。测试轮次间隔 8 秒；密集连续协商会触发服务器 `ClientIsFlooding`。

**快速重开限流（后续修复）**：21:04:48 用户第二次弹出时，服务器明确返回
`ClientIsFlooding`，不是窗口创建失败。原实现每轮发多条候选信令，且重复应答，
关闭再重开很快耗尽命令预算。此前增加测试间隔只能绕开问题，不能作为修复。

- 最多等待 2 秒收集 ICE，把已收集候选写入 SDP 对应媒体段，避免每个候选单发一条。
  本机原生 SDK 的 `getLocalDescription` 不包含这些候选，需显式合并；无法匹配媒体段
  的候选与迟到候选继续单发，不删除跨网络路径。完全相同的 offer 不重复应答，
  内容变化的 offer 保留正常重协商。
- 基础适配器保留服务端错误码；TS6 扩展仅对 `0x020c` 明确拒绝做 3/6 秒的两次
  延迟重试，总命令期限仍为 15 秒。权限拒绝、超时和不确定送达不重放，策略留在
  TS6 crate，core 与 UI 不判断协议错误编号。
- 独立窗口接收失败命令结果，重试耗尽会立即清理/恢复观看，不再空等媒体超时。
  媒体就绪判断同时要求远端轨道和本地 SDP 应答已提交，避免轨道事件先到时提前交接。

21:35–21:36 使用真实 TS6 连续三轮弹出、原生关闭、重新观看，无额外冷却间隔，
最后返回小窗通过。返回时确实遇到服务器限流，日志记录一次 3 秒后重试，随后渲染
首帧；共七次首帧记录、进程退出码 0。现已替代上一轮带 8 秒间隔的验证结论。
本机执行 3 轮通过，退出码 0；它不依赖服务器，不代表已验收真实 TS6 视频传输。
对应 Dart 回归覆盖通道选择/订阅顺序、已有远端流、并发音视频及关闭期间迟到结果。

**19:59 重试补记**：Windows Application 事件 1000 显示用户仍运行 Release 目录的旧版本，
而上一轮仅重建 Debug。旧 Release 仍报原来的 addTrack 错误，不能作为新修复的验证结果。
本轮补建 Release，后续验收必须核对实际可执行文件和媒体插件 DLL 的目录及更新时间。


## 采窗口会把窗口提到最前面（2026-10-08 用户确认已解决）

> **2026-10-08**：用户确认这条已解决。仓库里查不到对应改动（cmake 补丁、提交、已下载
> 的 libwebrtc DLL 都没有聚焦相关代码），**按用户实测为准记录**；`AGENTS.md` 的待办与
> §5.4 的相关段落已摘除。下面保留调查过程与已撤回的旧结论。

**现象**：共享一个窗口，或者只是预览它，那个窗口就会被提到最前面，而且不会自己回去。

**2026-10-07 复查修正**：此前把置前归因于「GDI 必须先翻到前面」并推导出
「只能重写发布端」，证据不足。当前依赖的 `libwebrtc.m150.7871.03`
[源码](https://github.com/webrtc-sdk/libwebrtc/blob/libwebrtc.m150.7871.03/src/rtc_desktop_capturer_impl.cc)
在 `RTCDesktopCapturerImpl::Start` 中显式调用 `FocusOnSelectedSource()`；构造函数调用的
是 `CreateWindowCapturer`，不是 `CreateRawWindowCapturer`。仅凭 DLL 中存在某个符号不能
判断实际选用了哪种采集器，探针调用崩溃也不能直接证明 API 未实现。

**本轮改进**：选择器的桌面预览改用插件已有的 `getDesktopSourceThumbnail`，不调用
`getDisplayMedia`，避免进入上述视频采集启动路径。该插件方法异步请求更新、立即返回缓存，
因此空缓存最多重试 10 次、间隔 100 ms；失败时保留来源选择，不回退到会置前的视频采集。
只加载选中来源，摄像头也只在选中后开启。所有预览请求串行释放，离开来源页、关闭对话框、
快速切换来源时，迟到的结果都会关闭；开始共享前等待预览清理完毕。

这是**静态缩略图预览**，并非实时视频。正式共享仍调用原来的采集路径，仍可能置前。
窗口被遮挡、最小化、受保护内容及 macOS/Linux 的缩略图表现尚待真机验收；本轮单测验证
调用路径与生命周期，不能替代原生桌面验收。上游缩略图实现参见
[媒体列表采集源码](https://github.com/webrtc-sdk/libwebrtc/blob/main/src/rtc_desktop_media_list_impl.cc)。

后续优先评估维护 libwebrtc 小补丁：让自动聚焦成为可选项，并验证背景窗口采集是否需要
显式启用 WGC；再决定是否值得更换发布端。**尚未构建或验证该 DLL 补丁。**
（2026-10-08 用户确认此问题已解决后，这条计划随之作废——记录留档。）

下面保留早期探针记录；其中「只能重写发布端」「GDI 必然置前」结论已由上述复查修正。

**早期调查**：`libwebrtc.dll` 里有**两套**窗口采集器——

```text
DesktopCapturer::CreateWindowCapturer    → DesktopCapturerDifferWrapper（fallback = WgcCapturerWin）
DesktopCapturer::CreateRawWindowCapturer → WindowCapturerWinGdi
```

WGC（Windows Graphics Capture）可以通过合成器获取后台窗口画面。早期根据符号推测
当前采集必走 Raw/GDI，这一推测已撤回；正式视频采集的显式聚焦调用见上面的源码。

**我们自己的探针验过**（`run/wgc-probe`，Windows 11 26220）：

```text
target: "桌面歌词"            ← 一个后台窗口
is the target in front?      false
CreateForWindow:             OK        ← Win11 放行
foreground while capturing:  同一个窗口
did the window move?         no        ← 没动
frame:                       252x924   ← 而且真的抓到了帧
```

**而「便宜的路」逐条查死了**：

| 看上去可行的钩子 | 实际情况 |
| --- | --- |
| `CreateCustomVideoSource` + `OnCapturedFrame`（`rtc_video_source.h`，注释写着「bypassing any underlying capture device」） | 头文件声明了，**DLL 里没实现** —— 调用直接段错误 |
| 自己实现 `RTCDesktopCapturer` 交给 `CreateDesktopSource` | 接口里**没有喂帧的方法**（只有 Start/Stop/source），帧的通道在 DLL 内部实现里 |
| `RTCVideoCapturer`（相机那条路 `CreateVideoSource`） | 同样只有 Start/Stop，**没有帧回调** |
| 换 field trial 让 shim 选 WGC | 那个 key 在 DLL 里根本不存在；shim 调的就是 Raw |

**早期方案**：自己拥有发布端（WGC 采集 + 编码 + 对等连接）是一个选项，
但不能据此排除修补现有 libwebrtc 的路线；缩略图预览也不需要自定义帧注入。

### 那件事的价钱（2026-10-07 查清，**没有开工**）

用户的要求是明确的：**采应用窗口不能把窗口提到前台**。这条要求目前**未满足**。
把它做完的价钱查清楚了，摆在这里备查：

| 环节 | 状态 |
| --- | --- |
| WGC 采窗口、不提窗口 | ✅ 已验证（上面那个探针） |
| `webrtc-rs` 能在这台机器上编译 | ✅ 编过（`webrtc 0.17.2`） |
| `webrtc-rs` **自己编码** | ❌ **它不编码**，只有 `TrackLocalStaticSample`，要自己喂已编码样本 |
| VP8 编码器 | ⚠️ `env-libvpx-sys` **不自带 libvpx**，要每台机器/CI 先编一份再指过去 |
| 本地预览 | ⚠️ 我们自己的帧要进 Flutter 得注册纹理，Windows 与 macOS 各写一遍 |
| macOS | ⚠️ 采集要另写一套（ScreenCaptureKit + VideoToolbox） |
| `webrtc-rs` 与 TeamSpeak 的 offer/ICE 互通 | ❌ **没验过**，且这条不成立则前面全白做 |

代价还包括**永久维护两套媒体栈**（Rust 发布端 + flutter_webrtc 观看端）。

**用户此前的决定：先记录自建发布端的成本，不开工。** 当时的产品行为是（预览已由本轮替换）：

- **屏幕 / 摄像头**：选中即预览，共享也不碰你的桌面。
- **应用程序（窗口）**：选择器**不会**为你点一下就开采集；点某个窗口后要按「预览」才会去看，
  按钮下面写着它会把这个窗口提到前面。**共享一个窗口时同样会提一次**——这一条绕不开。

> **两个探针在 `run/` 下**（仓库忽略，克隆后需要重建）。
> `run/wgc-probe`：Rust + `windows` crate，`GraphicsCaptureItem::CreateForWindow` +
> `Direct3D11CaptureFramePool`，挑一个**不在前台**的窗口抓一帧，前后各读一次
> `GetForegroundWindow`。上面的结论就是它跑出来的。
> `run/source-probe`：C++ + CMake，链 `libwebrtc.dll.lib`，调
> `LibWebRTC::Initialize()` → `CreateRTCPeerConnectionFactory()` →
> `CreateCustomVideoSource()`；最后一步段错误，就是「声明了没实现」的证据。

---

## 安全

- **SDP 与 ICE 永远不进 `Debug` 与日志。** 它们带着 DTLS 指纹、ICE 凭据和
  对端的网络地址。`ScreenSignal` / `ScreenCommand` / `ScreenEvent` 三个类型的
  `Debug` 都是手写的 `<redacted>`（§4.5），有测试盯着。
- 错误路径不回流载荷：`ScreenSharing::execute` 的失败只有
  `Unsupported` / `Timeout` / 服务器返回的错误，`serde_json` 的报错只有行列号。
- 长度有上限：流 id ≤256 字节、任何参数值 >64KB 或含 `\0` 一律拒绝，
  入站的 `json` 载荷同样限 64KB。
- 令牌与身份不受影响：信令走的是已经建立的那条连接，没有新的凭据。

---

## 验证到了哪一步

**已做**（全部是单测与静态检查）：

| 项 | 位置 |
| --- | --- |
| 六个命令的编码、三个枚举的取值、超长与空 id 被拒 | `ts-protocol-ts6/src/screen.rs`，4 条 |
| 入站 `notify*` 的解码、`answer` 键名、`is_remove` | 同上 |
| SDP 不出现 `Debug` 里 | 同上 |
| 没有 `ScreenSharing` 的后端回 `Unsupported` | `ts-session` 1 条 |
| 信令顺序（先 offer 后 ICE）、迟到采集被关掉、频道切换收摊、观看上限、系统停止共享、被拒绝、订阅者离场 | `screen_controller_test.dart`，8 条 |
| 入口按能力位显示（且住在底栏里）、按钮 → 命令 → 状态往返、从成员行进出一个共享 | `pages_render_test.dart`，3 条 |
| 能力位真的会到达前端（`capabilities_changed` + `screen_stream` 两个名字） | `ts-events` 1 条 + 上面那 3 条改用真实载荷解码 |
| 发布端的读数轮询随共享起停、同一读数不重复唤醒窗口 | `screen_controller_test.dart` 1 条 |
| **收端不依赖 `msid`** | ⚠️ **只有代码路径**——要验得和一个不带 msid 的发端连一次，`flutter_test` 里没有 `getDisplayMedia` |
| Windows debug 构建、Web release 构建、clippy、格式 | 门禁 |

> **入口一开始是不存在的**：`CapabilitiesChanged` 定义了、序列化了、Dart 也处理了，
> 就是没有任何后端发布过它，于是 `capabilities.screen_stream` 恒为 false，面板一次
> 都没画出来过——而当时所有的测试都是绿的。根因与修法见 `AGENTS.md` §6 ⑳。

**用户 2026-10-07 实测过两轮**，报回四条，都修了（`AGENTS.md` §6 ㉑–㉔）：

| 报回来的 | 根因 |
| --- | --- |
| 界面上找不到入口 | `CapabilitiesChanged` 从来没有被发布过 |
| 收不到别人的共享，但别人看得到我的 | `onTrack` 要求 `event.streams` 非空，而**发端没有义务在 offer 里放 `msid`**——TS6 官方客户端就没放 |
| **还是看不到画面** | `_VideoState._init` 里的 `renderer.muted = …` 抛异常。那个属性不是「别播自己的声音」，而是「静音麦克风」，在没有 `srcObject` 时必抛——异常把 `_init` 断在设 `srcObject` 之前，渲染器一次都没拿到流 |
| 浮动小窗拖不动 | 只有 32px 的标题条能拖，而手先抓的是那块 320×180 的画面 |

**每一轮修完都还没被人用过。** 拿到的唯一读数：

```text
screen: sending 1280x720 5.0fps (bandwidth)
```

即发布端自报被**带宽估计**卡住，不是 CPU。下一次要注意的是同一次会话里那句：

```text
screen: send parameters applied=true ... preference=MAINTAIN_FRAMERATE
```

它说明码率上限与降级策略**到底设上没有**。设上了却仍然被带宽卡成个位数帧率，
答案就不在降级策略上，而在**给它一个不需要那么多码率的画面**（限制分辨率），
或者干脆接受参考实现的选择（保分辨率、放弃帧率）。没看到那一行之前不要再猜。

剩下要确认的：

- 能不能收到官方客户端的共享，以及自己预览里看到的画面是不是实时。
- macOS / Android / iOS 上的采集与权限（iOS 需要 Broadcast Extension）未验证。
- 浏览器端：`getDisplayMedia` 需要用户手势与安全上下文，未在真机验证。

### 出问题时先看哪里

协议路径**每一条命令和每一个事件都记一行 `info` 日志**（只有类型、stream id、
client id；SDP 与 ICE 一律不进日志，§4.5）。发布端另有每 10 秒一行的自报：

```text
screen: send join stream=s client=2
screen: recv join_answered/signal stream=s client=2
screen: send parameters applied=true encodings=1 cap=[4000000] preference=MAINTAIN_FRAMERATE
screen: sending 1920x1080 29.6fps (none)
```

「帧率低」有三种互不相干的原因——带宽估计把画面缩小、机器来不及编码、采集本身
就没在出帧——`limited-by` 那一项是唯一能把它们分开的东西。

> 这一批日志是「看不到画面」那次唯一的线索：信令每一步都正常，只有一行
> `Can't be muted: The MediaStream is null` 露在外面。**先有日志，才有答案**——
> 上一轮写它们时并不知道要找什么。

---

## 怎么试

```bash
# 1. 起客户端（Windows）
cd apps/client && flutter run -d windows
# 2. 连 TS6 服务器，进一个有人（或第二个自己）的频道
# 3. 底部聊天区顶部出现「共享屏幕」→ 选屏幕或窗口
# 4. 另一个人点「观看 · 名字」
```

**已知的对齐差异**：webspeak3 的 ICE 服务器列表里还有一条
`stun:stun.l.google.com:19302`，这里**没有**——只用了 TeamSpeak 官方客户端用的
那两条（`turn.teamspeak.com`、`turn2.teamspeak.com`）。本项目的部署多在局域网，
host candidate 就够；跨 NAT 打不通时再补，那是一个要往外发查询的第三方端点，
不默认加上。
