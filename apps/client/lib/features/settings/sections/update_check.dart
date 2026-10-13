import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/updates/update_controller.dart';
import '../../../core/updates/update_service.dart';
import '../../../design/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/app_exit.dart';

class UpdateCheck extends ConsumerWidget {
  const UpdateCheck({super.key, this.service, this.exitApplication});
  final UpdateService? service;
  final Future<void> Function()? exitApplication;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(updateControllerProvider(service));
    if (!controller.service.available) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final label = switch (controller.activity) {
          UpdateActivity.checking => l10n.updateChecking,
          UpdateActivity.downloading => l10n.updateProgress(
            ((controller.progress ?? 0) * 100).round(),
          ),
          UpdateActivity.installing => l10n.updateInstalling,
          UpdateActivity.idle =>
            controller.prepared != null
                ? l10n.updateInstall
                : controller.update != null
                ? l10n.updateDownload
                : l10n.updateCheck,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: tokens.space4),
            OutlinedButton(
              onPressed: controller.busy
                  ? null
                  : () async {
                      if (controller.prepared != null) {
                        await controller.install(
                          Localizations.localeOf(context).toLanguageTag(),
                          exitApplication ?? exitForUpdate,
                        );
                      } else if (controller.update != null) {
                        await controller.download();
                      } else {
                        await controller.check();
                      }
                    },
              child: Text(label),
            ),
            if (controller.failed) Text(l10n.updateError),
            if (!controller.failed &&
                controller.checked &&
                controller.update == null)
              Text(l10n.updateCurrent),
            if (controller.update != null) ...[
              if (!controller.busy && controller.prepared == null)
                Text(l10n.updateAvailable(controller.update!.version)),
              if (controller.activity == UpdateActivity.downloading) ...[
                LinearProgressIndicator(value: controller.progress ?? 0),
                TextButton(
                  onPressed: controller.cancelDownload,
                  child: Text(l10n.updateCancel),
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}
