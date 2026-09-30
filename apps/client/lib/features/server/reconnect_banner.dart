// The strip across the top of a server whose connection is being retried.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/components/app_banner.dart';
import '../../design/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/providers.dart';

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
    final tokens = DesignTokens.of(context);
    final progress = ref.watch(sessionsProvider)[widget.session]?.reconnect;

    // No scheduled retry yet means the core is between attempts; saying so
    // without a number is more honest than showing a countdown that is not
    // running.
    final label = progress == null
        ? l10n.bannerReconnecting
        : l10n.bannerRetryCountdown(progress.secondsLeft, progress.attempt);

    return AppBanner(
      icon: Icons.cloud_off,
      // §8's warning rather than §9's presence-idle: a connection being
      // retried is a state of the application, not of a person.
      iconColour: tokens.warning,
      actions: [
        TextButton(
          onPressed: () => ref.read(sessionsProvider.notifier).disconnect(widget.session),
          child: Text(l10n.bannerDisconnect),
        ),
      ],
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tokens.warning),
      ),
    );
  }
}
