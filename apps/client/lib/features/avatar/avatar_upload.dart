import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/events.dart';
import '../../providers/providers.dart';
import 'avatar_editor.dart';
import '../../core/avatar/avatar_crop.dart';

Future<void> uploadAvatar(
  BuildContext context,
  WidgetRef ref,
  int session, {
  Uint8List? existingImage,
  AvatarCrop initialCrop = const AvatarCrop(),
}) async {
  try {
    Uint8List source;
    if (existingImage != null) {
      source = existingImage;
    } else {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Image',
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
            mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
            uniformTypeIdentifiers: ['public.image'],
          ),
        ],
      );
      if (file == null) return;
      if (await file.length() > 10 * 1024 * 1024) {
        throw const FormatException('avatar size');
      }
      source = await file.readAsBytes();
    }
    if (!context.mounted) return;
    final bytes = await editAvatar(context, source, initialCrop: initialCrop);
    if (bytes == null || !context.mounted) return;
    if (ref.read(sessionsProvider)[session]?.isConnected != true) return;
    ref
        .read(clientTransportProvider)
        .setAvatar(
          session,
          base64Encode(bytes.image),
          edit: {'source': base64Encode(source), ...bytes.crop.toJson()},
        );
  } catch (_) {
    if (!context.mounted) return;
    ref
        .read(lastErrorProvider.notifier)
        .report(const ClientError(kind: 'avatar_image'));
  }
}
