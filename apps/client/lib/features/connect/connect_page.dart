// The screen shown before anything is connected.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/components/app_logo.dart';
import '../../design/components/app_section_title.dart';
import '../../design/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/bookmarks.dart';
import '../../models/connect_request.dart';
import '../../models/domain.dart';
import '../../models/settings.dart';
import '../../providers/providers.dart';
import '../settings/settings_dialog.dart';

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
    final client = ref.read(clientTransportProvider);
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

  /// Connects straight to a saved server, past the form.
  ///
  /// A double click on a row. The request is built by
  /// `ConnectRequest.fromBookmark` — the same rule the server switcher uses, so
  /// "which of the bookmark and the settings wins" has one answer. The form is
  /// deliberately left alone: this is the shortcut for someone who already
  /// knows which server they want, and rewriting the fields under them would
  /// make the click feel like two.
  void _connectTo(Bookmark bookmark) {
    setState(() => _connecting = true);
    ref
        .read(clientTransportProvider)
        .connect(ConnectRequest.fromBookmark(bookmark, ref.read(settingsProvider) ?? const Settings()));
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
    ref.read(clientTransportProvider).connect(
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

    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(tokens.space7),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    // §16's page-level size. The mark takes §5's primary
                    // from the theme, so it follows all three of them.
                    const AppLogo(size: 32),
                    SizedBox(width: tokens.space3),
                    // `Expanded`, not a fixed `Text` plus a `Spacer`: the
                    // settings button shares this row now, and at a narrow
                    // window the three of them overflowed by a couple of
                    // dozen pixels. Taking the space that is left both pushes
                    // the button to the edge and gives the brand something to
                    // do other than run off it.
                    Expanded(
                      child: Text(
                        'Nightcord Speak',
                        overflow: TextOverflow.ellipsis,
                        // §12.2's `headline`: this is a page title. Not
                        // `display` (28) — that is for the rare special screen,
                        // and 28 next to a 32px mark would make the mark look
                        // like an accident.
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    // The way in before there is a server, which is when a
                    // user is most likely to be looking for the log folder or
                    // the language — the settings dialog's own comment says as
                    // much. No session: everything in there except the
                    // microphone test is a preference.
                    IconButton(
                      tooltip: l10n.settingsTitle,
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const SettingsDialog(),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: tokens.space7),

                // Saved servers first, because coming back to one is the common
                // case; typing an address is what you do the first time.
                _SavedServers(
                  onPick: _fillFrom,
                  onConnect: _connectTo,
                  onRename: _rename,
                  onDelete: _delete,
                ),

                TextField(
                  controller: _address,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l10n.connectAddressLabel,
                    hintText: l10n.connectAddressHint,
                  ),
                  onSubmitted: (_) => _connect(),
                ),
                SizedBox(height: tokens.space3),

                TextField(
                  controller: _nickname,
                  decoration: InputDecoration(labelText: l10n.connectNicknameLabel),
                  onSubmitted: (_) => _connect(),
                ),
                SizedBox(height: tokens.space3),

                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.connectServerPasswordLabel,
                    hintText: l10n.connectServerPasswordHint,
                  ),
                  onSubmitted: (_) => _connect(),
                ),
                SizedBox(height: tokens.space5),

                // The protocol is a choice rather than a guess: detection during
                // the handshake is on the roadmap, and until then picking the
                // wrong one should be the user's explicit mistake rather than a
                // silent default (§34).
                //
                // Both segments are enabled: the TS6 backend has been working
                // since M0.4 — this page still said "not implemented" and
                // refused the choice long after that stopped being true.
                //
                // Colours come from the theme's `segmentedButtonTheme`; the
                // stock Material version rendered in its own palette.
                SegmentedButton<ProtocolKind>(
                  segments: const [
                    ButtonSegment(value: ProtocolKind.ts3, label: Text('TeamSpeak 3')),
                    ButtonSegment(value: ProtocolKind.ts6, label: Text('TeamSpeak 6')),
                  ],
                  selected: {_protocol},
                  onSelectionChanged: (selection) =>
                      setState(() => _protocol = selection.first),
                ),
                SizedBox(height: tokens.space6),

                // Saving is offered next to connecting rather than in a menu:
                // the moment someone has just typed an address they are happy
                // with is the moment they want to keep it.
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _address,
                  builder: (context, value, _) => Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: value.text.trim().isEmpty ? null : _save,
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: Text(l10n.connectSaveServer),
                    ),
                  ),
                ),
                SizedBox(height: tokens.space3),

                // §17.1's colours, height and radius all come from the theme.
                FilledButton(
                  onPressed: _connecting ? null : _connect,
                  child: _connecting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.connectButton),
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
    required this.onConnect,
    required this.onRename,
    required this.onDelete,
  });

  final ValueChanged<Bookmark> onPick;

  /// Opens the connection straight away, for a double click.
  final ValueChanged<Bookmark> onConnect;

  final void Function(int index, Bookmark bookmark) onRename;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = DesignTokens.of(context);
    final bookmarks = ref.watch(bookmarksProvider)?.bookmarks ?? const <Bookmark>[];
    if (bookmarks.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(AppLocalizations.of(context).connectSavedServers),
          SizedBox(height: tokens.space2),
          for (var index = 0; index < bookmarks.length; index++)
            _SavedServerRow(
              bookmark: bookmarks[index],
              onPick: () => onPick(bookmarks[index]),
              onConnect: () => onConnect(bookmarks[index]),
              onRename: () => onRename(index, bookmarks[index]),
              onDelete: () => onDelete(index),
            ),
        ],
      ),
    );
  }
}

