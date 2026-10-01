// Chooses what the window shows: the connect screen, or a server.

import 'dart:io' show Platform;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme/app_theme.dart';
import '../features/connect/connect_page.dart';
import '../features/crash/crash_banner.dart';
import '../features/shortcuts/shortcut_host.dart';
import '../features/notifications/notice_stack.dart';
import '../features/server/server_page.dart';
import '../ffi/rust_client.dart';
import '../models/connect_request.dart';
import '../l10n/app_localizations.dart';
import '../l10n/errors.dart';
import '../models/crash.dart';
import '../models/events.dart';
import '../models/settings.dart';
import '../providers/providers.dart';
import '../util/reveal.dart';
import '../util/system_notifications.dart';

/// An address to connect to on launch, from the environment.
///
/// A development aid, not a feature: it lets a script drive the app so the
/// connected UI can be checked without someone typing an address every time.
/// Saved servers are the real answer for users (§40).
const String _autoConnectVar = 'NIGHTCORD_AUTO_CONNECT';

/// A nickname to use with [_autoConnectVar].
const String _nicknameVar = 'NIGHTCORD_NICKNAME';

/// An identity profile to use with [_autoConnectVar].
///
/// TeamSpeak refuses a second connection from the same identity while the first
/// is still open, so repeated scripted runs need a distinct profile each time.
const String _profileVar = 'NIGHTCORD_PROFILE';

