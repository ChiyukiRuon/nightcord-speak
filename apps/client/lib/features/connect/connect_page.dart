// The screen shown before anything is connected.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/rust_client.dart';
import '../../models/bookmarks.dart';
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
    final client = ref.read(rustClientProvider);
    client.requestSettings();
    client.requestBookmarks();
    ref.listenManual(settingsProvider, (_, settings) {
      if (settings == null || !mounted) return;
      // Not while the user is typing, and not after a bookmark filled it in:
      // overwriting what is there with the stored default is a fine way to lose
      // someone's edit.
      if (_nickname.text == _nicknameFromSettings) {
        _nicknameFromSettings = settings.connection.nickname;
        _nickname.text = _nicknameFromSettings;
      }
    });
  }

  /// Fills the form from a saved server.
  ///
  /// Fills rather than connects: the point of this screen is that the details
  /// can still be changed before the connection is made, and a bookmark that
  /// dialled out the moment it was touched would take that away.
  void _fillFrom(Bookmark bookmark) {
    setState(() {
      _address.text = bookmark.address;
      // Remembered as "not from settings" so the settings arriving later do not
      // quietly put the default back.
      _nicknameFromSettings = '';
      _nickname.text = bookmark.nickname ?? '';
      _password.text = bookmark.serverPassword ?? '';
      _protocol = bookmark.protocol;
    });

    // An entry saved without a nickname means "use the default", so the field
    // shows what that currently is — and still counts as untouched.
    if (bookmark.nickname == null) {
      final nickname = ref.read(settingsProvider)?.connection.nickname ?? _nicknameFromSettings;
      setState(() {
        _nicknameFromSettings = nickname;
        _nickname.text = nickname;
      });
    }
  }

  /// Saves what the form currently holds.
  Future<void> _save() async {
    final address = _address.text.trim();
    if (address.isEmpty) return;

    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(initial: address),
    );
    if (name == null || !mounted) return;

    final nickname = _nickname.text.trim();
    ref.read(bookmarksProvider.notifier).add(
      NewBookmark(
        name: name,
        address: address,
        nickname: nickname.isEmpty ? null : nickname,
        protocol: _protocol,
        serverPassword: _password.text.isEmpty ? null : _password.text,
      ),
    );
  }

  /// Renames a saved server, keeping everything else about it.
  Future<void> _rename(int index, Bookmark bookmark) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(initial: bookmark.name),
    );
    if (name == null || !mounted) return;

    final bookmarks = ref.read(bookmarksProvider);
    if (bookmarks == null) return;
    ref
        .read(bookmarksProvider.notifier)
        .update(bookmarks.replaceAt(index, bookmark.copyWith(name: name)));
  }

  void _delete(int index) {
    final bookmarks = ref.read(bookmarksProvider);
    if (bookmarks == null) return;
    ref.read(bookmarksProvider.notifier).update(bookmarks.removeAt(index));
  }

  /// The nickname the settings last put in the field.
  ///
  /// Mutable, unlike the other controllers' starting value: choosing a saved
  /// server replaces it, and the settings arriving afterwards must not undo that.
  String _nicknameFromSettings = 'Nightcord User';

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

                // Saved servers first, because coming back to one is the common
                // case; typing an address is what you do the first time.
                _SavedServers(
                  onPick: _fillFrom,
                  onRename: _rename,
                  onDelete: _delete,
                ),

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

                // Saving is offered next to connecting rather than in a menu:
                // the moment someone has just typed an address they are happy
                // with is the moment they want to keep it.
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _address,
                  builder: (context, value, _) => Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: value.text.trim().isEmpty ? null : _save,
                      icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                      style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                      label: const Text('保存这个服务器'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

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

/// The saved servers, above the form.
///
/// Absent entirely when there are none: an empty "you have no saved servers"
/// box on the first run is noise, and the form below already says what to do.
class _SavedServers extends ConsumerWidget {
  const _SavedServers({
    required this.onPick,
    required this.onRename,
    required this.onDelete,
  });

  final ValueChanged<Bookmark> onPick;
  final void Function(int index, Bookmark bookmark) onRename;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(bookmarksProvider)?.bookmarks ?? const <Bookmark>[];
    if (bookmarks.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('已保存的服务器', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          for (var index = 0; index < bookmarks.length; index++)
            _SavedServerRow(
              bookmark: bookmarks[index],
              onPick: () => onPick(bookmarks[index]),
              onRename: () => onRename(index, bookmarks[index]),
              onDelete: () => onDelete(index),
            ),
        ],
      ),
    );
  }
}

/// One saved server.
class _SavedServerRow extends StatelessWidget {
  const _SavedServerRow({
    required this.bookmark,
    required this.onPick,
    required this.onRename,
    required this.onDelete,
  });

  final Bookmark bookmark;
  final VoidCallback onPick;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.dns_outlined, size: 20, color: AppColors.textSecondary),
      title: Text(bookmark.displayName, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        bookmark.address,
        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
      // Fills the form rather than connecting: this screen exists so the
      // details can still be changed before the connection is made.
      onTap: onPick,
      trailing: PopupMenuButton<String>(
        tooltip: '更多',
        icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textMuted),
        onSelected: (choice) => choice == 'rename' ? onRename() : onDelete(),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('重命名')),
          PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
    );
  }
}

/// Asks for the name of a saved server.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.sidebar,
      title: const Text('保存服务器'),
      content: TextField(
        controller: _name,
        autofocus: true,
        decoration: const InputDecoration(labelText: '名称'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
