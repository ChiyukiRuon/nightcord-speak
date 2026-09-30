# UI Design System

> 适用平台：Web / Windows / macOS / iOS / Android
> 技术栈建议：Flutter
> 视觉基准：深色、低饱和蓝紫色、柔和层级、轻量桌面通讯客户端
> 设计目标：统一品牌视觉，同时遵循桌面端与移动端各自的交互习惯。

---

## 1. 设计原则

### 1.1 核心关键词

- Muted Purple：低饱和蓝紫
- Soft Dark：柔和深色，而不是纯黑
- Layered：通过明度建立层级
- Quiet UI：减少强烈边框、阴影和高饱和色
- Content First：聊天内容优先
- Cross Platform：视觉 Token 统一，交互方式按平台适配

### 1.2 总体视觉比例

建议视觉占比：

  类型           占比 说明

---

  Background      70% 页面、Sidebar、大面积区域
  Surface         15% 卡片、输入框、附件、悬浮层
  Primary          8% 交互、选中、Focus
  Semantic         2% 成功、警告、错误、信息
  Other            5% 文字、Icon、分割线等

**禁止使用 Primary 大面积铺满页面。**

---

# 2. Color System

## 2.1 Background

  Token                   HEX         用途

---

  `backgroundPrimary`     `#484868`   主内容区
  `backgroundSecondary`   `#383060`   Sidebar、输入区域
  `backgroundTertiary`    `#302850`   Modal、Context Menu、深层背景
  `backgroundElevated`    `#50486C`   Floating Panel

层级关系：

```text
#302850  Deep
#383060  Secondary
#484868  Primary
#50486C  Elevated
```

---

## 2.2 Surface

  Token        HEX         用途

---

  `surface1`   `#50486C`   Hover、普通 Card
  `surface2`   `#686080`   Attachment、Tooltip、Elevated Card
  `surface3`   `#78708E`   Active、Strong Surface

不要通过大量 Border 制造层级，优先使用 Surface 明度变化。

---

## 2.3 Primary

  Token               HEX         状态

---

  `primary`           `#887EB4`   Normal
  `primaryHover`      `#968CBD`   Hover
  `primaryPressed`    `#766CA3`   Pressed
  `primaryFocus`      `#AAA2CB`   Focus
  `primaryDisabled`   `#625A72`   Disabled

Primary 用于：

- Button
- Link
- Selected
- Focus
- Active Icon
- Progress
- Slider
- Badge
- 未读状态

---

## 2.4 Text

  Token             HEX         用途

---

  `textPrimary`     `#F8F7FA`   标题、用户名、主要消息
  `textSecondary`   `#D0CBDD`   时间、辅助信息
  `textTertiary`    `#A7A1B8`   Placeholder、Metadata
  `textDisabled`    `#77718A`   Disabled
  `textOnPrimary`   `#FFFFFF`   Primary Button

不要默认使用纯白 `#FFFFFF` 作为所有文字。

---

## 2.5 Border

  Token             HEX         用途

---

  `borderSubtle`    `#5B5678`   弱分割线
  `borderDefault`   `#68627F`   默认边框
  `borderStrong`    `#79718F`   强调边框

推荐优先使用透明白：

```dart
Colors.white.withValues(alpha: 0.08)
Colors.white.withValues(alpha: 0.12)
Colors.white.withValues(alpha: 0.18)
```

---

## 2.6 Semantic Colors

### Success

```text
success     #7FB89A
successBg   #344F48
```

### Warning

```text
warning     #D0B071
warningBg   #554B3A
```

### Error

```text
error       #CF858D
errorBg     #533C48
```

### Info

```text
info        #82AFC5
infoBg      #394B5C
```

语义颜色应保持低饱和，避免破坏整体紫色氛围。

---

## 2.7 Presence

用于语音服务器、频道、好友、成员列表：

  Token       HEX         状态

---

  `online`    `#8CC9A3`   在线
  `idle`      `#D0B978`   离开
  `busy`      `#C9828C`   忙碌
  `offline`   `#77718A`   离线

Presence Dot 推荐直径：

- Desktop：8px
- Mobile：8px
- 高密度列表：6px

---

## 2.8 Window Controls

仅用于桌面窗口控制：

```text
close       #EF6F91
minimize    #F1C85B
maximize    #52C7D9
```

不要把这三个颜色扩散到普通 UI。

---

# 3. Flutter Color Tokens

推荐建立统一的 `AppColors`：

