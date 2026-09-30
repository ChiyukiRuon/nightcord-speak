// The strip across the top of a server whose connection is being retried.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';

/// Says that the connection dropped, how long until the next attempt, and offers
/// a way out of it.
///
/// The tree and the conversation stay on screen underneath. The session is not
/// over — the core is retrying it — and clearing what the user was looking at
/// would make a blip feel like a crash. A reconnect re-sends the whole tree and
/// the view is idempotent, so what comes back fills in rather than duplicating.
///
/// The parent decides whether to show this at all, which also decides whether
/// the countdown below is running.
class ReconnectBanner extends ConsumerStatefulWidget {
  /// The session being retried.
  const ReconnectBanner({required this.session, super.key});

  /// The session to watch and to end if the user gives up.
  final int session;

  @override
  ConsumerState<ReconnectBanner> createState() => _ReconnectBannerState();
}

class _ReconnectBannerState extends ConsumerState<ReconnectBanner> {
  /// Redraws once a second so the countdown is not stale the moment it is drawn.
  ///
  /// A timer rather than an animation: this is one integer changing, and it does
  /// not need a frame budget.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progress = ref.watch(sessionsProvider)[widget.session]?.reconnect;

    // No scheduled retry yet means the core is between attempts; saying so
    // without a number is more honest than showing a countdown that is not
    // running.
    final label = progress == null
        ? l10n.bannerReconnecting
        : l10n.bannerRetryCountdown(progress.secondsLeft, progress.attempt);

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.header,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.only(left: 14, right: 6, top: 4, bottom: 4),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 16, color: AppColors.idle),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.idle),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () =>
                ref.read(sessionsProvider.notifier).disconnect(widget.session),
            child: Text(l10n.bannerDisconnect),
          ),
        ],
      ),
    );
  }
}
