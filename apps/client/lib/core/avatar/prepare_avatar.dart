import 'dart:typed_data';

import 'avatar_crop.dart';

/// Noninteractive callers use the same centred square crop as the editor.
Future<Uint8List> prepareAvatar(Uint8List source) async {
  final image = await decodeAvatarForEditing(source);
  try {
    return await exportAvatarCrop(image, const AvatarCrop());
  } finally {
    image.dispose();
  }
}
