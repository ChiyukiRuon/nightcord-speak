import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/avatar/avatar_repository.dart';
import '../../core/avatar/own_avatar.dart';
import '../../design/components/app_avatar.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/providers.dart';
import 'avatar_upload.dart';
import 'client_avatar.dart';

Future<void> openOwnProfile(BuildContext context, int session) =>
    showDialog<void>(
      context: context,
      builder: (_) => _AvatarDetails(session: session),
    );

class OwnAvatarButton extends ConsumerWidget {
  const OwnAvatarButton({required this.session, super.key});
  final int session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(sessionsProvider)[session];
    final client = view?.ownClient;
    final enabled = view?.isConnected == true && client != null;
    final label = AppLocalizations.of(context).profileTitle;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        enabled: enabled,
        child: InkWell(
          key: const ValueKey('own-avatar-button'),
          customBorder: const CircleBorder(),
          onTap: enabled ? () => openOwnProfile(context, session) : null,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: client == null
                ? const Avatar(name: '', size: 28)
                : ClientAvatar(session: session, client: client, size: 28),
          ),
        ),
      ),
    );
  }
}

class _AvatarDetails extends ConsumerStatefulWidget {
  const _AvatarDetails({required this.session});
  final int session;

  @override
  ConsumerState<_AvatarDetails> createState() => _AvatarDetailsState();
}

class _AvatarDetailsState extends ConsumerState<_AvatarDetails> {
  int get session => widget.session;
  late final _nickname = TextEditingController(
    text: ref.read(sessionsProvider)[session]?.ownClient?.name ?? '',
  );

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nickname.text.trim();
    final view = ref.read(sessionsProvider)[session];
    if (name.isEmpty ||
        view?.isConnected != true ||
        name == view?.ownClient?.name) {
      return;
    }
    ref.read(clientTransportProvider).setNickname(session, name);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(sessionsProvider)[session];
    final client = view?.ownClient;
    final version = client?.avatarVersion;
    final own = ref.watch(ownAvatarProvider);
    final image = own.configured
        ? own.image
        : client == null || version == null
        ? null
        : ref
              .watch(
                avatarImageProvider((
                  session: session,
                  clientId: client.id,
                  identity: client.uniqueId,
                  version: version,
                )),
              )
              .value;
    final enabled = view?.isConnected == true && client != null;
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.profileTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Avatar(name: client?.name ?? '', image: image, size: 160),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('profile-nickname-field'),
            controller: _nickname,
            enabled: enabled,
            decoration: InputDecoration(labelText: l10n.connectNicknameLabel),
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
          ),
          if (image != null && own.source == null) ...[
            const SizedBox(height: 8),
            Text(l10n.avatarOriginalMissing),
          ],
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: enabled
                    ? () => uploadAvatar(context, ref, session)
                    : null,
                child: Text(l10n.avatarUpload),
              ),
              OutlinedButton(
                onPressed: enabled && image != null
                    ? () => uploadAvatar(
                        context,
                        ref,
                        session,
                        existingImage: own.source,
                        initialCrop: own.crop,
                      )
                    : null,
                child: Text(l10n.avatarEdit),
              ),
              TextButton(
                onPressed:
                    enabled &&
                        (own.configured ? own.image != null : version != null)
                    ? () {
                        ref
                            .read(clientTransportProvider)
                            .setAvatar(session, null);
                      }
                    : null,
                child: Text(l10n.avatarRemove),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
        FilledButton(
          key: const ValueKey('profile-save-button'),
          onPressed:
              enabled &&
                  _nickname.text.trim().isNotEmpty &&
                  _nickname.text.trim() != client.name
              ? _save
              : null,
          child: Text(l10n.saveButton),
        ),
      ],
    );
  }
}
