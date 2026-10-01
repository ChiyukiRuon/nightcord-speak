# 快捷键（Milestone 0.6）

## §42 要什么

```text
Ctrl + Shift + M  →  Mute
Ctrl + Shift + D  →  Deafen
Ctrl + Shift + P  →  PTT
快捷键系统应该独立。
```

最后那句是这一项的形态：**一个系统**，而不是在已有的键盘处理上加三个 `if`。
此前整个客户端只有一处键盘代码——`voice_bar.dart` 里一个窗口内的 `Focus`，
按键写死、不可配置。

---

## 为什么必须是系统级

**PTT 的意义就是在游戏里按一下说话。** 那时窗口不在前台。窗口内的快捷键在最需要它的
场景下正好失效，所以这一项要么做到系统级，要么没做。

`hotkey_manager` 一个包覆盖 Windows/macOS/Linux，同时支持系统级与应用内，
并且有 `keyDownHandler` / `keyUpHandler` 两个回调——PTT 需要后者。

**已知风险与实测结果**：该包最后发布于 **2024-05**，比当前 Flutter 老不少。
实测：`flutter build windows` 通过，系统级热键生效（见下）。它也是 `local_notifier`
同一个作者，那个包在通知那一轮已经证明可用。

---

## 顺带修掉的一个真 bug

旧处理器这样判断组合（`voice_bar.dart`）：

```dart
event.logicalKey == LogicalKeyboardKey.keyP &&
HardwareKeyboard.instance.isControlPressed &&
HardwareKeyboard.instance.isShiftPressed
```

读的是**当前**的修饰键状态。于是**先松 Ctrl、再松 P** 时，`KeyUpEvent` 被判定为
「不是这个组合」而忽略，`_held` 永远停在 `true`——**一直发着，直到用户再按一次**。

`hotkey_manager` 按**注册的组合**投递松开事件，与修饰键此刻是否还按着无关，
这个毛病因此从机制上消失。同时 `Chord.matches()` 要求修饰键**精确匹配**，
Ctrl+M 不会被 Ctrl+Shift+M 触发（反之亦然）——有测试盯着。

---

## 模型：`Chord` 与 `ShortcutSettings`

`lib/models/shortcuts.dart`，与 `ts_settings::ShortcutSettings` 逐字对应。

**键存的是物理键的 USB HID 用途码，不是字母。** 在 AZERTY 键盘上 QWERTY 的 M 在
完全不同的位置，而快捷键（尤其 PTT）要的是「手放在哪里」，不是「打出了什么字母」。

代价：Flutter 只能 `findKeyByCode(code)`，没有按名字查的 API，所以存名字无法无损往返
——`settings.json` 里这一节是机器写的。**设置界面是它的编辑器**，文档在这里写明。

**`Chord.matches` 把修饰键当参数传，不去读 `HardwareKeyboard`。** 与
`NotificationPolicy` 注入时钟同一个理由：规则要能直接测，不需要键盘、不需要窗口。
那一句「先松 Ctrl 会卡住」因此有了一条纯函数的回归测试。

**「清空」与「没设置过」是两回事。** 每个动作是 `Option<Chord>`：文件里
`"mute": null` 是用户主动解绑，缺这个键则是「写在快捷键存在之前的文件」，只有后者回落到
§42 的默认。判断用 `containsKey` 而不是 `??`——这个区别很容易写错，而写错的后果是
用户清掉的快捷键每次启动都自己回来。

---

## 系统：一处注册，一处分发

`lib/features/shortcuts/shortcut_host.dart` 包住整个 shell：

- 设置一变就 `unregisterAll()` 再按新绑定注册；没变就不动。
- `HotKeyScope.system`：窗口不在前台也生效。
- 注册失败（组合被别的程序占了）**写进 core 的日志**。快捷键不工作是静默失效最难查的
  一种——它和「没绑定」在界面上长得一样。

`shortcut_host.dart` 是**唯一知道插件存在的地方**，其余代码只说 `Chord` 与
`ShortcutAction`。设置里的记录器（`chord_field.dart`）也是自己写的而不是用插件自带的
`HotKeyRecorder`：后者不处理 `Esc` 取消与清空，而且会把插件的 `HotKey` 泄漏进设置界面。

### 动作走的是和按钮同一条路

