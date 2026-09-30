// The channel tree, the server switcher, and the voice controls.

// `ConnectionState` is hidden because `material.dart` exports a different one
// (for `AsyncSnapshot`); ours is the session lifecycle from the Rust core.
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/components/app_avatar.dart';
import '../../design/components/app_badge.dart';
import '../../design/components/app_section_title.dart';
import '../../design/components/app_unread_dot.dart';
import '../../design/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/bookmarks.dart';
import '../../models/connect_request.dart';
import '../../models/domain.dart';
import '../../models/events.dart';
import '../../models/settings.dart';
import '../../providers/providers.dart';
import '../../state/server_view.dart';

/// The left column of the window.
class ChannelSidebar extends ConsumerStatefulWidget {
  /// Renders `view`.
  const ChannelSidebar({required this.view, super.key});

  /// The server to draw.
  final ServerView view;

  @override
  ConsumerState<ChannelSidebar> createState() => _ChannelSidebarState();
}

class _ChannelSidebarState extends ConsumerState<ChannelSidebar> {
  /// Channels whose children are hidden, by id.
  ///
  /// Kept here rather than in [ServerView] on purpose: collapsing is how the
  /// tree is being *viewed*, not a fact about the server.
  final Set<int> _collapsed = {};

  ServerView get _view => widget.view;

  void _toggle(int channelId) {
    setState(() {
      if (!_collapsed.remove(channelId)) _collapsed.add(channelId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);

    return Container(
      // §2.2: the sidebar is the `#3F3661` step — one below the page it sits
      // beside, which is how the boundary is drawn instead of with a border.
      color: tokens.bgSidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ServerHeader(view: _view),
          Divider(height: 1, color: tokens.borderSubtle),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(vertical: tokens.space2),
              children: _rows(),
            ),
          ),
        ],
      ),
    );
  }

  /// The flattened channel tree.
  List<Widget> _rows() {
    final rows = <Widget>[];
    final tree = _view.tree(isCollapsed: (channel) => _collapsed.contains(channel.id));

    for (final row in tree) {
      rows.add(
        _ChannelRow(
          row: row,
          collapsed: _collapsed.contains(row.channel.id),
          selected: row.channel.id == _view.ownChannelId,
          unread: _view.channelHasUnread(row.channel.id),
          onTap: () => _openChannel(row.channel),
          onToggle: row.hasChildren ? () => _toggle(row.channel.id) : null,
        ),
      );

      // Members sit under their channel, as in the reference design.
      if (_collapsed.contains(row.channel.id)) continue;
      for (final member in _view.clientsIn(row.channel.id)) {
        rows.add(
          _MemberRow(
            member: member,
            depth: row.depth + 1,
            speaking: _view.speaking.contains(member.id),
            // Someone else's name is the way into a private conversation with
            // them — the only one there is, and without it a private message
            // arrives with nowhere to read it.
            onTap: member.isSelf ? null : () => _view.open(ConversationKey.client(member.id)),
            unread: _view.unread.contains(ConversationKey.client(member.id)),
          ),
        );
      }
    }

    rows.addAll(_offlineRows());
    return rows;
  }

  /// The offline section, shown only when someone is in it.
  List<Widget> _offlineRows() {
    if (_view.offline.isEmpty) return const [];

    final collapsed = _collapsed.contains(_offlineKey);
    final rows = <Widget>[
      _CategoryRow(
        label: AppLocalizations.of(context).sidebarOffline(_view.offline.length),
        collapsed: collapsed,
        onToggle: () => _toggle(_offlineKey),
      ),
    ];
    if (collapsed) return rows;

    rows.addAll(
      _view.offline.map((c) => _MemberRow(member: c, depth: 1, dimmed: true)),
    );
    return rows;
  }

  /// A synthetic id for the offline section's collapse state.
  ///
  /// Channel ids are server-assigned and start at 1, so 0 is free.
  static const int _offlineKey = 0;

  /// Moves us into a channel.
  void _openChannel(Channel channel) {
    if (channel.id == _view.ownChannelId) return; // already there
    if (!_view.permissions.canJoinChannel) {
      // A Dart-side kind with no payload; `l10n/errors.dart` turns it into the
      // sentence, so no language is baked in here.
      ref.read(lastErrorProvider.notifier).report(const ClientError(kind: 'join_denied'));
      return;
    }
    ref.read(clientTransportProvider).joinChannel(_view.session, channel.id);
  }
}

/// The server name and its switcher.
class _ServerHeader extends ConsumerWidget {
  const _ServerHeader({required this.view});

