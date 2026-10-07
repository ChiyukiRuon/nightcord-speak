// The floating window a screen share plays in.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/screen/screen_providers.dart';
import '../../core/screen/screen_share_backend.dart';
import '../../core/platform/services.dart';
import '../../design/theme/app_theme.dart';
import '../../state/server_view.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/providers.dart';
import 'detached/detached_screen.dart';
import 'detached/screen_window.dart';
import 'viewers.dart';

/// The window's width. Everything else follows from it.
const double _width = 320;

/// The title strip. §33's "toolbar icon area" starts at 32, which is the only
/// size the two controls in it can have without growing the window.
const double _headerHeight = 32;

/// Video height at 16:9, which is what a shared screen almost always is.
const double _videoHeight = _width * 9 / 16;

/// How tall the window is, for anything that has to clear it.
const double screenPipHeight = _headerHeight + _videoHeight;

/// The share on screen, floating over the conversation.
///
/// It floats rather than taking a band off the top of the chat because a share
/// is something to watch *while* talking about it: a strip above the messages
/// pushes them down and out of the window exactly when they matter most. It
/// draws only when there is something to draw, so every server without screen
/// sharing — and every session in which nobody is — looks exactly as it did.
///
/// It has to be a direct child of a `Stack`, and [bounds] has to be that
/// stack's size: the window is dragged around the conversation area and has to
/// know where the edges are.
class ScreenPip extends ConsumerStatefulWidget {
  const ScreenPip({required this.view, required this.bounds, super.key});

  /// The session it belongs to, and where the names live.
  final ServerView view;

  /// The area the window may be dragged within.
  final Size bounds;

  @override
  ConsumerState<ScreenPip> createState() => _ScreenPipState();
}

class _ScreenPipState extends ConsumerState<ScreenPip> {
  /// Where the user dragged it, or null while it still sits in the corner.
  /// Kept across shares on purpose: someone who moved it out of the way meant
  /// it, and putting it back for the next one would be undoing their work.
  Offset? _at;

  /// The media the user closed the window on.
  ///
  /// Compared by identity, so the next share — which is always a new media
  /// object — opens a window again without anything having to reset a flag.
  ScreenMedia? _dismissed;
  bool _detaching = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.watch(screenControllerProvider(widget.view.session));

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // Remote first: publishing and watching at once is allowed, and what
        // the user went out of their way to open is the other person.
        final media = controller.remote ?? controller.preview;
        if (media == null || identical(_dismissed, media)) {
          return const SizedBox.shrink();
        }
        final watching = controller.remote != null;

        final size = const Size(_width, screenPipHeight);
        final at = _clamp(_at ?? _corner(size), size);

        // The person's name rather than the stream's: a stream is called
        // whatever its publisher typed, and two people on one server can type
        // the same thing.
        final client = watching
            ? controller.watchingClient
            : widget.view.ownClientId;

