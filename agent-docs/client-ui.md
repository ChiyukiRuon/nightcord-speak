# Client UI and Localization

## Shared Product UI

Flutter owns native/web product UI. `crates/ts-gateway/web` is diagnostic, not an alternative product frontend. `ClientTransport` separates embedded FFI from remote WebSocket below providers; UI/state must not depend on selected transport.

- `lib/design/{tokens,theme,components}` holds shared design primitives.
- `lib/features` holds shared business components.
- `lib/layout` owns adaptive desktop/mobile shells; choose by viewport/input capability, not OS.
- Platform services use interfaces/conditional implementations; avoid scattered `Platform.isX` or `kIsWeb` branches in business widgets.

Respect product decisions: server selection is a dropdown; do not add a server rail, separate member sidebar, or custom title bar without a new request. Members stay in the channel tree; left-click opens private chat and right-click moderation. Chat uses grouped rows rather than a bubble per message.

Use existing palette, typography, spacing, radius, motion, and theme extensions instead of local hardcoded colors/fonts. Nightcord/Black/White/system selection exists. Light theme has its own contrast and semantic pairs, not an inverted dark palette. Preserve transparent Material surface tint and interaction feedback. Minimum UI text is 12 px; spacing uses the existing 4 px grid.

Standard Material controls inherit `ThemeData`; add wrappers only for real reuse. Keep brand painter, SVG, desktop/web icons consistent through `scripts/make-app-icon.py`.

## Localization and Fonts

`app_en.arb` owns template keys and placeholder metadata/types. Update matching keys in `app_zh.arb`, `app_zh_Hant.arb`, `app_ja.arb`, and `app_ko.arb`, then run `flutter gen-l10n` in `apps/client`. Include generated `app_localizations*.dart`; analyze/test do not regenerate them.

State stores structured data; localize at rendering time through `l10n/labels.dart` and `l10n/errors.dart`. Model enums stay independent of UI strings. User/server content, physical key labels, brands, and core free-text details are not translated. `debugMessage` is diagnostic, not the default UI sentence.

Reuse `resolveAppLocale` across windows/notifications. TW/HK/MO need explicit Hant resolution or Flutter may choose plain `zh`. Unknown persisted language falls back without invalidating unrelated settings; unsupported system locales fall back to English.

Adding a locale requires coordinated changes:

1. ARB, supported-locale resolution, settings whitelist, and selector.
2. `scripts/fetch-fonts.sh` downloads/checksums, `pubspec.yaml` declarations, and `app_fonts.dart` mapping together; nonexistent families silently use system fonts.
3. macOS `.strings`, Xcode resource groups, and native language mapping.

Use distinct SC/TC/JP/KR fonts and preserve mixed-language fallbacks. Do not remove asset declarations to hide font failures.

## State and Notifications

Treat `Connected` itself as connected, preserve views during reconnect, and apply snapshots idempotently. Preserve initial-handshake replay suppression, ignore already-visible joins, and filter self-message echoes by ID rather than nickname.

Unread tracks the viewed conversation. Foreground floating notices avoid the active thread; background notifications follow focus/settings. Reconnect banners do not need duplicate floating notices.

`NotificationPolicy` gets localization via a getter; rebuilding it on language change resets session replay state and can announce every member again. macOS uses `nightcord/notifications`; do not revert to the ineffective legacy notifier path.

## Shortcuts and Exit

Persist physical USB HID codes with exact modifiers. Preserve `null` (cleared) versus missing (default) in Rust/Dart; defaults belong to `ts-settings`.

Native PTT uses system hotkeys; web shortcuts are page-scoped. Release PTT on key-up even if modifiers were released first, on disposal/loss paths, and when the last device tab closes. Capturing a shortcut releases PTT, unregisters active shortcuts, supports Esc cancellation, and surfaces registration failures.

Main-window exit explicitly shuts down core and cancels pending handshakes. Do not rely on `ProviderScope` disposal. Mark clean exit only after successful shutdown; failed workers retain abnormal-exit evidence. Detached windows have their own viewing close lifecycle.