  final ServerView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final sessions = ref.watch(sessionsProvider);
    final name = view.info?.name.isNotEmpty == true
        ? view.info!.name
        : (view.server?.displayName ?? l10n.connectionStateDisconnected);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showSwitcher(context, ref, sessions),
        hoverColor: tokens.surface1,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            tokens.space4,
            tokens.space3,
            tokens.space3,
            tokens.space3,
          ),
          child: Row(
            children: [
              // §16's large size, and §5's primary for the brand mark.
              Icon(Icons.bubble_chart, color: tokens.primary, size: 24),
              SizedBox(width: tokens.space2),
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Icon(Icons.expand_more, size: 20, color: tokens.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  /// Lists every session, so several servers can be connected at once and
  /// switched between without disconnecting any of them (§24).
  void _showSwitcher(
    BuildContext context,
    WidgetRef ref,
    Map<int, ServerView> sessions,
  ) {
    final saved = ref.read(bookmarksProvider)?.bookmarks ?? const <Bookmark>[];
    final settings = ref.read(settingsProvider) ?? const Settings();

    showModalBottomSheet<void>(
      context: context,
      // Colour and radius come from the theme's `bottomSheetTheme` (§25/§2.2):
      // a sheet is a modal, and this is the app's only one.
      builder: (sheetContext) {
        final l10n = AppLocalizations.of(sheetContext);
        final tokens = DesignTokens.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in sessions.entries)
                ListTile(
                  leading: Icon(Icons.dns_outlined, color: tokens.textSecondary),
                  title: Text(
                    entry.value.server?.displayName ?? l10n.sidebarSessionFallback(entry.key),
                  ),
                  subtitle: Text(
                    _stateLabel(l10n, entry.value.connection),
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                  trailing: entry.key == view.session
                      ? const Icon(Icons.check, size: 20)
                      : (entry.value.hasUnread ? const UnreadDot() : null),
                  onTap: () {
                    ref.read(activeSessionProvider.notifier).select(entry.key);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              if (saved.isNotEmpty) ...[
                Divider(height: 1, color: tokens.borderSubtle),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    tokens.space4,
                    tokens.space3,
                    tokens.space4,
                    tokens.space1,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SectionTitle(l10n.sidebarSheetSaved),
                  ),
                ),
                for (final bookmark in saved)
                  ListTile(
                    leading: Icon(Icons.bookmark_outline, color: tokens.textSecondary),
                    title: Text(bookmark.displayName, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      bookmark.address,
                      style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                        color: tokens.textTertiary,
                      ),
                    ),
                    // Connects straight away here, unlike the connect screen:
                    // this sheet is for "open another one", and the details of a
                    // server already saved are not what the user came to change.
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      ref
                          .read(clientTransportProvider)
                          .connect(ConnectRequest.fromBookmark(bookmark, settings));
                    },
                  ),
              ],
              Divider(height: 1, color: tokens.borderSubtle),
              ListTile(
                leading: Icon(Icons.add, color: tokens.textSecondary),
                title: Text(l10n.sidebarAddServer),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  // Clearing the active session returns to the connect screen,
                  // leaving the current connection running in the background.
                  ref.read(activeSessionProvider.notifier).forget(view.session);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  static String _stateLabel(AppLocalizations l10n, ConnectionState state) => switch (state) {
    ConnectionState.connected => l10n.connectionStateConnected,
    ConnectionState.connecting => l10n.connectionStateConnecting,
    ConnectionState.reconnecting => l10n.connectionStateReconnecting,
    ConnectionState.disconnecting => l10n.connectionStateDisconnecting,
    ConnectionState.failed => l10n.connectionStateFailed,
    ConnectionState.disconnected => l10n.connectionStateDisconnected,
  };
}

/// A collapsible section header.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.label,
    required this.collapsed,
    required this.onToggle,
  });

  final String label;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tokens.space3,
          tokens.space2,
          tokens.space3,
          tokens.space1,
        ),
        child: Row(
          children: [
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 16,
              color: tokens.textSecondary,
            ),
            SizedBox(width: tokens.space1),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                // Was 11px/700 — under the floor the font specification sets,
                // and a weight nothing else in the app used. §12.2's `label` is
                // the level for this, and it reads as a heading at 13/500
                // because of where it sits and what it is next to, not because
                // it is shouting.
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One channel in the tree.
///
/// Stateful for one reason: §19 gives a hovered channel row a different text
/// colour as well as a different background, and the text colour needs to know
/// about the pointer. `InkWell` tracks hover for its own background but does
/// not expose it.
class _ChannelRow extends StatefulWidget {
  const _ChannelRow({
    required this.row,
    required this.collapsed,
    required this.selected,
    required this.onTap,
    this.onToggle,
    this.unread = false,
  });

  final TreeRow row;
  final bool collapsed;
  final bool selected;
  final VoidCallback onTap;

  /// Whether the channel — or someone in it — has something new.
  final bool unread;

  /// Absent when the channel has no children, so no disclosure is drawn.
  final VoidCallback? onToggle;

  @override
  State<_ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends State<_ChannelRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    final text = Theme.of(context).textTheme;
    final row = widget.row;

    // §19's three states, in order of precedence: selected beats hovered,
    // hovered beats resting.
    final contentColour = widget.selected
        ? tokens.textPrimary
        : (_hovered ? tokens.textPrimary : tokens.textSecondary);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: EdgeInsets.only(
          left: tokens.space2 + row.depth * tokens.space3,
          right: tokens.space2,
        ),
        child: Material(
          color: widget.selected ? tokens.surface1 : Colors.transparent,
          borderRadius: AppRadius.smAll,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: AppRadius.smAll,
            hoverColor: tokens.channelHoverBg,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tokens.space2,
                vertical: tokens.space2,
              ),
              child: Row(
                children: [
                  if (widget.onToggle != null)
                    GestureDetector(
                      onTap: widget.onToggle,
                      child: Icon(
                        widget.collapsed ? Icons.chevron_right : Icons.expand_more,
                        size: 16,
                        color: contentColour,
                      ),
                    )
                  else
                    const SizedBox(width: 16),
                  SizedBox(width: tokens.space1),
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 16,
                    color: contentColour,
                  ),
                  SizedBox(width: tokens.space2),
                  Expanded(
                    child: Text(
                      row.channel.name,
                      overflow: TextOverflow.ellipsis,
                      // §19 gives the selected row `textPrimary`; weight is
                      // not specified, so the emphasis level carries it — 14/500
                      // against the resting 14/400.
                      style: widget.selected
                          ? text.titleMedium?.copyWith(color: contentColour)
                          : text.bodyMedium?.copyWith(color: contentColour),
                    ),
                  ),
                  if (row.channel.hasPassword)
                    Padding(
                      padding: EdgeInsets.only(left: tokens.space1),
                      child: Icon(
                        Icons.lock_outline,
                        size: 16,
                        color: tokens.textTertiary,
                      ),
                    ),
                  if (widget.unread)
                    Padding(
                      padding: EdgeInsets.only(left: tokens.space2),
                      child: const UnreadDot(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A user inside a channel, or in the offline list.
class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.depth,
    this.dimmed = false,
    this.speaking = false,
    this.onTap,
    this.unread = false,
  });

  final Client member;
  final int depth;
  final bool dimmed;

  /// Whether this person is talking right now.
  final bool speaking;

  /// Opens a private conversation, when there is one to open.
  final VoidCallback? onTap;

  /// Whether this person has said something the user has not read.
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final text = Theme.of(context).textTheme;

    // The name lighting up is the whole indicator, the way TeamSpeak draws it:
    // an icon next to a talking name is one more thing to read when the eye is
    // already on the name.
    //
    // `online` rather than the old green: §9 is the presence family and this
    // is a state of a person. A muted red would have been the wrong family —
    // nothing has gone wrong.
    final nameColour = speaking
        ? tokens.online
        : (dimmed ? tokens.offline : tokens.textPrimary);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(
          left: tokens.space6 + depth * tokens.space3,
          right: tokens.space2,
          top: tokens.space1 / 2,
          bottom: tokens.space1 / 2,
        ),
        child: Row(
          children: [
            // §22's compact size.
            Avatar(name: member.name, size: 28, dimmed: dimmed),
            SizedBox(width: tokens.space2),
            Expanded(
              child: Text(
                member.name,
                overflow: TextOverflow.ellipsis,
                style: (member.isSelf ? text.titleMedium : text.bodyMedium)?.copyWith(
                  color: nameColour,
                ),
              ),
            ),
            if (member.flags.away && !dimmed)
              StateBadge(
                colour: tokens.idle,
                tooltip: l10n.memberAway,
                icon: Icons.schedule,
              ),
            if (member.flags.inputMuted && !dimmed)
              StateBadge(
                colour: tokens.error,
                tooltip: l10n.memberMuted,
                icon: Icons.mic_off,
              ),
            // Deafened is its own badge, not a quieter microphone: the two say
            // different things about who can hear whom, and the official client
            // draws them apart for the same reason.
            if (member.flags.outputMuted && !dimmed)
              StateBadge(
                colour: tokens.error,
                tooltip: l10n.memberDeafened,
                icon: Icons.headset_off,
              ),
            if (member.flags.recording)
              StateBadge(
                colour: tokens.error,
                tooltip: l10n.memberRecording,
                icon: Icons.fiber_manual_record,
              ),
            if (unread) ...[
              SizedBox(width: tokens.space2),
              const UnreadDot(),
            ],
          ],
        ),
      ),
    );
  }
}
