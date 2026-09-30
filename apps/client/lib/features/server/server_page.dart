// The window once a server is connected.
//
// Mirrors the reference layout: a channel sidebar on the left, the message list
// on the right, and the voice controls pinned to the bottom of the sidebar.

// `ConnectionState` is hidden because `material.dart` exports a different one
// (a `FutureBuilder`'s), and this file means the session's.
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/domain.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../voice/voice_bar.dart';
import 'channel_sidebar.dart';
import 'chat_panel.dart';
import 'reconnect_banner.dart';

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
      return const Scaffold(
        body: Center(child: Text('会话已结束', style: TextStyle(color: AppColors.textSecondary))),
      );
    }

    // The voice controls go in the Scaffold's own bottom bar rather than in a
    // Column under the content. Both should be equivalent, but the Column
    // version left the bar unpainted here while this one does not — and the
    // Scaffold is also the idiomatic place for chrome that spans the window.
    return Scaffold(
      bottomNavigationBar: VoiceBar(session: session),
      body: Column(
        children: [
          // Above the content rather than over it: a strip that covered the
          // first channel row would be read once and then be in the way.
          if (view.connection == ConnectionState.reconnecting)
            ReconnectBanner(session: session),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 288, child: ChannelSidebar(view: view)),
                const VerticalDivider(width: 1, color: AppColors.divider),
                Expanded(child: ChatPanel(view: view)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