/// Shows a failure, with the way to the log it was written to.
///
/// The path is here because the snack bar used to be the *only* copy of the
/// error: it faded after a few seconds and took the evidence with it, which is
/// exactly how bug ③ became hard to chase. Naming the file while the message is
/// still on screen is the difference between a report and a guess.
void _showError(BuildContext context, ClientError error) {
  final l10n = AppLocalizations.of(context);
  final tokens = DesignTokens.of(context);
  final logDirectory = coreLogDirectory();
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger.showSnackBar(
    SnackBar(
      // The insets are the content's own rather than Material's, because the
      // close button belongs at the bar's right *edge* and Material's padding
      // would hold it a finger's width short of it.
      padding: EdgeInsets.zero,
      content: Row(
        // Centred, not top-aligned: the button belongs to the whole bar, and
        // the column beside it is one line or three depending on whether there
        // is a log path to show.
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                tokens.space4,
                tokens.space3,
                tokens.space2,
                tokens.space3,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The sentence is built here, in the language on screen now —
                  // the error itself carries data, not words (see
                  // `l10n/errors.dart`).
                  Text(error.describe(l10n)),
                  if (logDirectory != null)
                    Padding(
                      padding: EdgeInsets.only(top: tokens.space1),
                      child: Text(
                        l10n.shellLogPath(logDirectory),
                        style: TextStyle(
                          // Was 11px, under the floor `docs/UI字体规范.md` §3
                          // sets.
                          fontSize: AppTypography.captionSize,
                          fontFamily: AppTypography.monospaceFamily,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Both buttons live in the content, and the close is last.
          //
          // `SnackBar.action` is laid out *after* the content whatever this row
          // does, so with it the close button could never be the rightmost
          // thing on the bar — which is where it belongs, because it is the one
          // that applies to the bar rather than to what the bar is about.
          if (logDirectory != null)
            TextButton(
              onPressed: () => revealDirectory(logDirectory),
              child: Text(l10n.shellOpenLog),
            ),
          IconButton(
            icon: const Icon(Icons.close),
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            // The icon takes the bar's own foreground colour, which the theme
            // sets per variant: `onErrorBg` on the red bar, `onInfoBg` on the
            // informational one.
            color: Theme.of(context).snackBarTheme.contentTextStyle?.color,
            tooltip: l10n.shellDismissError,
            onPressed: messenger.hideCurrentSnackBar,
          ),
          // A hair of margin so the glyph is not touching the bar's rounded
          // corner.
          SizedBox(width: tokens.space1),
        ],
      ),
      // §27's error variant for something that cannot be retried, and the
      // theme's default (also §27) for something that can — the retry banner
      // already said so, and a red bar over a recoverable hiccup reads worse
      // than the hiccup.
      //
      // This replaces `Colors.red.shade900` and a `null` that used to fall
      // through to Material's `inverseSurface`, which in a dark theme is a
      // *light* bar — the long-standing "looks like a bug" item in
      // `AGENTS.md` §7. Both halves now come from the specification.
      backgroundColor: error.isRetryable ? tokens.infoBg : tokens.errorBg,
      // Long enough to actually press the button — the default four seconds is
      // not, and the reason to show it at all is that someone acts on it.
      duration: const Duration(seconds: 10),
    ),
  );
}

/// The root of the app.
class AppShell extends ConsumerStatefulWidget {
  /// Builds the shell.
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  /// Watches for the window's close button.
  ///
  /// The exit path is the one place "this run ended cleanly" can be recorded:
  /// the provider scope is never torn down on the way out, so the client's
  /// `dispose` never runs, and without this every normal exit would look like
  /// a crash to the next start.
  AppLifecycleListener? _exitListener;

  /// What the previous runs left behind, asked once at start-up.
  CrashStatus _crash = CrashStatus.none;

  /// Whether the user waved the banner away for this session.
  bool _crashDismissed = false;

  @override
  void dispose() {
    _exitListener?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(windowFocusProvider.notifier).set(state == AppLifecycleState.resumed);
  }

  /// Whether the auto-connect has already been attempted.
  bool _autoConnected = false;

  @override
  void initState() {
    super.initState();
    // The only thing the app knows about being away, and the only reason a
    // desktop notification is ever sent — while the window is in front, a toast
    // inside it is both visible and less intrusive.
    WidgetsBinding.instance.addObserver(this);

    // Asked before anything can fail again, and answered without the core —
    // see the no-handle exports in `ffi/bindings.dart`.
    _crash = ref.read(rustClientProvider).crashStatus();

    _exitListener = AppLifecycleListener(
      onExitRequested: () {
        // Synchronous, before the response: after `exit` no Dart callback runs.
        //
        // `dispose` rather than `markCleanExit`: it stops the core, which says
        // goodbye to every server on the way out. Without that the server holds
        // the session until it times out, and TS3 refuses a second connection
        // from the same identity until then — so closing the window and opening
        // it again reported the user's own nickname as already in use. It marks
        // the run clean too, and only when the core really did stop cleanly,
        // which is stricter than the call it replaces.
        //
        // Blocking is bounded by the core's own shutdown grace, which is the
        // price of the disconnect reaching the wire.
        ref.read(clientTransportProvider).dispose();
        return Future.value(AppExitResponse.exit);
      },
    );
    // A pop-up that never appears is a real possibility on Windows, where an
    // unpackaged app needs a Start Menu shortcut carrying an AppUserModelID.
    // The wrapper logs the failure rather than letting it pass unnoticed.
    initSystemNotifications();
    // The defaults the environment does not override — nickname and identity
    // profile — come from the settings, so this waits for them to arrive. It is
    // a development aid; a round trip is nothing next to typing an address.
    ref.read(clientTransportProvider).requestSettings();
    ref.listenManual(settingsProvider, (_, settings) => _autoConnect(settings));

    // In case the answer beat the subscription above.
    _autoConnect(ref.read(settingsProvider));
  }

  /// Connects to every address named in the environment.
  ///
  /// Comma-separated, so more than one can be given at once. That is what makes
  /// multi-session actually exercisable: the server switcher and the per-session
  /// stores need two live servers before they mean anything (§86).
  void _autoConnect(Settings? settings) {
    if (settings == null || _autoConnected || !mounted) return;

    final raw = Platform.environment[_autoConnectVar];
    if (raw == null || raw.isEmpty) return;

    _autoConnected = true;

    // The environment wins where it says anything: it is the development aid,
    // and a saved preference must not quietly override what a script asked for.
    final nickname = Platform.environment[_nicknameVar];
    final profile = Platform.environment[_profileVar];

    final client = ref.read(clientTransportProvider);
    for (final address in raw.split(',').map((part) => part.trim())) {
      if (address.isEmpty) continue;

      debugPrint('[nightcord] auto-connecting to $address');
      client.connect(
        ConnectRequest(
          address: address,
          nickname: (nickname == null || nickname.isEmpty)
              ? settings.connection.nickname
              : nickname,
          profile: (profile == null || profile.isEmpty)
              ? settings.connection.profile
              : profile,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watching the sessions map is load-bearing, not incidental: building that
    // provider is what subscribes to the core's event stream, which is what
    // starts polling. Without it no command result ever arrives — including the
    // one that opens a session — so the app would sit on the connect screen
    // forever.
    ref.watch(sessionsProvider);
    final active = ref.watch(activeSessionProvider);

    // No fallback to "whatever session exists". There used to be one, so that a
    // `connect` succeeding while the user was still on the connect screen would
    // switch over by itself — but a connect result already selects its own
    // session explicitly, so the fallback only ever fired for the one case it
    // broke: "add server", which clears the selection while deliberately
    // leaving the running connection alone. The sheet closed, the selection was
    // cleared, and this line put it straight back, so the button looked dead.

    // Failures surface once, as a snack bar. Nothing is cleared here: a
    // repeated failure is a *new* error object, so `listen` fires again
    // naturally, and mutating state from inside a listener would be a rebuild
    // during a rebuild.
    ref.listen(lastErrorProvider, (_, error) {
      if (error == null) return;
      _showError(context, error);
    });

    // The notices ride above whichever screen is showing, including the connect
    // one: a private message can arrive for a server you are not looking at.
    // The crash banner rides above both for the same reason — and because it is
    // most needed exactly when a server screen does not exist.
    return ShortcutHost(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (active == null) const ConnectPage() else ServerPage(session: active),
          const NoticeStack(),
          if (_crash.shouldNotify && !_crashDismissed)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: CrashBanner(
                status: _crash,
                onDismissed: () => setState(() => _crashDismissed = true),
                onResolved: () =>
                    setState(() => _crash = ref.read(rustClientProvider).crashStatus()),
              ),
            ),
        ],
      ),
    );
  }
}
