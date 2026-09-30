// The message list and the composer.

// `ConnectionState` is hidden because `material.dart` exports a different one
// (a `FutureBuilder`'s), and this file means the session's.
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/components/app_avatar.dart';
import '../../design/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/domain.dart';
import '../../providers/providers.dart';
import '../../state/server_view.dart';

/// The right-hand column of the window.
class ChatPanel extends ConsumerStatefulWidget {
  /// Renders `view`.
  const ChatPanel({required this.view, super.key});

  /// The server to draw.
  final ServerView view;

  @override
  ConsumerState<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<ChatPanel> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  /// How many messages the last frame drew, so a new one can scroll into view.
  int _lastCount = 0;

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  ServerView get _view => widget.view;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);

    // `shownConversation`, not `activeConversation`: a private conversation the
    // user opened stays open even as the channel they are in changes underneath.
    final conversation = _view.shownConversation;
    final messages = _view.messagesIn(conversation);

    if (messages.length != _lastCount) {
      _lastCount = messages.length;
      // After the frame, so the new extent is known and the scroll lands at the
      // true bottom rather than the previous one.
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChatHeader(view: _view),
        Divider(height: 1, color: tokens.borderSubtle),
        Expanded(
          child: messages.isEmpty
              ? const _EmptyChannel()
              : ListView.builder(
                  controller: _scroll,
                  padding: EdgeInsets.symmetric(vertical: tokens.space4),
                  itemCount: messages.length,
                  itemBuilder: (_, index) => _MessageTile(message: messages[index]),
                ),
        ),
        _Composer(
          controller: _composer,
          onSend: _send,
          enabled: _canSend,
          hint: _hint,
        ),
      ],
    );
  }

  /// Whether a message can be sent right now.
  bool get _canSend =>
      _view.isConnected &&
      _view.ownChannelId != null &&
      _view.permissions.canSendChannelMessage;

  /// What the input box says about itself.
  ///
  /// Why it is disabled matters. While reconnecting the user *is* in a channel,
  /// so the old blanket 「加入频道后才能发言」 blamed the one thing that was not
  /// wrong — and the input stayed disabled with nothing on screen explaining it.
  String get _hint {
    final l10n = AppLocalizations.of(context);
    if (_canSend) return l10n.chatHintCompose;

    return switch (_view.connection) {
      ConnectionState.reconnecting => l10n.chatHintReconnecting,
      ConnectionState.connecting => l10n.chatHintConnecting,
      ConnectionState.disconnected || ConnectionState.failed => l10n.chatHintDisconnected,
      _ => l10n.chatHintJoinChannel,
    };
  }

  void _send() {
    final text = _composer.text.trim();
    if (text.isEmpty || !_canSend) return;

    // Echoed back by the server, so nothing is added locally: a message that
    // failed to send should not appear to have succeeded.
    final target = _target();
    if (target == null) return;

    ref.read(clientTransportProvider).sendMessage(_view.session, target, text);
    _composer.clear();
  }

  /// Where a message typed now should go.
  ///
  /// The thread on screen decides: a private conversation sends to that person,
  /// the channel sends to the channel — which is what everyone in it expects.
  MessageTarget? _target() {
    final open = _view.openConversation;
    if (open != null && open.startsWith('client:')) {
      final id = int.tryParse(open.substring('client:'.length));
      if (id != null) return ClientTarget(id);
    }

    final channel = _view.ownChannelId;
    return channel == null ? null : ChannelTarget(channel);
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      // §27's panel timing, and §27's curve for something already on screen.
      duration: AppMotion.panel,
      curve: AppMotion.enter,
    );
  }
}

