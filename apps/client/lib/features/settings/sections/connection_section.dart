// Who we are by default, and what happens when the server goes away.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/settings.dart';
import '../../../providers/providers.dart';

/// Defaults for new connections, and the reconnect policy.
class ConnectionSection extends ConsumerStatefulWidget {
  /// Edits `settings`.
  const ConnectionSection({required this.settings, super.key});

  final Settings settings;

  @override
  ConsumerState<ConnectionSection> createState() => _ConnectionSectionState();
}

class _ConnectionSectionState extends ConsumerState<ConnectionSection> {
  // Seeded once, in `initState` — the fields cannot be filled from `build`
  // (that would fight the user's typing on every rebuild), and cannot be
  // filled from a field initializer (`widget` is not there yet).
  late final TextEditingController _nickname;
  late final TextEditingController _profile;

  @override
  void initState() {
    super.initState();
    _nickname = TextEditingController(text: widget.settings.connection.nickname);
    _profile = TextEditingController(text: widget.settings.connection.profile);
  }

  @override
  void dispose() {
    _nickname.dispose();
    _profile.dispose();
    super.dispose();
  }

  /// Stores a connection change.
  void _connection(ConnectionSettings connection) =>
      ref.read(settingsProvider.notifier).update(
        widget.settings.copyWith(connection: connection),
      );

  /// Stores whatever the text fields currently hold.
  ///
  /// On submit and on leaving the field rather than per keystroke: writing the
  /// file once per character would be absurd, and a half-typed nickname saved
  /// because the user paused is worse than one saved when they move on.
  void _commitText() {
    final nickname = _nickname.text.trim();
    final profile = _profile.text.trim();
    if (nickname.isEmpty || profile.isEmpty) return;

    final current = widget.settings.connection;
    if (nickname == current.nickname && profile == current.profile) return;

    _connection(current.copyWith(nickname: nickname, profile: profile));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final connection = widget.settings.connection;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nickname,
          decoration: InputDecoration(labelText: l10n.settingsDefaultNickname),
          onSubmitted: (_) => _commitText(),
          onTapOutside: (_) => _commitText(),
        ),
        SizedBox(height: tokens.space3),
        TextField(
          controller: _profile,
          decoration: InputDecoration(
            labelText: l10n.settingsIdentityProfile,
            helperText: l10n.settingsIdentityProfileHelper,
          ),
          onSubmitted: (_) => _commitText(),
          onTapOutside: (_) => _commitText(),
        ),
        SizedBox(height: tokens.space3),
        DropdownButtonFormField<int?>(
          initialValue: connection.maxReconnectAttempts,
          isExpanded: true,
          decoration: InputDecoration(labelText: l10n.settingsAfterDrop),
          items: [
            DropdownMenuItem(
              value: null,
              child: Text(l10n.settingsReconnectUnlimited),
            ),
            DropdownMenuItem(value: 3, child: Text(l10n.settingsReconnectAttempts(3))),
            DropdownMenuItem(value: 10, child: Text(l10n.settingsReconnectAttempts(10))),
            DropdownMenuItem(value: 0, child: Text(l10n.settingsReconnectNever)),
          ],
          onChanged: (attempts) => _connection(
            connection.copyWith(
              maxReconnectAttempts: attempts,
              clearMaxReconnectAttempts: attempts == null,
            ),
          ),
        ),
      ],
    );
  }
}
