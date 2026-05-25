// lib/watermark/layouts/layout_cinematic_v2.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutCinematicV2 extends WatermarkLayoutBase {
  @override
  String get name => 'Cinematic V2';

  static const int _padX = 36;
  static const bool _positionBottom = true; // true = bottom, false = top

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
    required bool showMiniMap,
    Uint8List? mapBytes,
    bool showAddress = true,
    bool showCoordinates = true,
    double opacity = 0.85,
    bool showBorder = true,
    String fontSize = 'normal',
    String mapSize = 'medium',
    String dateFormat = 'dd MMM yyyy',
    String timeFormat = 'HH:mm:ss',
  }) {
    final double scale = (src.width / 1080).clamp(0.7, 2.0);
    final double fsMultiplier = fontSize == 'small' ? 0.75 : fontSize == 'large' ? 1.4 : 1.0;

    final int gradH = (180 * scale).round();
    final int padX = (_padX * scale).round();
    final int lineH = (28 * scale * fsMultiplier).round();
    final int lineHSmall = (22 * scale * fsMultiplier).round();

    final int gradY0 = _positionBottom ? src.height - gradH : 0;
    if (gradY0 < 0 || gradY0 >= src.height) return WatermarkLayoutBase.encodeJpg(src);

    _applyGradient(src, gradY0: gradY0, gradH: gradH, isTop: !_positionBottom, opacity: opacity);

    final int divY = _positionBottom ? gradY0 + (36 * scale).round() : gradH - (40 * scale).round();
    if (showBorder) {
      img.fillRect(src, x1: padX - 2, y1: divY - 1, x2: src.width - padX + 2, y2: divY + 3,
          color: img.ColorRgba8(30, 144, 255, 40));
      img.fillRect(src, x1: padX, y1: divY, x2: src.width - padX, y2: divY + 2,
          color: img.ColorRgba8(30, 144, 255, 200));
    }

    final font = fontSize == 'small' ? img.arial14 : img.arial24;
    final fontSmall = fontSize == 'small' ? img.arial14 : img.arial24;

    int cy = _positionBottom ? gradY0 + (12 * scale).round() : (16 * scale).round();

    _shadowText(src, DateFormat('HH : mm : ss').format(timestamp),
        font: font, x: padX, y: cy, color: WatermarkLayoutBase.white);
    cy += lineH;
    _shadowText(src, DateFormat('dd  MMMM  yyyy').format(timestamp),
        font: font, x: padX, y: cy, color: WatermarkLayoutBase.blue);
    cy += lineH + (8 * scale).round();

    if (showCoordinates && hasPosition && lat != null && lon != null) {
      img.drawString(src, '${lat.toStringAsFixed(5)}°N   ${lon.toStringAsFixed(5)}°E',
          font: fontSmall, x: padX, y: cy, color: WatermarkLayoutBase.offWhite);
      cy += lineHSmall;
      if (showAccuracy && acc != null) {
        img.drawString(src, 'ACCURACY  ±${acc.toStringAsFixed(0)} M',
            font: fontSmall, x: padX, y: cy, color: WatermarkLayoutBase.grey);
        cy += lineHSmall;
      }
    }

    if (showAddress && address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      final maxChars = (src.width / 7).toInt().clamp(30, 55);
      final shortAddr = address.length > maxChars ? '${address.substring(0, maxChars - 1)}…' : address;
      img.drawString(src, shortAddr, font: fontSmall, x: padX, y: cy, color: WatermarkLayoutBase.grey);
      cy += lineHSmall;
    }

    if (showWeather && weather.isNotEmpty) {
      img.fillRect(src, x1: padX - 4, y1: cy - 2,
          x2: padX + weather.length * 7 + 12, y2: cy + lineHSmall - 4,
          color: img.ColorRgba8(30, 144, 255, 30));
      img.drawString(src, weather, font: fontSmall, x: padX + 4, y: cy + 2, color: WatermarkLayoutBase.blue);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  void _shadowText(img.Image src, String text, {required img.BitmapFont font, required int x, required int y, required img.Color color}) {
    img.drawString(src, text, font: font, x: x + 1, y: y + 1, color: img.ColorRgba8(0, 0, 0, 120));
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  void _applyGradient(img.Image src, {required int gradY0, required int gradH, required bool isTop, required double opacity}) {
    for (int y = gradY0; y < gradY0 + gradH; y++) {
      if (y < 0 || y >= src.height) continue;
      final double t = isTop ? 1.0 - (y - gradY0) / gradH : (y - gradY0) / gradH;
      final int alpha = (t * 220 * opacity).toInt().clamp(0, 220);
      for (int x = 0; x < src.width; x++) {
        final px = src.getPixel(x, y);
        src.setPixel(x, y, img.ColorRgba8(
          ((px.r * (255 - alpha)) ~/ 255),
          ((px.g * (255 - alpha)) ~/ 255),
          ((px.b * (255 - alpha)) ~/ 255), 255));
      }
    }
  }
}
