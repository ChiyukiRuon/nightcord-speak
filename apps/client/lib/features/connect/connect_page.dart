// The screen shown before anything is connected.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/rust_client.dart';
import '../../models/domain.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';

/// Collects a server address and nickname and opens a connection.
class ConnectPage extends ConsumerStatefulWidget {
  /// Builds the page.
  const ConnectPage({super.key});

  @override
  ConsumerState<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends ConsumerState<ConnectPage> {
  final _address = TextEditingController();
  final _nickname = TextEditingController(text: 'Nightcord User');
  final _password = TextEditingController();

  /// Set while a connect is in flight, so the button cannot be pressed twice.
  bool _connecting = false;

  ProtocolKind _protocol = ProtocolKind.ts3;

  @override
  void initState() {
    super.initState();
    // Ask for the settings, and fill the nickname in when they arrive. The field
    // starts with the same fallback the settings default to, so the page looks
    // the same whether the answer comes back before or after the first frame.
    ref.read(rustClientProvider).requestSettings();
    ref.listenManual(settingsProvider, (_, settings) {
      if (settings == null || !mounted) return;
      // Not while the user is typing: overwriting a half-written nickname with
      // the stored one would be a fine way to lose their edit.
      if (_nickname.text == _initialNickname) {
        _nickname.text = settings.connection.nickname;
      }
    });
  }

  /// What the nickname field held before any settings arrived.
  late final String _initialNickname = _nickname.text;

  @override
  void dispose() {
    _address.dispose();
    _nickname.dispose();
    _password.dispose();
    super.dispose();
  }

  void _connect() {
    final address = _address.text.trim();
    if (address.isEmpty) return;

    // The identity profile comes from the settings — there is no field for it
    // here, and it is what decides which client the server sees you as. Before
    // the settings arrive, the request's own default applies, which is the same
    // value.
    final profile = ref.read(settingsProvider)?.connection.profile ?? 'default';

    setState(() => _connecting = true);
    ref.read(rustClientProvider).connect(
      ConnectRequest(
        address: address,
        nickname: _nickname.text.trim(),
        serverPassword: _password.text.isEmpty ? null : _password.text,
        protocol: _protocol,
        profile: profile,
      ),
    );
    // Deliberately not awaited. The core answers on its own thread and the
    // store is what reacts to the result: on success the shell switches to the
    // server, and on failure the listener below re-enables the button. Nothing
    // here needs to know which happened.
  }

  @override
  Widget build(BuildContext context) {
    // A failure ends the attempt, so the button becomes usable again. A
    // timeout would be the wrong signal — it cannot tell "slow server" from
    // "wrong password" — and this is exact.
    ref.listen(lastErrorProvider, (_, error) {
      if (error != null && _connecting && mounted) {
        setState(() => _connecting = false);
      }
    });

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.bubble_chart, color: AppColors.accent, size: 32),
                    SizedBox(width: 12),
                    Text(
                      'Nightcord Speak',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                TextField(
                  controller: _address,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'example.com 或 192.168.1.10:9987',
                  ),
                  onSubmitted: (_) => _connect(),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _nickname,
                  decoration: const InputDecoration(labelText: '昵称'),
                  onSubmitted: (_) => _connect(),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '服务器密码',
                    hintText: '没有就留空',
                  ),
                  onSubmitted: (_) => _connect(),
                ),
                const SizedBox(height: 20),

                // The protocol is a choice rather than a guess: detection during
                // the handshake is on the roadmap, and until then picking the
                // wrong one should be the user's explicit mistake rather than a
                // silent default (§34).
                SegmentedButton<ProtocolKind>(
                  segments: const [
                    ButtonSegment(value: ProtocolKind.ts3, label: Text('TeamSpeak 3')),
                    ButtonSegment(
                      value: ProtocolKind.ts6,
                      label: Text('TeamSpeak 6'),
                      enabled: false,
                    ),
                  ],
                  selected: {_protocol},
                  onSelectionChanged: (selection) =>
                      setState(() => _protocol = selection.first),
                ),
                if (_protocol == ProtocolKind.ts6)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'TS6 后端尚未实现（Milestone 0.4）',
                      style: TextStyle(color: AppColors.idle, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 24),

                FilledButton(
                  onPressed: _connecting ? null : _connect,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _connecting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('连接'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