/// Who a private conversation is with, when one is open.
///
/// The name comes from the view, and a client who has since disconnected is
/// still in its offline list — a conversation should not lose its title because
/// the other person logged off mid-sentence.
({int id, String name})? _privateWith(ServerView view, AppLocalizations l10n) {
  final open = view.openConversation;
  if (open == null || !open.startsWith('client:')) return null;

  final id = int.tryParse(open.substring('client:'.length));
  if (id == null) return null;

  final name =
      view.clients[id]?.name ??
      view.offline.where((c) => c.id == id).firstOrNull?.name ??
      l10n.chatPrivateLabel;
  return (id: id, name: name);
}

/// The channel name and topic.
class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.view});

  final ServerView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final text = Theme.of(context).textTheme;
    final channel = view.ownChannel;
    final other = _privateWith(view, l10n);

    return Container(
      // §35: the band above the content is a secondary area.
      color: tokens.backgroundSecondary,
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space5,
        vertical: tokens.space3,
      ),
      child: Row(
        children: [
          if (other != null)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: l10n.chatBackToChannel,
              onPressed: view.closeConversation,
            )
          else
            Icon(Icons.chat_bubble_outline, color: tokens.textSecondary),
          SizedBox(width: tokens.space2),
          Text(
            other?.name ?? channel?.name ?? l10n.chatNotInChannel,
            // §5.2's `title`: this is the heading of the whole content area,
            // which is what the level is for.
            style: text.titleLarge,
          ),
          if (other != null)
            Padding(
              padding: EdgeInsets.only(left: tokens.space2),
              child: Text(
                l10n.chatPrivateLabel,
                style: text.bodySmall?.copyWith(color: tokens.textTertiary),
              ),
            ),
          if (channel?.topic != null && channel!.topic!.isNotEmpty) ...[
            SizedBox(width: tokens.space3),
            SizedBox(
              height: 16,
              child: VerticalDivider(width: 1, color: tokens.borderSubtle),
            ),
            SizedBox(width: tokens.space3),
            Expanded(
              child: Text(
                channel.topic!,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: tokens.textSecondary),
              ),
            ),
          ],
          const Spacer(),
          if (view.info != null)
            Text(
              l10n.chatOnlineCount(view.info!.clientsOnline),
              style: text.bodySmall?.copyWith(color: tokens.textTertiary),
            ),
        ],
      ),
    );
  }
}

