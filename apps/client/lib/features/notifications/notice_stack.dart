// The in-app notices, stacked in the corner.
//
// Not SnackBars. `ScaffoldMessenger` shows one at a time for its full duration,
// so a busy minute would queue notices up and deliver them long after the fact —
// and the app already uses one for errors, where a 10-second wait is right.
// These are transient by nature: three at most, four seconds each, and clicking
// one goes to whatever it was about.
//
// The look is §19's toast: a coloured background, an icon and the text, with
// the three variants the specification names. The tile that used to be here —
// the sidebar colour with a coloured stripe down the left — predates the design
// system and had no icon at all.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/theme/app_theme.dart';
import '../../providers/providers.dart';
import '../../state/notifications.dart';
import '../voice/voice_bar.dart';

/// Draws whatever is in [noticesProvider], over the top of the current screen.
class NoticeStack extends ConsumerWidget {
  /// Builds the stack.
  const NoticeStack({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(noticesProvider);
    if (notices.isEmpty) return const SizedBox.shrink();

    final tokens = DesignTokens.of(context);

    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        // Clear of the voice bar along the bottom. Derived from the bar's own
        // height rather than the 72 that used to be written here, so moving the
        // bar cannot leave the toasts sitting on top of it.
        padding: EdgeInsets.only(
          right: tokens.space4,
          bottom: voiceBarHeight + tokens.space4,
        ),
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
  /// How wide a notice is.
  ///
  /// A layout constant, like the sidebar's width: §19 describes the colours and
  /// the contents of a toast, not its size, and this is the width the notices
  /// have always been.
  static const double _width = 300;

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
    final tokens = DesignTokens.of(context);
    final text = Theme.of(context).textTheme;
    final variant = _variant(widget.notice.kind, tokens);

    return Padding(
      padding: EdgeInsets.only(top: tokens.space2),
      child: Container(
        // §8's level 2 is the one for a popup: this floats over the page, it is
        // not a dialog. Applied as a token rather than through
        // `Material(elevation:)`, which would use Material's own shadow and
        // quietly opt out of the specification.
        decoration: BoxDecoration(
          boxShadow: tokens.shadow2,
          borderRadius: AppRadius.mdAll,
        ),
        child: Material(
          color: variant.background,
          borderRadius: AppRadius.mdAll,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _open,
            child: SizedBox(
              width: _width,
              child: Padding(
                padding: EdgeInsets.all(tokens.space3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(variant.icon, size: 16, color: variant.colour),
                    SizedBox(width: tokens.space2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.notice.title,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelLarge?.copyWith(
                              color: tokens.textPrimary,
                            ),
                          ),
                          SizedBox(height: tokens.space1 / 2),
                          Text(
                            widget.notice.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: tokens.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// §19's three variants, and which of them this kind is.
  ///
  /// The specification names success, error and info. Six kinds have to land on
  /// three looks plus warning (§2.6 defines one but §19 does not draw it), so
  /// the mapping is by what the notice *means*: something arrived (info),
  /// something worth noticing happened (success), something went wrong (error),
  /// someone wants your attention (warning).
  static _ToastVariant _variant(NoticeKind kind, DesignTokens tokens) => switch (kind) {
    NoticeKind.directMessage => _ToastVariant(
      background: tokens.infoBg,
      colour: tokens.info,
      icon: Icons.mail_outline,
    ),
    NoticeKind.channelMessage => _ToastVariant(
      background: tokens.infoBg,
      colour: tokens.info,
      icon: Icons.chat_bubble_outline,
    ),
    NoticeKind.poke => _ToastVariant(
      background: tokens.warningBg,
      colour: tokens.warning,
      icon: Icons.notifications_active_outlined,
    ),
    NoticeKind.presence => _ToastVariant(
      background: tokens.successBg,
      colour: tokens.success,
      icon: Icons.person_add_alt,
    ),
    NoticeKind.connectionLost => _ToastVariant(
      background: tokens.errorBg,
      colour: tokens.error,
      icon: Icons.cloud_off,
    ),
    NoticeKind.connectionRestored => _ToastVariant(
      background: tokens.successBg,
      colour: tokens.success,
      icon: Icons.cloud_done_outlined,
    ),
  };
}

/// The three parts of a toast that vary by kind (§19).
class _ToastVariant {
  const _ToastVariant({
    required this.background,
    required this.colour,
    required this.icon,
  });

  final Color background;
  final Color colour;
  final IconData icon;
}
