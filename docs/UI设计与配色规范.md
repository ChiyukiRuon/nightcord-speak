# 跨平台通讯客户端 UI Design System（修订版）

> 版本：v2.0\
> 适用平台：Web / Windows / macOS / iOS / Android\
> 技术栈：Flutter\
> 视觉基准：用户提供的 TeamSpeak / Nightcord 风格参考界面\
> 核心风格：深紫蓝、低饱和、柔和、低对比层级、轻量通讯客户端

------------------------------------------------------------------------

## 1. 修订说明

本版本以参考界面的**实际视觉关系**作为主要基准，修正上一版偏灰、偏蓝的问题。

上一版的问题主要是：

-   Main Background 过于灰蓝
-   Sidebar 与 Main 的色相差异不够明确
-   Surface 偏灰
-   Primary 偏灰紫
-   整体缺少参考图中明显的「紫蓝色」氛围

本版本的核心调整：

``` text
旧 Main Background
#484868

新 Main Background
#4F486E
```

``` text
旧 Sidebar
#383060

新 Sidebar
#3F3661
```

``` text
旧 Primary
#887EB4

新 Primary
#8C82C2
```

**后续开发只使用本版本 Token，不再使用上一版颜色。**

------------------------------------------------------------------------

# 2. 设计目标

## 2.1 核心关键词

-   Deep Purple Blue
-   Muted Purple
-   Soft Dark
-   Layered
-   Quiet UI
-   Content First
-   Cross Platform

视觉目标：

> 保持参考图中深沉、柔和、偏紫的整体氛围，同时通过明度建立 UI 层级。

------------------------------------------------------------------------

## 2.2 最重要的颜色关系

整个 UI 的核心不是 Primary，而是背景色本身。

``` text
Deep
#302850
   ↓
Sidebar
#3F3661
   ↓
Main
#4F486E
   ↓
Surface
#5A5278
   ↓
Elevated
#696180
   ↓
Strong Surface
#7A7190
   ↓
Primary
#8C82C2
   ↓
Text
#F8F7FA
```

因此：

**不要使用高饱和紫色作为大面积背景。**

参考图的紫色氛围主要来自：

``` text
#3F3661
+
#4F486E
```

而不是来自 Primary。

------------------------------------------------------------------------

# 3. Core Color Palette

## 3.1 Background

  Token          HEX         用途
  -------------- ----------- ---------------------------------
  `bgDeep`       `#302850`   Modal、Context Menu、深层 Popup
  `bgSidebar`    `#3F3661`   Sidebar、Navigation
  `bgMain`       `#4F486E`   主聊天区、页面背景
  `bgElevated`   `#554C75`   Floating Panel

### 使用规则

``` text
Sidebar → #3F3661
Main    → #4F486E
Modal   → #302850
```

不要：

``` text
Main → #000000
Sidebar → #000000
```

------------------------------------------------------------------------

# 4. Surface

  Token        HEX         用途
  ------------ ----------- ------------------------------------
  `surface1`   `#5A5278`   Selected、Hover、普通 Card
  `surface2`   `#696180`   Attachment、Tooltip、Elevated Card
  `surface3`   `#7A7190`   强调 Surface

核心关系：

``` text
#4F486E  Main
   ↓
#5A5278  Surface 1
   ↓
#696180  Surface 2
   ↓
#7A7190  Surface 3
```

优先通过 Surface 明度建立层级，不要依赖粗边框。

------------------------------------------------------------------------

# 5. Primary

  Token               HEX         用途
  ------------------- ----------- ----------
  `primary`           `#8C82C2`   Normal
  `primaryHover`      `#9A90CF`   Hover
  `primaryPressed`    `#786EAD`   Pressed
  `primaryFocus`      `#AEA6D6`   Focus
  `primaryDisabled`   `#625A78`   Disabled

Primary 用于：

-   Button
-   Link
-   Selected Icon
-   Focus Ring
-   Progress
-   Slider
-   Active State
-   Badge
-   未读提示

**Primary 不用于大面积页面背景。**

------------------------------------------------------------------------

# 6. Text

  Token             HEX         用途
  ----------------- ----------- ------------------------
  `textPrimary`     `#F8F7FA`   标题、用户名、主要消息
  `textSecondary`   `#D2CCDE`   时间、辅助信息
  `textTertiary`    `#AAA3BB`   Placeholder、Metadata
  `textDisabled`    `#7C758E`   Disabled
  `textOnPrimary`   `#FFFFFF`   Primary Button

