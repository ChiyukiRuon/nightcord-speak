# UI 字体规范

## 1. 目标

为 Flutter 跨平台 UI 提供统一的：

* 简体中文
* 繁体中文
* 日文
* 韩文
* 英文

字体方案，并保证 Windows、macOS、Linux、Android、iOS、Web 的 UI 视觉尽可能一致。

---

## 2. 字体选型

### 推荐：Noto Sans CJK

采用 Noto Sans 字体体系：

| Locale                      | 字体           |
| --------------------------- | ------------ |
| `en`                        | Noto Sans    |
| `zh-CN`                     | Noto Sans SC |
| `zh-TW` / `zh-HK` / `zh-MO` | Noto Sans TC |
| `ja`                        | Noto Sans JP |
| `ko`                        | Noto Sans KR |

官方仓库：

* Noto CJK：https://github.com/notofonts/noto-cjk
* Noto Fonts：https://github.com/notofonts

### 备选：Source Han Sans

思源黑体与 Noto Sans CJK 属于相近的 CJK 字体体系，同样适合 Flutter UI。

官方仓库：

https://github.com/adobe-fonts/source-han-sans

**项目只需要选择 Noto Sans 或 Source Han Sans 其中一套。**

---

## 3. 字重规范

UI 只保留四个常用字重：

```text
400 Regular
500 Medium
600 SemiBold
700 Bold
```

建议：

| 用途      |  字重 |
| ------- | --: |
| 正文 / 列表 | 400 |
| 按钮 / 标签 | 500 |
| 标题      | 600 |
| 强调      | 700 |

常规 UI 字号：

```text
标题：20–32 px
正文：14–16 px
辅助文字：12–14 px
最小字号：12 px
```

---

# 4. 实施步骤

## Step 1：下载字体

从 Noto CJK 官方仓库获取对应语言字体。

项目实际支持：

```text
Noto Sans
Noto Sans SC
Noto Sans TC
Noto Sans JP
Noto Sans KR
```

如果 App 不需要某种语言，不要打包对应字体。

---

## Step 2：建立字体目录

推荐：

```text
project/
├── assets/
│   └── fonts/
│       ├── NotoSans-Regular.ttf
│       ├── NotoSans-Medium.ttf
│       ├── NotoSans-SemiBold.ttf
│       ├── NotoSans-Bold.ttf
│       │
│       ├── NotoSansSC-Regular.ttf
│       ├── NotoSansSC-Medium.ttf
│       ├── NotoSansSC-SemiBold.ttf
│       ├── NotoSansSC-Bold.ttf
│       │
│       ├── NotoSansTC-Regular.ttf
│       ├── NotoSansTC-Medium.ttf
│       ├── NotoSansTC-SemiBold.ttf
│       ├── NotoSansTC-Bold.ttf
│       │
│       ├── NotoSansJP-Regular.ttf
│       ├── NotoSansJP-Medium.ttf
│       ├── NotoSansJP-SemiBold.ttf
│       ├── NotoSansJP-Bold.ttf
│       │
│       ├── NotoSansKR-Regular.ttf
│       ├── NotoSansKR-Medium.ttf
│       ├── NotoSansKR-SemiBold.ttf
│       └── NotoSansKR-Bold.ttf
│
└── pubspec.yaml
```

---

## Step 3：配置 `pubspec.yaml`

```yaml
flutter:
  fonts:
    - family: NotoSans
      fonts:
        - asset: assets/fonts/NotoSans-Regular.ttf
          weight: 400
        - asset: assets/fonts/NotoSans-Medium.ttf
          weight: 500
        - asset: assets/fonts/NotoSans-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/NotoSans-Bold.ttf
          weight: 700

    - family: NotoSansSC
      fonts:
        - asset: assets/fonts/NotoSansSC-Regular.ttf
          weight: 400
        - asset: assets/fonts/NotoSansSC-Medium.ttf
          weight: 500
        - asset: assets/fonts/NotoSansSC-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/NotoSansSC-Bold.ttf
          weight: 700

    - family: NotoSansTC
      fonts:
        - asset: assets/fonts/NotoSansTC-Regular.ttf
          weight: 400
        - asset: assets/fonts/NotoSansTC-Medium.ttf
          weight: 500
        - asset: assets/fonts/NotoSansTC-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/NotoSansTC-Bold.ttf
          weight: 700

    - family: NotoSansJP
      fonts:
        - asset: assets/fonts/NotoSansJP-Regular.ttf
          weight: 400
        - asset: assets/fonts/NotoSansJP-Medium.ttf
          weight: 500
        - asset: assets/fonts/NotoSansJP-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/NotoSansJP-Bold.ttf
          weight: 700

    - family: NotoSansKR
      fonts:
        - asset: assets/fonts/NotoSansKR-Regular.ttf
          weight: 400
        - asset: assets/fonts/NotoSansKR-Medium.ttf
          weight: 500
        - asset: assets/fonts/NotoSansKR-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/NotoSansKR-Bold.ttf
          weight: 700
```

然后：

```bash
flutter pub get
```

---

# 5. Step 4：实现 Locale → 字体映射

建立：

```text
lib/core/theme/app_fonts.dart
```

代码：

