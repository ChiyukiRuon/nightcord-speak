// The microphone gain panel that appears when the pointer rests on the voice
// bar's microphone button.
//
// A flyout rather than a second dialog: adjusting how loud you are is something
// people do mid-sentence, and a modal would put a scrim over the conversation.
// It is deliberately the *same* value the settings page edits, down to the
// stored field — two controls, one truth, and the curve they draw comes from
// `util/gain.dart` so they cannot disagree about where a value sits.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/providers.dart';
import '../../util/gain.dart';

/// How long the pointer may be away before the panel closes.
///
/// Long enough to cross the gap between the button and the panel, short enough
/// that it is gone by the time the pointer has settled somewhere else.
const Duration _hideDelay = Duration(milliseconds: 250);

/// The gap between the button and the panel, in logical pixels.
const double _gap = 8;

/// How wide the panel is: the value at the top, and nothing else.
///
/// No label — the panel is on the microphone button, which is what says what it
/// adjusts, and a word there only made the panel wide enough to cover its
/// neighbours. Wide enough for the longest reading it can show, `+10 dB`.
const double _panelWidth = 72;

/// How tall the slider's travel is.
///
/// The travel is the length of the slide, and a vertical one is only as long as
/// it is drawn: a thumb dragged in a 60-pixel slot lands on the wrong decibel.
/// A panel hanging off the bottom edge has the whole window to grow into.
const double _slideLength = 208;

/// How thick the slider is across its travel — Material's touch target.
const double _slideThickness = 48;

/// Wraps [child] so that hovering it shows the microphone gain above it.
class MicGainFlyout extends ConsumerStatefulWidget {
  /// Shows the gain panel while the pointer is on [child].
  const MicGainFlyout({required this.child, super.key});

  /// The button the panel belongs to.
  final Widget child;

  @override
  ConsumerState<MicGainFlyout> createState() => _MicGainFlyoutState();
}

class _MicGainFlyoutState extends ConsumerState<MicGainFlyout> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  Timer? _hide;

  /// How many of the two regions the pointer is inside.
  ///
  /// A count rather than a flag: moving from the button into the panel leaves
  /// one region and enters the other in the same frame, and the order they
  /// arrive in depends on the hit test, not on the user.
  int _hovered = 0;

  /// True while a slider drag is in flight, wherever the pointer has got to.
  bool _dragging = false;

  /// The value the slider is showing mid-drag, in decibels.
  ///
  /// Kept here rather than written straight to the settings so a drag does not
  /// write the file on every pixel — the same reason the settings page keeps
  /// one.
  double? _dragDb;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _enter() {
    _hovered++;
    _hide?.cancel();
    if (!_portal.isShowing) _portal.show();
  }

  void _exit() {
    _hovered = (_hovered - 1).clamp(0, 2);
    _scheduleHide();
  }

  void _scheduleHide() {
    if (_dragging) return;
    _hide?.cancel();
    _hide = Timer(_hideDelay, () {
      if (mounted && _hovered == 0) _portal.hide();
    });
  }

  void _write(double db) {
    final settings = ref.read(settingsProvider);
    if (settings == null) return;
    ref
        .read(settingsProvider.notifier)
        .update(settings.copyWith(audio: settings.audio.copyWith(inputGainDb: db)));
  }

  @override
  Widget build(BuildContext context) {
    // Watched, not read: a change made on the settings page has to move this
    // slider, and the reverse travels through the same notifier.
    final stored = ref.watch(settingsProvider)?.audio.inputGainDb ?? 0.0;
    final value = _dragDb ?? stored;

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => _anchor(context, value),
      child: CompositedTransformTarget(
        link: _link,
        child: MouseRegion(
          onEnter: (_) => _enter(),
          onExit: (_) => _exit(),
          child: widget.child,
        ),
      ),
    );
  }

  /// Places the panel above the button, hit-testable only where it is drawn.
  ///
  /// The follower's box is the whole overlay — `RenderFollowerLayer` is a proxy
  /// box, and the overlay lays its children out with tight constraints — so the
  /// anchors are applied to that box and the panel is aligned inside it: the
  /// box's bottom-centre lands on the button's top-centre, and `Align` sits the
  /// panel on that point. The empty rest of the box takes no hits, because
  /// neither `RenderProxyBox` nor `RenderPositionedBox` claims them.
  Widget _anchor(BuildContext context, double db) {
    return CompositedTransformFollower(
      link: _link,
      targetAnchor: Alignment.topCenter,
      followerAnchor: Alignment.bottomCenter,
      offset: const Offset(0, -_gap),
      showWhenUnlinked: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: MouseRegion(
          onEnter: (_) => _enter(),
          onExit: (_) => _exit(),
          child: _panel(context, db),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context, double db) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final text = Theme.of(context).textTheme;

    return Container(
      width: _panelWidth,
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space2,
        vertical: tokens.space2,
      ),
      // §15's level 2 — "dropdowns and popups" — and the same surface the
      // context menus use, so a floating panel looks like one thing.
      decoration: BoxDecoration(
        color: tokens.bgDeep,
        border: Border.all(color: tokens.borderDefault),
        borderRadius: AppRadius.mdAll,
        boxShadow: tokens.shadow2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The reading, and only the reading: what the slider does is written
          // on the button it hangs from.
          Text(
            formatGainDb(db, silentLabel: l10n.settingsMicGainSilent),
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: tokens.textSecondary),
          ),
          SizedBox(height: tokens.space2),
          // Vertical, because the panel hangs above a button on the bottom
          // edge: the travel grows upwards, where there is room, instead of
          // sideways, where the conversation is. `Slider` has no vertical
          // mode, so the rotation is the whole trick — `quarterTurns: 3` is
          // the direction that leaves silence at the bottom, since the value
          // it starts from (left) ends up there.
          SizedBox(
            width: _slideThickness,
            height: _slideLength,
            child: RotatedBox(
              quarterTurns: 3,
              child: Slider(
                value: gainDbToSlider(db).clamp(0.0, 1.0),
                onChangeStart: (_) => setState(() => _dragging = true),
                onChanged: (position) => setState(() => _dragDb = gainSliderToDb(position)),
                onChangeEnd: (position) {
                  final db = gainSliderToDb(position);
                  setState(() {
                    _dragging = false;
                    _dragDb = null;
                  });
                  _write(db);
                  // The pointer may have left while the drag was holding the
                  // panel open; if it did, the panel goes now.
                  _scheduleHide();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
