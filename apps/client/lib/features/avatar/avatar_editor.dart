import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/avatar/avatar_crop.dart';
import '../../l10n/app_localizations.dart';

/// The caller owns the decoded image until the dialog has fully closed.
typedef AvatarEditResult = ({Uint8List image, AvatarCrop crop});

Future<AvatarEditResult?> editAvatar(
  BuildContext context,
  Uint8List source, {
  AvatarCrop initialCrop = const AvatarCrop(),
}) async {
  final image = await decodeAvatarForEditing(source);
  try {
    if (!context.mounted) return null;
    final route = DialogRoute<AvatarEditResult>(
      context: context,
      builder: (_) => AvatarEditor(image: image, initialCrop: initialCrop),
    );
    final result = await Navigator.of(context).push(route);
    await route.completed;
    return result;
  } finally {
    image.dispose();
  }
}

class AvatarEditor extends StatefulWidget {
  const AvatarEditor({
    required this.image,
    this.initialCrop = const AvatarCrop(),
    super.key,
  });
  final AvatarCrop initialCrop;
  final ui.Image image;
  @override
  State<AvatarEditor> createState() => _AvatarEditorState();
}

class _AvatarEditorState extends State<AvatarEditor> {
  late AvatarCrop _crop = widget.initialCrop;
  double _gestureZoom = 1;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final bytes = await exportAvatarCrop(widget.image, _crop);
      if (mounted) Navigator.pop(context, (image: bytes, crop: _crop));
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).avatarInvalidImage),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewport = MediaQuery.sizeOf(context);
    final side = math
        .min(280.0, math.min(viewport.width - 96, viewport.height - 330))
        .clamp(80.0, 280.0);
    return AlertDialog(
      title: Text(l10n.avatarEdit),
      content: SingleChildScrollView(
        child: SizedBox(
          width: side,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                key: const ValueKey('avatar-crop-preview'),
                onScaleStart: _saving ? null : (_) => _gestureZoom = _crop.zoom,
                onScaleUpdate: _saving
                    ? null
                    : (details) {
                        setState(() {
                          _crop = AvatarCrop(
                            turns: _crop.turns,
                            zoom: (_gestureZoom * details.scale).clamp(1, 4),
                            x: _crop.x,
                            y: _crop.y,
                          ).drag(widget.image, details.focalPointDelta, side);
                        });
                      },
                child: CustomPaint(
                  size: Size.square(side),
                  painter: _CropPainter(
                    widget.image,
                    _crop,
                    Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(l10n.avatarEditHint),
              Row(
                children: [
                  Text(l10n.avatarZoom),
                  Expanded(
                    child: Slider(
                      value: _crop.zoom,
                      min: 1,
                      max: 4,
                      onChanged: _saving
                          ? null
                          : (zoom) => setState(() {
                              final rect = _crop.rect(widget.image);
                              final size = _crop.orientedSize(widget.image);
                              _crop = AvatarCrop(
                                turns: _crop.turns,
                                zoom: zoom,
                                x: rect.center.dx / size.width,
                                y: rect.center.dy / size.height,
                              );
                            }),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _crop = AvatarCrop(
                              turns: (_crop.turns + 1) % 4,
                              zoom: _crop.zoom,
                            );
                          }),
                    child: Text(l10n.avatarRotate),
                  ),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _crop = const AvatarCrop();
                          }),
                    child: Text(l10n.avatarReset),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.avatarUpload),
        ),
      ],
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.crop, this.border);
  final ui.Image image;
  final AvatarCrop crop;
  final Color border;
  @override
  void paint(Canvas canvas, Size size) {
    crop.paint(canvas, image, size.width);
    final circle = Rect.fromLTWH(0, 0, size.width, size.height);
    final shade = Path.combine(
      PathOperation.difference,
      Path()..addRect(circle),
      Path()..addOval(circle),
    );
    canvas.drawPath(
      shade,
      Paint()..color = Colors.black.withValues(alpha: .55),
    );
    canvas.drawOval(
      circle.deflate(1),
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CropPainter oldDelegate) =>
      oldDelegate.crop != crop ||
      oldDelegate.image != image ||
      oldDelegate.border != border;
}
