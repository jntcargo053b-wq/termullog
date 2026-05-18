// lib/watermark/layouts/layout_cinematic.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutCinematic extends WatermarkLayoutBase {
  @override
  String get name => 'Cinematic';

  static const int gradH = 160;
  static const int padX = 32;
  static const int lineH = 30;

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
    final bool isTop = watermarkPosition == 'top';
    final int y0 = isTop ? 0 : src.height - gradH;
    if (y0 < 0 || y0 >= src.height) return WatermarkLayoutBase.encodeJpg(src);

    for (int y = y0; y < y0 + gradH; y++) {
      if (y < 0 || y >= src.height) continue;
      final t = isTop ? 1.0 - (y - y0) / gradH : (y - y0) / gradH;
      final a = (t * 220 * opacity).toInt().clamp(0, 220);
      img.fillRect(src, x1: 0, y1: y, x2: src.width - 1, y2: y + 1,
          color: img.ColorRgba8(0, 0, 0, a));
    }

    final font = fontSize == 'small' ? img.arial14 : fontSize == 'large' ? img.arial24 : img.arial24;
    int cy = isTop ? 20 : y0 + 16;

    final int divY = isTop ? gradH - 40 : y0 + 40;
    if (showBorder) {
      img.fillRect(src, x1: padX, y1: divY, x2: src.width - padX, y2: divY + 2,
          color: img.ColorRgba8(30, 144, 255, 200));
    }

    img.drawString(src, DateFormat('HH:mm:ss').format(timestamp),
        font: font, x: padX, y: cy, color: WatermarkLayoutBase.white);
    cy += lineH;
    img.drawString(src, DateFormat('dd MMMM yyyy').format(timestamp),
        font: font, x: padX, y: cy, color: WatermarkLayoutBase.blue);
    cy += lineH + 8;

    if (showCoordinates && hasPosition) {
      img.drawString(src, '${lat!.toStringAsFixed(5)}°N  ${lon!.toStringAsFixed(5)}°E',
          font: font, x: padX, y: cy, color: WatermarkLayoutBase.white);
      cy += lineH;
      if (showAccuracy) {
        img.drawString(src, 'Accuracy ±${acc?.toStringAsFixed(0) ?? '?'} m',
            font: font, x: padX, y: cy, color: WatermarkLayoutBase.grey);
      }
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }
}
