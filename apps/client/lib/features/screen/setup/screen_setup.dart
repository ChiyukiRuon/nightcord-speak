// Asking what to share and how, in the reference client's two steps.

import 'package:flutter/material.dart';

import '../../../core/screen/screen_share_backend.dart';
import '../../../design/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/screen_options.dart';
import '../../../models/settings.dart';
import 'settings_step.dart';
import 'source_step.dart';

/// What the user settled on.
class ScreenSetup {
  const ScreenSetup({required this.source, required this.settings});

  /// The endpoint to capture, or null when the platform runs its own picker —
  /// a browser hands one out of `getDisplayMedia` and will not be second
  /// guessed.
  final ScreenSource? source;

  /// The numbers the encoder and the server will be told.
  final ScreenSettings settings;
}

/// Asks for a source and how to share it, or null if the user backed out.
///
/// Two steps rather than one page because they answer different questions: what
/// everyone will see, and how good it will look. The reference client splits
/// them the same way, and the split earns its keep — the source choice is the
/// one people are sure about, and putting the numbers first would ask them to
/// decide about bandwidth before they have decided what they are showing.
///
/// A dialog rather than a route, so the app stays visible behind it. Both
/// questions are about *this* window, and covering it up hides the thing being
/// chosen from.
///
/// On macOS the source half arrives already answered: the system's own picker
/// chose it, so [initialSource] is set and [skipSourceStep] opens straight on
/// the settings — the only question left.
Future<ScreenSetup?> showScreenSetup(
  BuildContext context, {
  required ScreenShareBackend backend,
  required List<ScreenSource> sources,
  required ScreenSettings settings,
  ScreenSource? initialSource,
  bool skipSourceStep = false,
}) => showDialog<ScreenSetup>(
  context: context,
  builder: (context) => _SetupDialog(
    backend: backend,
    sources: sources,
    settings: settings,
    initialSource: initialSource,
    skipSourceStep: skipSourceStep,
  ),
);

class _SetupDialog extends StatefulWidget {
  const _SetupDialog({
    required this.backend,
    required this.sources,
    required this.settings,
    this.initialSource,
    this.skipSourceStep = false,
  });

  final ScreenShareBackend backend;
  final List<ScreenSource> sources;
  final ScreenSettings settings;
  final ScreenSource? initialSource;
  final bool skipSourceStep;

  @override
  State<_SetupDialog> createState() => _SetupDialogState();
}

class _SetupDialogState extends State<_SetupDialog> {
  late var _onSettings = widget.skipSourceStep;

  /// The settings as edited so far. Held here and written only when the share
  /// actually starts: a page someone opened, changed their mind on and closed
  /// should not leave tomorrow's share at 360p because of a click.
  late var _settings = widget.settings;

  late ScreenSource? _source = widget.initialSource;

  /// Which tab is showing. Owned here rather than by the step because the tab
  /// is what decides which captures are open.
  late var _kind = _firstKind();

  // Native capture requests cannot be cancelled. Close late results before
  // opening another source, including when leaving the dialog.
  final _previews = <String, ScreenMedia>{};
  Future<void> _previewWork = Future<void>.value();
  var _pass = 0;
  var _finishing = false;

  bool get _canContinue => _source != null || widget.sources.isEmpty;

  List<ScreenSource> _of(ScreenSourceKind kind) => [
    for (final source in widget.sources)
      if (source.kind == kind) source,
  ];

  ScreenSourceKind _firstKind() {
    for (final kind in sourceTabOrder) {
      if (_of(kind).isNotEmpty) return kind;
    }
    return ScreenSourceKind.screen;
  }

  @override
  void dispose() {
    _queuePreview(null);
    super.dispose();
  }

  Future<void> _closePreviews() async {
    final open = _previews.values.toList();
    _previews.clear();
    for (final media in open) {
      try {
        await media.close();
      } catch (_) {
        // One failed native release must not prevent releasing other media.
      }
    }
  }

  void _queuePreview(ScreenSource? source) {
    final pass = ++_pass;
    _previewWork = _previewWork.then((_) async {
      await _closePreviews();
      if (!mounted || pass != _pass || source == null) return;
      setState(() {});
      if (source.thumbnail?.isNotEmpty == true) return;
      try {
        final media = await widget.backend.preview(source);
        if (!mounted || pass != _pass) {
          await media.close();
          return;
        }
        setState(() => _previews[source.id] = media);
      } catch (_) {
        // An unavailable preview must not prevent sharing the source.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: _onSettings
                  ? SettingsStep(
                      settings: _settings,
                      source: _source?.kind ?? ScreenSourceKind.screen,
                      onChanged: (next) => setState(() => _settings = next),
                    )
                  : SourceStep(
                      sources: widget.sources,
                      previews: _previews,
                      kind: _kind,
                      selected: _source,
                      onKind: (kind) {
                        setState(() {
                          _kind = kind;
                          _source = null;
                        });
                        _queuePreview(null);
                      },
                      onSelected: (source) {
                        setState(() => _source = source);
                        _queuePreview(source);
                      },
                      onPreview: previewSelected,
                    ),
            ),
            Divider(height: 1, color: tokens.borderSubtle),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_onSettings)
                    TextButton(
                      onPressed: _finishing ? null : _toSource,
                      child: Text(l10n.screenSetupBack),
                    )
                  else
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.cancelButton),
                    ),
                  const Spacer(),
                  FilledButton(
                    // Refused rather than silent while nothing is picked: the
                    // next step is about a source that is not chosen yet.
                    onPressed: !_canContinue || _finishing
                        ? null
                        : () => _onSettings ? _goLive(context) : _toSettings(),
                    child: Text(
                      _onSettings
                          ? l10n.screenSetupGoLive
                          : l10n.screenSetupNext,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void previewSelected() => _queuePreview(_source);

  void _toSettings() {
    _queuePreview(null);
    setState(() => _onSettings = true);
  }

  void _toSource() {
    setState(() => _onSettings = false);
    _queuePreview(_source);
  }

  Future<void> _goLive(BuildContext context) async {
    if (_finishing) return;
    setState(() => _finishing = true);
    _queuePreview(null);
    await _previewWork;
    if (!context.mounted) return;
    Navigator.of(context)
        .pop(ScreenSetup(source: _source, settings: _settings));
  }
}
