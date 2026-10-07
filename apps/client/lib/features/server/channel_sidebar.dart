// The channel tree, the server switcher, and the voice controls.

// `ConnectionState` is hidden because `material.dart` exports a different one
// (for `AsyncSnapshot`); ours is the session lifecycle from the Rust core.
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/components/app_avatar.dart';
import '../../design/components/app_badge.dart';
import '../../design/components/app_logo.dart';
import '../../design/components/app_section_title.dart';
import '../../design/components/app_text_prompt.dart';
import '../../design/components/app_unread_dot.dart';
import '../../design/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/bookmarks.dart';
import '../../models/connect_request.dart';
import '../../models/domain.dart';
import '../../models/events.dart';
import '../../models/settings.dart';
import '../../core/screen/screen_providers.dart';
import '../../providers/providers.dart';
import '../../state/server_view.dart';

/// The left column of the window.
class ChannelSidebar extends ConsumerStatefulWidget {
  /// Renders `view`.
  const ChannelSidebar({required this.view, this.onOpenChat, super.key});

  /// The server to draw.
  final ServerView view;
  final VoidCallback? onOpenChat;

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

  /// Opens the action menu for `member` at `position`.
  ///
  /// Right-click rather than left, because left is already the way into a
  /// private conversation with them — the only such way there is.
  ///
  /// Permission bits decide what is offered, but a refused action is still
  /// possible: the server is the authority, and this snapshot can be stale. So
  /// a greyed item explains itself rather than being absent, and an item that
  /// is offered and then refused comes back as a permission error naming what
  /// was missing.
  Future<void> _openMemberMenu(Client member, Offset position) async {
    final l10n = AppLocalizations.of(context);
    final permissions = _view.permissions;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;

    // Everything below acts on someone else, so it is all gated on the bit that
    // covers it. Poking has no bit of its own in the model — the server decides.
    bool allows(bool granted) => granted || member.isSelf;

    final selection = await showMenu<_MemberAction>(
      context: context,
      // No fade at all. A context menu is a direct answer to a click that
      // already happened, and 300 ms of it sliding out of nothing makes the
      // gesture feel unacknowledged.
      popUpAnimationStyle: AnimationStyle.noAnimation,
      position: RelativeRect.fromRect(position & Size.zero, Offset.zero & overlay.size),
      items: [
        PopupMenuItem(
          value: _MemberAction.poke,
          enabled: !member.isSelf,
          child: Text(l10n.memberPoke),
        ),
        PopupMenuItem(
          value: _MemberAction.move,
          enabled: !member.isSelf && allows(permissions.canMoveClients),
          child: Text(l10n.memberMove),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _MemberAction.kickChannel,
          enabled: !member.isSelf && allows(permissions.canKick),
          child: Text(l10n.memberKickChannel),
        ),
        PopupMenuItem(
          value: _MemberAction.kickServer,
          enabled: !member.isSelf && allows(permissions.canKick),
          child: Text(l10n.memberKickServer),
        ),
        PopupMenuItem(
          value: _MemberAction.ban,
          enabled: !member.isSelf && allows(permissions.canBan),
          child: Text(l10n.memberBan),
        ),
        const PopupMenuDivider(),
        // Not for ourselves: our own audio is already at the level the output
        // volume slider sets, and a second control for it would be a way to
        // make the same thing quiet twice.
        PopupMenuItem(
          value: _MemberAction.volume,
          enabled: !member.isSelf,
          child: Text(l10n.memberVolume),
        ),
      ],
    );

    if (!mounted || selection == null) return;
    switch (selection) {
      case _MemberAction.poke:
        await _promptPoke(member);
      case _MemberAction.move:
        await _promptMove(member);
      case _MemberAction.kickChannel:
        await _confirmKick(member, KickScope.channel);
      case _MemberAction.kickServer:
        await _confirmKick(member, KickScope.server);
      case _MemberAction.ban:
        await _promptBan(member);
      case _MemberAction.volume:
        await _promptVolume(member);
    }
  }

