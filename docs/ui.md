# 客户端视觉层：设计系统与字体

两份规范——[`UI设计与配色规范.md`](UI设计与配色规范.md) 与
[`UI字体规范.md`](UI字体规范.md)——定义了长什么样。这份文档说的是**代码**：
东西放在哪、哪些地方与规范不一致以及为什么、这轮做到哪。

## 东西在哪

```text
apps/client/lib/design/          # AGENTS.md「三层 UI」的层 1，六端共享
├── tokens/                      # 规范原文的数字，一个不多一个不少
│   ├── app_colors.dart          #   配色规范 §2/§3
│   ├── app_fonts.dart           #   字体规范 §2/§5：locale → 家族
│   ├── app_typography.dart      #   配色规范 §5.2 + 字体规范 §3
│   ├── app_spacing.dart         #   §6 的 4px 网格
│   ├── app_radius.dart          #   §7
│   ├── app_shadows.dart         #   §8
│   └── app_motion.dart          #   §27
├── theme/
│   ├── app_theme.dart           # buildAppTheme(locale)
│   └── design_tokens.dart       # ThemeExtension：widget 唯一该读的那层
└── components/                  # 有第二个使用者的公共件
    ├── app_avatar.dart  app_badge.dart  app_banner.dart
    ├── app_section_title.dart  app_unread_dot.dart
```

`lib/theme/app_theme.dart` 与 `lib/widgets/avatar.dart` 已删除（内容拆进上面）。

**没有为每种控件包一层 `AppButton` / `AppInput`**（虽然最初的计划里有）：
`ThemeData` 的组件主题已经把 §10–§19 全部编码进去了，再包一层只是多一层间接，
而且会让人以为必须用包装器才能拿到规范样式。页面直接用 `FilledButton`、
`TextField`、`AlertDialog`，样式就是对的。只有**有真实重复**的东西才提成了
组件——头像（两个文件用）、未读点（三处）、状态徽章、区块标题（两份私有实现
合并）、横幅壳（崩溃与重连两种）。

## 主题做了什么

1. **把 `ColorScheme` 填满。** 之前只填了 5 个角色，剩下约 25 个走 Material 3
   默认的紫灰——下拉框、开关、滑块、对话框因此**根本不在配色里**。现在每个
   M3 都会读的角色都有值，`surfaceContainer*` 五级按 §35 的明度阶梯铺开。
2. **`surfaceTint` 设为透明。** M3 会按高程给表面糊一层紫，那正是 §8 禁止的发光。
3. **`fontFamily` 按 locale 选**（字体规范 §5），`TextTheme` 十五个槽位全部填满——
   留空的槽位不是「没用到」，而是 Material 的默认字号。
4. **组件主题**：input / tooltip / dialog / bottomSheet / snackBar / popupMenu /
   dropdown / segmentedButton / switch / slider / divider / listTile / card /
   iconButton / 三种 button。
5. **反馈状态恢复了。** 之前全局 `NoSplash.splashFactory`，连按下都没有反馈，
   只剩 hover——而 hover 恰恰是键盘用户永远看不到的东西。现在 hover 用
   `white@8%`（§28 自己举的例子：`#50486C` 加上它就是 `#686080`）。

顺带修掉：`buildAppTheme()` 原先在 `build()` 里调用，每帧重建一个 `ThemeData`；
现在只在语言变化时重建（字体家族跟着 locale）。

## 两份规范打架的地方

规范之间、以及规范与现状之间有四处冲突，都在代码里裁过并留了注释：

| 冲突 | 裁定 | 在哪 |
| --- | --- | --- |
| 配色 §5.2 有 `overline` **11px**，字体规范 §3 写「最小字号 12px」 | **12px 下限生效**，`overline` 不进字阶，全app 没有 11px 的文字 | `app_typography.dart` |
| 配色 §12.2 / §15 用了三个 §3 没列出的颜色（`#C0BBCD` / `#443C68` / `#E8E5F0`） | 补成命名 token（`rowText` / `rowHoverBg` / `rowHoverText`），并注明它们是补充项 | `app_colors.dart` |
| 配色 §2.8 的窗口控制三色 | 照 §3 定义，但**没有接线**——窗口用的是系统标题栏 | `app_colors.dart` |
| 字体目录：AGENTS.md 写 `lib/design/`、配色 §31 写 `lib/theme/`、字体 §12 写 `lib/core/theme/` | 统一到 `lib/design/`（用户拍板；AGENTS.md 的「三层 UI」层 1） | 本文件 |

**还有一处没改**：配色 §21 说频道侧栏 240–280，现状是 **288**（`channel_sidebar.dart`
上方有注释）。那属于布局，这轮明确不动。

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

## 这轮没做

- **布局**：Server Rail、独立成员栏、移动端 Shell、窗口自绘标题栏——
  配色规范 §20–§23 那一层整块留到下一轮。
- **浅色主题**：§30 明说浅色必须重新设计而不是由 `Color.lerp` 推导，目前只有深色。
- **§27 的动效只用到一处**（聊天滚到底），其余时长与曲线已备好但还没有地方用。
- **§29 的无障碍只做到颜色不是唯一信号**（徽章有 tooltip、图标有语义），
  完整的语义树走查没做。

## 相关

- [`UI设计与配色规范.md`](UI设计与配色规范.md)、[`UI字体规范.md`](UI字体规范.md) —— 规范本身
- [`localization.md`](localization.md) —— 语言怎么决定，以及它为什么决定字体
- [`client.md`](client.md) —— 客户端整体
- `apps/client/test/design_test.dart` —— 把上面这些约束变成断言的地方
