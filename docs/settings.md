# 设置（Milestone 0.6）

## 为什么有它

在此之前，应用**只持久化一样东西**——客户端身份。用户能选的一切都活在某个前端的
内存里：在设置对话框里选一个麦克风，关掉对话框它就没了；重启应用，全部回到默认。

而且代码里有两处早就为「保存下来的值」铺好了路，只是一直没人走：

- `crates/ts-audio/src/device.rs:44-46` 写着 cpal 的设备 id 支持解析回来，
  **「这正是让保存的设备能跨重启存活的东西」**；`resolve()` 已经会处理失效的保存 id
  ——回退到系统默认并 `warn!`，它的测试注释甚至提到「手改过的设置文件」。
- `VoiceGate::set_settings`（`vad.rs:96`）、`TransmitPolicy::set_settings`、
  `VoiceEngine::set_settings`（`engine.rs:358`）三处都存在，**生产代码里从未调用过**。
  `vad.rs:12-13` 写着「线性而不是 dBFS：**阈值是给用户拖的滑块**」，
  `set_settings` 还特意设计成不关闭已打开的闸门——「用户拖动灵敏度滑块时不该听到
  自己被打断」。

这一项补上的就是那个「存哪儿」。

---

## 文件

```text
<应用数据目录>/settings.json
```

与 `identity/`、`logs/` 并列。目录本身来自 `ts_identity::app_data_root()`
——全项目唯一知道「本应用的每用户目录在哪」的地方，见 `docs/architecture.md`。

> 书签在**另一个文件** `bookmarks.json` 里，因为它含服务器密码而这个文件不含。
> 见 [`docs/bookmarks.md`](bookmarks.md)。

格式是**给人看的 JSON**：字段都有默认值，所以删掉一行就是重置那一项；出现未知字段
会被忽略而不是报错（旧版本遇到新文件也能读）。保存用「临时文件 + 重命名」，
中断的保存不会留下一个半截的文件——那会是一次静默的「设置全部丢失」。

```json
{
  "version": 1,
  "audio": {
    "input_device": null,
    "output_device": null,
    "mode": "voice_activation",
    "activation": { "sensitivity": 0.05, "attack_ms": 60, "release_ms": 400 }
  },
  "connection": {
    "nickname": "Nightcord User",
    "profile": "default",
    "max_reconnect_attempts": null
  },
  "notifications": {
    "presence": true,
    "poke": true,
    "channel_message": true,
    "direct_message": true,
    "connection": true,
    "system": true
  },
  "shortcuts": {
    "mute":         { "key": 458768, "ctrl": true, "shift": true, "alt": false, "meta": false },
    "deafen":       { "key": 458759, "ctrl": true, "shift": true, "alt": false, "meta": false },
    "push_to_talk": { "key": 458771, "ctrl": true, "shift": true, "alt": false, "meta": false }
  },
  "ui": {
    "language": null,
    "theme":    null
  }
}
```

`shortcuts` 的 `key` 是 **Flutter 的 `PhysicalKeyboardKey.usbHidUsage`**——物理键而不是
字母，因为快捷键要的是「手放在哪里」。代价是这一节不便手改，界面是它的编辑器，
见 [`docs/shortcuts.md`](shortcuts.md)。

`ui.language` 是 `"zh"` 或 `"en"`，`null` 表示跟随操作系统。core 存这一节但从不读它——
`settings.json` 是应用唯一的偏好文件，为前端的偏好另开存储会多出第二个真相。一个不认识的
值（手改的 `"fr"`）按「跟随系统」处理而**不会**让整个文件算坏，值本身也保留。细节见
[`docs/localization.md`](localization.md)。

`ui.theme` 是 `"nightcord"` / `"black"` / `"white"` / `"system"`。这里 `null` 的含义
**和 `language` 不一样**——它不是「跟随系统」，而是**默认主题 Nightcord**：一个写在
这个键存在之前的文件应当表示「应用发什么就是什么」，而不是把今天的默认值冻进文件。
「跟随系统」是一个要显式选的值（`"system"`），因为在系统深色时用 Black、浅色时用
White 是一对主题而不是一种模式。三套主题见 [`docs/ui.md`](ui.md)。

`input_device` / `output_device` 是 cpal 的 `"<host>:<device>"`，`null` 表示系统默认。
想知道该填什么，`cargo run -p ts-audio --example list_devices`。

### `max_reconnect_attempts`

一个字段表达三件事，因为 `ReconnectPolicy::should_retry(0)` 对 `Some(0)` 已经返回 false：