  /// Asks what to say with the poke, then sends it.
  Future<void> _promptPoke(Client member) async {
    final l10n = AppLocalizations.of(context);
    final message = await showTextPrompt(
      context,
      title: l10n.memberPokePrompt(member.name),
      label: l10n.memberPokeMessage,
      confirm: l10n.memberPoke,
    );
    if (message == null || !mounted) return;

    ref.read(clientTransportProvider).poke(_view.session, member.id, message);
  }

  /// Picks a channel, then moves them into it.
  Future<void> _promptMove(Client member) async {
    final l10n = AppLocalizations.of(context);
    final channelId = await showDialog<int>(
      context: context,
      builder: (context) => _ChannelPickerDialog(
        title: l10n.memberMoveTitle(member.name),
        label: l10n.memberMoveChannel,
        confirm: l10n.saveButton,
        channels: _view.channelsInTreeOrder,
        selected: member.channelId,
      ),
    );
    if (channelId == null || !mounted) return;

    ref.read(clientTransportProvider).moveClient(_view.session, member.id, channelId);
  }

  /// Kicks, after asking. A kick is loud and immediate, so it is never one click.
  Future<void> _confirmKick(Client member, KickScope scope) async {
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<_ModerationRequest>(
      context: context,
      builder: (context) => _ModerationDialog(
        title: scope == KickScope.server ? l10n.memberKickServer : l10n.memberKickChannel,
        subject: member.name,
        reasonLabel: l10n.memberReason,
        confirm: scope == KickScope.server ? l10n.memberKickServer : l10n.memberKickChannel,
      ),
    );
    if (result == null || !mounted) return;

    ref.read(clientTransportProvider).kick(_view.session, member.id, scope, result.reason);
  }

  /// Bans, with a duration that defaults to permanent.
  Future<void> _promptBan(Client member) async {
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<_ModerationRequest>(
      context: context,
      builder: (context) => _ModerationDialog(
        title: l10n.memberBanTitle(member.name),
        subject: member.name,
        reasonLabel: l10n.memberReason,
        confirm: l10n.memberBan,
        durations: true,
      ),
    );
    if (result == null || !mounted) return;

    ref.read(clientTransportProvider).ban(_view.session, member.id, result.duration, result.reason);
  }

