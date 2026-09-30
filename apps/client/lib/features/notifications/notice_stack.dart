// The in-app notices, stacked in the corner.
//
// Not SnackBars. `ScaffoldMessenger` shows one at a time for its full duration,
// so a busy minute would queue notices up and deliver them long after the fact —
// and the app already uses one for errors, where a 10-second wait is right.
// These are transient by nature: three at most, four seconds each, and clicking
// one goes to whatever it was about.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../state/notifications.dart';
import '../../theme/app_theme.dart';

/// Draws whatever is in [noticesProvider], over the top of the current screen.
class NoticeStack extends ConsumerWidget {
  /// Builds the stack.
  const NoticeStack({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(noticesProvider);
    if (notices.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        // Clear of the voice bar along the bottom.
        padding: const EdgeInsets.only(right: 16, bottom: 72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final notice in notices) NoticeTile(key: ObjectKey(notice), notice: notice),
          ],
        ),
      ),
    );
  }
}

/// One notice.
class NoticeTile extends ConsumerStatefulWidget {
  /// Shows `notice`.
  const NoticeTile({required this.notice, super.key});

  final Notice notice;

  @override
  ConsumerState<NoticeTile> createState() => _NoticeTileState();
}

class _NoticeTileState extends ConsumerState<NoticeTile> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 4), _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _dismiss() {
    if (mounted) ref.read(noticesProvider.notifier).dismiss(widget.notice);
  }

  /// Goes to whatever the notice was about.
  void _open() {
    final notice = widget.notice;
    _dismiss();

    ref.read(activeSessionProvider.notifier).select(notice.session);

    final conversation = notice.conversation;
    if (conversation == null) return;

    // Straight into the view rather than through a provider call: the view is
    // the thing that knows what is on screen, and `SessionsNotifier` has no
    // business owning which thread someone is reading.
    ref.read(sessionsProvider)[notice.session]?.open(conversation);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: AppColors.sidebar,
        borderRadius: BorderRadius.circular(8),
        elevation: 6,
        child: InkWell(
          onTap: _open,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 300,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: _accent(widget.notice.kind), width: 3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.notice.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.notice.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The colour of the stripe down the left, by what happened.
  Color _accent(NoticeKind kind) => switch (kind) {
    NoticeKind.directMessage => AppColors.accent,
    NoticeKind.channelMessage => AppColors.textSecondary,
    NoticeKind.poke => AppColors.idle,
    NoticeKind.presence => AppColors.live,
    NoticeKind.connectionLost => AppColors.danger,
    NoticeKind.connectionRestored => AppColors.live,
  };
}

/// A dot meaning "there is something here you have not looked at".
class UnreadDot extends StatelessWidget {
  /// Draws the dot.
  const UnreadDot({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
  );
}