## 使用规则

不要让所有文字都使用：

``` text
#FFFFFF
```

推荐：

``` text
标题 / 用户名 / 消息
#F8F7FA

时间 / 辅助信息
#D2CCDE

Placeholder
#AAA3BB

Disabled
#7C758E
```

------------------------------------------------------------------------

# 7. Border

  Token             HEX         用途
  ----------------- ----------- ----------
  `borderSubtle`    `#575071`   弱分割线
  `borderDefault`   `#625A7C`   普通边框
  `borderStrong`    `#766D8D`   强调边框

推荐优先使用透明白：

``` dart
Colors.white.withValues(alpha: 0.08)
Colors.white.withValues(alpha: 0.12)
Colors.white.withValues(alpha: 0.18)
```

边框应该弱于文字，不应成为视觉焦点。

------------------------------------------------------------------------

# 8. Semantic Colors

整体 UI 使用低饱和状态色。

## Success

``` text
success
#7FB89A

successBg
#344F48
```

## Warning

``` text
warning
#D0B071

warningBg
#554B3A
```

## Error

``` text
error
#CF858D

errorBg
#533C48
```

## Info

``` text
info
#82AFC5

infoBg
#394B5C
```

状态色只在需要表达状态时使用。

------------------------------------------------------------------------

# 9. Presence

用于 TeamSpeak / 语音服务器 / 用户列表：

  Token       HEX         状态
  ----------- ----------- ------
  `online`    `#8CC9A3`   在线
  `idle`      `#D0B978`   离开
  `busy`      `#C9828C`   忙碌
  `offline`   `#7C758E`   离线

Presence Dot：

``` text
Desktop: 8px
Mobile: 8px
Compact: 6px
```

颜色不能作为唯一状态提示；需要时同时提供文本或辅助语义。

------------------------------------------------------------------------

# 10. Window Controls

仅用于 Desktop：

``` text
Close
#EF6F91

Minimize
#F1C85B

Maximize
#52C7D9
```

这些颜色不要扩散到普通 UI。

------------------------------------------------------------------------

# 11. Flutter AppColors

推荐统一定义：

``` dart
import 'package:flutter/material.dart';

abstract final class AppColors {
  // Background
  static const bgDeep =
      Color(0xFF302850);
  static const bgSidebar =
      Color(0xFF3F3661);
  static const bgMain =
      Color(0xFF4F486E);
  static const bgElevated =
      Color(0xFF554C75);

  // Surface
  static const surface1 =
      Color(0xFF5A5278);
  static const surface2 =
      Color(0xFF696180);
  static const surface3 =
      Color(0xFF7A7190);

  // Primary
  static const primary =
      Color(0xFF8C82C2);
  static const primaryHover =
      Color(0xFF9A90CF);
  static const primaryPressed =
      Color(0xFF786EAD);
  static const primaryFocus =
      Color(0xFFAEA6D6);
  static const primaryDisabled =
      Color(0xFF625A78);

  // Text
  static const textPrimary =
      Color(0xFFF8F7FA);
  static const textSecondary =
      Color(0xFFD2CCDE);
  static const textTertiary =
      Color(0xFFAAA3BB);
  static const textDisabled =
      Color(0xFF7C758E);
  static const textOnPrimary =
      Color(0xFFFFFFFF);

  // Border
  static const borderSubtle =
      Color(0xFF575071);
  static const borderDefault =
      Color(0xFF625A7C);
  static const borderStrong =
      Color(0xFF766D8D);

  // Semantic
  static const success =
      Color(0xFF7FB89A);
  static const successBg =
      Color(0xFF344F48);

  static const warning =
      Color(0xFFD0B071);
  static const warningBg =
      Color(0xFF554B3A);

  static const error =
      Color(0xFFCF858D);
  static const errorBg =
      Color(0xFF533C48);

  static const info =
      Color(0xFF82AFC5);
  static const infoBg =
      Color(0xFF394B5C);

  // Presence
  static const online =
      Color(0xFF8CC9A3);
  static const idle =
      Color(0xFFD0B978);
  static const busy =
      Color(0xFFC9828C);
  static const offline =
      Color(0xFF7C758E);

  // Desktop Window
  static const windowClose =
      Color(0xFFEF6F91);
  static const windowMinimize =
      Color(0xFFF1C85B);
  static const windowMaximize =
      Color(0xFF52C7D9);
}
```

------------------------------------------------------------------------

# 12. Typography

## 12.1 字体

UI 字体必须优先满足：