  /// Adjusts one person's playback gain.
  Future<void> _promptVolume(Client member) async {
    final l10n = AppLocalizations.of(context);
    final transport = ref.read(clientTransportProvider);
    final volume = await showDialog<double>(
      context: context,
      builder: (context) => _VolumeDialog(
        title: l10n.memberVolumeTitle(member.name),
        hint: l10n.memberVolumeHint,
        initial: _view.clientVolume(member.id),
      ),
    );
    if (volume == null || !mounted) return;

    _view.setClientVolume(member.id, volume);
    transport.setClientVolume(_view.session, member.id, volume);
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
          onJoin: () => _openChannel(row.channel),
          onOpen: widget.onOpenChat == null
              ? null
              : () {
                  ref
                      .read(sessionsProvider.notifier)
                      .openConversation(_view.session, ConversationKey.channel(row.channel.id));
                  widget.onOpenChat!();
                },
          onToggle: row.hasChildren ? () => _toggle(row.channel.id) : null,
        ),
      );

      // Members sit under their channel, as in the reference design.
      if (_collapsed.contains(row.channel.id)) continue;
      for (final member in _view.clientsIn(row.channel.id)) {
        rows.add(
          _MemberRow(
            member: member,
            singleTap: widget.onOpenChat != null,
            depth: row.depth + 1,
            speaking: _view.isSpeaking(member.id),
            // Someone else's name is the way into a private conversation with
            // them — the only one there is, and without it a private message
            // arrives with nowhere to read it.
            onOpen: member.isSelf
                ? null
                : () {
                    ref
                        .read(sessionsProvider.notifier)
                        .openConversation(_view.session, ConversationKey.client(member.id));
                    widget.onOpenChat?.call();
                  },
            unread: _view.unread.contains(ConversationKey.client(member.id)),
            onMenu: (position) => _openMemberMenu(member, position),
            session: _view.session,
            // Watching is something you do from inside the channel: the
            // controller only tracks the people it can see, and the server
            // refuses the join anyway.
            canWatch: !member.isSelf && member.channelId == _view.ownChannelId,
          ),
        );
      }
    }

    return rows;
  }

  /// Moves us into a channel.
  void _openChannel(Channel channel) {
    if (channel.id == _view.ownChannelId) {
      Scaffold.maybeOf(context)?.closeDrawer();
      return;
    }
    if (!_view.permissions.canJoinChannel) {
      // A Dart-side kind with no payload; `l10n/errors.dart` turns it into the
      // sentence, so no language is baked in here.
      ref.read(lastErrorProvider.notifier).report(const ClientError(kind: 'join_denied'));
      return;
    }
    ref.read(clientTransportProvider).joinChannel(_view.session, channel.id);
    Scaffold.maybeOf(context)?.closeDrawer();
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
          padding: EdgeInsets.fromLTRB(tokens.space4, tokens.space3, tokens.space3, tokens.space3),
          child: Row(
            children: [
              // §16's large size; the mark takes the theme's primary itself.
              const AppLogo(size: 24),
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
  void _showSwitcher(BuildContext context, WidgetRef ref, Map<int, ServerView> sessions) {
    final saved = ref.read(bookmarksProvider)?.bookmarks ?? const <Bookmark>[];
    final settings = ref.read(settingsProvider) ?? const Settings();

    // Which saved entry is the server we are on, if any. Matched on host and
    // port, which is what an entry *is* — the name is a label the user is free
    // to change, and two rows for one server is exactly the duplication that
    // rule exists to avoid.
    final server = view.server;
    final isSavedAt = server == null
        ? null
        : saved.indexWhere((b) => b.address == server.address && b.protocol == server.protocol);
    final isSaved = isSavedAt != null && isSavedAt >= 0;

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
                for (var index = 0; index < saved.length; index++)
                  ListTile(
                    leading: Icon(Icons.bookmark_outline, color: tokens.textSecondary),
                    title: Text(saved[index].displayName, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      saved[index].address,
                      style: Theme.of(sheetContext).textTheme.bodySmall
                          ?.copyWith(color: tokens.textTertiary),
                    ),
                    // Connects straight away here, unlike the connect screen:
                    // this sheet is for "open another one", and the details of a
                    // server already saved are not what the user came to change.
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      ref
                          .read(clientTransportProvider)
                          .connect(ConnectRequest.fromBookmark(saved[index], settings));
                    },
                    trailing: PopupMenuButton<_SavedAction>(
                      tooltip: l10n.connectMoreTooltip,
                      icon: Icon(Icons.more_vert, color: tokens.textSecondary),
                      onSelected: (choice) {
                        Navigator.of(sheetContext).pop();
                        switch (choice) {
                          case _SavedAction.edit:
                            _editBookmark(context, ref, index, saved[index]);
                          case _SavedAction.delete:
                            // No confirmation, matching the connect screen: a
                            // saved server is one line to type again, and a
                            // prompt for it would be noise.
                            ref
                                .read(bookmarksProvider.notifier)
                                .update(
                                  (ref.read(bookmarksProvider) ?? const BookmarkList()).removeAt(
                                    index,
                                  ),
                                );
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: _SavedAction.edit, child: Text(l10n.sidebarEditSaved)),
                        PopupMenuItem(value: _SavedAction.delete, child: Text(l10n.connectDelete)),
                      ],
                    ),
                  ),
              ],
              Divider(height: 1, color: tokens.borderSubtle),
              // What the server lets us do, in the one place a server-level
              // action already lives. Until this existed the six permission
              // bits travelled all the way from the server and were read
              // nowhere except the chat box's own enablement.
              ListTile(
                leading: Icon(Icons.shield_outlined, color: tokens.textSecondary),
                title: Text(l10n.permissionsTitle),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showDialog<void>(
                    context: context,
                    builder: (_) => _PermissionsDialog(permissions: view.permissions),
                  );
                },
              ),
              Divider(height: 1, color: tokens.borderSubtle),
              // The server in front of the user, saved or not. It is the one
              // they are most likely to want back, and until this existed the
              // only way to keep it was to go to the connect screen and retype
              // an address they were already connected to.
              ListTile(
                leading: Icon(
                  isSaved ? Icons.bookmark : Icons.bookmark_add_outlined,
                  color: tokens.textSecondary,
                ),
                title: Text(isSaved ? l10n.sidebarBookmarkRemove : l10n.sidebarBookmarkAdd),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  final notifier = ref.read(bookmarksProvider.notifier);
                  final list = ref.read(bookmarksProvider) ?? const BookmarkList();
                  final at = isSavedAt;
                  if (at != null && at >= 0) {
                    notifier.update(list.removeAt(at));
                  } else if (server != null) {
                    // Through `add` rather than `update`: the core parses the
                    // address, so an entry saved here is spelt the same way as
                    // one saved on the connect screen.
                    notifier.add(
                      NewBookmark(
                        name: server.displayName,
                        address: server.address,
                        protocol: server.protocol,
                      ),
                    );
                  }
                },
              ),
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

  /// Edits one saved server.
  ///
  /// Through `addBookmark` rather than `update`, because the address is the
  /// entry's identity and only the core has the parser that decides what a
  /// typed address means. `replaces` tells it which row the edit supersedes, so
  /// changing the address moves the entry instead of leaving the old one behind
  /// and adding a second.
  Future<void> _editBookmark(
    BuildContext context,
    WidgetRef ref,
    int index,
    Bookmark bookmark,
  ) async {
    final edited = await showDialog<NewBookmark>(
      context: context,
      builder: (_) => _BookmarkDialog(bookmark: bookmark),
    );
    if (edited == null) return;

    ref
        .read(bookmarksProvider.notifier)
        .add(
          NewBookmark(
            name: edited.name,
            address: edited.address,
            nickname: edited.nickname,
            protocol: edited.protocol,
            serverPassword: edited.serverPassword,
            replaces: bookmark.address,
          ),
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
    this.onOpen,
    required this.selected,
    required this.onJoin,
    this.onToggle,
    this.unread = false,
  });

  final TreeRow row;
  final bool collapsed;
  final VoidCallback? onOpen;
  final bool selected;

  /// Moves us into this channel, on a double click.
  ///
  /// Double rather than single because a channel is where everyone else can
  /// see you: walking into one by accident is worth a second click. It also
  /// costs nothing to be certain about, because a single click here has no
  /// side effect to hold back — the disclosure triangle has its own gesture.
  final VoidCallback onJoin;

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
            onTap: widget.onOpen,
            onDoubleTap: widget.onOpen == null ? widget.onJoin : null,
            onLongPress: widget.onJoin,
            borderRadius: AppRadius.smAll,
            hoverColor: tokens.channelHoverBg,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: tokens.space2, vertical: tokens.space2),
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
                  Icon(Icons.chat_bubble_outline, size: 16, color: contentColour),
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
                      child: Icon(Icons.lock_outline, size: 16, color: tokens.textTertiary),
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
    this.singleTap = false,
    required this.depth,
    this.speaking = false,
    this.onOpen,
    this.unread = false,
    this.onMenu,
    required this.session,
    this.canWatch = false,
  });

  final Client member;
  final bool singleTap;
  final int depth;

  /// Whether this person is talking right now.
  final bool speaking;

  /// Opens a private conversation, on a double click.
  ///
  /// Double, like a channel row and for the same reason: what it does is
  /// visible to the other person, so it is worth a second click to be sure of.
  final VoidCallback? onOpen;

  /// Whether this person has said something the user has not read.
  final bool unread;

  /// Opens the action menu, at a global position.
  ///
  /// Null for rows that are not a live client — the offline list.
  final ValueChanged<Offset>? onMenu;

  /// The session the badge drives, for the rows that have one.
  final int session;

  /// Whether this person's share can be watched from here.
  ///
  /// False for our own row — we are the one publishing, and for anyone outside
  /// our channel, which a share does not cross.
  final bool canWatch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final text = Theme.of(context).textTheme;

    // Wrapped in a `Material` for the same reason a channel row is: an
    // `InkWell` paints its hover highlight on the nearest `Material` above it,
    // and without one the colour was being set and never drawn.
    final row = Material(
      color: Colors.transparent,
      borderRadius: AppRadius.smAll,
      child: InkWell(
        onTap: singleTap ? onOpen : null,
        onDoubleTap: singleTap ? null : onOpen,
        onLongPress: onMenu == null
            ? null
            : () {
                final box = context.findRenderObject()! as RenderBox;
                onMenu!(box.localToGlobal(box.size.center(Offset.zero)));
              },
        onSecondaryTapDown: onMenu == null ? null : (details) => onMenu!(details.globalPosition),
        borderRadius: AppRadius.smAll,
        hoverColor: tokens.channelHoverBg,
        child: Padding(
          padding: EdgeInsets.only(
            left: tokens.space6 + depth * tokens.space3,
            right: tokens.space2,
            top: tokens.space1,
            bottom: tokens.space1,
          ),
          child: Row(
            children: [
              // §22's compact size.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Avatar(name: member.name, size: 28, speaking: speaking),
              ),
              SizedBox(width: tokens.space2),
              Expanded(
                // The away message rides with the name rather than hiding in a
                // tooltip: nobody hovers to find out why someone is quiet, and
                // the message is the whole answer. One `Text.rich` rather than
                // two widgets side by side, so the name keeps its room and the
                // message takes what is left — the line ellipsizes once, at the
                // end, instead of squeezing the name to half a row.
                child: Text.rich(
                  TextSpan(
                    text: member.name,
                    children: [
                      if (member.awayMessage case final message?)
                        TextSpan(
                          text: ' ($message)',
                          style: text.bodySmall?.copyWith(color: tokens.textSecondary),
                        ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                  style: (member.isSelf ? text.titleMedium : text.bodyMedium)?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: member.isSelf ? AppTypography.semibold : null,
                    fontVariations: member.isSelf ? const [FontVariation('wght', 600)] : null,
                  ),
                ),
              ),
              // First among the badges: what someone is *sending* is a bigger
              // fact than whether they are away, and for anyone in the same
              // channel it is also the way in.
              if (member.flags.streaming)
                _StreamBadge(session: session, member: member, canWatch: canWatch),
              if (member.flags.away)
                StateBadge(
                  colour: tokens.idle,
                  tooltip: l10n.memberAway,
                  // The same glyph the voice bar's away button wears, so the
                  // badge and the button read as one fact.
                  icon: Icons.snooze,
                ),
              if (member.flags.inputMuted)
                StateBadge(colour: tokens.error, tooltip: l10n.memberMuted, icon: Icons.mic_off),
              // Deafened is its own badge, not a quieter microphone: the two say
              // different things about who can hear whom, and the official client
              // draws them apart for the same reason.
              if (member.flags.outputMuted)
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
              if (unread) ...[SizedBox(width: tokens.space2), const UnreadDot()],
            ],
          ),
        ),
      ),
    );

    if (onMenu == null) return row;

    // The menu is on the secondary button, so the row also has to say what a
    // right-click would open for anyone who cannot perform one.
    return Semantics(label: l10n.memberMenu(member.name), onTap: onOpen, child: row);
  }
}

