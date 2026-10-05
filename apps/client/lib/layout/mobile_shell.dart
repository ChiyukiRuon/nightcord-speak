import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../models/domain.dart';
import '../l10n/app_localizations.dart';

/// Navigation is the root page; details are a separate step with a way back.
class MobileShell extends StatelessWidget {
  const MobileShell({
    required this.navigation,
    required this.content,
    required this.title,
    this.footer,
    this.banner,
    this.actions,
    required this.showingDetail,
    required this.onBack,
    super.key,
  });
  final Widget navigation;
  final Widget content;
  final Widget? footer;
  final Widget? banner;
  final String title;
  final List<Widget>? actions;
  final bool showingDetail;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !showingDetail,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && showingDetail) onBack();
    },
    child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !showingDetail,
        leading: showingDetail ? BackButton(onPressed: onBack) : null,
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: actions,
      ),
      bottomNavigationBar: footer == null
          ? null
          : SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [const _TouchPushToTalk(), footer!],
              ),
            ),
      body: Column(
        children: [
          ?banner,
          Expanded(child: showingDetail ? content : navigation),
        ],
      ),
    ),
  );
}

/// PTT cannot depend on a physical keyboard on a phone.
class _TouchPushToTalk extends ConsumerStatefulWidget {
  const _TouchPushToTalk();
  @override
  ConsumerState<_TouchPushToTalk> createState() => _TouchPushToTalkState();
}

class _TouchPushToTalkState extends ConsumerState<_TouchPushToTalk> with WidgetsBindingObserver {
  bool _held = false;
  int? _pointer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual(settingsProvider, (_, settings) {
      if (settings?.audio.mode != VoiceActivationMode.pushToTalk) _release();
    });
    ref.listenManual(activeViewProvider, (_, view) {
      if (!(view?.isConnected ?? false)) _release();
    });
  }

  void _set(bool held) {
    if (_held == held) return;
    _held = held;
    ref.read(clientTransportProvider).setPushToTalk(held);
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _release();
  }

  void _release() {
    _pointer = null;
    _set(false);
  }

  void _down(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _set(true);
  }

  void _up(PointerEvent event) {
    if (event.pointer == _pointer) _release();
  }

  @override
  void dispose() {
    if (_held) ref.read(clientTransportProvider).setPushToTalk(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final view = ref.watch(activeViewProvider);
    if (settings?.audio.mode != VoiceActivationMode.pushToTalk || !(view?.isConnected ?? false)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Semantics(
        button: true,
        excludeSemantics: true,
        label: AppLocalizations.of(context).voiceHoldToTalk,
        child: Listener(
          onPointerDown: _down,
          onPointerUp: _up,
          onPointerCancel: _up,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _held
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              AppLocalizations.of(context).voiceHoldToTalk,
              style: TextStyle(color: _held ? Theme.of(context).colorScheme.onPrimary : null),
            ),
          ),
        ),
      ),
    );
  }
}