        return Positioned(
          left: at.dx,
          top: at.dy,
          child: _Window(
            title: widget.view.clients[client]?.name ?? l10n.screenTitle,
            media: media,
            // A stream that has not arrived yet still gets a window: the
            // negotiation takes a moment, and an empty frame is what
            // "connecting" looks like in the meantime.
            connecting: watching && controller.watchPending,
            viewers: controller.publishing == null
                ? null
                : viewerCount(l10n, controller),
            // What we are actually sending, which is the only place the
            // publisher's own numbers are visible. The viewer count answers
            // "is anyone watching"; this answers "is it any good".
            rate: controller.publishing == null ? null : controller.rate,
            dismissTooltip: watching
                ? l10n.screenLeave
                : l10n.screenHidePreview,
            // Offered only where there is a second window to open and a stream
            // this one is taking itself: a detached window opens its own peer
            // connection, so leaving this one watching would deliver the same
            // picture twice.
            onDetach: watching && detachedWindowsAvailable && !_detaching
                ? _detach
                : null,
            onDrag: _drag,
            onDismiss: () {
              if (watching) {
                // Closing the window is the only way to stop watching: the
                // connection exists to feed it, and leaving it running with
                // nowhere to draw would be a leak with no visible symptom.
                unawaited(controller.leave());
              } else {
                setState(() => _dismissed = media);
              }
            },
          ),
        );
      },
    );
  }

  /// Bottom right, a margin in from both edges — or the top left when the area
  /// has no usable size, because "bottom right" of nothing is off the screen.
  Offset _corner(Size size) {
    final bounds = widget.bounds;
    if (!bounds.width.isFinite || !bounds.height.isFinite) return Offset.zero;
    return Offset(
      _nonNegative(bounds.width - size.width - AppSpacing.space4),
      _nonNegative(bounds.height - size.height - AppSpacing.space4),
    );
  }

  double _nonNegative(double value) => value > 0 ? value : 0;

  /// Hands the picture to a window of its own.
  ///
  /// The detached window owns its own media — an engine cannot use another
  /// engine's textures — so this is not a move but a handover: the new window
  /// joins the stream after this one releases the server's viewer entry.
  Future<void> _detach() async {
    if (_detaching) return;
    final controller = ref.read(screenControllerProvider(widget.view.session));
    final client = controller.watchingClient;
    if (client == null) return;
    // Leaving removes this widget; capture dependencies before that rebuild.
    final transport = ref.read(clientTransportProvider);
    final session = widget.view.session;
    final title =
        widget.view.clients[client]?.name ??
        AppLocalizations.of(context).screenTitle;
    setState(() => _detaching = true);
    try {
      await controller.transferWatch(
        (client) => openDetachedScreen(
          transport: transport,
          session: session,
          onReturn: () async {
            if (!controller.disposed && controller.connected) {
              await controller.watch(client);
            }
          },
          args: ScreenWindowArgs(
            session: session,
            clientId: client,
            title: title,
          ),
        ),
      );
    } catch (error, stack) {
      logToCore('error', 'screen: detach failed: $error\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).screenConnectionFailed),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _detaching = false);
    }
  }

  /// Moves the window by one pointer step.
  ///
  /// The arithmetic lives here rather than in a closure, because this is where
  /// the numbers behind "it will not drag" can be written down: what the
  /// pointer moved, what the window thought its position was, what it became,
  /// and which `State` did the thinking. A window that keeps its `_at` and
  /// still does not move, and a window whose `_at` is thrown away every frame,
  /// look exactly alike from the outside and need opposite fixes.
  void _drag(Offset delta, {required bool first}) {
    final size = const Size(_width, screenPipHeight);
    final before = _clamp(_at ?? _corner(size), size);
    final after = _clamp(before + delta, size);
    if (first) {
      logToCore(
        'info',
        'screen: dragged by $delta on state=$hashCode '
            'bounds=${widget.bounds} $before -> $after',
      );
    }
    setState(() => _at = after);
  }

  /// Keeps the whole window inside [widget.bounds].
  ///
  /// Clamped on the way *out* and not only while dragging: a window that is
  /// under the pointer when the area shrinks would otherwise keep a position
  /// outside the new bounds, and the next drag would jump.
  ///
  /// Both degenerate cases let the window move rather than pinning it. `clamp`
  /// asserts its limits are ordered, so the room was written as
  /// `(extent - size).clamp(0, infinity)` — and when the area is smaller than
  /// the window that collapses to `0`, which clamps *every* position to zero:
  /// the window sits still, the pointer arrives, and nothing anywhere says
  /// why. An area with no room is not an instruction to stay put; there is
  /// simply nothing to hold it in.
  Offset _clamp(Offset at, Size size) => Offset(
    _within(at.dx, widget.bounds.width - size.width),
    _within(at.dy, widget.bounds.height - size.height),
  );

  /// [value] held inside `[0, room]`, or left alone when there is no room to
  /// speak of — including an area that never got a real size.
  double _within(double value, double room) =>
      room.isFinite && room > 0 ? value.clamp(0, room) : value;
}

class _Window extends StatelessWidget {
  const _Window({
    required this.title,
    required this.media,
    required this.connecting,
    required this.viewers,
    required this.rate,
    required this.dismissTooltip,
    required this.onDetach,
    required this.onDrag,
    required this.onDismiss,
  });

  final String title;
  final ScreenMedia media;
  final bool connecting;

  /// The viewer count as it should be written, or null while not publishing.
  final String? viewers;
  final ScreenStats? rate;
  final String dismissTooltip;

  /// Hands the picture to a window of its own, where the platform has one.
  final VoidCallback? onDetach;
  final void Function(Offset delta, {required bool first}) onDrag;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final text = Theme.of(context).textTheme;