```dart
import 'package:flutter/material.dart';

abstract final class AppColors {
  // Background
  static const backgroundPrimary =
      Color(0xFF484868);
  static const backgroundSecondary =
      Color(0xFF383060);
  static const backgroundTertiary =
      Color(0xFF302850);
  static const backgroundElevated =
      Color(0xFF50486C);

  // Surface
  static const surface1 =
      Color(0xFF50486C);
  static const surface2 =
      Color(0xFF686080);
  static const surface3 =
      Color(0xFF78708E);

  // Primary
  static const primary =
      Color(0xFF887EB4);
  static const primaryHover =
      Color(0xFF968CBD);
  static const primaryPressed =
      Color(0xFF766CA3);
  static const primaryFocus =
      Color(0xFFAAA2CB);
  static const primaryDisabled =
      Color(0xFF625A72);

  // Text
  static const textPrimary =
      Color(0xFFF8F7FA);
  static const textSecondary =
      Color(0xFFD0CBDD);
  static const textTertiary =
      Color(0xFFA7A1B8);
  static const textDisabled =
      Color(0xFF77718A);
  static const textOnPrimary =
      Color(0xFFFFFFFF);

  // Border
  static const borderSubtle =
      Color(0xFF5B5678);
  static const borderDefault =
      Color(0xFF68627F);
  static const borderStrong =
      Color(0xFF79718F);

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
      Color(0xFF77718A);

  // Window
  static const windowClose =
      Color(0xFFEF6F91);
  static const windowMinimize =
      Color(0xFFF1C85B);
  static const windowMaximize =
      Color(0xFF52C7D9);
}
```

---

# 4. Color Usage Rules

## 4.1 背景

主内容区：

```text
#484868
```

Sidebar：

```text
#383060
```

Modal / Popup：

```text
#302850
```

不要使用：

```text
#000000
```

作为整个 App 的主背景。

---

## 4.2 Primary 使用规则

推荐：

```text
Button
Link
Selected
Focus
Active
Progress
Unread
```

不推荐：

```text
整块页面背景
大面积 Card
大量装饰
```

---

# 5. Typography

## 5.1 字体策略

跨平台 UI 推荐优先选择能够覆盖：

- 简体中文
- 繁体中文
- 日文
- 韩文
- 英文
- 数字

的统一字体。

字体选择原则：

1. UI 字体优先于装饰字体
2. 中文、日文、韩文需要完整 Glyph Coverage
3. 数字宽度和标点风格需要统一
4. Windows / macOS / Linux / iOS / Android
   不应因为系统字体差异产生明显跳动

建议使用项目内置字体，并配置 fallback。

---

## 5.2 Type Scale

  Token            Size Weight   用途

---

  `display`          28 700      特殊页面标题
  `headline`         22 700      页面标题
  `title`            18 600      Section 标题
  `bodyLarge`        16 400      主要正文
  `body`             14 400      默认正文
  `bodyMedium`       14 500      强调正文
  `label`            13 500      Button / Label
  `caption`          12 400      时间、Metadata
  `overline`         11 600      极少使用

聊天软件默认正文推荐：

```text
14px
```

移动端可根据设备密度和系统字体缩放适当调整。

---

# 6. Spacing System

使用 4px 基础网格。

```text
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

推荐：

  Token         Value

---

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

---

# 7. Radius System

推荐：

  Token             Value 用途

---

  `radiusXS`            4 Badge、小控件
  `radiusSM`            6 Input
  `radiusMD`            8 Card
  `radiusLG`           12 Dialog
  `radiusXL`           16 大型 Card
  `radiusRound`       999 Avatar / Pill

整体不要使用过度圆润的组件。

桌面端推荐：

```text
Input       6~8px
Card        8px
Dialog      12px
Button      6~8px
```

---

# 8. Elevation / Shadow

这个设计不依赖强阴影。

推荐：

### Level 0

```text
无阴影
```

普通聊天区域。

### Level 1

```text
0 2px 8px rgba(0, 0, 0, 0.12)
```

Card / Attachment。

### Level 2

```text
0 4px 16px rgba(0, 0, 0, 0.18)
```

Dropdown / Popup。

### Level 3

```text
0 8px 32px rgba(0, 0, 0, 0.24)
```

Dialog / Modal。

**避免使用明显的发光阴影。**

---

# 9. Icon System

推荐：

- 默认 20px
- 小图标 16px
- 大图标 24px
- 页面级 Icon 28\~32px

Icon 颜色：

```text
Primary Icon
#F8F7FA