静音与耳聋不是「快捷键自己的实现」，而是调 `SessionsNotifier.toggleInputMuted` /
`toggleOutputMuted`——**语音栏的按钮也调同一个方法**。两份实现会漂移，而它们漂移的表现是
「按钮按了有用、快捷键按了没用」。

PTT 例外：它是瞬时的（按下说话、松开停），直接打给引擎，不经过会话——引擎只有一个，
与屏幕上在看哪个服务器无关。

---

## 记录器

设置里每一项是一个可以点的框：点一下，按下你想要的组合，**松开时提交**。

在松开时提交而不是按下时：按 Ctrl+Shift+M 会依次产生三个 key-down，
在第一个上提交就会把「Ctrl」本身记下来。这与灵敏度滑块只在 `onChangeEnd` 提交
是同一种纪律——别在按键过程中写文件。

`Esc` 取消，`Delete` / `Backspace` 清空（清空后该项显示「未设置」且不再触发）。

---

## 默认值与显示按平台分

|  | Windows / Linux | macOS |
| --- | --- | --- |
| 默认组合 | `Ctrl+Shift+M/D/P` | `Cmd+Shift+M/D/P` |
| 显示拼写 | `Ctrl` / `Shift` / `Alt` / `Meta` | `Cmd` / `Ctrl` / `Option` / `Shift` |

**默认值由 `ts-settings` 拥有**：serde 补齐后它总会把三个键都序列化出去，所以 Dart 侧
`ShortcutSettings` 里那两个 `const` 默认值在实际运行中走不到——它们是「core 还没答复」
的占位，以及手写文件的兜底。它们是 `const`，而 `const` 问不了自己在哪个平台，所以保持
Windows 拼写；真正管事的和真正显示的都在能问的地方。`apps/client/lib/models/shortcuts.dart`
里那段注释写明了这件事。

**显示**用 `defaultTargetPlatform` 而不是 `Platform.isMacOS`：后者读的是跑测试的这台
机器，两种拼写里只有一种能被覆盖到。主修饰键在两边都排最前，其余三个按 Apple 的顺序
（Control、Option、Shift），所以常见情形读作 `Cmd+Shift+M`，四个全占时也不会有歧义。

**注册路径不需要按平台分**：`uni_platform` 的扩展在 macOS 上会把 Flutter 的 HID usage
查 `kMacOsToPhysicalKey` 换成正的 Carbon 虚拟键码。这一段是读插件源码确认的——不确认
很容易误以为是错键。

## 设置没有可绑定的动作，但有 ⌘,

`MainMenu.xib` 里模板自带一个 `Preferences…`，`keyEquivalent=","` 配默认修饰键就是
**⌘,**——但它**没有 action 也没有 target，是个死的**。`MainFlutterWindow` 按 key
equivalent 找到它、接上 target/action，经 `nightcord/shell` 通道让 Dart 打开设置页。

采纳的是 macOS 的惯例而不是一个全局热键：设置本来就不该占一个系统级组合，而且菜单项
这条路不花任何注册成本。Windows 上仍只有齿轮与语音栏两个入口。

## 已知取舍

- **只做三个动作**。切频道、离开频道、断开、打开设置都可以绑，但 §42 只列了三个，
  每个动作都要有自己的边界处理。**「打开设置」在 macOS 上走的是 ⌘, 菜单项**（见上），
  不是第四个可绑定动作。
- **每个动作只能绑一个组合**。§42 没有多绑定的要求，仓库里也没有列表型设置节的先例
  （`BookmarkList` 是独立文件，不是设置的一节）。
- **手柄与鼠标侧键不支持**：插件只处理键盘。
- **设置里改键不影响已注册但注册失败的项**：失败会记日志，界面目前不显示失败状态。
  快捷键冲突本来就少见，等真有人撞上再说。

---

## 相关

- `lib/models/shortcuts.dart` —— `Chord` / `ShortcutSettings` / §42 的默认
- `lib/features/shortcuts/shortcut_host.dart` —— 插件唯一出现的地方
- `lib/features/shortcuts/chord_field.dart` —— 记录器
- `crates/ts-settings/src/lib.rs` —— `ShortcutSettings`（Rust 侧必须同时有这一节，
  否则 Dart 传过去的会被静默剥掉）
- [`docs/settings.md`](settings.md)、[`docs/audio.md`](audio.md) §30
