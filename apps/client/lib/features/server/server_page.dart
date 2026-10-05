// The window once a server is connected.
//
// Mirrors the reference layout: a channel sidebar on the left, the message list
// on the right, and the voice controls pinned to the bottom of the sidebar.

// `ConnectionState` is hidden because `material.dart` exports a different one
// (a `FutureBuilder`'s), and this file means the session's.
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/theme/app_theme.dart';
import '../../layout/adaptive_shell.dart';
import '../../l10n/app_localizations.dart';
import '../../models/domain.dart';
import '../../providers/providers.dart';
import '../voice/voice_bar.dart';
import 'channel_sidebar.dart';
import 'chat_panel.dart';
import 'reconnect_banner.dart';

/// Shared desktop channel navigation width, within the design range.
const double channelSidebarWidth = 280;

/// One connected server.
class ServerPage extends ConsumerWidget {
  /// Shows `session`.
  const ServerPage({required this.session, super.key});

  /// The session handle this page renders.
  final int session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(sessionsProvider)[session];

    // Reached only when the session was deliberately forgotten — losing a
    // connection keeps the view, precisely so a reconnect can fill it back in.
    if (view == null) {
      return Scaffold(
        body: Center(
          child: Text(
            AppLocalizations.of(context).serverSessionEnded,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: DesignTokens.of(context).textSecondary),
          ),
        ),
      );
    }

    return AdaptiveShell(
      key: ValueKey(session),
      mobileNavigationBuilder: (open) => ChannelSidebar(view: view, onOpenChat: open),
      mobileTitle: view.info?.name ?? AppLocalizations.of(context).navigationChannels,
      navigationWidth: channelSidebarWidth,
      navigation: ChannelSidebar(view: view),
      content: ChatPanel(view: view),
      footer: VoiceBar(session: session),
      banner: view.connection == ConnectionState.reconnecting
          ? ReconnectBanner(session: session)
          : null,
    );
  }
}