-   简体中文
-   繁体中文
-   日文
-   韩文
-   英文
-   数字
-   常用符号

推荐项目内置字体并配置 fallback。

字体应该保持：

-   清晰
-   中性
-   高可读性
-   多语言 Glyph 完整

不要使用装饰性字体作为全局 UI 字体。

------------------------------------------------------------------------

## 12.2 Type Scale

  Token            Size   Weight 用途
  -------------- ------ -------- -----------------
  `display`          28      700 特殊页面标题
  `headline`         22      700 页面标题
  `title`            18      600 Section
  `bodyLarge`        16      400 大正文
  `body`             14      400 默认正文
  `bodyMedium`       14      500 强调正文
  `label`            13      500 Button / Label
  `caption`          12      400 时间 / Metadata
  `overline`         11      600 极少使用

聊天消息默认：

``` text
14px
```

------------------------------------------------------------------------

# 13. Spacing

采用 4px Grid：

``` text
4
8
12
16
20
24
32
40
48
64
```

推荐 Token：

  Token         Value
  ----------- -------
  `space1`          4
  `space2`          8
  `space3`         12
  `space4`         16
  `space5`         20
  `space6`         24
  `space7`         32
  `space8`         40
  `space9`         48
  `space10`        64

------------------------------------------------------------------------

# 14. Radius

  Token             Value 用途
  --------------- ------- ---------------
  `radiusXS`            4 Badge
  `radiusSM`            6 Input
  `radiusMD`            8 Card
  `radiusLG`           12 Dialog
  `radiusXL`           16 大 Card
  `radiusRound`       999 Avatar / Pill

推荐：

``` text
Input: 6~8px
Card: 8px
Dialog: 12px
Button: 6~8px
Avatar: 999px
```

不要让所有组件都使用 16\~24px 大圆角。

------------------------------------------------------------------------

# 15. Elevation

整体设计不依赖强阴影。

## Level 0

``` text
No Shadow
```

Main / Sidebar / 普通消息。

## Level 1

``` text
0 2px 8px rgba(0, 0, 0, 0.12)
```

Card / Attachment。

## Level 2

``` text
0 4px 16px rgba(0, 0, 0, 0.18)
```

Dropdown / Popup。

## Level 3

``` text
0 8px 32px rgba(0, 0, 0, 0.24)
```

Dialog / Modal。

不要使用紫色 Glow 作为普通组件阴影。

------------------------------------------------------------------------

# 16. Icon

推荐：

``` text
Small: 16px
Default: 20px
Large: 24px
Page: 28~32px
```

颜色：

``` text
Primary Icon
#F8F7FA

Secondary Icon
#D2CCDE

Inactive
#AAA3BB

Disabled
#7C758E

Active
#8C82C2
```

------------------------------------------------------------------------

# 17. Button

## Primary

``` text
Background: #8C82C2
Text: #FFFFFF
Hover: #9A90CF
Pressed: #786EAD
Disabled: #625A78
```

高度：

``` text
Desktop: 36~40px
Mobile: 44~48px
```

## Secondary

``` text
Background: #5A5278
Text: #F8F7FA
Border: #625A7C
```

Hover：

``` text
#696180
```

## Ghost

Normal：

``` text
Background: transparent
Text: #D2CCDE
```

Hover：

``` text
Background: #5A5278
Text: #F8F7FA
```

------------------------------------------------------------------------

# 18. Input

参考图中的消息输入框应保持较深、偏紫的样式。

``` text
Background
#3A3260

Border
#625A7C

Text
#F8F7FA

Placeholder
#AAA3BB
```

Focus：

``` text
Border
#8C82C2
```

Error：

``` text
Border
#CF858D
```

Disabled：

``` text
Background
#302850
Text
#7C758E
```

------------------------------------------------------------------------

# 19. Sidebar

## Desktop Width

普通 Sidebar：

``` text
240~320px
```

多级语音客户端：

``` text
Server Rail:
64~72px

Channel Sidebar:
240~280px

Member Sidebar:
220~280px
```

------------------------------------------------------------------------

## Sidebar Background

``` text
#3F3661
```

------------------------------------------------------------------------

## Channel Item

### Normal

``` text
Background: transparent
Text: #D2CCDE
```

### Hover

``` text
Background: #51496F
Text: #F8F7FA
```

### Selected

``` text
Background: #5A5278
Text: #F8F7FA
```

### Disabled

``` text
Text: #7C758E
```

Selected Item 不使用高饱和 Primary 背景。

------------------------------------------------------------------------

