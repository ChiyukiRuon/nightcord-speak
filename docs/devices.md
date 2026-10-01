# 设备管理（Milestone 0.6）

## 为什么有它

`AGENTS.md` 给这一项的备注是「界面已有雏形」——设置对话框确实早就有设备下拉了。
所以真正的问题是：**除了「从列表里挑一个」，还缺什么？**

答案是：**`open_devices` 之后，没有任何东西往回报告过。** 选了麦克风之后你无法知道
它在不在收音；保存的设备不在了只有日志知道；设备被拔掉界面上什么都不会发生。
四项功能都指向同一个缺口——**设备的状态没有出口。**

---

## 一个命令，三个问题

```c
void nightcord_voice_status(handle);   // → command_result "voice_status"
```

```json
{
  "input":  { "id": "…", "name": "ROG CARNYX", "available": true, "fell_back": false },
  "output": { "id": "…", "name": "…", "available": true, "fell_back": false },
  "level": 0.03, "peak": 0.11, "transmitting": false, "healthy": true
}
```

它一次回答了三个此前没人能回答的问题：

| 问题 | 字段 |
| --- | --- |
| 麦克风在收音吗？ | `level` / `peak` |
| **实际在用的是哪个设备？** | `input` / `output`，含 `fell_back` |
| 设备还活着吗？ | `available` / `healthy` |

### 为什么是「拉」不是「推」

引擎每 20 毫秒产出一帧。以那个频率发状态事件会：

- 塞满事件队列——而 `ts-ffi/src/audio.rs` 开篇就写着它存在的意义是「让每秒 50 帧
  Opus 留在 JSON 边界之外」；
- 给每个前端的**通知规则**一个 50 Hz 的心跳要跟上。

所以调用方自己决定多久问一次。设置对话框开着时 200 毫秒问一次。

### `fell_back` 才是关键字段

「你用的是系统默认，因为**你选的**就是默认」和「你用的是系统默认，因为**你选的耳机
不在了**」——少了这个字段，两者在界面上长得一模一样，而只有后者值得告诉用户。

`resolve()` 的回退行为从第一天起就在（它的文档写着「logs what happened **so the UI can
say so**」），但那个「UI」从来没收到过任何东西。顺带修掉一条**误导的日志**：
回退之后成功日志打的是**请求的** id，读起来像「你那只拔掉的耳机工作正常」。

---

## 麦克风测试：静音着开始语音

采集流只存在于会话绑定的引擎里，而**一个麦克风开不了两条采集流**——`client.rs` 自己
写着。所以「开始语音之前单独测试麦克风」需要**第二套引擎与它自己的生命周期**
（会话外的槽、自己的 ticker、与正在跑的引擎互斥）。

**这一轮没做那套**，因为一个更省的事实：**静音时采集照常跑**。`should_transmit`
一律返回 false，一个包都不发。所以「静音着开始语音」本来就是一次麦克风测试，
而对话框里已经有那个按钮。已实测：

```
正在使用：麦克风（ROG CARNYX）
[▬______|__________________________]   ← 电平条有读数
低于阈值，未传输                        ← 而服务器那头一个包都没收到
```

代价写在这里：**测麦克风要先点一下「开始语音」**。

电平在**四种传输模式下都被记录**，赋值写在 `should_transmit` **之前**——
PTT、持续、静音三种模式都会让闸门短路，写在后面的话电平表在四种模式里有三种恒为 0，
而那正是人们用来测试麦克风的两种。这条有专门的回归测试。

---

## 热插拔：轮询，不是回调

cpal 的设备增删回调在各宿主上行为不一，而这一轮需要的只是「对话框开着时列表会更新」。
所以**设置对话框打开期间每 5 秒重新枚举一次**，关掉就停。

频率这么低是因为枚举很贵：它是同步的、每个设备几次 COM 往返，而且**跑在 worker 循环上**
——枚举期间别的命令都要等。这也是为什么它只在一个模态对话框开着时跑。
（状态查询是另一回事：读的是引擎早就有的数字，200 毫秒一次无所谓。）

---

## 顺带修掉的两个真 bug

**① `ClientEvent::VoiceStateChanged` 全仓库从未被发布过。** Dart 解析它、
`ServerView` 应用它、`ts-ffi` 的文档还写着「resulting `VoiceStateChanged` matters」，
但零个构造点。也就是说静音按钮显示的是**自己的乐观猜测**，核心永远不会纠正它——
`providers.dart` 那句「the core's `voice_state_changed` is what makes it stick」
描述的是一个从未到达的事件。今天两者恰好一致（`voice_intent` 记的是同一件事），
但那是巧合不是保证。

现在由 **ts-ffi 发布**，因为引擎住在那一层（`ts-core` 刻意不依赖 `ts-audio`，§2），
所以音频状态是出口的事。

**② 下拉的 `initialValue` 问题。** `FormFieldState.didUpdateWidget` **只对
`forceErrorText` 有反应、从不理 `initialValue`**（在装的 Flutter 3.47.5 SDK 源码里核实过）。
对话框等的是 settings 而不是设备列表，所以列表晚到时下拉会**一直是「系统默认」**，
而且「上次选的设备不在了」这句会在**列表还没到、或枚举失败**时也显示——把「读不到」
说成了「设备没了」。修法：用 `ObjectKey(devices)` 在列表到达时重建，
并且只在列表非空时才说那句话。

---

## 已知取舍

- **没有会话外的音频监视器**，见上。代价：测麦克风要先点「开始语音」。
- **没有 cpal 热插拔回调**，见上。代价：列表最多晚 5 秒。
- **播放音量**：总音量已是设置里的一项（`Playback::set_volume`，一个原子写，设备回调
  每帧读一次，不分配不阻塞），单人音量在成员菜单里，由后端按说话人施加。前者对新开的
  流也要生效，所以 `engine` 自己存一份并在 `open_with_volume` 时传进去；否则换一次设备
  就会把音量打回 1.0。测试提示音仍生成得很轻（振幅 0.2），但它走用户的增益，所以听到的
  就是通话时的音量。
- **`set_input_device` / `set_output_device` 仍是死代码**（`engine.rs`），而且后者会破坏
  会话持有的 sink 快照——换设备仍然走「改设置 → 下次开始语音」。记在 `AGENTS.md` 待办。

---

## 相关

- `crates/ts-audio/src/engine.rs` —— `measure()`、`input_level()`、`OpenDevice`
- `crates/ts-audio/src/device.rs` —— `resolve()` 现在返回*解析出来的*设备
- `crates/ts-ffi/src/client.rs` —— `device_json()`、`report_voice_state()`
- `lib/models/voice_status.dart`、`lib/features/settings/settings_dialog.dart`
- [`docs/audio.md`](audio.md) §5 —— 设备错误瞬态与致命的分类
