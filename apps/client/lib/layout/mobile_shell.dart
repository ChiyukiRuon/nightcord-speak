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
    this.navigationTitle,
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
  final String? navigationTitle;
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
      bottomNavigationBar: footer == null
          ? null
          : SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [const _TouchPushToTalk(), footer!],
              ),
            ),
      body: Navigator(
        onDidRemovePage: (page) {
          if (page.key == const ValueKey('detail') && showingDetail) onBack();
        },
        pages: [
          MaterialPage<void>(
            key: const ValueKey('navigation'),
            maintainState: false,
            child: _page(
              title: navigationTitle ?? title,
              body: navigation,
              leading: Navigator.of(context).canPop()
                  ? BackButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : null,
            ),
          ),
          if (showingDetail)
            MaterialPage<void>(
              key: const ValueKey('detail'),
              child: _page(
                title: title,
                body: content,
                leading: BackButton(onPressed: onBack),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _page({
    required String title,
    required Widget body,
    Widget? leading,
  }) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      leading: leading,
      title: Text(title, overflow: TextOverflow.ellipsis),
      actions: actions,
    ),
    body: Column(
      children: [
        ?banner,
        Expanded(child: body),
      ],
    ),
  );
}

/// PTT cannot depend on a physical keyboard on a phone.
class _TouchPushToTalk extends ConsumerStatefulWidget {
  const _TouchPushToTalk();
  @override
  ConsumerState<_TouchPushToTalk> createState() => _TouchPushToTalkState();
}

class _TouchPushToTalkState extends ConsumerState<_TouchPushToTalk>
    with WidgetsBindingObserver {
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
    if (settings?.audio.mode != VoiceActivationMode.pushToTalk ||
        !(view?.isConnected ?? false)) {
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
              style: TextStyle(
                color: _held ? Theme.of(context).colorScheme.onPrimary : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