# 20. Chat Message

参考界面采用**无气泡消息**。

推荐：

``` text
Avatar

Username       Time
Message
Message
```

默认不要给每条消息添加：

``` text
Card
Border
Shadow
```

------------------------------------------------------------------------

## Message Spacing

同一用户连续消息：

``` text
4~8px
```

不同用户：

``` text
16~20px
```

Username：

``` text
14px / 500
#F8F7FA
```

Time：

``` text
12px / 400
#AAA3BB
```

Message：

``` text
14px / 400
#F8F7FA
```

------------------------------------------------------------------------

# 21. Empty State

参考图中的：

``` text
还没有消息
```

属于弱视觉内容。

Icon：

``` text
#AAA3BB
```

Text：

``` text
#AAA3BB
```

不要使用 Primary。

推荐布局：

``` text
        Icon

      还没有消息
```

居中显示。

------------------------------------------------------------------------

# 22. Avatar

  场景              Size
  --------------- ------
  Compact           28px
  Default           36px
  Chat              40px
  Profile           64px
  Large Profile     96px

Avatar：

``` text
Radius: 999
```

Presence Dot：

``` text
8px
```

------------------------------------------------------------------------

# 23. Attachment

参考图中的文件附件：

``` text
Background
#696180

Radius
8px
```

文件名：

``` text
#F8F7FA
14px
```

Metadata：

``` text
#D2CCDE
12px
```

Hover：

``` text
#7A7190
```

------------------------------------------------------------------------

# 24. Tooltip

``` text
Background
#302850

Text
#F8F7FA

Radius
6px

Padding
8px 10px
```

Desktop Tooltip：

``` text
Delay: 300~500ms
```

Mobile 不依赖 Tooltip。

------------------------------------------------------------------------

# 25. Modal / Dialog

``` text
Background
#302850

Border
#625A7C

Radius
12px
```

Overlay：

``` text
rgba(10, 8, 20, 0.55)
```

Shadow：

``` text
Elevation Level 3
```

------------------------------------------------------------------------

# 26. Context Menu

``` text
Background
#302850
Radius
8px
```

Item：

``` text
Height: 36px
Horizontal Padding: 12px
```

Hover：

``` text
#5A5278
```

Danger：

``` text
#CF858D
```

------------------------------------------------------------------------

# 27. Toast

## Success

``` text
Background: #344F48
Icon: #7FB89A
Text: #F8F7FA
```

## Error

``` text
Background: #533C48
Icon: #CF858D
Text: #F8F7FA
```

## Info

``` text
Background: #394B5C
Icon: #82AFC5
Text: #F8F7FA
```

------------------------------------------------------------------------

# 28. Desktop Layout

适用于：

-   Windows
-   macOS
-   Desktop Web

推荐：

``` text
┌───────────────────────────────────────────────────────────┐
│ Header                                                    │
├──────────────┬────────────────────────────────────────────┤
│              │                                            │
│ Server /     │                                            │
│ Channel      │              Main Content                  │
│ Sidebar      │                                            │
│              │                                            │
│              │                                            │
├──────────────┴────────────────────────────────────────────┤
│ Optional Status / Input                                   │
└───────────────────────────────────────────────────────────┘
```

最小窗口：

``` text
960 × 640
```

舒适尺寸：

``` text
1280 × 720+
```

------------------------------------------------------------------------

# 29. Mobile Layout

适用于：

-   iOS
-   Android

不要直接复制 Desktop Sidebar。

推荐：

``` text
┌───────────────────────┐
│ Header                │
├───────────────────────┤
│                       │
│ Chat                  │
│                       │
│                       │
├───────────────────────┤
│ Message Input         │
├───────────────────────┤
│ Navigation            │
└───────────────────────┘
```

可以使用：

-   Bottom Navigation
-   Drawer
-   Modal Sheet
-   Full Screen Channel Selector

------------------------------------------------------------------------

# 30. Responsive Breakpoints

  Width           Layout
  --------------- -----------------------------
  `< 600px`       Mobile
  `600~839px`     Large Mobile / Small Tablet
  `840~1199px`    Tablet / Compact Desktop
  `1200~1599px`   Desktop
  `>= 1600px`     Large Desktop

优先使用 Width 判断布局，而不是直接判断操作系统。

``` dart
if (width < 600) {
  // Mobile
} else if (width < 1200) {
  // Compact
} else {
  // Desktop
}
```

------------------------------------------------------------------------

# 31. Platform Adaptation

## Web

支持：

