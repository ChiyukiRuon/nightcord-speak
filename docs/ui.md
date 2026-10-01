# 客户端视觉层：设计系统与字体

两份规范——[`UI设计与配色规范.md`](UI设计与配色规范.md)（**v2.0**）与
[`UI字体规范.md`](UI字体规范.md)——定义了长什么样。这份文档说的是**代码**：
东西放在哪、哪些地方与规范不一致以及为什么、做到哪了。

## v2 换掉了整套颜色

v2 的修订说明写得很直白：上一版「偏灰、偏蓝」，修正的方式是**把每一个面色
重新给值**，并给背景组换了名字。§41 禁止 8 进一步规定：上一版的颜色不得再
作为核心 token 使用。

| 组 | v1 | v2 |
| --- | --- | --- |
| 主背景 | `backgroundPrimary` `#484868` | `bgMain` `#4F486E` |
| 侧栏 | `backgroundSecondary` `#383060` | `bgSidebar` `#3F3661` |
| 深层 | `backgroundTertiary` `#302850` | `bgDeep` `#302850`（不变） |
| 浮层 | `backgroundElevated` `#50486C` | `bgElevated` `#554C75` |
| Surface | `#50486C` / `#686080` / `#78708E` | `#5A5278` / `#696180` / `#7A7190` |
| Primary | `#887EB4` | `#8C82C2`（四个状态色同步换） |
| 文字 | 二/三级 `#D0CBDD` / `#A7A1B8` | `#D2CCDE` / `#AAA3BB` |
| 边框 | `#5B5678` / `#68627F` / `#79718F` | `#575071` / `#625A7C` / `#766D8D` |

语义色（成功/警告/错误/信息）、在线状态色、窗口控制色、字阶、间距、圆角、
阴影、动效**都没有变**。

`design_test.dart` 里有一组断言把上面这些逐条钉住，另有一组**禁止 v1 的值出现**
——两套调色板很接近，抄错一个只会让界面「差不多对」，而差不多对是最难发现的。

## 三套主题

客户端内置三个主题，设置 →「界面」里切：

| 主题 | 是什么 | 来源 |
| --- | --- | --- |
| **Nightcord** | 深紫蓝，**默认** | 配色规范 v2 原文，逐值照抄 |
| **Black** | 中性近黑 | **本仓库自己定的**，规范里没有 |
| **White** | 中性浅色 | **同上** |

「跟随系统」不是第四个主题，而是一对：系统深色时用 Black，浅色时用 White。
实现上就是把这一对填进 `MaterialApp` 的 `theme` / `darkTheme` 两个槽位，
所以系统换主题时客户端会跟着换、不用重启。

**规范只定义了一套深色。** Black 与 White 保留的是规范给出的**结构**——同样的
token 名、同样的层级阶梯、同样的语义家族——颜色是新定的。两套中性主题的主色
也是中性灰，不带紫；Nightcord 的紫只属于 Nightcord。`theme` 字段存
`null`（缺省＝Nightcord）/ `nightcord` / `black` / `white` / `system`。

### 浅色主题为什么是「设计」出来的而不是「反色」

§37 要求浅色主题重新定义 Background / Surface / Border / Text / Primary
Contrast，而不是 `Color.lerp` 推出来。这条不是客套，有两处推导不出来：

**一、层级方向整个反过来。** 深色主题里「越高越亮」，所以弹窗是最深的那一档；
浅色背景上白之上没有更白，于是弹窗变成**最亮的**面，而侧栏、hover、选中这些
「凹下去」的东西是灰的。`design_test.dart` 里 Nightcord/Black 的阶梯断言是逐级
**升**，White 的是逐级**降**——同一个序列，两个方向。

**二、§27 的通知必须重配。** 规范的 toast 是**深底 + 近白字**（`textPrimary`）。
浅色主题里 `textPrimary` 是深色，照搬会变成深底深字，整个看不见。所以浅色的
语义色拆成「淡底 + 深前景」：`successBg #DDEFE4` 配 `success #2F6B4F`，四组
都是。`design_test.dart` 对**三套**都断言「文字与它所在的通知底色足够分开」，
这条就是冲着它去的。

### 主题切换是淡入的

`DesignTokens` 从「无字段、转发常量」改成了「持有一个 `AppPalette` 值」，
`lerp` 逐字段插值——`MaterialApp` 内部的 `AnimatedTheme` 每帧都会调它，
所以换主题是 200ms 交叉淡入而不是硬切。布局 token（间距/圆角/阴影）不是字段，
换主题不会让任何东西移位。

**这是当初把取色收进 `DesignTokens.of(context)` 的回报**：35 处取色全走 context，
页面、组件、状态层一行没改就支持了三套主题。

## 东西在哪

