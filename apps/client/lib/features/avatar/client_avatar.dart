import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/avatar/avatar_repository.dart';
import '../../core/avatar/own_avatar.dart';
import '../../design/components/app_avatar.dart';
import '../../models/domain.dart';

/// The feature layer resolves images; the design component only draws them.
class ClientAvatar extends ConsumerWidget {
  const ClientAvatar({
    required this.session,
    required this.client,
    this.size = 28,
    this.speaking = false,
    super.key,
  });

  final int session;
  final Client client;
  final double size;
  final bool speaking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (client.isSelf) {
      final own = ref.watch(ownAvatarProvider);
      if (own.configured) {
        return Avatar(
          name: client.name,
          image: own.image,
          size: size,
          speaking: speaking,
        );
      }
    }
    final version = client.avatarVersion;
    final image = version == null
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
    return Avatar(
      name: client.name,
      size: size,
      speaking: speaking,
      image: image,
    );
  }
}