/// The badge that says someone is sharing their screen — and, for anyone who
/// can watch it, the way to do so.
///
/// One badge doing both jobs rather than a badge beside a button: a member row
/// already means "a fact about this person", and the action is that same fact
/// seen from where the user is standing. It draws in the *online* colour
/// because sharing is something the server is carrying for them, not a warning
/// — the recording badge's red would say otherwise.
///
/// It listens to the controller itself, so a share that is connecting — which
/// notifies on every step — rebuilds one badge rather than the whole tree.
class _StreamBadge extends ConsumerWidget {
  const _StreamBadge({required this.session, required this.member, required this.canWatch});

  final int session;
  final Client member;
  final bool canWatch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final controller = ref.watch(screenControllerProvider(session));

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // Filled while it is the one we are on, so a channel with several
        // shares says which of them the window is showing — and filled from
        // the moment it is asked for, not when the picture arrives.
        final watching = canWatch && controller.watches(member.id);
        final icon = Icon(
          watching ? Icons.screen_share : Icons.screen_share_outlined,
          size: 16,
          color: watching ? tokens.primary : tokens.online,
        );

        if (!canWatch) {
          return StateBadge(
            icon: Icons.screen_share,
            colour: tokens.online,
            tooltip: l10n.memberStreaming,
          );
        }

