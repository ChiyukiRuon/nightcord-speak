// The publisher's answer to "may I watch?".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/screen/screen_controller.dart';
import '../../core/screen/screen_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../state/server_view.dart';

/// Asks the publisher about the viewers a private share is holding.
///
/// A public share admits on arrival, so this never appears for one. Private and
/// contacts shares queue every request instead: the server stores the privacy
/// setting and then forwards the request anyway, which makes this side the only
/// gate there is.
///
/// It renders nothing itself — it lives in the page's stack so the dialog can
/// rise over whatever the conversation is doing. Dismissing the dialog answers
/// nothing: the unanswered stay queued and the next arrival raises it again,
/// and a requester who gives up (the viewer side waits about twenty-five
/// seconds) takes their row with them.
class ScreenViewerRequests extends ConsumerStatefulWidget {
  const ScreenViewerRequests({required this.view, super.key});

  /// The session it belongs to, and where the names live.
  final ServerView view;

  @override
  ConsumerState<ScreenViewerRequests> createState() =>
      _ScreenViewerRequestsState();
}

class _ScreenViewerRequestsState extends ConsumerState<ScreenViewerRequests> {
  ScreenController? _controller;

  /// How many were waiting the last time we looked, so that "one arrived" can
  /// be told from "the list changed" — answering a row must not re-open a
  /// dialog the user is already done with.
  int _seen = 0;
  bool _open = false;

  void _follow(ScreenController controller) {
    if (identical(_controller, controller)) return;
    _controller?.removeListener(_onChanged);
    _controller = controller;
    _seen = 0;
    controller.addListener(_onChanged);
    if (controller.pendingViewers.isNotEmpty) {
      // Requests were already waiting before this widget was on screen — a
      // page that was rebuilt, or a session switched back to. Raise the dialog
      // as if one had just arrived.
      WidgetsBinding.instance.addPostFrameCallback((_) => _onChanged());
    }
  }

  void _onChanged() {
    final pending = _controller?.pendingViewers.length ?? 0;
    final arrived = pending > _seen;
    _seen = pending;
    if (!arrived || _open || !mounted) return;
    _open = true;
    showDialog<void>(
      context: context,
      builder: (context) =>
          _RequestDialog(view: widget.view, controller: _controller!),
    ).whenComplete(() => _open = false);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _follow(ref.watch(screenControllerProvider(widget.view.session)));
    return const SizedBox.shrink();
  }
}

class _RequestDialog extends StatelessWidget {
  const _RequestDialog({required this.view, required this.controller});

  final ServerView view;
  final ScreenController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.screenRequestTitle),
      content: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final pending = controller.pendingViewers;
          if (pending.isEmpty) {
            // The last one was answered, or its requester gave up. Either way
            // there is nothing left to ask about.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) Navigator.of(context).pop();
            });
            return const SizedBox.shrink();
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final id in pending)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.screenRequestMessage(
                          view.clients[id]?.name ?? l10n.screenRequestSomeone,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => controller.denyViewer(id),
                      child: Text(l10n.screenRequestDeny),
                    ),
                    FilledButton(
                      onPressed: () => controller.approveViewer(id),
                      child: Text(l10n.screenRequestAllow),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
