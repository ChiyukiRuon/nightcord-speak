// The window once a server is connected.
//
// Mirrors the reference layout: a channel sidebar on the left, the message list
// on the right, and the voice controls pinned to the bottom of the sidebar.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../voice/voice_bar.dart';
import 'channel_sidebar.dart';
import 'chat_panel.dart';

/// One connected server.
class ServerPage extends ConsumerWidget {
  /// Shows `session`.
  const ServerPage({required this.session, super.key});

  /// The session handle this page renders.
  final int session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(sessionsProvider)[session];

    // The store drops a session the moment it is disconnected, so this is a
    // normal transition rather than an error.
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
      // NOTE: in this environment the bottom of the window is clipped — see
      // docs/client.md. The bar is correct; the window is a third too small.
      bottomNavigationBar: VoiceBar(session: session),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 288, child: ChannelSidebar(view: view)),
          const VerticalDivider(width: 1, color: AppColors.divider),
          Expanded(child: ChatPanel(view: view)),
        ],
      ),
    );
  }
}