    return Material(
      color: tokens.bgElevated,
      elevation: 8,
      borderRadius: AppRadius.lgAll,
      clipBehavior: Clip.antiAlias,
      // The whole window drags, picture included — not just the title strip.
      // A 320px rectangle whose only grabbable part is 32px of chrome reads as
      // broken when the other 180 are the thing the pointer is actually over
      // and the one a hand reaches for.
      child: _DragArea(
        onDrag: onDrag,
        child: SizedBox(
          width: _width,
          height: screenPipHeight,
          child: Column(
            children: [
              SizedBox(
                height: _headerHeight,
                child: Row(
                  children: [
                    SizedBox(width: AppSpacing.space3),
                    // The same glyph and colour the member row uses for the
                    // same fact, so the two read as one thing.
                    Icon(Icons.screen_share, size: 14, color: tokens.online),
                    SizedBox(width: AppSpacing.space2),
                    Expanded(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                    if (rate case final reading?)
                      Padding(
                        padding: const EdgeInsets.only(
                          right: AppSpacing.space2,
                        ),
                        child: Text(
                          // Resolution and frames per second, and what is
                          // holding them back when it is not the machine's own
                          // indifference — a share that has been scaled down to
                          // fit a thin link should say so rather than just look
                          // soft.
                          '${reading.width}×${reading.height} · '
                          '${reading.fps.round()}fps'
                          '${reading.limitedBy == null || reading.limitedBy == 'none' ? '' : ' · ${reading.limitedBy}'}',
                          style: text.bodySmall?.copyWith(
                            color:
                                reading.limitedBy == null ||
                                    reading.limitedBy == 'none'
                                ? tokens.textSecondary
                                : tokens.warning,
                          ),
                        ),
                      ),
                    if (viewers case final label?)
                      Padding(
                        padding: const EdgeInsets.only(
                          right: AppSpacing.space1,
                        ),
                        child: Text(
                          label,
                          style: text.bodySmall?.copyWith(
                            color: tokens.textSecondary,
                          ),
                        ),
                      ),
                    if (onDetach case final detach?)
                      _HeaderButton(
                        icon: Icons.open_in_new,
                        tooltip: l10n.screenPopOut,
                        onPressed: detach,
                      ),
                    _HeaderButton(
                      icon: Icons.fullscreen,
                      tooltip: l10n.screenFullscreen,
                      onPressed: () => _fullscreen(context),
                    ),
                    _HeaderButton(
                      icon: Icons.close,
                      tooltip: dismissTooltip,
                      onPressed: onDismiss,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ColoredBox(
                  color: tokens.bgDeep,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Keyed on the media: switching between two shares has
                      // to rebuild the platform view rather than re-point the
                      // one that is already attached to the old stream.
                      KeyedSubtree(key: ObjectKey(media), child: media.view()),
                      if (connecting)
                        Center(
                          child: Text(
                            l10n.screenConnecting,
                            style: text.bodySmall?.copyWith(
                              color: tokens.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The same picture, as large as the display allows.
  ///
  /// A dialog rather than a route: closing it has to leave the conversation
  /// exactly as it was, and this is something you glance out of the page for,
  /// not somewhere you travel to.
  void _fullscreen(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.black,
              child: KeyedSubtree(key: ObjectKey(media), child: media.view()),
            ),
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.space4),
                child: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.fullscreenExit,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Moves the window with the pointer, without asking a gesture for permission.
///
/// This is a `Listener` and not a `GestureDetector`, and that is the whole
/// point. A pan gesture has to win a gesture arena and clear a slop before it
/// reports anything, and when either of those goes wrong the symptom is
/// indistinguishable from "the window is not receiving the pointer at all" —
/// which is exactly the report that took two rounds to chase. A `Listener`
/// sees every move the window is handed, so the two stop looking alike; the
/// log line below says which one it was.
///
/// The two buttons keep their taps: a `Listener` does not compete in the arena,
/// so nothing is taken from them.
class _DragArea extends StatefulWidget {
  const _DragArea({required this.onDrag, required this.child});

  final void Function(Offset delta, {required bool first}) onDrag;
  final Widget child;

  @override
  State<_DragArea> createState() => _DragAreaState();
}

class _DragAreaState extends State<_DragArea> {
  /// Reset on every press, so the line below is one per drag rather than one
  /// per pointer event.
  bool _moved = false;

  @override
  Widget build(BuildContext context) => Listener(
    // Opaque rather than the default `deferToChild`: a `Row` only hit-tests
    // where its children are, so the gaps between the title, the readout and
    // the buttons were gaps you could not grab.
    behavior: HitTestBehavior.opaque,
    onPointerDown: (_) => _moved = false,
    // Only fires with a button held — hover arrives as its own event — so this
    // does not need to ask whether a drag is in progress.
    onPointerMove: (event) {
      _moved = true;
      widget.onDrag(event.delta, first: !_moved);
    },
    child: widget.child,
  );
}

/// One control in the window's title strip.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon),
    iconSize: 16,
    tooltip: tooltip,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(
      width: _headerHeight,
      height: _headerHeight,
    ),
    color: DesignTokens.of(context).textSecondary,
    onPressed: onPressed,
  );
}
