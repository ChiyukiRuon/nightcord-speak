import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/events.dart';
import 'avatar_crop.dart';
import '../../providers/providers.dart';

class OwnAvatarState {
  const OwnAvatarState({
    this.configured = false,
    this.image,
    this.revision = 0,
    this.source,
    this.crop = const AvatarCrop(),
  });
  final Uint8List? source;
  final AvatarCrop crop;
  final int revision;
  final bool configured;
  final Uint8List? image;
}

/// One preference for every session; public avatars of other users still
/// belong to their respective server and use the ordinary repository.
final ownAvatarProvider = NotifierProvider<OwnAvatarNotifier, OwnAvatarState>(
  OwnAvatarNotifier.new,
);

class OwnAvatarNotifier extends Notifier<OwnAvatarState> {
  @override
  OwnAvatarState build() {
    final transport = ref.watch(clientTransportProvider);
    ref.listen(eventStreamProvider, (_, next) {
      final event = next.value;
      if (event is DomainEvent && event.event is OwnAvatarChangedEvent) {
        _adopt((event.event as OwnAvatarChangedEvent).data);
      } else if (event is CommandResultEvent &&
          event.result.ok &&
          event.result.command == 'settings' &&
          event.result.data?['own_avatar'] is Map) {
        _adopt(
          (event.result.data!['own_avatar'] as Map).cast<String, dynamic>(),
        );
      }
    });
    transport.requestSettings();
    return const OwnAvatarState();
  }

  void _adopt(Map<String, dynamic> data) {
    final revision = data['revision'] as int? ?? 0;
    if (revision < state.revision) return;
    Uint8List? bytes;
    final encoded = data['image'];
    if (encoded is String && encoded.length <= 273068) {
      try {
        final decoded = base64Decode(encoded);
        if (decoded.isNotEmpty && decoded.length <= 200 * 1024) bytes = decoded;
      } on FormatException {
        /* Fall back safely for malformed responses. */
      }
    }
    Uint8List? source;
    var crop = const AvatarCrop();
    final edit = data['edit'];
    if (bytes != null && edit is Map && edit['source'] is String) {
      try {
        final encodedSource = edit['source'] as String;
        if (encodedSource.length > 13981016) {
          throw const FormatException('source size');
        }
        final decoded = base64Decode(encodedSource);
        final savedCrop = AvatarCrop.fromJson(edit.cast<String, dynamic>());
        if (decoded.isEmpty ||
            decoded.length > 10 * 1024 * 1024 ||
            savedCrop.turns < 0 ||
            savedCrop.turns > 3 ||
            !savedCrop.zoom.isFinite ||
            savedCrop.zoom < 1 ||
            savedCrop.zoom > 4 ||
            !savedCrop.x.isFinite ||
            savedCrop.x < 0 ||
            savedCrop.x > 1 ||
            !savedCrop.y.isFinite ||
            savedCrop.y < 0 ||
            savedCrop.y > 1) {
          throw const FormatException('crop');
        }
        source = decoded;
        crop = savedCrop;
      } catch (_) {
        // Old or malformed editing data must not hide a valid public avatar.
      }
    }
    state = OwnAvatarState(
      revision: revision,
      configured: data['configured'] == true,
      image: bytes,
      source: source,
      crop: crop,
    );
  }
}
