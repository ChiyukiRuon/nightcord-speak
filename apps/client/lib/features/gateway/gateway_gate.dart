import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/transport/remote_transport.dart';
import '../../core/transport/gateway_config.dart';
import '../../design/components/app_logo.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/providers.dart';

/// Remote clients authenticate before mounting state that issues core commands.
class GatewayGate extends ConsumerStatefulWidget {
  const GatewayGate({
    required this.child,
    this.config = const GatewayConfig.environment(),
    super.key,
  });
  final Widget child;
  final GatewayConfig config;
  @override
  ConsumerState<GatewayGate> createState() => _GatewayGateState();
}

class _GatewayGateState extends ConsumerState<GatewayGate> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  StreamSubscription<GatewayState>? _subscription;
  Timer? _ticker;
  String? _error;
  bool _connecting = false;
  bool _requiresToken = false;

  @override
  void initState() {
    super.initState();
    final client = ref.read(clientTransportProvider);
    if (client is! RemoteTransport) return;
    _url.text = widget.config.address(Uri.base);
    _token.text = widget.config.token;
    _subscription = client.states.listen((state) {
      if (!mounted) return;
      if (state == GatewayState.disconnected) {
        // A refresh/reconnect gets a fresh gateway snapshot. Never retain stale ids.
        ref.invalidate(sessionsProvider);
        ref.invalidate(activeSessionProvider);
        ref.invalidate(settingsProvider);
        ref.invalidate(bookmarksProvider);
        ref.invalidate(noticesProvider);
      }
      setState(() {
        _error = client.failure == null
            ? null
            : AppLocalizations.of(context).gatewayConnectionFailed;
      });
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && client.state == GatewayState.ready) setState(() {});
    });
    if (widget.config.autoConnect) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_connect(client));
      });
    }
  }

  Future<void> _connect(RemoteTransport client) async {
    final l10n = AppLocalizations.of(context);
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null ||
        !{'ws', 'wss'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        (Uri.base.scheme == 'https' && uri.scheme != 'wss')) {
      setState(() => _error = l10n.gatewayInvalidUrl);
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      await client.openGateway(uri, _token.text);
      _token.clear();
    } catch (_) {
      if (mounted) {
        setState(() {
          _requiresToken =
              client.failure == 'Gateway token required' || widget.config.token.isNotEmpty;
          _error = client.failure == 'Gateway token required'
              ? l10n.gatewayTokenRequired
              : l10n.gatewayConnectionFailed;
        });
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ticker?.cancel();
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(clientTransportProvider);
    if (client is! RemoteTransport) return widget.child;
    final l10n = AppLocalizations.of(context);
    if (_connecting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (client.state == GatewayState.ready) {
      final active = ref.watch(activeSessionProvider);
      final connected =
          active != null && (ref.watch(sessionsProvider)[active]?.isConnected ?? false);
      return Column(
        children: [
          if (connected && client.voice.status['healthy'] != true)
            Material(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(l10n.webAudioHint)),
                      TextButton.icon(
                        onPressed: () => client.voiceStart(active),
                        icon: const Icon(Icons.volume_up_outlined),
                        label: Text(l10n.webEnableAudio),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(child: widget.child),
        ],
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: AppLogo(size: 56)),
                    const SizedBox(height: 24),
                    Text(l10n.gatewayTitle, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    Text(l10n.gatewayDescription),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _url,
                      enabled: !_connecting,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: l10n.gatewayUrlLabel,
                        hintText: 'wss://gateway.example.com/ws',
                      ),
                    ),
                    if (_requiresToken || widget.config.token.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _token,
                        enabled: !_connecting,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(labelText: l10n.gatewayTokenLabel),
                        onSubmitted: (_) {
                          if (!_connecting) unawaited(_connect(client));
                        },
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _connecting ? null : () => _connect(client),
                      child: Text(
                        _connecting ? l10n.connectionStateConnecting : l10n.gatewayConnect,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