```dart
import 'package:flutter/widgets.dart';

String fontFamilyForLocale(Locale locale) {
  switch (locale.languageCode) {
    case 'zh':
      switch (locale.countryCode) {
        case 'TW':
        case 'HK':
        case 'MO':
          return 'NotoSansTC';
        default:
          return 'NotoSansSC';
      }

    case 'ja':
      return 'NotoSansJP';

    case 'ko':
      return 'NotoSansKR';

    default:
      return 'NotoSans';
  }
}
```

这样可以避免日文汉字错误地使用中文字体字形。

---

# 6. Step 5：统一 Theme

建立：

```text
lib/core/theme/app_theme.dart
```

例如：

```dart
ThemeData createAppTheme(Locale locale) {
  final fontFamily = fontFamilyForLocale(locale);

  return ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,

    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontWeight: FontWeight.w600,
      ),
      headlineMedium: TextStyle(
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: TextStyle(
        fontWeight: FontWeight.w400,
      ),
      labelLarge: TextStyle(
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}
```

应用入口：

```dart
MaterialApp(
  theme: createAppTheme(currentLocale),
);
```

---

# 7. Step 6：不要在 Widget 中重复指定字体

推荐：

```dart
Text(
  '服务器设置',
)
```

而不是：

```dart
Text(
  '服务器设置',
  style: const TextStyle(
    fontFamily: 'NotoSansSC',
  ),
)
```

字体、字重和字号统一由 `ThemeData` / `TextTheme` 管理。

这样未来更换字体时只需要修改 Theme。

---

# 8. Step 7：处理 Emoji

Emoji 不需要打包到 Noto Sans。

保持：

```text
普通文字 → App 内置 Noto Sans
Emoji → 系统 Emoji
```

例如：

```text
🎤  🔊  🔴  🟢  ⭐
```

交给系统字体处理即可。

---

# 9. Step 8：控制字体体积

CJK 字体文件较大，不建议无条件打包全部语言和全部字重。

根据实际支持的 Locale 选择资源。

例如仅支持：

```text
中文 + 日文 + 英文
```

则无需加入：

```text
NotoSansKR
```

如果 App 对体积非常敏感，可以进一步进行**字体子集化**，只保留应用实际使用的字符。

---

# 10. Step 9：测试四语 UI

至少测试以下文本：

```text
服务器设置
繁體中文設定
サーバー設定
서버 설정
Server Settings
```

以及混排：

```text
Server 服务器 サーバー 서버
```

重点检查：

* 字体高度
* 字符宽度
* 字重
* 行高
* 按钮宽度
* 文本截断
* 自动换行
* 中英文混排
* 日文汉字字形
* 韩文显示
* Emoji fallback

---

# 11. Step 10：多平台测试

最终至少测试：

```text
Windows
macOS
Linux
Android
iOS
Web
```

特别注意：

```text
Windows / macOS / Linux
```

不要因为系统自带字体不同而出现明显的 UI 差异。

应用字体应该始终使用项目内置字体。

---

# 12. 项目最终结构

推荐最终结构：

```text
lib/
├── core/
│   └── theme/
│       ├── app_fonts.dart
│       ├── app_theme.dart
│       └── app_typography.dart
│
assets/
└── fonts/
    ├── NotoSans-*.ttf
    ├── NotoSansSC-*.ttf
    ├── NotoSansTC-*.ttf
    ├── NotoSansJP-*.ttf
    └── NotoSansKR-*.ttf
```

---

# 13. 最终规范

```text
字体体系：
Noto Sans / Noto Sans CJK

语言：
en      → Noto Sans
zh-CN   → Noto Sans SC
zh-TW   → Noto Sans TC
zh-HK   → Noto Sans TC
zh-MO   → Noto Sans TC
ja      → Noto Sans JP
ko      → Noto Sans KR

字重：
400 / 500 / 600 / 700

正文：
14–16 px

辅助：
12–14 px

最小：
12 px

字体来源：
App 内置

Emoji：
系统字体

字体管理：
ThemeData + TextTheme

Locale：
根据 Locale 动态选择 CJK 字体
```

---

# 14. 实施 Checklist

* [ ] 确认项目支持的 Locale
* [ ] 下载对应 Noto Sans 字体
* [ ] 删除不需要的语言字体
* [ ] 放入 `assets/fonts/`
* [ ] 配置 `pubspec.yaml`
* [ ] 执行 `flutter pub get`
* [ ] 实现 `fontFamilyForLocale()`
* [ ] 创建统一 `ThemeData`
* [ ] 创建 `TextTheme`
* [ ] 移除 Widget 中硬编码的 `fontFamily`
* [ ] 测试中 / 日 / 英 / 韩混排
* [ ] 测试 Emoji
* [ ] 测试 Windows
* [ ] 测试 macOS
* [ ] 测试 Linux
* [ ] 测试 Android
* [ ] 测试 iOS
* [ ] 测试 Web
* [ ] 检查最终 App 体积
* [ ] 将字体 License 加入第三方许可文件

---

## 推荐最终方案

对于 Flutter 跨平台客户端，采用：

**Noto Sans + Noto Sans SC/TC/JP/KR + Locale 动态选择 + Theme 统一管理。**

这样可以在保持中日英韩字体视觉一致性的同时，避免 CJK 区域字形错误，并为后续字体替换和多平台发布留下清晰的架构。