        return Tooltip(
          // The name is in the tooltip because the row's title is not always
          // readable — it ellipsizes, and with several shares the badge alone
          // cannot say whose is whose.
          message: '${watching ? l10n.screenLeave : l10n.screenWatch} · ${member.name}',
          child: GestureDetector(
            onTap: () => watching ? controller.leave() : controller.watch(member.id),
            child: Padding(
              // The same inset `StateBadge` uses, so the row's badges stay
              // evenly spaced whether or not one of them is a control.
              padding: const EdgeInsets.only(left: AppSpacing.space1),
              child: SizedBox(width: 20, height: 20, child: Center(child: icon)),
            ),
          ),
        );
      },
    );
  }
}

/// What a saved server's row menu can be asked to do.
enum _SavedAction { edit, delete }

/// Edits one saved server.
///
/// Every field, including the address: an entry whose address is wrong is an
/// entry that does not work, and telling the user to delete it and type a new
/// one would be asking them to lose the name, nickname and password they had
/// already set on it.
class _BookmarkDialog extends StatefulWidget {
  const _BookmarkDialog({required this.bookmark});

  final Bookmark bookmark;

  @override
  State<_BookmarkDialog> createState() => _BookmarkDialogState();
}

class _BookmarkDialogState extends State<_BookmarkDialog> {
  late final _name = TextEditingController(text: widget.bookmark.name);
  late final _address = TextEditingController(text: widget.bookmark.address);
  late final _nickname = TextEditingController(text: widget.bookmark.nickname ?? '');
  late final _password = TextEditingController(text: widget.bookmark.serverPassword ?? '');
  late ProtocolKind _protocol = widget.bookmark.protocol;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _nickname.dispose();
    _password.dispose();
    super.dispose();
  }

  /// What to save, or null when the address is empty.
  NewBookmark? _collect() {
    final address = _address.text.trim();
    if (address.isEmpty) return null;
    return NewBookmark(
      name: _name.text.trim(),
      address: address,
      nickname: _nickname.text.trim().isEmpty ? null : _nickname.text.trim(),
      protocol: _protocol,
      serverPassword: _password.text.isEmpty ? null : _password.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.bookmarkEditTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: l10n.connectNameLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              decoration: InputDecoration(labelText: l10n.connectAddressLabel),
              // Empty is the only thing worth refusing here: whether an address
              // reaches a server is the core's answer, and it is given when the
              // dialog is confirmed rather than guessed at here.
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nickname,
              decoration: InputDecoration(labelText: l10n.connectNicknameLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.connectServerPasswordLabel,
                hintText: l10n.connectServerPasswordHint,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<ProtocolKind>(
              segments: [
                for (final kind in ProtocolKind.values)
                  ButtonSegment(value: kind, label: Text(kind.label)),
              ],
              selected: {_protocol},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => setState(() => _protocol = selection.first),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancelButton)),
        FilledButton(
          onPressed: () {
            final edited = _collect();
            if (edited != null) Navigator.of(context).pop(edited);
          },
          child: Text(l10n.saveButton),
        ),
      ],
    );
  }
}

