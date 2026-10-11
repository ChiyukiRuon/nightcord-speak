import 'package:flutter/material.dart';

import '../../../core/updates/update_service.dart';
import '../../../design/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/app_exit.dart';

class UpdateCheck extends StatefulWidget {
  const UpdateCheck({super.key, this.service, this.exitApplication});
  final UpdateService? service;
  final Future<void> Function()? exitApplication;
  @override
  State<UpdateCheck> createState() => _UpdateCheckState();
}

class _UpdateCheckState extends State<UpdateCheck> {
  late final UpdateService _service = widget.service ?? createUpdateService();
  bool _busy = false;
  bool _checked = false;
  bool _failed = false;
  DesktopUpdate? _update;
  PreparedUpdate? _prepared;
  double? _progress;
  bool _installing = false;

  @override
  void dispose() {
    _service.cancelDownload();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await action();
    } on UpdateCancelled {
      // Cancellation is a user action, not a failed update.
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _installing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_service.available) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: tokens.space4),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => _run(() async {
                  final update = await _service.check();
                  if (mounted) {
                    setState(() {
                      _update = update;
                      _prepared = null;
                      _checked = true;
                    });
                  }
                }),
          child: Text(_busy ? l10n.updateChecking : l10n.updateCheck),
        ),
        if (_failed) Text(l10n.updateError),
        if (!_failed && _checked && _update == null) Text(l10n.updateCurrent),
        if (_update != null) ...[
          Text(l10n.updateAvailable(_update!.version)),
          Text(l10n.updateDownloadHint),
          if (_progress != null) ...[
            LinearProgressIndicator(value: _progress),
            Text(l10n.updateProgress((_progress! * 100).round())),
            TextButton(
              onPressed: _service.cancelDownload,
              child: Text(l10n.updateCancel),
            ),
          ],
          if (_installing) Text(l10n.updateInstalling),
          if (!_busy && _prepared == null)
            TextButton(
              onPressed: () => _run(() async {
                setState(() => _progress = 0);
                final prepared = await _service.download(_update!, (progress) {
                  if (mounted) setState(() => _progress = progress);
                });
                if (mounted) setState(() => _prepared = prepared);
              }),
              child: Text(l10n.updateDownload),
            ),
          if (_prepared != null) ...[
            Text(l10n.updateReady),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      setState(() => _installing = true);
                      await _service.install(
                        _prepared!,
                        Localizations.localeOf(context).toLanguageTag(),
                      );
                      await (widget.exitApplication ?? exitForUpdate)();
                    }),
              child: Text(l10n.updateInstall),
            ),
          ],
        ],
      ],
    );
  }
}
