import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Crop coordinates are measured after rotation, so dragging and export use
/// the same transform even for portrait images.
class AvatarCrop {
  const AvatarCrop({this.turns = 0, this.zoom = 1, this.x = .5, this.y = .5});
  Map<String, dynamic> toJson() => {
    'turns': turns,
    'zoom': zoom,
    'x': x,
    'y': y,
  };
  factory AvatarCrop.fromJson(Map<String, dynamic> json) => AvatarCrop(
    turns: json['turns'] as int,
    zoom: (json['zoom'] as num).toDouble(),
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
  );
  final int turns;
  final double zoom;
  final double x;
  final double y;

  ui.Size orientedSize(ui.Image image) => turns.isEven
      ? ui.Size(image.width.toDouble(), image.height.toDouble())
      : ui.Size(image.height.toDouble(), image.width.toDouble());

  ui.Rect rect(ui.Image image) {
    final size = orientedSize(image);
    final side = math.min(size.width, size.height) / zoom;
    final cx = (x * size.width).clamp(side / 2, size.width - side / 2);
    final cy = (y * size.height).clamp(side / 2, size.height - side / 2);
    return ui.Rect.fromCenter(
      center: ui.Offset(cx, cy),
      width: side,
      height: side,
    );
  }

  AvatarCrop drag(ui.Image image, ui.Offset delta, double viewport) {
    final size = orientedSize(image);
    final crop = rect(image);
    final factor = crop.width / viewport;
    return AvatarCrop(
      turns: turns,
      zoom: zoom,
      x: ((crop.center.dx - delta.dx * factor) / size.width).clamp(0, 1),
      y: ((crop.center.dy - delta.dy * factor) / size.height).clamp(0, 1),
    );
  }

  void paint(ui.Canvas canvas, ui.Image image, double outputSide) {
    final crop = rect(image);
    final size = orientedSize(image);
    canvas.save();
    canvas.clipRect(ui.Rect.fromLTWH(0, 0, outputSide, outputSide));
    canvas.translate(outputSide / 2, outputSide / 2);
    canvas.scale(outputSide / crop.width);
    canvas.translate(-crop.center.dx, -crop.center.dy);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(turns * math.pi / 2);
    canvas.drawImage(
      image,
      ui.Offset(-image.width / 2, -image.height / 2),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    canvas.restore();
  }
}

Future<ui.Image> decodeAvatarForEditing(Uint8List source) async {
  if (source.isEmpty || source.length > 10 * 1024 * 1024) {
    throw const FormatException('avatar size');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(source);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      if (descriptor.width > 8192 ||
          descriptor.height > 8192 ||
          descriptor.width * descriptor.height > 32 * 1024 * 1024) {
        throw const FormatException('avatar dimensions');
      }
      final longest = math.max(descriptor.width, descriptor.height);
      final codec = await descriptor.instantiateCodec(
        targetWidth: descriptor.width >= descriptor.height
            ? math.min(longest, 2048)
            : null,
        targetHeight: descriptor.height > descriptor.width
            ? math.min(longest, 2048)
            : null,
      );
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}

Future<Uint8List> exportAvatarCrop(ui.Image image, AvatarCrop crop) async {
  for (final side in [256, 128, 64]) {
    final recorder = ui.PictureRecorder();
    crop.paint(ui.Canvas(recorder), image, side.toDouble());
    final picture = recorder.endRecording();
    final output = await picture.toImage(side, side);
    try {
      final data = await output.toByteData(format: ui.ImageByteFormat.png);
      if (data != null && data.lengthInBytes <= 200 * 1024) {
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      }
    } finally {
      output.dispose();
      picture.dispose();
    }
  }
  throw const FormatException('avatar encoding');
}
