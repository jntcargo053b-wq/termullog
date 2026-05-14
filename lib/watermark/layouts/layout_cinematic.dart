```dart
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

    // Gradient cinematic overlay
    _applyGradient(src, gradY0, isTop);

    // Divider line
    final int divY = isTop ? gradH - 40 : gradY0 + 36;

    img.fillRect(
      src,
      x1: padX,
      y1: divY,
      x2: src.width - padX,
      y2: divY + 2,
      color: img.ColorRgba8(30, 144, 255, 200),
    );

    // FONT
    final font = img.arial24;

    int cy = isTop ? 16 : gradY0 + 12;

    // TIME
    img.drawString(
      src,
      DateFormat('HH : mm : ss').format(timestamp),
      font: font,
      x: padX,
      y: cy,
      color: WatermarkLayoutBase.white,
    );

    cy += lineH;

    // DATE
    img.drawString(
      src,
      DateFormat('dd  MMMM  yyyy').format(timestamp),
      font: font,
      x: padX,
      y: cy,
      color: WatermarkLayoutBase.blue,
    );

    cy += lineH + 8;

    // GPS
    if (hasPosition && lat != null && lon != null) {
      img.drawString(
        src,
        '${lat.toStringAsFixed(5)}°N   ${lon.toStringAsFixed(5)}°E',
        font: font,
        x: padX,
        y: cy,
        color: WatermarkLayoutBase.offWhite,
      );

      cy += lineH;

      // ACCURACY
      if (showAccuracy) {
        img.drawString(
          src,
          'ACCURACY  ±${acc?.toStringAsFixed(0) ?? '?'} M',
          font: font,
          x: padX,
          y: cy,
          color: WatermarkLayoutBase.grey,
        );

        cy += lineH;
      }
    }

    // ADDRESS
    if (address.isNotEmpty &&
        address != 'Tidak ada lokasi' &&
        !address.startsWith('GPS:')) {
      String sh = address.length > maxAddressLen
          ? '${address.substring(0, maxAddressLen - 1)}…'
          : address;

      img.drawString(
        src,
        sh,
        font: font,
        x: padX,
        y: cy,
        color: WatermarkLayoutBase.grey,
      );

      cy += lineH;
    }

    // WEATHER
    if (showWeather && weather.isNotEmpty) {
      img.drawString(
        src,
        weather,
        font: font,
        x: padX,
        y: cy,
        color: WatermarkLayoutBase.blue,
      );
    }

    // MINI MAP
    if (showMiniMap && mapBytes != null && hasPosition) {
      WatermarkLayoutBase.drawMiniMap(
        src,
        mapBytes,
        watermarkHeight: gradH,
        isTop: isTop,
      );
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  void _applyGradient(
    img.Image src,
    int gradY0,
    bool isTop,
  ) {
    for (int y = gradY0; y < gradY0 + gradH; y++) {
      if (y < 0 || y >= src.height) continue;

      final t = isTop
          ? 1.0 - (y - gradY0) / gradH
          : (y - gradY0) / gradH;

      final alpha = (t * 200).toInt().clamp(0, 200);

      for (int x = 0; x < src.width; x++) {
        final px = src.getPixel(x, y);

        final r = px.r.toInt();
        final g = px.g.toInt();
        final b = px.b.toInt();

        src.setPixel(
          x,
          y,
          img.ColorRgba8(
            (r * (255 - alpha)) ~/ 255,
            (g * (255 - alpha)) ~/ 255,
            (b * (255 - alpha)) ~/ 255,
            255,
          ),
        );
      }
    }
  }
}
```