/// What the member menu can be asked to do.
enum _MemberAction { poke, move, kickChannel, kickServer, ban, volume }

/// Lists what the server lets *us* do, and says so when it lets us do nothing.
///
/// Every line is a live answer from the server rather than a guess, which is the
/// only reason this panel is worth having: a moderator whose rights were taken
/// away mid-session finds out here instead of from a menu that silently stopped
/// offering things.
class _PermissionsDialog extends StatelessWidget {
  const _PermissionsDialog({required this.permissions});

  final Permissions permissions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final text = Theme.of(context).textTheme;

    // Only what the server actually answered, and only what it granted.
    //
    // Both halves matter. Every bit reads as allowed when the server sends no
    // hints — right for deciding whether to grey out a button, wrong for
    // telling the user what they may do, and this panel used to do exactly that:
    // on a server that reports nothing it listed six rights the user did not
    // have. A permission nobody confirmed is not a permission.
    final entries = <String>[
      if (permissions.channelKnown) ...[
        if (permissions.canJoinChannel) l10n.permissionsJoinChannel,
        if (permissions.canSendChannelMessage) l10n.permissionsSendChannelMessage,
      ],
      if (permissions.clientKnown) ...[
        if (permissions.canMoveClients) l10n.permissionsMoveClients,
        if (permissions.canSendPrivateMessage) l10n.permissionsSendPrivateMessage,
        if (permissions.canKick) l10n.permissionsKick,
        if (permissions.canBan) l10n.permissionsBan,
      ],
    ];
    final answered = permissions.channelKnown || permissions.clientKnown;

