# 本地化

M0.6 的一项：Flutter 客户端支持 **zh + en** 两种语言。语言选择随
`settings.json` 持久化，可以在设置里切换，默认跟随操作系统。

`DEVELOPMENT.md` §70 只列了「Localization」一词，本文记录实现时的全部决定。

---

## 1. 工具与文件

官方 `flutter gen-l10n`，没有自造的 l10n 层，也没有第三方包：

| 文件 | 作用 |
| --- | --- |
| `apps/client/l10n.yaml` | 生成配置：模板、输出位置、回退顺序 |
| `apps/client/lib/l10n/app_en.arb` | **模板**。所有 key 与 `@` 元数据（占位符类型、说明）都在这里 |
| `apps/client/lib/l10n/app_zh.arb` | 中文翻译，只有 key: 值 |
| `apps/client/lib/l10n/app_localizations*.dart` | **生成产物，提交进仓库** |
| `apps/client/lib/l10n/labels.dart` | 枚举的 UI 标签（模型层不引入 l10n） |
| `apps/client/lib/l10n/errors.dart` | `ClientError` 的句子（同上） |

**为什么生成产物要提交**：`flutter pub get` / `run` / `build` 会自动跑 gen-l10n，
但 **`flutter analyze` 与 `flutter test` 不会**——而这两条正是门禁。不提交的话，
克隆后第一次 `flutter analyze` 就会因为找不到 `app_localizations.dart` 而变红。
改了 ARB 之后跑一次 `flutter gen-l10n`，把生成文件一起提交。

**为什么英文是模板**：模板是缺翻译时的回退目标。对非中文用户回退到英文比回退到
中文合理；`@` 元数据也只维护一份。

---

## 2. 语言如何决定

三层，从具体到兜底：

1. `settings.json` 的 `ui.language`：`"zh"` 或 `"en"`；
2. 值为 `null`（选「跟随系统」，或文件写在这些键之前）→ 操作系统语言；
3. 系统语言既不是 zh 也不是 en → 回退**英文**（`l10n.yaml` 的
   `preferred-supported-locales: [en, zh]` 决定顺序）。

四个刻意的决定：

- **core 存而不用。** `UiSettings` 在 `ts-settings` 里，但 core 从不读它——因为
  `settings.json` 是应用唯一的偏好文件，为「前端的东西」另开存储会多出第二个真相。
- **不认识的值按「跟随系统」处理，而不是让文件算坏**（`UiSettings.requestedLanguage`）。
  手改一个 `"fr"` 只损失这一项偏好，不会连带重置昵称、设备、快捷键；值本身保留在
  文件里，将来支持法语时还在。
- **解析只发生在一处**：`providers.dart` 的 `localeProvider` 返回一个具体的
  `Locale`（绝不为 null），`MaterialApp.locale` 直接用它。这样系统通知那条路
  （没有 BuildContext）拿到的是同一个答案，窗口与通知不会说两种语言。
- **启动失败屏只有系统语言**：`startup_failure.dart` 在 ProviderScope 之外，
  出现时 core 没起来——而语言设置归 core 管。

启动时的第一帧到设置返回之间，界面是系统语言；core 答完如果设置说别的，
整棵树立即换过来。没有阻塞首帧，因为等一个文件 IO 才画界面更糟。

---

## 3. 没有 BuildContext 的地方怎么拿文案

两处组句发生在 widget 树之外。做法一致：**状态层只存数据，句子在渲染期组。**

### 错误

`ClientError` 现在只有 `kind` + 原始 `detail`（`lib/models/events.dart`）；
人类可读的句子在 `l10n/errors.dart` 的 `describe(l10n)` 里组，由 SnackBar 渲染点
调用。core 发来的自由文本（`detail.message`）**原样透传**——它已经是这件事最具体
的说法，包一层只会加字。Dart 侧自造的错误用文档化的 kind：

