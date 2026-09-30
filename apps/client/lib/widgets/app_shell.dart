// Chooses what the window shows: the connect screen, or a server.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/connect/connect_page.dart';
import '../features/server/server_page.dart';
import '../features/voice/voice_bar.dart';
import '../ffi/rust_client.dart';
import '../providers/providers.dart';

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

/// The default nickname when none was given.
const String _defaultNickname = 'Nightcord User';

/// The root of the app.
class AppShell extends ConsumerStatefulWidget {
  /// Builds the shell.
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    // After the first frame, so providers are settled and the connect is not
    // issued during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoConnect());
  }

  /// Connects to every address named in the environment.
  ///
  /// Comma-separated, so more than one can be given at once. That is what makes
  /// multi-session actually exercisable: the server switcher and the per-session
  /// stores need two live servers before they mean anything (§86).
  void _autoConnect() {
    final raw = Platform.environment[_autoConnectVar];
    if (raw == null || raw.isEmpty || !mounted) return;

    final nickname = Platform.environment[_nicknameVar];
    final profile = Platform.environment[_profileVar];

    final client = ref.read(rustClientProvider);
    for (final address in raw.split(',').map((part) => part.trim())) {
      if (address.isEmpty) continue;

      debugPrint(
        '[nightcord] auto-connecting to $address (profile ${profile ?? "default"})',
      );
      client.connect(
        ConnectRequest(
          address: address,
          nickname: (nickname == null || nickname.isEmpty) ? _defaultNickname : nickname,
          profile: (profile == null || profile.isEmpty) ? 'default' : profile,
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
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: error.isRetryable ? null : Colors.red.shade900,
        ),
      );
    });

    if (active == null) return const ConnectPage();

    // Push-to-talk watches the keyboard whenever a server is on screen (§30).
    return PushToTalkListener(session: active, child: ServerPage(session: active));
  }
}