    return AlertDialog(
      title: Text(l10n.permissionsTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            answered ? l10n.permissionsHint : l10n.permissionsNotReported,
            style: text.bodySmall?.copyWith(color: tokens.textTertiary),
          ),
          if (entries.isNotEmpty) const SizedBox(height: 12),
          for (final label in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  // The icon as well as the words: §36's rule, and the reason
                  // this panel is still legible in a palette with no red or
                  // green in it.
                  Icon(Icons.check_circle_outline, size: 16, color: tokens.online),
                  const SizedBox(width: 8),
                  Expanded(child: Text(label)),
                ],
              ),
            ),
          if (answered && entries.isEmpty) ...[
            const SizedBox(height: 12),
            Text(l10n.permissionsNone),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancelButton)),
      ],
    );
  }
}

/// A kick or a ban, as the dialog collected it.
class _ModerationRequest {
  const _ModerationRequest(this.reason, [this.duration = BanDuration.permanent]);

  /// The optional explanation. Empty means none.
  final String? reason;

  /// Only meaningful for a ban.
  final BanDuration duration;
}

/// Asks which channel, and returns its id.
class _ChannelPickerDialog extends StatefulWidget {
  const _ChannelPickerDialog({
    required this.title,
    required this.label,
    required this.confirm,
    required this.channels,
    required this.selected,
  });

  final String title;
  final String label;
  final String confirm;
  final List<Channel> channels;

  /// Pre-selected, so the common case — moving someone next door — is two
  /// clicks rather than a hunt through a long tree.
  final int? selected;

  @override
  State<_ChannelPickerDialog> createState() => _ChannelPickerDialogState();
}

class _ChannelPickerDialogState extends State<_ChannelPickerDialog> {
  int? _chosen;