Secondary Icon
#D0CBDD

Inactive Icon
#A7A1B8

Disabled Icon
#77718A

Active Icon
#887EB4
```

Icon 不要默认使用纯白。

---

# 10. Button

## 10.1 Primary Button

```text
Background: #887EB4
Text:       #FFFFFF
Hover:      #968CBD
Pressed:    #766CA3
Disabled:   #625A72
```

高度：

```text
Desktop: 36~40px
Mobile:  44~48px
```

---

## 10.2 Secondary Button

```text
Background: #50486C
Text:       #F8F7FA
Border:     #68627F
```

Hover：

```text
#686080
```

---

## 10.3 Ghost Button

默认：

```text
Background: transparent
Text: #D0CBDD
```

Hover：

```text
Background: #50486C
Text: #F8F7FA
```

适合 Toolbar。

---

# 11. Input

默认：

```text
Background: #383060
Border: #5B5678
Text: #F8F7FA
Placeholder: #A7A1B8
```

Focus：

```text
Border: #887EB4
```

Error：

```text
Border: #CF858D
```

Disabled：

```text
Background: #302850
Text: #77718A
```

---

# 12. Sidebar

## 12.1 Desktop

推荐宽度：

```text
280px ~ 320px
```

如果存在 Server / Channel / Member 多级导航：

```text
Server Rail
      +
Channel Sidebar
      +
Main Content
```

---

## 12.2 Channel Item

### Normal

```text
Background: transparent
Text: #C0BBCD
```

### Hover

```text
Background: #443C68
Text: #E8E5F0
```

### Selected

```text
Background: #50486C
Text: #F8F7FA
```

### Disabled

```text
Text: #77718A
```

---

# 13. Chat Message

推荐使用无气泡消息布局。

```text
Avatar

Username        Time
Message content
Message content
```

不要默认给每条消息添加：

```text
Card
Border
Shadow
```

---

## Message 间距

同一用户连续消息：

```text
4~8px
```

不同用户：

```text
16~20px
```

时间：

```text
12px
#A7A1B8
```

用户名：

```text
14px
#F8F7FA
```

正文：

```text
14px
#F8F7FA
```

---

# 14. Avatar

尺寸建议：

  场景              Size

---

  Compact             28
  Default             36
  Chat                40
  Profile             64
  Large Profile       96

Avatar 默认圆形：

```text
radius: 999
```

Presence Dot：

```text
8px
```

---

# 15. Attachment

附件 Card：

```text
Background: #686080
Radius: 8px
```

文件名：

```text
#F8F7FA
14px
```

文件 Metadata：

```text
#C0BBCD
12px
```

Hover：

```text
#78708E
```

下载 Icon：

```text
#F8F7FA
```

---

# 16. Tooltip

背景：

```text
#302850
```

文字：

```text
#F8F7FA
```

Radius：

```text
6px
```

Padding：

```text
8px 10px
```

Desktop 推荐延迟：

```text
300~500ms
```

Mobile 不依赖 Tooltip。

---

# 17. Modal / Dialog

Background：

```text
#302850
```

Border：

```text
#68627F
```

Radius：

```text
12px
```

Shadow：

```text
Level 3
```

Overlay：

```text
rgba(10, 8, 20, 0.55)
```

标题：

```text
18px / 600
```

正文：

```text
14px / 400
```

---

# 18. Context Menu

Background：

```text
#302850
```

Item Height：

```text
36px
```

Horizontal Padding：

```text
12px
```

Normal：

```text
transparent
```

Hover：

```text
#50486C
```

Danger：

```text
#CF858D
```

---

# 19. Toast / Notification

### Success

```text
Background: #344F48
Icon: #7FB89A
Text: #F8F7FA
```

### Error

```text
Background: #533C48
Icon: #CF858D
Text: #F8F7FA
```

### Info

```text
Background: #394B5C
Icon: #82AFC5
Text: #F8F7FA
```

---

# 20. Desktop Layout

适用于：

- Windows
- macOS
- Web Desktop

推荐：

```text
┌───────────────────────────────────────────────────────────┐
│ Window / App Header                                       │
├──────────────┬────────────────────────────────────────────┤
│              │                                            │
│ Server       │                                            │
│ / Channel    │              Main Content                  │
│ Sidebar      │                                            │
│              │                                            │
│              │                                            │
├──────────────┴────────────────────────────────────────────┤
│ Optional Status / Input                                   │
└───────────────────────────────────────────────────────────┘
```

推荐最小窗口：

```text
Width: 960px
Height: 640px
```

推荐舒适窗口：

```text
Width: 1280px+
Height: 720px+
```

---

# 21. Desktop Sidebar Width

推荐：

```text
240px ~ 320px
```

如果是多级结构：

```text
Server Rail:
64~72px