```text
apps/client/lib/design/          # AGENTS.md「三层 UI」的层 1，六端共享
├── tokens/                      # 规范原文的数字，一个不多一个不少
│   ├── app_colors.dart          #   配色规范 §3–§10，外加 §18/§19 各自点名的两个
│   ├── app_fonts.dart           #   字体规范 §2/§5：locale → 家族
│   ├── app_typography.dart      #   配色规范 §12.2 + 字体规范 §3
│   ├── app_spacing.dart         #   §13 的 4px 网格
│   ├── app_radius.dart          #   §14
│   ├── app_shadows.dart         #   §15
│   └── app_motion.dart          #   §34
├── theme/
│   ├── app_theme.dart           # buildAppTheme(locale)
│   └── design_tokens.dart       # ThemeExtension：widget 唯一该读的那层
└── components/                  # 有第二个使用者的公共件
    ├── app_avatar.dart  app_badge.dart  app_banner.dart
    ├── app_logo.dart  app_section_title.dart  app_text_prompt.dart
    └── app_unread_dot.dart
```

### 品牌标记是画出来的，不是加载进来的

`AppLogo` 用 `CustomPainter` 画那个「月牙 + 两只眼」——源文件
`apps/client/assets/nightcord-logo.svg` 只有三个圆，而画布本来就会画圆和
even-odd 路径。为此引一个矢量图库、加一道构建步骤、再多一份要保持同步的
生成文件，都不值当；换成位图则要为每个尺寸导一份，而没导过的尺寸一定会糊。

`AppLogo` 默认取当前主题的 `primary`，所以三套主题下它都是对的——Nightcord
是那个紫，Black 是近白，White 是近黑。

Windows 的 `.ico` 由 `scripts/make-app-icon.py` 从**同一组数字**生成
（7 个尺寸，8 倍超采样后缩到目标尺寸——16px 下那两只眼睛不到一个像素，
需要这点余量）。之所以是个脚本而不是一次性生成的二进制：committed 二进制
如果没人能重新生成，也就没人敢动它。颜色用的是 Nightcord 的 `#8C82C2`
而不是 SVG 里的纯白——纯白标记在透明底上遇到浅色任务栏会整个消失，而应用
现在有浅色主题了；中间调的紫在明暗两边都看得见。

`lib/theme/app_theme.dart` 与 `lib/widgets/avatar.dart` 已删除（内容拆进上面）。

**没有为每种控件包一层 `AppButton` / `AppInput`**（虽然最初的计划里有）：
`ThemeData` 的组件主题已经把 §17–§27 全部编码进去了，再包一层只是多一层间接，
而且会让人以为必须用包装器才能拿到规范样式。页面直接用 `FilledButton`、
`TextField`、`AlertDialog`，样式就是对的。只有**有真实重复**的东西才提成了
组件——头像（两个文件用）、未读点（三处）、状态徽章、区块标题（两份私有实现
合并）、横幅壳（崩溃与重连两种）。

## 主题做了什么

1. **把 `ColorScheme` 填满。** 之前只填了 5 个角色，剩下约 25 个走 Material 3
   默认的紫灰——下拉框、开关、滑块、对话框因此**根本不在配色里**。现在每个
   M3 都会读的角色都有值，`surfaceContainer*` 五级按 §2.2 的明度阶梯铺开。
2. **`surfaceTint` 设为透明。** M3 会按高程给表面糊一层紫，那正是 §15 禁止的发光。
3. **`fontFamily` 按 locale 选**（字体规范 §5），`TextTheme` 十五个槽位全部填满——
   留空的槽位不是「没用到」，而是 Material 的默认字号。
4. **组件主题**：input / tooltip / dialog / bottomSheet / snackBar / popupMenu /
   dropdown / segmentedButton / switch / slider / divider / listTile / card /
   iconButton / 三种 button。
5. **反馈状态恢复了。** 之前全局 `NoSplash.splashFactory`，连按下都没有反馈，
   只剩 hover——而 hover 恰恰是键盘用户永远看不到的东西。现在 hover 用
   `white@8%`（§35 的例子是 `#5A5278 → #696180`，8% 白落在差一两个色阶的地方）。

顺带修掉：`buildAppTheme()` 原先在 `build()` 里调用，每帧重建一个 `ThemeData`；
现在只在语言变化时重建（字体家族跟着 locale）。

## 规范上没有写全、或者两份互相打架的地方

| 情况 | 裁定 | 在哪 |
| --- | --- | --- |
| §12.2 有 `overline` **11px**，`UI字体规范.md` §3 写「最小字号 12px」 | **12px 下限生效**，`overline` 不进字阶，全 app 没有 11px 的文字 | `app_typography.dart` |
| §18 给输入框点名 `#3A3260`、§19 给频道 hover 点名 `#51496F`，两个都不在 §11 的 `AppColors` 块里，也不在 §42 的表里 | 命名成 `inputBg` / `channelHoverBg`，注明来源是组件章节 | `app_colors.dart` |
| §10 的窗口控制三色 | 照定义，但**不接线**——窗口用系统标题栏，自绘标题栏不做（用户定，2026-10-02） | `app_colors.dart` |
| 字体目录：AGENTS.md 写 `lib/design/`、配色 §40 写 `lib/theme/`、字体规范 §12 写 `lib/core/theme/` | 统一到 `lib/design/`（用户拍板；AGENTS.md 的「三层 UI」层 1） | 本文件 |