| 值 | 含义 |
| --- | --- |
| `null` | 永远重试（默认）。退避封顶 30 秒，服务器挂一小时也值得自己接回去 |
| `0` | 不自动重连。掉线即报错并结束会话 |
| `n` | 最多 n 次 |

---

## 损坏的文件为什么与身份文件处理不同

身份文件损坏是 `Err`，而且不能被糊弄过去——**把损坏读成不存在会悄悄铸出一个新客户端**，
用户的权限就没了。设置不同：`ts-core` 记一条 `warn!`、**保留原文件**、用默认值继续跑。

理由很直接：因为一个偏好文件而拒绝启动，是把一个化妆品级的问题变成了致命问题。
保留原文件则是为了让证据留在那儿——下一次保存会覆盖它，但至少用户有机会看一眼。

```
WARN ts_core::client: using default settings
     error="C:\Users\...\Nightcord Speak\settings.json: key must be a string at line 1 column 3"
     path="C:\Users\...\Nightcord Speak\settings.json"
```

消息里带着**文件名**，因为同一个错误类型也服务于书签文件——一句写着
「settings file」的文案在书签出错时是指向错误的。

已实测：把文件写成 `{ this is not json at all`，应用照常启动、照常连上服务器，
文件原样不动。

---

## 谁读它，什么时候生效

**核心拥有设置。** 前端只是它的编辑器——这样 CLI、Flutter、以后的 Web Gateway
看到的是同一份偏好，且只有一处真相。

| 设置 | 谁读 | 什么时候生效 |
| --- | --- | --- |
| 重连次数 | `ts-core`，填进 `ConnectionConfig.reconnect` | 下一次连接 |
| 设备 | `ts-ffi` 的 worker，`start_voice` 时 | 下一次「开始语音」。实际在用哪个可以从 `nightcord_voice_status` 看到，见 [`docs/devices.md`](devices.md) |
| 传输方式 | 同上，另外**改了就应用**到活着的引擎 | 立即 |
| 灵敏度 | 同上，同上 | 立即 |
| 通知开关 | 前端 | 立即（见 [`docs/notifications.md`](notifications.md)） |
| 快捷键 | 前端 | 立即重新注册系统热键（见 [`docs/shortcuts.md`](shortcuts.md)） |
| 界面语言 | 前端 | 立即整棵树换语言（见 [`docs/localization.md`](localization.md)） |

设备是唯一不能立即生效的：替换一条活着的 cpal 流意味着拆掉重开，在别人说话的时候做
这件事比等一等更糟。设置界面在设备下拉下面写明了这一点。

`voice_start` 的显式参数**优先于**设置，所以 CLI 的 `--input-device` 仍然名副其实；
传空就是用设置里的。

**静音不持久化。** 传输方式是偏好（Discord 与 TS 都这么分），「已静音」不是——
没人希望每次启动都发现自己被静音了。

---

## 一处被删掉的 ABI

传输方式变成设置之后，`nightcord_voice_set_mode` 就成了第二个改同一个值的入口。
对话框是它唯一的调用方，所以它被**从 FFI 导出里删掉**了，core 里的应用路径保留。

删掉之后 clippy 立刻报出 `parse_mode` 与 `Command::VoiceSetMode` 从未被构造——
所谓「两个入口会漂移」，这次是当场发生的。

---

## 已知取舍

- **写文件是按次发生的**。拖动灵敏度滑块只在**松手时**提交（`onChangeEnd`），
  否则每移动一个像素就是一次文件写入。代价：拖动过程中听不到变化，
  松手后才应用——而 `VoiceGate::set_settings` 保证那一下不会把正在说的话切断。
- **昵称与身份档在提交时保存**（回车或点到别处），不是每敲一个键。
- **设备改动要等下次「开始语音」**，见上。
- **改日志级别不在界面上**：需要 `tracing-subscriber` 的 reload handle，而 `ts-logging`
  刻意没有保留它（guard 停在 static 里）。留给「日志」那一项自己决定。

---

## 相关

- `crates/ts-settings` —— 结构、存储、`Some(0)` 的语义
- `crates/ts-core/src/client.rs` —— 它怎么被读进去、怎么进 `ConnectionConfig`
- `crates/ts-ffi/src/client.rs` 的 `apply_settings` —— 哪些改动能立即应用
- [`docs/reconnect.md`](reconnect.md) —— 退避表本身
- [`docs/logging.md`](logging.md) —— 另一个租户，住在同一个目录下