/// Shown when the channel has no messages.
class _EmptyChannel extends StatelessWidget {
  /// Builds the placeholder.
  const _EmptyChannel();

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // §9's page-level size. The icon here was 40, which is not on that
          // scale.
          Icon(Icons.forum_outlined, size: 32, color: tokens.textDisabled),
          SizedBox(height: tokens.space3),
          Text(
            AppLocalizations.of(context).chatEmpty,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// One message.
class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final text = Theme.of(context).textTheme;

    return Padding(
      // §13: 8px above and below gives consecutive messages 16px between them,
      // which is the low end of the 16–20 it asks for. It does not distinguish
      // "same sender" from "different sender" — the view does not keep that
      // grouping, and inventing it here would mean guessing at data the core
      // never sent.
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space5,
        vertical: tokens.space2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // §14's chat size.
          Avatar(name: message.senderName, size: 40),
          SizedBox(width: tokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        message.senderName,
                        overflow: TextOverflow.ellipsis,
                        // §13: username 14px, `textPrimary`.
                        style: text.titleMedium?.copyWith(color: tokens.textPrimary),
                      ),
                    ),
                    SizedBox(width: tokens.space2),
                    Text(
                      formatTimestamp(l10n, message.sentAt),
                      // §13: time 12px, `textTertiary` — the one line of §13
                      // that names both a size and a colour, and this matches
                      // both.
                      style: text.bodySmall?.copyWith(color: tokens.textTertiary),
                    ),
                    if (message.isPrivate) ...[
                      SizedBox(width: tokens.space2),
                      Icon(Icons.lock_outline, size: 16, color: tokens.idle),
                    ],
                  ],
                ),
                if (message.content.isNotEmpty) ...[
                  SizedBox(height: tokens.space1),
                  SelectableText(
                    message.content,
                    // §13: body 14px `textPrimary`. The line height comes from
                    // the scale rather than being set here.
                    style: text.bodyMedium?.copyWith(color: tokens.textPrimary),
                  ),
                ],
                for (final attachment in message.attachments)
                  Padding(
                    padding: EdgeInsets.only(top: tokens.space2),
                    child: _AttachmentCard(attachment: attachment),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A shared file.
///
/// File transfer is the second phase (§39), so nothing the core sends carries
/// an attachment yet. The card is here so the layout is already right, and the
/// download control is visibly disabled with a reason rather than silently
/// doing nothing.
class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final text = Theme.of(context).textTheme;
    final available = attachment.isAvailable;

    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      decoration: BoxDecoration(
        // §15: an attachment card is `#686080`, which is `surface2`.
        color: tokens.surface2,
        borderRadius: AppRadius.mdAll,
      ),
      padding: EdgeInsets.all(tokens.space3),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.backgroundPrimary,
              // §7's `radiusXS` — "badges and small controls".
              borderRadius: AppRadius.xsAll,
            ),
            child: Text(
              attachment.kindLabel,
              // Was 10px. The floor the font specification sets is 12, and a
              // three-letter label fits a 40px tile at 12.
              style: text.bodySmall?.copyWith(
                fontWeight: AppTypography.bold,
                color: tokens.textRow,
              ),
            ),
          ),
          SizedBox(width: tokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.name,
                  overflow: TextOverflow.ellipsis,
                  // §15: file name 14px `textPrimary`.
                  style: text.titleMedium?.copyWith(color: tokens.textPrimary),
                ),
                SizedBox(height: tokens.space1 / 2),
                Text(
                  '${attachment.readableSize}${attachment.mimeType == null ? '' : ' · ${attachment.mimeType}'}',
                  // §15: metadata 12px `#C0BBCD`, which is `rowText`.
                  style: text.bodySmall?.copyWith(color: tokens.textRow),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: available ? null : null,
            tooltip: available ? l10n.chatDownload : l10n.chatFileTransferLater,
            icon: const Icon(Icons.download),
          ),
        ],
      ),
    );
  }
}

/// The message box.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.enabled,
    required this.hint,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;

  /// Shown when the box is empty. Says why it is disabled when it is.
  final String hint;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.space5,
        tokens.space2,
        tokens.space5,
        tokens.space4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              // §11's colours and radius come from the theme's
              // `inputDecorationTheme`; only the hint is this widget's.
              decoration: InputDecoration(
                hintText: hint,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.alternate_email, color: tokens.textTertiary),
                    SizedBox(width: tokens.space3),
                    Icon(Icons.text_fields, color: tokens.textTertiary),
                    SizedBox(width: tokens.space3),
                    Icon(Icons.tag_faces_outlined, color: tokens.textTertiary),
                    SizedBox(width: tokens.space3),
                    Icon(Icons.attach_file, color: tokens.textTertiary),
                    SizedBox(width: tokens.space3),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A message timestamp, in the form a person reads.
///
/// 「今天 5:04」 rather than a full date for anything recent, because that is
/// what someone scrolling a live conversation needs. The words come from the
/// strings file; the clock stays 24-hour in both languages — a deliberate
/// simplification recorded in `docs/localization.md`.
String formatTimestamp(AppLocalizations l10n, DateTime when, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final clock = '${when.hour}:${when.minute.toString().padLeft(2, '0')}';

  final today = DateTime(reference.year, reference.month, reference.day);
  final that = DateTime(when.year, when.month, when.day);
  final days = today.difference(that).inDays;

  if (days == 0) return l10n.timestampToday(clock);
  if (days == 1) return l10n.timestampYesterday(clock);
  if (when.year == reference.year) return l10n.timestampThisYear(when.month, when.day, clock);
  return l10n.timestampOtherYear(when.year, when.month, when.day);
}