**v2 反而修掉了 v1 的一处毛病**：v1 的 §12.2/§15 用了三个 token 表里没有的颜色
（`#C0BBCD` / `#443C68` / `#E8E5F0`），当时只好补成三个补充 token。v2 的 §19 把
它们换成了 `textSecondary` / `textPrimary` / 一个新的 hover 值，于是那三个补充
token 全部删掉了。

**还有一处没改**：§19 说频道侧栏 240–280，现状是 **288**
（`channel_sidebar.dart` 上方有注释）。那属于布局，这轮明确不动。

## 字体

**不进仓库**，由 `scripts/fetch-fonts.sh` 下载到 `apps/client/assets/fonts/`：

| 文件 | 大小 | 覆盖 |
| --- | --- | --- |
| `NotoSans-Variable.ttf` | ≈2 MB | 拉丁字母与符号 |
| `NotoSansSC-Variable.ttf` | ≈17.7 MB | 中日文汉字与假名 |
| `OFL.txt` | 4 KB | 许可证（OFL §1 要求随字体分发） |

只打包 en + zh 两套：App 的 `supportedLocales` 就是这两个，字体规范 §9 明说
不需要的语言不要打包。韩文、繁中字形由 Flutter 的**逐字系统回退**兜住——与
§8 让 Emoji 走系统字体是同一个机制。

### 实测过两件事

1. **可变字体的字重**：`fontWeight` **与** `fontVariations` 都能驱动 `wght` 轴，
   两者在同一字号下给出**完全相同的栅格宽度**（421.76 / 425.79 / 429.95 / 434.91
   对应 400/500/600/700）。`AppTypography` 两个都写——文档只承诺
   `fontVariations` 有效，两个都写则谁生效都对，且 `design_test.dart` 断言两者
   不许分家。
2. **缺字体时会发生什么**：`flutter analyze` 与 `flutter test` 都**失败**，
   分别是 `asset_does_not_exist` 与 `unable to locate asset entry`。这是刻意的，
   见 AGENTS.md §3.2。

### 字体家族名与 monospace

`fontFamily` 只在 `AppTypography` 里出现（字体规范 §7：widget 不许自己写）。
`monospace` 保留为一个**角色**而不是一个家族选择——日志路径、调用栈、按键组合
都需要等宽，Noto Sans 是比例字体，换掉只会更难读。

## 设置页：第一个左右布局的页面

设置原本是一个 480px 的 `AlertDialog`，六节内容摞在一条滚动里。现在是页面
（`lib/features/settings/settings_page.dart`）：左栏 240px 的分节导航，右侧当前一节，
六节各在 `sections/` 里一个文件。

- **左栏**：`bgSidebar`（§2.2 的导航面），行样式照抄频道行——选中 `surface1` + 文字
  `textPrimary` + `titleMedium`，hover `channelHoverBg` + `textPrimary`，其余
  `textSecondary` + `bodyMedium`。选中的判断与 hover 都是手写的（`MouseRegion`），
  因为 §19 连**文字颜色**都随状态变，而 `InkWell` 不管文字。
- **宽度 240**：§19 给 240–280，这里取下限——标签是一两个词，不是带话题和在线数的频道名，
  所以没有跟频道栏的 288 对齐。
- **右侧**：`Material(bgMain)`，内容最宽 640，节标题用 `titleLarge`（与聊天头部同级）。
  **必须是 `Material`，不能是刷了底色的 `Container`**：通知一节是 `SwitchListTile`，
  而 `ListTile` 把水波纹画在最近的 `Material` 上——中间垫一层纯色会让 Flutter 直接断言
  「ink 会被盖住」（第一次跑测试就撞上了）。
- **入口**：语音栏 ⚙ 与连接页标题行的 ⚙，都走 `SettingsPage.open`；这是仓库里第一个
  `Navigator.push` 的路由（此前只有 dialog 与 sheet）。

## 这轮没做

- **布局**：Server Rail、独立成员栏、移动端 Shell——
  配色规范 §28–§30 那一层整块留到下一轮。**自绘窗口标题栏（§10）不在其中：不做**
  （用户定，2026-10-02），两个平台都用系统标题栏。
- **浅色主题**：§37 明说浅色必须重新设计而不是由 `Color.lerp` 推导，目前只有深色。
- **§34 的动效只用到一处**（聊天滚到底），其余时长与曲线已备好但还没有地方用。
- **§36 的无障碍只做到颜色不是唯一信号**（徽章有 tooltip、图标有语义），
  完整的语义树走查没做。

## 相关

- [`UI设计与配色规范.md`](UI设计与配色规范.md)、[`UI字体规范.md`](UI字体规范.md) —— 规范本身
- [`localization.md`](localization.md) —— 语言怎么决定，以及它为什么决定字体
- [`client.md`](client.md) —— 客户端整体
- `apps/client/test/design_test.dart` —— 把上面这些约束变成断言的地方