| kind | 谁造 | 含义 |
| --- | --- | --- |
| `command_failed` | `providers.dart` | 命令失败且 core 没给原因 |
| `lagged` | `providers.dart` | 界面跟不上，丢了 N 个事件（`detail: {'missed': n}`） |
| `unparsable` | `ffi/rust_client.dart` | core 的事件解不开（`detail: {'message': ...}`） |
| `join_denied` | `channel_sidebar.dart` | 本地权限快照拒绝加入频道 |

为什么不解析时就组句：解析发生在 `rust_client.dart`（那里没有语言），而且提前组句
会让「切换语言前产生的错误在切换后仍显示旧语言」。现在这类句子总是按**显示时**的
语言渲染。

`ClientError.debugMessage` 是给日志与测试用的英文原文，UI 不用它——日志保持英文
是 §4.1 的约定，core 自己的话不进 ARB。

### 通知

`NotificationPolicy` 接收的是 `AppLocalizations Function()` 而不是现成实例。

**为什么是 getter**：policy 只在通知开关变化时重建，与 session 同寿。如果在切语言
时重建它，`_connectedAt` 会被清掉、2 秒重放窗口会重新武装——重连后会把服务器上
所有人再播报一遍。getter 让切换只影响下一句话。

---

## 4. 枚举标签

`VoiceActivationMode` / `ShortcutAction` 的 `label` 从模型层移到了 `l10n/labels.dart`
的扩展方法。两个原因：模型是数据、标签是展示；以及 Dart 的扩展方法与实例成员同名
时会被**静默遮蔽**——`mode.label` 仍会调用旧的中文 getter，把 bug 藏起来。

`ShortcutAction` 的日志行从中文标签改成了 `action.name`（枚举名本身就是英文）。

---

## 5. 什么不本地化

| 类别 | 例子 | 原因 |
| --- | --- | --- |
| 品牌 | Nightcord Speak / TeamSpeak 3 / TS3 | 专有名词 |
| 用户与服务器内容 | 消息、昵称、频道名、话题、设备名 | 数据不是文案 |
| 物理键名 | `Ctrl` / `Shift` / `M` | 键盘上印的字不随语言变 |
| 文件大小单位 | `B` / `KB` / `MB` / `GB` | 通用 |
| core 的自由文本 | `malformed request: ...` | 原样透传，见 §3 |

---

## 6. 已知边界

- **时间戳固定 24 小时制**（`formatTimestamp`）：两种语言都用 `H:mm`。做地区时钟
  约定（en 的 AM/PM）要动 intl 的日期符号，留作后续——`intl` 已是依赖。
- **Windows 窗口标题不随语言变**：标题在 `windows/runner/main.cpp` 里启动时写死为
  品牌名 `Nightcord Speak`；运行中改它需要 `window_manager` 类插件，为装饰性需求
  不值得。`Runner.rc` 的 `FileDescription` / `ProductName` 同步为品牌名
  （`InternalName` / `OriginalFilename` 保持 exe 的实际文件名）。
- **运行中改系统语言不重解析**：`MaterialApp.locale` 从 provider 取具体值；系统语言
  变化不会触发重算。桌面端换系统语言本来就要重启，影响可忽略。
- **翻译是机器与人工结合的产物**：英文由开发者撰写、中文取自原文；两种语言都只有
  一个维护者，文案改动时以 `app_en.arb` 为起源。

---

## 7. 加一条文案 / 加一种语言

**加文案**：`app_en.arb` 加 key 与 `@` 元数据（带占位符的必须写 `"type"`，否则生成
的参数是 `Object`）→ `app_zh.arb` 加同一个 key → `flutter gen-l10n` → 一起提交。

守卫：`test/l10n_test.dart` 直接比较两份 ARB 的 key 集合——gen-l10n 对「翻译缺失」
是**静默回退到英文**的，那会表现为中文界面里冒出一句英文，没人会注意到。

**加一种语言**：加 `app_xx.arb` → 在 `l10n.yaml` 的 `preferred-supported-locales`
里排出回退顺序 → `UiSettings.requestedLanguage` 的白名单加值 → 设置里的语言下拉加
一项。除此之外没有别的地方认识具体的语言代码。
