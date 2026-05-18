// lib/watermark/layouts/layout_polaroid.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutPolaroid extends WatermarkLayoutBase {
  @override
  String get name => 'Polaroid';

  static const int borderTop = 24;
  static const int borderSide = 24;
  static const int borderBottom = 90;

  @override
  Uint8List apply({
    required img.Image src,
    required DateTime timestamp,
    required bool hasPosition,
    required double? lat,
    required double? lon,
    required double? acc,
    required String address,
    required String weather,
    required bool showWeather,
    required bool showAccuracy,
    required String watermarkPosition,
    required bool showMiniMap,
    Uint8List? mapBytes,
    bool showAddress = true,
    bool showCoordinates = true,
    double opacity = 0.85,
    bool showBorder = true,
    String fontSize = 'normal',
  }) {
    final int newW = src.width + borderSide * 2;
    final int newH = src.height + borderTop + borderBottom;

    // Canvas ivory
    final canvas = img.Image(width: newW, height: newH);
    img.fillRect(canvas, x1: 0, y1: 0, x2: newW - 1, y2: newH - 1,
        color: img.ColorRgba8(248, 245, 235, 255));

    // Shadow
    img.fillRect(canvas,
        x1: borderSide + 4, y1: borderTop + 4,
        x2: borderSide + src.width + 4, y2: borderTop + src.height + 4,
        color: img.ColorRgba8(0, 0, 0, 20));

    // Foto
    img.compositeImage(canvas, src, dstX: borderSide, dstY: borderTop, blend: img.BlendMode.alpha);

    // Teks
    final font = fontSize == 'small' ? img.arial14 : fontSize == 'large' ? img.arial24 : img.arial24;
    final textColor = img.ColorRgba8(40, 40, 40, 255);
    int cy = src.height + borderTop + 14;

    img.drawString(canvas, DateFormat('dd MMM yyyy • HH:mm').format(timestamp),
        font: font, x: borderSide, y: cy, color: textColor);

    return WatermarkLayoutBase.encodeJpg(canvas);
  }
}
