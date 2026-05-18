// lib/watermark/layouts/layout_dslr_corner.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutDSLRCorner extends WatermarkLayoutBase {
  @override
  String get name => 'DSLR Corner';

  static const int padX = 20;
  static const int padY = 16;
  static const int lineH = 22;

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
    final font = fontSize == 'small' ? img.arial14 : fontSize == 'large' ? img.arial24 : img.arial14;
    final int textW = 220;
    final int textH = (hasPosition ? 3 : 2) * lineH + padY * 2;
    final int x0 = src.width - textW - padX;
    final int y0 = src.height - textH - padY;
    if (x0 < 0 || y0 < 0) return WatermarkLayoutBase.encodeJpg(src);

    img.fillRect(src, x1: x0, y1: y0, x2: x0 + textW, y2: y0 + textH,
        color: img.ColorRgba8(0, 0, 0, (200 * opacity).toInt()));

    if (showBorder) {
      img.drawRect(src, x1: x0, y1: y0, x2: x0 + textW, y2: y0 + textH,
          color: img.ColorRgba8(255, 255, 255, 40), thickness: 1);
    }

    int cy = y0 + padY;
    img.drawString(src, DateFormat('HH:mm:ss').format(timestamp),
        font: font, x: x0 + 8, y: cy, color: WatermarkLayoutBase.white);
    cy += lineH;
    img.drawString(src, DateFormat('yyyy-MM-dd').format(timestamp),
        font: font, x: x0 + 8, y: cy, color: WatermarkLayoutBase.blue);
    cy += lineH;

    if (showCoordinates && hasPosition) {
      img.drawString(src, '${lat!.toStringAsFixed(5)}  ${lon!.toStringAsFixed(5)}',
          font: font, x: x0 + 8, y: cy, color: WatermarkLayoutBase.white);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }
}
