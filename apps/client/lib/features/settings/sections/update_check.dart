import 'package:flutter/material.dart';

import '../../../core/updates/update_service.dart';
import '../../../design/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';

class UpdateCheck extends StatefulWidget {
  const UpdateCheck({super.key, this.service});
  final UpdateService? service;
  @override
  State<UpdateCheck> createState() => _UpdateCheckState();
}

class _UpdateCheckState extends State<UpdateCheck> {
  late final UpdateService _service = widget.service ?? createUpdateService();
  bool _busy = false;
  bool _checked = false;
  bool _failed = false;
  DesktopUpdate? _update;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
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
          TextButton(
            onPressed: _busy ? null : () => _run(() => _service.open(_update!)),
            child: Text(l10n.updateDownload),
          ),
        ],
      ],
    );
  }
}