-   Mouse Hover
-   Keyboard Navigation
-   Context Menu
-   Responsive Layout
-   Browser Resize
-   Deep Link

## Windows

支持：

-   Hover
-   Right Click
-   Keyboard Shortcut
-   Window Resize
-   Native Window Controls
-   Compact Density

## macOS

支持：

-   Mouse / Trackpad
-   Command Shortcut
-   Context Menu
-   Window Resize
-   更宽松的窗口间距

## iOS

重点：

-   Touch
-   Safe Area
-   Dynamic Type
-   Swipe
-   Bottom Sheet
-   Navigation Stack
-   44px 最小触控区域

## Android

重点：

-   Touch
-   Back Gesture
-   System Navigation
-   Edge-to-edge
-   Bottom Sheet
-   Accessibility

------------------------------------------------------------------------

# 32. Touch Target

移动端：

``` text
Minimum: 44 × 44px
Recommended: 48 × 48px
```

即使 Icon：

``` text
20px
```

也应放进：

``` text
44~48px
```

的点击区域。

------------------------------------------------------------------------

# 33. Desktop Density

桌面端推荐：

``` text
Button: 36~40px
Input: 36~40px
List Item: 36~44px
Toolbar Icon Area: 32~36px
```

不要为了增加信息密度而牺牲点击体验。

------------------------------------------------------------------------

# 34. Motion

  类型        Duration
  ------- ------------
  Hover     100\~150ms
  Press      80\~120ms
  Fade      150\~200ms
  Panel     200\~250ms
  Modal     200\~280ms

推荐：

``` text
easeOut
easeInOut
```

避免：

-   长动画
-   强烈 Bounce
-   大范围缩放
-   高频闪烁
-   Glow Animation

------------------------------------------------------------------------

# 35. Focus / Hover / Press

## Hover

只针对 Desktop / Web。

推荐通过：

``` text
Surface 明度 +5~10%
```

例如：

``` text
#5A5278
→
#696180
```

## Pressed

降低 Surface 明度，或使用：

``` text
#8C82C2
→
#786EAD
```

## Focus

``` text
#AEA6D6
```

推荐：

``` text
2px Focus Ring
```

------------------------------------------------------------------------

# 36. Accessibility

颜色不能作为唯一状态提示。

错误：

``` text
仅使用红色
```

正确：

``` text
红色 Icon
+
错误文字
+
Semantics
```

在线状态同理：

``` text
绿色 Dot
+
Online
```

支持：

-   Screen Reader
-   Keyboard Navigation
-   Focus State
-   Text Scaling
-   高对比需求
-   Reduced Motion

------------------------------------------------------------------------

# 37. Dark Theme

本 Design System 默认 Dark Theme。

不要简单：

``` dart
Color.lerp(dark, white, 0.5)
```

生成 Light Theme。

Light Theme 应重新定义：

-   Background
-   Surface
-   Border
-   Text
-   Primary Contrast

Dark Theme 与 Light Theme 应共享语义 Token，而不是简单反转颜色。

------------------------------------------------------------------------

# 38. Material 3

推荐架构：

``` text
Material 3
      ↓
Flutter Theme
      ↓
App Design Tokens
      ↓
Custom Widgets
```

Material 3 负责：

-   Accessibility
-   Focus
-   Widget State
-   Keyboard
-   Semantics
-   基础组件行为

本 Design System 负责：

-   颜色
-   间距
-   圆角
-   字体
-   Surface
-   视觉密度
-   布局风格

不要直接使用 Material 3 默认 Purple Scheme。

------------------------------------------------------------------------

# 39. AppTheme 基础实现

``` dart
ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,

    scaffoldBackgroundColor:
        AppColors.bgMain,

    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: AppColors.textOnPrimary,

      surface: AppColors.bgMain,
      onSurface: AppColors.textPrimary,

      error: AppColors.error,
      onError: AppColors.textOnPrimary,
    ),

    dividerColor:
        AppColors.borderSubtle,
  );
}
```

非 Material 标准 Token 推荐通过：

``` dart
ThemeExtension
```

统一管理。

------------------------------------------------------------------------

# 40. 推荐项目结构

``` text
lib/
├── theme/
│   ├── app_colors.dart
│   ├── app_theme.dart
│   ├── app_typography.dart
│   ├── app_spacing.dart
│   ├── app_radius.dart
│   ├── app_shadows.dart
│   └── app_theme_extensions.dart
│
├── widgets/
│   ├── app_button.dart
│   ├── app_input.dart
│   ├── app_avatar.dart
│   ├── app_sidebar.dart
│   ├── app_channel_tile.dart
│   ├── app_message.dart
│   ├── app_attachment.dart
│   └── app_dialog.dart
│
└── features/
    ├── chat/
    ├── channels/
    ├── server/
    ├── settings/
    └── profile/
```

