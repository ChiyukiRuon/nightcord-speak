// The channel tree, the server switcher, and the voice controls.

// `ConnectionState` is hidden because `material.dart` exports a different one
// (for `AsyncSnapshot`); ours is the session lifecycle from the Rust core.
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/domain.dart';
import '../../models/events.dart';
import '../../providers/providers.dart';
import '../../state/server_view.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar.dart';

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
    return Container(
      color: AppColors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ServerHeader(view: _view),
          const Divider(height: 1, color: AppColors.divider),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
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
          onTap: () => _openChannel(row.channel),
          onToggle: row.hasChildren ? () => _toggle(row.channel.id) : null,
        ),
      );

      // Members sit under their channel, as in the reference design.
      if (_collapsed.contains(row.channel.id)) continue;
      for (final member in _view.clientsIn(row.channel.id)) {
        rows.add(_MemberRow(member: member, depth: row.depth + 1));
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
        label: '离线 — ${_view.offline.length}',
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
      ref.read(lastErrorProvider.notifier).report(
        const ClientError(kind: 'permission', message: '没有加入该频道的权限'),
      );
      return;
    }
    ref.read(rustClientProvider).joinChannel(_view.session, channel.id);
  }
}

/// The server name and its switcher.
class _ServerHeader extends ConsumerWidget {
  const _ServerHeader({required this.view});

  final ServerView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider);
    final name = view.info?.name.isNotEmpty == true
        ? view.info!.name
        : (view.server?.displayName ?? '未连接');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showSwitcher(context, ref, sessions),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              const Icon(Icons.bubble_chart, color: AppColors.accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.expand_more, size: 18, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  /// Lists every session, so several servers can be connected at once and
  /// switched between without disconnecting any of them (§16).
  void _showSwitcher(
    BuildContext context,
    WidgetRef ref,
    Map<int, ServerView> sessions,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.sidebar,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in sessions.entries)
              ListTile(
                leading: const Icon(Icons.dns_outlined, size: 20),
                title: Text(entry.value.server?.displayName ?? '服务器 ${entry.key}'),
                subtitle: Text(
                  _stateLabel(entry.value.connection),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: entry.key == view.session ? const Icon(Icons.check, size: 18) : null,
                onTap: () {
                  ref.read(activeSessionProvider.notifier).select(entry.key);
                  Navigator.of(sheetContext).pop();
                },
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.add, size: 20),
              title: const Text('添加服务器'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                // Clearing the active session returns to the connect screen,
                // leaving the current connection running in the background.
                ref.read(activeSessionProvider.notifier).forget(view.session);
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _stateLabel(ConnectionState state) => switch (state) {
    ConnectionState.connected => '已连接',
    ConnectionState.connecting => '连接中',
    ConnectionState.reconnecting => '重连中',
    ConnectionState.disconnecting => '断开中',
    ConnectionState.failed => '连接失败',
    ConnectionState.disconnected => '未连接',
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
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Row(
          children: [
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 16,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: AppColors.textSecondary,
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
class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.row,
    required this.collapsed,
    required this.selected,
    required this.onTap,
    this.onToggle,
  });

  final TreeRow row;
  final bool collapsed;
  final bool selected;
  final VoidCallback onTap;

  /// Absent when the channel has no children, so no disclosure is drawn.
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final background = selected ? AppColors.sidebarSelected : null;

    return Padding(
      padding: EdgeInsets.only(left: 8 + row.depth * 12.0, right: 8, top: 1, bottom: 1),
      child: Material(
        color: background ?? Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: AppColors.sidebarHover,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                if (onToggle != null)
                  GestureDetector(
                    onTap: onToggle,
                    child: Icon(
                      collapsed ? Icons.chevron_right : Icons.expand_more,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  )
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 4),
                const Icon(Icons.chat_bubble_outline, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    row.channel.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (row.channel.hasPassword)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.lock_outline, size: 13, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A user inside a channel, or in the offline list.
class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.depth, this.dimmed = false});

  final Client member;
  final int depth;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final nameColour = dimmed ? AppColors.textMuted : AppColors.textPrimary;

    return Padding(
      padding: EdgeInsets.only(left: 24 + depth * 12.0, right: 8, top: 2, bottom: 2),
      child: Row(
        children: [
          Avatar(name: member.name, size: 24, dimmed: dimmed),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              member.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: nameColour,
                fontWeight: member.isSelf ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (member.flags.away && !dimmed) ...[
            const _StateBadge(colour: AppColors.idle, tooltip: '离开', icon: Icons.schedule),
          ],
          if (member.flags.inputMuted && !dimmed)
            const _StateBadge(colour: AppColors.danger, tooltip: '已静音', icon: Icons.mic_off),
          if (member.flags.recording)
            const _StateBadge(
              colour: AppColors.danger,
              tooltip: '录音中',
              icon: Icons.fiber_manual_record,
            ),
        ],
      ),
    );
  }
}

/// A small state dot on a member row.
class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.colour, required this.tooltip, required this.icon});

  final Color colour;
  final String tooltip;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.only(left: 5),
        child: Icon(icon, size: 14, color: colour),
      ),
    );
  }
}
