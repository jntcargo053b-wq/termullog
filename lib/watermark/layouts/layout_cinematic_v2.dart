// lib/watermark/layouts/layout_cinematic_v2.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutCinematicV2 extends WatermarkLayoutBase {
  @override
  String get name => 'Cinematic V2';

  static const int gradH = 180;
  static const int padX = 36;
  static const int lineH = 28;

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
    final int gradY0 = isTop ? 0 : src.height - gradH;
    _applyGradient(src, gradY0, isTop);

    final int divY = isTop ? gradH - 40 : gradY0 + 36;
    img.fillRect(src, x1: padX, y1: divY, x2: src.width - padX, y2: divY + 2,
        color: img.ColorRgba8(30, 144, 255, 200));

    final font = fontSize == 'small' ? img.arial14 : fontSize == 'large' ? img.arial24 : img.arial24;
    int cy = isTop ? 16 : gradY0 + 12;

    img.drawString(src, DateFormat('HH : mm : ss').format(timestamp),
        font: font, x: padX, y: cy, color: WatermarkLayoutBase.white);
    cy += lineH;
    img.drawString(src, DateFormat('dd  MMMM  yyyy').format(timestamp),
        font: font, x: padX, y: cy, color: WatermarkLayoutBase.blue);
    cy += lineH + 8;

    if (showCoordinates && hasPosition) {
      img.drawString(src, '${lat!.toStringAsFixed(5)}°N   ${lon!.toStringAsFixed(5)}°E',
          font: font, x: padX, y: cy, color: WatermarkLayoutBase.offWhite);
      cy += lineH;
      if (showAccuracy) {
        img.drawString(src, 'ACCURACY  ±${acc?.toStringAsFixed(0) ?? '?'} M',
            font: font, x: padX, y: cy, color: WatermarkLayoutBase.grey);
      }
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  @override
  Future<Uint8List> applyAsync({
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
  }) async {
    return apply(
      src: src, timestamp: timestamp, hasPosition: hasPosition,
      lat: lat, lon: lon, acc: acc, address: address, weather: weather,
      showWeather: showWeather, showAccuracy: showAccuracy,
      watermarkPosition: watermarkPosition, showMiniMap: showMiniMap,
      mapBytes: mapBytes,
      showAddress: showAddress,
      showCoordinates: showCoordinates,
      opacity: opacity,
      showBorder: showBorder,
      fontSize: fontSize,
    );
  }

  void _applyGradient(img.Image src, int gradY0, bool isTop) {
    for (int y = gradY0; y < gradY0 + gradH; y++) {
      if (y < 0 || y >= src.height) continue;
      final t = isTop ? 1.0 - (y - gradY0) / gradH : (y - gradY0) / gradH;
      final alpha = (t * 220).toInt().clamp(0, 220);
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