/// One saved server.
/// One saved server: click to fill the form, click twice to connect.
///
/// Stateful because the double click is detected here rather than by
/// `GestureDetector.onDoubleTap`, and that needs to remember when the last
/// click was.
class _SavedServerRow extends StatefulWidget {
  const _SavedServerRow({
    required this.bookmark,
    required this.onPick,
    required this.onConnect,
    required this.onRename,
    required this.onDelete,
  });

  final Bookmark bookmark;
  final VoidCallback onPick;
  final VoidCallback onConnect;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  State<_SavedServerRow> createState() => _SavedServerRowState();
}

class _SavedServerRowState extends State<_SavedServerRow> {
  /// How long after a click a second one still counts as a double click.
  ///
  /// Flutter's own `kDoubleTapTimeout`, spelled out rather than imported so
  /// that changing it here is a decision rather than a consequence of a
  /// framework bump.
  static const Duration _doubleClickWindow = Duration(milliseconds: 300);

  /// Armed while a second click would still make the last one a double click.
  ///
  /// A `Timer` rather than a recorded timestamp: a timestamp would have to be
  /// read against a clock, and the only clocks available here are the wall
  /// clock — which a widget test does not control — or the monotonic one. A
  /// timer runs on the scheduler's clock, which is the one the rest of the
  /// frame schedule uses and the one `flutter_test` can advance.
  Timer? _doubleClickWindowOpen;

  @override
  void dispose() {
    _doubleClickWindowOpen?.cancel();
    super.dispose();
  }

  void _onTap() {
    if (_doubleClickWindowOpen?.isActive ?? false) {
      // The second click of a pair. Cancel first, so a third click starts a
      // fresh pair rather than chaining into another connect.
      _doubleClickWindowOpen!.cancel();
      _doubleClickWindowOpen = null;
      widget.onConnect();
      return;
    }

    // The form fills on the click itself, which is the whole point of doing
    // this by hand: a second click connects *in addition*, rather than the
    // first having been held back to find out.
    widget.onPick();

    _doubleClickWindowOpen = Timer(_doubleClickWindow, () {
      _doubleClickWindowOpen = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final bookmark = widget.bookmark;

    return ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        // Icon colour and size come from the theme's `listTileTheme` and
        // `iconTheme` (§16): 20px, `textSecondary`.
        //
        // The inset is because the tile's own padding is zero — the rows line
        // up with the form fields below, and the glyph was landing flush
        // against that edge with nothing between it and the border.
        leading: Padding(
          padding: EdgeInsets.only(left: tokens.space2),
          child: const Icon(Icons.dns_outlined),
        ),
        title: Text(bookmark.displayName, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          bookmark.address,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: tokens.textTertiary),
        ),
        // Fills the form, or connects if this is the second click of a pair:
        // see [_SavedServerRowState._onTap]. Left to Flutter, a `ListTile` that
        // also had an `onDoubleTap` would hold every single click back for the
        // double-tap timeout, so the form filled a beat after the click — which
        // is the whole reason this is hand-rolled.
        onTap: _onTap,
        trailing: PopupMenuButton<String>(
          tooltip: l10n.connectMoreTooltip,
          icon: const Icon(Icons.more_vert),
          onSelected: (choice) =>
              choice == 'rename' ? widget.onRename() : widget.onDelete(),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'rename', child: Text(l10n.connectRename)),
            PopupMenuItem(value: 'delete', child: Text(l10n.connectDelete)),
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
    final l10n = AppLocalizations.of(context);

    // Background, border, radius and shadow come from the theme's
    // `dialogTheme` (§25) — this used to name the sidebar colour, which was
    // neither the modal colour nor the right one.
    return AlertDialog(
      title: Text(l10n.connectSaveServerTitle),
      content: TextField(
        controller: _name,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.connectNameLabel),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.saveButton)),
      ],
    );
  }
}
