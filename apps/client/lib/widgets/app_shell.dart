// Chooses what the window shows: the connect screen, or a server.

import 'dart:io' show Platform;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../theme/app_theme.dart';
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
  final logDirectory = coreLogDirectory();
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger.showSnackBar(
    SnackBar(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The sentence is built here, in the language on screen now — the
          // error itself carries data, not words (see `l10n/errors.dart`).
          Text(error.describe(l10n)),
          if (logDirectory != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.shellLogPath(logDirectory),
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
      backgroundColor: error.isRetryable ? null : Colors.red.shade900,
      // Long enough to actually press the button — the default four seconds is
      // not, and the reason to show it at all is that someone acts on it.
      duration: const Duration(seconds: 10),
      action: logDirectory == null
          ? null
          : SnackBarAction(
              label: l10n.shellOpenLog,
              onPressed: () => revealDirectory(logDirectory),
            ),
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
        // Synchronous, before the response: after `exit` no Dart callback
        // runs, and a marker left behind would be a false crash. The call is
        // cheap by design — it must not hold the close button hostage.
        ref.read(rustClientProvider).markCleanExit();
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
    final sessions = ref.watch(sessionsProvider);
    final requested = ref.watch(activeSessionProvider);

    // Falling back to the newest session means a `connect` that succeeds while
    // the user is still on the connect screen switches over by itself, which is
    // what makes the auto-connect hook usable.
    final active = requested ?? (sessions.isEmpty ? null : sessions.keys.last);

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
