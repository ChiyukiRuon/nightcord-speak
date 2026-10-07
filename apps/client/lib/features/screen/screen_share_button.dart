// Our own screen share: the control that starts and stops it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/screen/screen_controller.dart';
import '../../core/screen/screen_providers.dart';
import '../../core/screen/screen_share_backend.dart';
import '../../design/components/voice_bar_button.dart';
import '../../l10n/app_localizations.dart';
import '../../models/screen_options.dart';
import '../../models/settings.dart';
import 'setup/screen_setup.dart';
import '../../providers/providers.dart';
import 'viewers.dart';

/// Starts and stops our own screen share.
///
/// It stands in the voice bar rather than in a strip of its own above the chat:
/// starting a share is something *we* do to the server, like going away or
/// muting the microphone, and that is what the bar is for. What other people
/// share is a fact about *them*, so the way in is on their row in the member
/// list — see `channel_sidebar.dart`.
///
/// The whole control is absent on a protocol that cannot carry screen sharing,
/// rather than present and disabled: a button that can never work is a promise
/// the server never made (§15).
class ScreenShareButton extends ConsumerStatefulWidget {
  const ScreenShareButton({required this.session, super.key});

  final int session;

  @override
  ConsumerState<ScreenShareButton> createState() => _ScreenShareButtonState();
}

class _ScreenShareButtonState extends ConsumerState<ScreenShareButton> {
  ScreenController? _controller;

  /// The error already shown, so a controller that notifies again about the
  /// same failure does not stack SnackBars.
  String? _reported;

  /// Watches the controller for failures.
  ///
  /// The controller is a plain `ChangeNotifier` rather than a Riverpod notifier
  /// — it holds WebRTC objects, not just state — so this is a listener rather
  /// than `ref.listen`.
  void _follow(ScreenController controller) {
    if (identical(_controller, controller)) return;
    _controller?.removeListener(_onChanged);
    _controller = controller;
    controller.addListener(_onChanged);
  }

  void _onChanged() {
    final error = _controller?.error;
    if (error == null) {
      // Cleared on the next attempt, which is what makes the same failure
      // reportable twice.
      _reported = null;
      return;
    }
    if (error == _reported) return;
    _reported = error;

    // Deferred: the controller notifies from inside the session provider's own
    // rebuild when the connection changes, and a SnackBar cannot be shown
    // during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final message = switch (error) {
        'capture' => l10n.screenCaptureFailed,
        'refused' => l10n.screenRefused,
        'timeout' => l10n.screenTimeout,
        _ => l10n.screenConnectionFailed,
      };
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.watch(screenControllerProvider(widget.session));
    _follow(controller);

    final view = ref.watch(sessionsProvider)[widget.session];
    final online = view?.isConnected ?? false;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // Read inside the builder, not above it: `controller.active` is what
        // the button *shows*, and a captured copy would keep drawing the old
        // face until something else rebuilt the bar.
        final sharing = controller.active;
        return VoiceBarButton(
          // The glyph the member row and the floating window both wear for this
          // fact, so all three read as one thing.
          icon: sharing ? Icons.stop_screen_share : Icons.screen_share_outlined,
          tooltip: sharing ? '${l10n.screenStop} · ${viewerCount(l10n, controller)}' : l10n.screenStart,
          active: sharing,
          enabled: online,
          // One button, two verbs, for the same reason the microphone has one:
          // there is nothing to decide between them, and the state is on
          // screen.
          onPressed: () => sharing ? controller.stop() : _start(controller, l10n),
        );
      },
    );
  }

  /// Asks what to share and how, then starts publishing it.
  ///
  /// The dialog only runs where there is something to ask: a browser hands its
  /// own picker out of `getDisplayMedia`, and mobile has no capture at all, so
  /// an empty source list means "just ask the platform" and the first step
  /// shows nothing but a Next button.
  Future<void> _start(ScreenController controller, AppLocalizations l10n) async {
    try {
      final sources = await controller.backend.sources();
      if (!mounted) return;

      final settings = ref.read(settingsProvider)?.screen ?? const ScreenSettings();
      final setup = await showScreenSetup(
        context,
        backend: controller.backend,
        sources: sources,
        settings: settings,
      );
      if (setup == null || !mounted) return;

      // Written now rather than as the dialog was edited: someone who set a
      // share up and backed out changed nothing, and tomorrow's share should
      // not start at 360p because of a click they cancelled.
      final chosen = setup.settings;
      if (chosen != settings) {
        final current = ref.read(settingsProvider);
        if (current != null) {
          ref.read(settingsProvider.notifier).update(current.copyWith(screen: chosen));
        }
      }

      await controller.start(setup.source, l10n.screenTitle, _options(chosen, setup.source));
    } catch (_) {
      // Anything thrown before `start` — a denied capture permission, a picker
      // that never opened — is the same failure to the user as one thrown
      // inside it.
      controller.fail('capture');
    }
  }

  /// The settings, as the share that is about to start.
  ///
  /// `detail` is worked out from the numbers rather than stored: which preset
  /// they are decides how the encoder gives way when it runs out of room, and a
  /// hand-edited set matches none of them — which is "custom", and gets the
  /// movement default. Storing the choice as well would let the name and the
  /// numbers disagree.
  ScreenOptions _options(ScreenSettings screen, ScreenSource? source) {
    final preset = ScreenPreset.matching(screen.height, screen.fps, screen.videoBitrateKbps);
    return ScreenOptions(
      source: source?.kind ?? ScreenSourceKind.screen,
      height: screen.height,
      fps: screen.fps,
      videoBitrateKbps: screen.videoBitrateKbps,
      audio: screen.audio,
      audioBitrateKbps: screen.audioBitrateKbps,
      access: screen.access,
      viewerLimit: screen.viewerLimit,
      mode: screen.mode,
      detail: preset?.detail ?? false,
    );
  }
}
