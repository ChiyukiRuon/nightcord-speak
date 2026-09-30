# 通知（Milestone 0.6）

## 为什么有它

§43 的要求很短：

```text
事件：Someone joined / left、Private message、Channel message、Poke、
      Connection lost / restored
由 Rust Event 产生。
Flutter 决定怎么显示。
```

事件**早就全都有了**，也一直在往 Flutter 流。核心不需要任何改动——所以这一项的实质
不是「产生通知」，而是**「什么时候不该打扰用户」**。一个照着 §43 直接写出来的版本会
在每次连接时刷上百条通知。

---

## 三种送达方式，三种意图

| 方式 | 什么时候 | 意图 |
| --- | --- | --- |
| **浮层**（右下角，4 秒） | 窗口在前台、且那件事不在屏幕上 | 「看一眼，但别丢下你手上的事」 |
| **未读点** | 任何时候，只要不是正在看的线程 | 「回头有一个地方要你去」 |
| **系统通知** | 窗口**不**在前台 | 「你可能不在这个应用里，所以我出来找你」 |

浮层刻意不用 SnackBar：`ScaffoldMessenger` 一次只显示一条、每条占满时长，
忙碌一分钟会排成长队且延迟送达——而应用已经把它用于错误提示（10 秒是那里对的时长）。
浮层最多三条、点一条就跳过去。

**连接类事件不弹浮层**：重连横幅已经在窗口顶部横着，再给一个说同样话的浮层是噪音。
它们只走系统通知（窗口在后台时你才需要被告知）。

---

## 三个坑，以及为什么规则长这样

**① 首次快照会把所有人报成「刚加入」。**
`diff::between` 的契约就是「第一次快照，什么都是新的」，而它在**每次握手后**都跑——
连接时、以及每次重连时。`EventBus` 自己的注释就写着「连上时可能有一百个客户端加入」。
天真的「有人加入就通知」等于每连一次刷一屏。

两条规则一起挡住它：

- **握手后 2 秒内不报进出**（`replayWindow`）。窗口而非计时器：握手那一批在同一批里
  到达，而 2 秒比 CLI 的 400 毫秒 settle 宽——后者只覆盖它本来就要打印的一串，
  前者不能把慢网络下的真实加入吞掉。
- **已经在视图里的人不算「加入」**。这条对**重连**不管用（服务器每次重连都发新 id），
  但能挡住同一连接内的重放，而且成本只有一行。

**② 自己的消息可能被回显。**
`publish_book_event` 对自己的 `invoker.id` 没有任何过滤，而从这一侧看不出 tsclientlib
会不会把我们的消息当 book event 回送。所以按 id 过滤（不是按昵称——一个服务器上
两个人可以同名）。一条「你刚说了什么」的通知比漏掉一个罕见情况更糟。

**③ 私聊原本没有可打开的界面。**
`ChatPanel` 只渲染「当前频道」或「服务器」，`ConversationKey.client(id)` 永远不是
「正在看的」那个——消息收得到、存在视图里，就是没有入口。所以这一轮顺带补上了：
**点频道树里的某个人就打开与他的私聊**，聊天面板头部显示对方名字与一个返回箭头。
没有它，私聊通知点了没地方去，未读也永远清不掉。

---

## 「别打扰正在看的」

已确认的规则：**事件就发生在你正在看的那个线程里，就不提醒**——消息已经在你眼前，
浮层只会把它盖住。

`Attention`（正在看什么）有三个输入，其中两个是容易搞错的：

- **哪个服务器在前台**：不能用 `activeSessionProvider` 就完事。`AppShell` 在它为空时
  会回退到最新的 session，所以「屏幕上是哪个」必须镜像那条回退，否则刚连上的一瞬间
  规则会判错。
- **哪个线程**：用 `ServerView.shownConversation`（手动打开的线程，否则回退到所在频道）。
- **窗口在不在前台**：`WidgetsBindingObserver.didChangeAppLifecycleState`。这是应用
  唯一知道的「用户走开了」，也是桌面通知唯一的触发条件。

`channel:1` 在每个服务器上都叫这个名字，所以判断要**同时**看 session 与线程。

---

## 哪些事件永远不出通知

除 §43 的六项之外的一切。其中一个值得点名：**`ServerInfoChanged` 永不通知**——
它承载在线人数，几乎每次进出都会发（`ts-events` 自己的文档写着），绑上去等于把
每个到达翻倍。

`OwnClientIdentified` / `PermissionsChanged` / `CapabilitiesChanged` / `ChannelUpdated` /
`ClientUpdated` / `ClientMoved` / `Speaking` / `VoiceStateChanged` 同理：界面会重画的东西
不是新闻。

---

## 系统通知：桌面插件与它的 Windows 风险

`local_notifier` 一个包覆盖 Windows / macOS / Linux。**移动端插件没加**：仓库里只有
`windows/` 一个平台目录，`android/` 与 `ios/` 根本不存在，应用也从未在那两个平台上构建过。
插件只在 `lib/util/system_notifications.dart` 一个文件里出现，将来换掉或补移动端只动那里。

**风险与实测结果**：Windows 上非打包应用的 toast 通常需要 Start Menu 里一个带
AppUserModelID 的快捷方式，而本仓库的 runner 是原版模板，一个都没有。首次启动时
插件确实报了 `Error, shell link not found`——**然后它自己把那个 `.lnk` 创建了出来**，
第二次起就正常。已实测：应用在后台时收到「后台测试员 加入了服务器」的 Windows toast。

失败路径仍然有兜底：`initSystemNotifications` 与 `showSystemNotification` 都不抛，
把原因写进 core 的日志（`warn`）而不是静默消失。

---

## 相关

- `lib/state/notifications.dart` —— 判断规则，无 BuildContext；时钟与文案表都可注入。
  文案是 `AppLocalizations Function()` 而不是现成实例：切语言不该重建 policy（会重置
  重放窗口），细节见 [`docs/localization.md`](localization.md)
- `test/notification_test.dart` —— 19 条，包括两个坑各自的回归与一条语言切换
- `lib/features/notifications/notice_stack.dart` —— 浮层与未读点
- `lib/util/system_notifications.dart` —— 插件唯一出现的地方
- [`docs/settings.md`](settings.md) —— 开关存在 `settings.json` 的 `notifications` 一节