Channel Sidebar:
240~280px

Member Sidebar:
220~280px
```

不要把所有 Sidebar 都固定成极宽布局。

---

# 22. Mobile Layout

适用于：

- iOS
- Android

移动端不要强行复制桌面 Sidebar。

推荐：

```text
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
│ Channels / Navigation │
└───────────────────────┘
```

导航可以使用：

- Bottom Navigation
- Drawer
- Modal Sheet
- Full Screen Channel Selector

---

# 23. Responsive Breakpoints

建议：

  Breakpoint      类型

---

  `< 600px`       Mobile
  `600~839px`     Large Mobile / Small Tablet
  `840~1199px`    Tablet / Compact Desktop
  `1200~1599px`   Desktop
  `>= 1600px`     Large Desktop

不要仅根据平台判断布局。

例如：

```dart
if (width < 600) {
  // Mobile
} else if (width < 1200) {
  // Compact
} else {
  // Desktop
}
```

比：

```dart
if (Platform.isWindows) {}
```

更合理。

---

# 24. Platform Adaptation

## Web

重点：

- Mouse Hover
- Keyboard Navigation
- Context Menu
- Responsive Layout
- Browser Window 尺寸变化
- URL / Deep Link

---

## Windows

重点：

- Hover
- Right Click
- Keyboard Shortcut
- Window Resize
- Native Window Controls
- Compact Density

---

## macOS

重点：

- Mouse / Trackpad
- Keyboard Shortcut
- Command Key
- Context Menu
- 更宽松的窗口间距
- 原生窗口行为

---

## iOS

重点：

- Touch
- Safe Area
- Dynamic Type
- Swipe
- Bottom Sheet
- Navigation Stack
- 44px 左右最小触控区域

---

## Android

重点：

- Touch
- Back Gesture
- System Navigation
- Edge-to-edge
- Bottom Sheet
- Material Accessibility

---

# 25. Touch Target

移动端交互控件：

```text
Minimum: 44 × 44px
Recommended: 48 × 48px
```

即使 Icon 本身只有：

```text
20px
```

也应该放进：

```text
48 × 48px
```

的点击区域。

---

# 26. Desktop Density

桌面端可以更紧凑：

```text
Button: 36~40px
Input: 36~40px
List Item: 36~44px
Toolbar Icon: 32~36px
```

但不要为了"信息密度"压缩到无法点击。

---

# 27. Motion

动画应该短、轻、稳定。

推荐：

  类型        Duration

---

  Hover     100\~150ms
  Press      80\~120ms
  Fade      150\~200ms
  Panel     200\~250ms
  Modal     200\~280ms

推荐 Curve：

```text
easeOut
easeInOut
```

避免：

- 弹跳过度
- 长时间动画
- 大范围缩放
- 高亮闪烁

聊天客户端应保持安静。

---

# 28. Hover / Press / Focus

## Hover

仅 Desktop / Web。

推荐：

```text
Surface 明度 +5~10%
```

例如：

```text
#50486C
→
#686080
```

---

## Pressed

推荐：

```text
Surface 明度降低
```

或：

```text
Primary
#887EB4
→
#766CA3
```

---

## Focus

必须明显，但不要刺眼：

```text
#AAA2CB
```

推荐 Focus Ring：

```text
2px
```

---

# 29. Accessibility

颜色不能作为唯一状态提示。

例如：

错误不能只使用：

```text
红色
```

还应该：

```text
红色 Icon
+
错误文字
+
可访问性语义
```

同理：

在线状态：

```text
绿色 Dot
+
"Online"
```

在适当场景提供文本语义。

---

# 30. Dark Theme

该设计系统默认以 Dark Theme 为主。

推荐不要简单通过：

```dart
Color.lerp(...)
```

自动生成 Light Theme。

Light Theme 应该重新定义：

- Background
- Surface
- Border
- Text
- Primary Contrast

因为深色 UI 的色彩关系不能直接反转。

---

# 31. Flutter Theme 架构

推荐：

```text
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