------------------------------------------------------------------------

# 41. 禁止事项

## 禁止 1：纯黑大面积背景

``` text
#000000
```

不作为主 Background。

## 禁止 2：高饱和紫色大面积使用

Primary 只用于交互。

## 禁止 3：每条消息都做气泡

默认采用无气泡聊天。

## 禁止 4：过重边框

不要用高对比 1px Border 到处描边。

## 禁止 5：强烈阴影

不要让 Card 看起来像悬浮在页面上。

## 禁止 6：过度圆角

不要所有组件都使用 16\~24px。

## 禁止 7：平台布局完全一致

颜色和设计语言统一，布局与交互按平台适配。

## 禁止 8：使用上一版颜色

开发中不得继续使用：

``` text
#484868
#383060
#50486C
#686080
#887EB4
```

作为本 Design System 的核心 Token。

应使用：

``` text
#4F486E
#3F3661
#5A5278
#696180
#8C82C2
```

------------------------------------------------------------------------

# 42. Final Palette

这是开发人员最常用的一张表：

  Category     Token               HEX
  ------------ ------------------- -----------
  Background   `bgDeep`            `#302850`
  Background   `bgSidebar`         `#3F3661`
  Background   `bgMain`            `#4F486E`
  Background   `bgElevated`        `#554C75`
  Surface      `surface1`          `#5A5278`
  Surface      `surface2`          `#696180`
  Surface      `surface3`          `#7A7190`
  Primary      `primary`           `#8C82C2`
  Primary      `primaryHover`      `#9A90CF`
  Primary      `primaryPressed`    `#786EAD`
  Primary      `primaryFocus`      `#AEA6D6`
  Primary      `primaryDisabled`   `#625A78`
  Text         `textPrimary`       `#F8F7FA`
  Text         `textSecondary`     `#D2CCDE`
  Text         `textTertiary`      `#AAA3BB`
  Text         `textDisabled`      `#7C758E`
  Border       `borderSubtle`      `#575071`
  Border       `borderDefault`     `#625A7C`
  Border       `borderStrong`      `#766D8D`
  Success      `success`           `#7FB89A`
  Warning      `warning`           `#D0B071`
  Error        `error`             `#CF858D`
  Info         `info`              `#82AFC5`
  Online       `online`            `#8CC9A3`
  Idle         `idle`              `#D0B978`
  Busy         `busy`              `#C9828C`
  Offline      `offline`           `#7C758E`

------------------------------------------------------------------------

# 43. 最终视觉规则

只需要记住：

1.  **Main = `#4F486E`**
2.  **Sidebar = `#3F3661`**
3.  **Deep = `#302850`**
4.  **Selected / Surface = `#5A5278`**
5.  **Elevated = `#696180`**
6.  **Primary = `#8C82C2`**
7.  **Primary 不做大面积背景**
8.  **文字以 `#F8F7FA / #D2CCDE / #AAA3BB` 分层**
9.  **聊天默认无气泡**
10. **使用明度而不是强边框制造层级**
11. **桌面支持 Hover / Focus / Right Click / Keyboard**
12. **移动端支持 Touch / Safe Area / Gesture**
13. **五个平台共享 Color / Typography / Spacing / Radius Token**
14. **布局和交互根据平台适配**
15. **本 v2.0 文档是唯一颜色规范来源**

------------------------------------------------------------------------

# 44. Design Philosophy

最终目标不是让：

``` text
Web
Windows
macOS
iOS
Android
```

拥有完全相同的布局。

而是让它们拥有：

``` text
同一种颜色语言
+
同一种字体语言
+
同一种间距语言
+
同一种组件语言
+
符合平台习惯的交互
```

最终结构：

``` text
                    Design System
                         │
              ┌──────────┴──────────┐
              │                     │
        Shared Tokens          Platform UX
              │                     │
      ┌───────┼───────┐      ┌──────┼──────┐
      │       │       │      │      │      │
    Color   Type   Layout   Web  Desktop Mobile
                              │      │      │
                              └──────┼──────┘
                                     │
                         Web / Win / macOS /
                            iOS / Android
```

**统一的是视觉语言，不是强制统一所有平台的交互。**
