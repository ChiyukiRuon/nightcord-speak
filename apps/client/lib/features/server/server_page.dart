// The window once a server is connected.
//
// Mirrors the reference layout: a channel sidebar on the left, the message list
// on the right, and the voice controls pinned to the bottom of the sidebar.

// `ConnectionState` is hidden because `material.dart` exports a different one
// (a `FutureBuilder`'s), and this file means the session's.
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/domain.dart';
import '../../providers/providers.dart';
import '../voice/voice_bar.dart';
import 'channel_sidebar.dart';
import 'chat_panel.dart';
import 'reconnect_banner.dart';

/// How wide the channel sidebar is.
///
/// **Note for the layout round:** §19 gives 240–280 for a channel sidebar and
/// warns against fixing every sidebar at its widest. This one is 288, from
/// before the design system existed. It is left alone here because the layout
/// is explicitly out of scope for this pass — narrowing it is a one-line change
/// whenever that pass happens.
const double channelSidebarWidth = 288;

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
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: DesignTokens.of(context).textSecondary),
          ),
        ),
      );
    }

    final tokens = DesignTokens.of(context);

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
                SizedBox(width: channelSidebarWidth, child: ChannelSidebar(view: view)),
                VerticalDivider(width: 1, color: tokens.borderSubtle),
                Expanded(child: ChatPanel(view: view)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
