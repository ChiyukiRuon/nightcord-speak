// Step two: how to share it.

import 'package:flutter/material.dart';

import '../../../design/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/screen_options.dart';
import '../../../models/settings.dart';
import 'controls.dart';

/// The heights a preset offers, plus "the source's own".
///
/// Zero is the source's own, which is why it is at the end of every list that
/// has it rather than first: it is the option people arrive at after deciding
/// the numbers are all wrong.
const _heights = [360, 480, 720, 1080, 1440, 0];
const _rates = [5, 30, 60];
const _audioRates = [64, 96, 128, 192, 256, 320];

/// Decides everything the server and the encoder will be told.
class SettingsStep extends StatefulWidget {
  const SettingsStep({
    required this.settings,
    required this.source,
    required this.onChanged,
    super.key,
  });

  final ScreenSettings settings;
  final ScreenSourceKind source;
  final ValueChanged<ScreenSettings> onChanged;

  @override
  State<SettingsStep> createState() => _SettingsStepState();
}

class _SettingsStepState extends State<SettingsStep> {
  /// Open by default when the numbers are already someone's own: if a preset
  /// is not carrying them, the controls that are have to be reachable.
  late bool _advanced = _isCustom;

  bool get _isCustom =>
      ScreenPreset.matching(
        widget.settings.height,
        widget.settings.fps,
        widget.settings.videoBitrateKbps,
      ) ==
      null;

  ScreenSettings get _settings => widget.settings;

  void _edit(ScreenSettings next) {
    widget.onChanged(next);
    // Rebuilt from the parent's copy, so the advanced section can open itself
    // the moment an edit makes the numbers stop matching a preset.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final text = Theme.of(context).textTheme;
    final preset = ScreenPreset.matching(
      _settings.height,
      _settings.fps,
      _settings.videoBitrateKbps,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SetupSection(label: l10n.screenSetupBasic),
          SetupRow(
            label: l10n.screenSetupPreset,
            help: l10n.screenSetupHelpPreset,
            control: SetupChoice<ScreenPreset>(
              value: preset,
              options: [
                for (final option in ScreenPreset.all)
                  (option, _presetLabel(l10n, option), true),
              ],
              onChanged: (chosen) => _edit(
                _settings.copyWith(
                  height: chosen.height,
                  fps: chosen.fps,
                  videoBitrateKbps: chosen.bitrateKbps,
                ),
              ),
            ),
          ),
          SetupRow(
            label: l10n.screenSetupCaptureAudio,
            help: l10n.screenSetupHelpCaptureAudio,
            control: Switch(
              value: _settings.audio,
              onChanged: (on) => _edit(_settings.copyWith(audio: on)),
            ),
          ),
          SetupRow(
            label: l10n.screenSetupPrivacy,
            help: l10n.screenSetupHelpPrivacy,
            control: SetupChoice<ScreenAccess>(
              value: _settings.access,
              options: [
                (ScreenAccess.public, l10n.screenSetupPublic, true),
                (ScreenAccess.contacts, l10n.screenSetupContacts, true),
                (ScreenAccess.private, l10n.screenSetupPrivate, true),
              ],
              onChanged: (chosen) => _edit(_settings.copyWith(access: chosen)),
            ),
          ),

          SizedBox(height: tokens.space3),
          // Folded away because most people never open it — and opened for
          // them when the numbers stopped being a preset, since that is the
          // only way to see what they actually are.
          InkWell(
            onTap: () => setState(() => _advanced = !_advanced),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Text(
                    l10n.screenSetupAdvanced,
                    style: text.titleSmall?.copyWith(color: tokens.primary),
                  ),
                  const Spacer(),
                  Icon(
                    _advanced ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: tokens.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_advanced) ...[
            SetupRow(
              label: l10n.screenSetupResolution,
              help: l10n.screenSetupHelpResolution,
              control: SetupChoice<int>(
                value: _settings.height,
                options: [
                  for (final height in _heights)
                    (
                      height,
                      height == 0 ? l10n.screenSetupSource : '$height',
                      true,
                    ),
                ],
                onChanged: (chosen) => _edit(_settings.copyWith(height: chosen)),
              ),
            ),
            SetupRow(
              label: l10n.screenSetupFps,
              help: l10n.screenSetupHelpFps,
              control: SetupChoice<int>(
                value: _settings.fps,
                options: [for (final fps in _rates) (fps, '$fps', true)],
                onChanged: (chosen) => _edit(_settings.copyWith(fps: chosen)),
              ),
            ),
            SetupRow(
              label: l10n.screenSetupVideoBitrate,
              help: l10n.screenSetupHelpVideoBitrate,
              control: SetupStepper(
                text: '${_settings.videoBitrateKbps}',
                unit: l10n.screenSetupKbps,
                canDecrease: _settings.videoBitrateKbps > _bitrateFloor,
                // Stepping by a hundred rather than by one: nobody knows what
                // one kilobit a second looks like, and reaching 4000 a click at
                // a time is not a control, it is a chore.
                onStep: (direction) => _edit(
                  _settings.copyWith(
                    videoBitrateKbps: _settings.videoBitrateKbps + direction * 100,
                  ),
                ),
              ),
            ),
            SetupRow(
              label: l10n.screenSetupAudioBitrate,
              help: l10n.screenSetupHelpAudioBitrate,
              // Greyed rather than hidden while capture audio is off: it is a
              // real setting that is simply not being used, and hiding it would
              // make the page change shape when a switch is flipped.
              control: Opacity(
                opacity: _settings.audio ? 1 : 0.4,
                child: IgnorePointer(
                  ignoring: !_settings.audio,
                  child: SetupChoice<int>(
                    value: _settings.audioBitrateKbps,
                    options: [for (final rate in _audioRates) (rate, '$rate', true)],
                    onChanged: (chosen) => _edit(_settings.copyWith(audioBitrateKbps: chosen)),
                  ),
                ),
              ),
            ),
            SetupRow(
              label: l10n.screenSetupViewerLimit,
              help: l10n.screenSetupHelpViewerLimit,
              control: SetupStepper(
                text: _settings.viewerLimit == 0
                    ? l10n.screenSetupUnlimited
                    : '${_settings.viewerLimit}',
                unit: '',
                canDecrease: _settings.viewerLimit > 0,
                onStep: (direction) => _edit(
                  _settings.copyWith(viewerLimit: _settings.viewerLimit + direction),
                ),
              ),
            ),
            SetupRow(
              label: l10n.screenSetupMode,
              help: l10n.screenSetupHelpMode,
              control: SetupChoice<ScreenMode>(
                value: _settings.mode,
                options: [
                  (ScreenMode.p2p, 'P2P', true),
                  // Refused by the core as well, in `ts-protocol-ts6`. Sending
                  // it would produce a stream that never connects and says
                  // nothing about why, so it is greyed here and rejected there.
                  (ScreenMode.sfu, l10n.screenSetupMode, false),
                ],
                onChanged: (chosen) => _edit(_settings.copyWith(mode: chosen)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// `360`, `源` or `演示` — the numbers speak for themselves; only the two
  /// that are not numbers need a word, and those words are not English.
  static String _presetLabel(AppLocalizations l10n, ScreenPreset preset) {
    if (preset.height > 0) return '${preset.height}';
    return preset.detail ? l10n.screenSetupPresentation : l10n.screenSetupSource;
  }
}

/// The lowest bitrate the stepper will go to.
///
/// Not zero, which the core refuses outright: a stream with no bitrate is not a
/// bad picture, it is no picture.
const _bitrateFloor = 200;
