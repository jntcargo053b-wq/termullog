
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutCinematic extends WatermarkLayoutBase {
  @override
  String get name => 'Cinematic';
  
  static const int gradH = 180;
  static const int padX = 36;
  static const int lineH = 28;
  static const int maxAddressLen = 55;

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
  }) {
    final bool isTop = watermarkPosition == 'top';
    final int gradY0 = isTop ? 0 : src.height - gradH;

    // Apply gradient overlay
    _applyGradient(src, gradY0, isTop);

    // Divider line
    final int divY = isTop ? gradH - 40 : gradY0 + 36;
    img.fillRect(src, x1: padX, y1: divY, x2: src.width - padX, y2: divY + 2,
        color: img.ColorRgba8(30, 144, 255, 200));

    final font = img.arial24;
    int cy = isTop ? 16 : gradY0 + 12;

    img.drawString(src, DateFormat('HH : mm : ss').format(timestamp), 
      font: font, x: padX, y: cy, color: WatermarkLayoutBase.white);
    cy += lineH;
    img.drawString(src, DateFormat('dd  MMMM  yyyy').format(timestamp), 
      font: font, x: padX, y: cy, color: WatermarkLayoutBase.blue);
    cy += lineH + 8;

    if (hasPosition) {
      img.drawString(src,
          '${lat!.toStringAsFixed(5)}°N   ${lon!.toStringAsFixed(5)}°E',
          font: font, x: padX, y: cy, color: WatermarkLayoutBase.offWhite);
      cy += lineH;
      if (showAccuracy) {
        img.drawString(src, 'ACCURACY  ±${acc?.toStringAsFixed(0) ?? '?'} M',
            font: font, x: padX, y: cy, color: WatermarkLayoutBase.grey);
        cy += lineH;
      }
    }

    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      String sh = address.length > maxAddressLen 
          ? '${address.substring(0, maxAddressLen - 1)}…' : address;
      img.drawString(src, sh, font: font, x: padX, y: cy, color: WatermarkLayoutBase.grey);
      cy += lineH;
    }

    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, weather, font: font, x: padX, y: cy, color: WatermarkLayoutBase.blue);
    }

    // Mini map
    if (showMiniMap && mapBytes != null && hasPosition) {
      WatermarkLayoutBase.drawMiniMap(src, mapBytes,
          watermarkHeight: gradH, isTop: isTop);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  void _applyGradient(img.Image src, int gradY0, bool isTop) {
    for (int y = gradY0; y < gradY0 + gradH; y++) {
      if (y < 0 || y >= src.height) continue;
      final t = isTop ? 1.0 - (y - gradY0) / gradH : (y - gradY0) / gradH;
      final alpha = (t * 200).toInt().clamp(0, 200);
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
