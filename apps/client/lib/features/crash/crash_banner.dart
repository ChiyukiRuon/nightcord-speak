// The strip across the top when the previous session did not exit cleanly.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/components/app_banner.dart';
import '../../design/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/crash.dart';
import '../../providers/providers.dart';
import '../../util/reveal.dart';

/// Says the previous run died without a clean exit, and offers the report.
///
/// The evidence itself lives next to the logs (`docs/crash.md`); this is the
/// one surface that tells the user it is there. Nothing leaves the machine: a
/// report is a text file they can read before deciding what to do with it.
class CrashBanner extends ConsumerWidget {
  /// Shows the banner for [status].
  const CrashBanner({
    required this.status,
    required this.onDismissed,
    required this.onResolved,
    super.key,
  });

  /// What the previous runs left behind.
  final CrashStatus status;

  /// The user is done with the banner; hide it for this session.
  final VoidCallback onDismissed;

  /// A report was generated — the evidence it bundled is consumed, so the
  /// caller should re-ask rather than trust this snapshot.
  final VoidCallback onResolved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final text = Theme.of(context).textTheme;

    return AppBanner(
      icon: Icons.report_outlined,
      // §2.6's warning, not §2.7's presence-idle. The two are a similar yellow
      // and the old code used the presence one, but this is a state of the
      // *application*, not of a person.
      iconColour: tokens.warning,
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: tokens.primary),
          onPressed: () => _generate(context, ref),
          child: Text(l10n.crashGenerateReport),
        ),
        TextButton(
          onPressed: () => revealDirectory(status.directory),
          child: Text(l10n.crashOpenFolder),
        ),
        TextButton(onPressed: onDismissed, child: Text(l10n.crashDismiss)),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.crashBannerTitle, style: text.bodySmall?.copyWith(color: tokens.warning)),
          if (status.notes > 0)
            Text(
              l10n.crashBannerNotes(status.notes),
              style: text.bodySmall?.copyWith(color: tokens.textTertiary),
            ),
        ],
      ),
    );
  }

  /// Builds the report and says where it went.
  ///
  /// Synchronous on purpose, like the settings writes: it is a few file reads
  /// and one write, and the alternative — an async gap before the snack bar —
  /// buys nothing.
  void _generate(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final result = ref.read(rustClientProvider).buildCrashReport();

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          result.path != null
              ? l10n.crashReportWritten(result.path!)
              : l10n.crashReportFailed,
        ),
        duration: const Duration(seconds: 10),
        action: result.path == null
            ? null
            : SnackBarAction(
                label: l10n.crashOpenFolder,
                onPressed: () => revealDirectory(status.directory),
              ),
      ),
    );

    if (result.path != null) onResolved();
  }
}
