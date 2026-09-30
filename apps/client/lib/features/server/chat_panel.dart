// The message list and the composer.

// `ConnectionState` is hidden because `material.dart` exports a different one
// (a `FutureBuilder`'s), and this file means the session's.
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/domain.dart';
import '../../providers/providers.dart';
import '../../state/server_view.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar.dart';

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
        const Divider(height: 1, color: AppColors.divider),
        Expanded(
          child: messages.isEmpty
              ? const _EmptyChannel()
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: 16),
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

    ref.read(rustClientProvider).sendMessage(_view.session, target, text);
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
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
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
    final channel = view.ownChannel;
    final other = _privateWith(view, l10n);

    return Container(
      color: AppColors.header,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      child: Row(
        children: [
          if (other != null)
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 18),
              tooltip: l10n.chatBackToChannel,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: view.closeConversation,
            )
          else
            const Icon(Icons.chat_bubble_outline, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Text(
            other?.name ?? channel?.name ?? l10n.chatNotInChannel,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          if (other != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                l10n.chatPrivateLabel,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
          if (channel?.topic != null && channel!.topic!.isNotEmpty) ...[
            const SizedBox(width: 12),
            const SizedBox(height: 16, child: VerticalDivider(width: 1)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                channel.topic!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
          const Spacer(),
          if (view.info != null)
            Text(
              l10n.chatOnlineCount(view.info!.clientsOnline),
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.forum_outlined, size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.of(context).chatEmpty,
            style: const TextStyle(color: AppColors.textSecondary),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(name: message.senderName, size: 38),
          const SizedBox(width: 14),
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
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatTimestamp(l10n, message.sentAt),
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                    if (message.isPrivate) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.lock_outline, size: 12, color: AppColors.idle),
                    ],
                  ],
                ),
                if (message.content.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  SelectableText(
                    message.content,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                ],
                for (final attachment in message.attachments)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
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
    final available = attachment.isAvailable;

    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      decoration: BoxDecoration(
        color: AppColors.composer,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.chatBackground,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              attachment.kindLabel,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  '${attachment.readableSize}${attachment.mimeType == null ? '' : ' · ${attachment.mimeType}'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: available ? null : null,
            tooltip: available ? l10n.chatDownload : l10n.chatFileTransferLater,
            icon: const Icon(Icons.download, size: 20),
            color: AppColors.textSecondary,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
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
              decoration: InputDecoration(
                hintText: hint,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.alternate_email, size: 18, color: AppColors.textMuted),
                    SizedBox(width: 14),
                    Icon(Icons.text_fields, size: 18, color: AppColors.textMuted),
                    SizedBox(width: 14),
                    Icon(Icons.tag_faces_outlined, size: 18, color: AppColors.textMuted),
                    SizedBox(width: 14),
                    Icon(Icons.attach_file, size: 18, color: AppColors.textMuted),
                    SizedBox(width: 12),
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