---

# 32. Material 3 使用策略

推荐：

```text
Material 3
      ↓
Flutter Theme
      ↓
App Design Tokens
      ↓
Custom Widgets
```

不要直接使用 Material 3 默认颜色。

Material 3 主要负责：

- Accessibility
- Widget State
- Focus
- Keyboard
- Semantics
- 基础组件行为

视觉由本 Design System 控制。

---

# 33. AppTheme 基本结构

```dart
ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,

    scaffoldBackgroundColor:
        AppColors.backgroundPrimary,

    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: AppColors.textOnPrimary,

      surface: AppColors.backgroundPrimary,
      onSurface: AppColors.textPrimary,

      error: AppColors.error,
      onError: AppColors.textOnPrimary,
    ),

    dividerColor:
        AppColors.borderSubtle,
  );
}
```

实际项目中建议继续通过 `ThemeExtension` 扩展 Surface、Presence、Border
等非标准 Material Token。

---

# 34. 禁止事项

## 不要

```text
纯黑大背景 #000000
```

## 不要

```text
纯白文字遍布所有区域
```

## 不要

```text
高饱和紫色大面积使用
```

## 不要

```text
每个 Card 都加明显阴影
```

## 不要

```text
每条聊天消息都做成气泡
```

## 不要

```text
大量 1px 高对比边框
```

## 不要

```text
Windows / iOS / Android 强行使用完全相同的布局
```

---

# 35. 推荐的最终视觉层级

```text
#302850
│
├── Modal
├── Context Menu
└── Deep Surface

#383060
│
├── Sidebar
├── Input
└── Secondary Area

#484868
│
├── Main Background
└── Chat

#50486C
│
├── Hover
├── Card
└── Selected

#686080
│
├── Attachment
├── Tooltip
└── Elevated Surface

#78708E
│
└── Strong Active Surface

#887EB4
│
├── Primary
├── Active
├── Focus
└── Interaction

#F8F7FA
│
└── Primary Text
```

---

# 36. Design System 的核心规则

最终只需要记住以下十条：

1. **主背景使用 `#484868`。**
2. **Sidebar 使用 `#383060`。**
3. **Primary 使用 `#887EB4`，不要大面积使用。**
4. **文字以 `#F8F7FA / #D0CBDD / #A7A1B8` 建立三级层级。**
5. **Surface 优先使用明度差，而不是粗边框。**
6. **聊天消息默认不使用气泡。**
7. **桌面端支持 Hover / Focus / Right Click / Keyboard。**
8. **移动端优先 Touch / Safe Area / Gesture / Bottom Sheet。**
9. **颜色 Token 在所有平台统一，布局和交互按照平台适配。**
10. **Material 3 负责 Flutter 组件行为，App Design System 负责视觉。**

---

# 37. 推荐项目最终结构

```text
Design System
│
├── Colors
│   ├── Background
│   ├── Surface
│   ├── Primary
│   ├── Text
│   ├── Border
│   ├── Semantic
│   └── Presence
│
├── Typography
│   ├── Display
│   ├── Headline
│   ├── Title
│   ├── Body
│   ├── Label
│   └── Caption
│
├── Layout
│   ├── Spacing
│   ├── Radius
│   ├── Elevation
│   └── Breakpoints
│
├── Components
│   ├── Button
│   ├── Input
│   ├── Sidebar
│   ├── Channel
│   ├── Message
│   ├── Avatar
│   ├── Attachment
│   ├── Dialog
│   ├── Tooltip
│   └── Toast
│
└── Platform
    ├── Web
    ├── Windows
    ├── macOS
    ├── iOS
    └── Android
```

---

## Final Principle

这套设计系统不是要求五个平台"长得完全一样"。

正确目标是：

> **五个平台拥有同一种视觉语言，但拥有符合各自平台习惯的交互方式。**

也就是：

```text
                 ONE DESIGN LANGUAGE
                         │
          ┌──────────────┼──────────────┐
          │              │              │
       Desktop         Web           Mobile
          │              │              │
     Windows/macOS      Web        iOS/Android
          │              │              │
          └──────────────┼──────────────┘
                         │
                   SAME COLOR TOKENS
                   SAME TYPOGRAPHY
                   SAME SPACING
                   SAME BRAND
```

这样后续无论继续扩展
TeamSpeak、文字聊天、语音频道、文件传输、好友系统还是服务器管理，这套
Design System 都可以继续复用。