  @override
  void initState() {
    super.initState();
    _chosen = widget.selected;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(widget.title),
      content: DropdownButtonFormField<int>(
        initialValue: _chosen,
        isExpanded: true,
        decoration: InputDecoration(labelText: widget.label),
        items: [
          for (final channel in widget.channels)
            DropdownMenuItem(value: channel.id, child: Text(channel.name)),
        ],
        onChanged: (id) => setState(() => _chosen = id),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancelButton)),
        FilledButton(
          onPressed: _chosen == null ? null : () => Navigator.of(context).pop(_chosen),
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}

/// Collects the optional reason, and for a ban the duration.
class _ModerationDialog extends StatefulWidget {
  const _ModerationDialog({
    required this.title,
    required this.subject,
    required this.reasonLabel,
    required this.confirm,
    this.durations = false,
  });

  final String title;

  /// Who it is about, shown so the dialog names a person rather than an action.
  final String subject;
  final String reasonLabel;
  final String confirm;

  /// Whether to offer a ban length.
  final bool durations;

  @override
  State<_ModerationDialog> createState() => _ModerationDialogState();
}

class _ModerationDialogState extends State<_ModerationDialog> {
  final _reason = TextEditingController();
  BanDuration _duration = BanDuration.permanent;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// The presets. A free-text number of seconds is a worse experience than four
  /// buttons, and this is not a screen anyone uses often enough to want one.
  static const List<int> _minuteSteps = [5, 30];
  static const List<int> _hourSteps = [1, 6, 24];
  static const List<int> _daySteps = [7, 30];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _reason,
            decoration: InputDecoration(labelText: widget.reasonLabel),
          ),
          if (widget.durations) ...[
            const SizedBox(height: 16),
            // The group owns the selection, and the tiles below only name
            // their own value: Flutter deprecated the per-tile `groupValue` in
            // favour of this, because a tile carrying its own copy of the
            // group's state can disagree with it.
            RadioGroup<BanDuration>(
              groupValue: _duration,
              onChanged: (value) => setState(() => _duration = value!),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final minutes in _minuteSteps)
                    RadioListTile<BanDuration>(
                      value: BanDuration.seconds(minutes * 60),
                      title: Text(l10n.memberBanMinutes(minutes)),
                    ),
                  for (final hours in _hourSteps)
                    RadioListTile<BanDuration>(
                      value: BanDuration.seconds(hours * 3600),
                      title: Text(l10n.memberBanHours(hours)),
                    ),
                  for (final days in _daySteps)
                    RadioListTile<BanDuration>(
                      value: BanDuration.seconds(days * 86400),
                      title: Text(l10n.memberBanDays(days)),
                    ),
                  // Last: a ban that never expires should be the one you have
                  // to scroll to and mean.
                  RadioListTile<BanDuration>(
                    value: BanDuration.permanent,
                    title: Text(l10n.memberBanPermanent),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancelButton)),
        FilledButton(
          onPressed: () =>
              Navigator.of(context)
                  .pop(_ModerationRequest(_reason.text.isEmpty ? null : _reason.text, _duration)),
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}

/// Adjusts one person's playback gain.
class _VolumeDialog extends StatefulWidget {
  const _VolumeDialog({required this.title, required this.hint, required this.initial});

  final String title;
  final String hint;
  final double initial;

  @override
  State<_VolumeDialog> createState() => _VolumeDialogState();
}

class _VolumeDialogState extends State<_VolumeDialog> {
  late double _value = widget.initial;

  /// The ceiling, matching `MAX_CLIENT_VOLUME` in the backend.
  ///
  /// Above unity because the point of the control is rescuing a quiet
  /// microphone; the mixer clamps rather than wrapping, so the worst case at
  /// the top of this range is a dull peak when several people speak at once.
  static const double _max = 2.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final text = Theme.of(context).textTheme;

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Spacer(),
              Text(
                '${(_value * 100).round()}%',
                style: text.bodySmall?.copyWith(color: tokens.textTertiary),
              ),
            ],
          ),
          Slider(value: _value, max: _max, onChanged: (value) => setState(() => _value = value)),
          Text(widget.hint, style: text.bodySmall?.copyWith(color: tokens.textTertiary)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancelButton)),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_value),
          child: Text(l10n.saveButton),
        ),
      ],
    );
  }
}
