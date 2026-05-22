import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'watermark_layout_base.dart';
import '../../core/constants.dart';

class LayoutCinematic extends WatermarkLayoutBase {
  @override
  String get name => 'Cinematic';
  @override
  String get defaultPosition => 'bottom';
  @override
  double get defaultOpacity => 1.0;
  @override
  bool get supportsMiniMap => true;
  @override
  bool get supportsBorder => false;

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
    double opacity = 1.0,
    bool showBorder = false,
    String fontSize = 'normal',
  }) {
    final double scale = (src.width / 1080).clamp(0.7, 2.0);
    final double fsMultiplier = fontSize == 'small' ? 0.75 : fontSize == 'large' ? 1.4 : 1.0;
    final int gradH = (180 * scale).round();
    final int padX = (36 * scale).round();
    final int lineH = (28 * scale * fsMultiplier).round();
    final int lineHSmall = (22 * scale * fsMultiplier).round();

    final int gradY0 = WatermarkLayoutBase.resolveYStart(
      watermarkPosition: watermarkPosition,
      imageHeight: src.height,
      contentHeight: gradH,
    );
    if (gradY0 < 0 || gradY0 >= src.height) return WatermarkLayoutBase.encodeJpg(src);

    final bool atTop = WatermarkLayoutBase.isAtTopEdge(gradY0, src.height);

    // Gradient bar
    for (int i = 0; i < gradH; i++) {
      final double t = atTop ? (i / gradH) : (1.0 - i / gradH);
      final int alpha = (200 * t).clamp(0, 200).round();
      final int barColor = (0xFF0A0F28 & 0x00FFFFFF) | (alpha << 24);
      img.drawLine(src, 0, gradY0 + i, src.width - 1, gradY0 + i, barColor);
    }

    int textY = atTop ? gradY0 + (gradH * 0.15).round() : gradY0 + (gradH * 0.10).round();

    final String dateStr = DateFormat('dd MMM yyyy').format(timestamp);
    final String timeStr = DateFormat('HH:mm:ss').format(timestamp);

    _drawTextCentered(src, dateStr, src.width ~/ 2, textY, 24, kColorWhite);
    textY += lineH;
    _drawTextCentered(src, timeStr, src.width ~/ 2, textY, 14, kColorLightGrey);
    textY += lineHSmall + 4;

    if (hasPosition && showCoordinates && lat != null && lon != null) {
      final String coordStr = '${lat.toStringAsFixed(5)}°, ${lon.toStringAsFixed(5)}°';
      _drawTextCentered(src, coordStr, src.width ~/ 2, textY, 12, kColorLightGrey);
      textY += lineHSmall;
    }

    if (hasPosition && showAccuracy && acc != null) {
      final String accStr = '±${acc.toStringAsFixed(1)} m';
      _drawTextCentered(src, accStr, src.width ~/ 2, textY, 12, getAccuracyColor(acc));
      textY += lineHSmall;
    }

    if (showAddress && address.isNotEmpty) {
      final truncated = address.length > 55 ? '${address.substring(0, 52)}...' : address;
      _drawTextCentered(src, truncated, src.width ~/ 2, textY, 12, kColorLightGrey);
      textY += lineHSmall;
    }

    if (showWeather && weather.isNotEmpty) {
      _drawTextCentered(src, weather, src.width ~/ 2, textY, 12, kColorLightGrey);
    }

    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) {
      try {
        final mapImg = img.decodeImage(mapBytes);
        if (mapImg != null) {
          final mapSize = (gradH * 0.80).round();
          final mapResized = img.copyResize(mapImg, width: mapSize, height: mapSize);
          final mapX = src.width - mapSize - padX;
          final mapY = gradY0 + ((gradH - mapSize) ~/ 2);
          img.compositeImage(src, mapResized, dstX: mapX, dstY: mapY);
        }
      } catch (_) {}
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  void _drawTextCentered(img.Image image, String text, int centerX, int y, int size, int color) {
    final int approxWidth = (text.length * (size ~/ 2)).round();
    int x = centerX - (approxWidth ~/ 2);
    if (x < 0) x = 0;
    if (size <= 14) {
      img.drawString(image, img.arial14, x, y, text, color: color);
    } else if (size <= 24) {
      img.drawString(image, img.arial24, x, y, text, color: color);
    } else {
      img.drawString(image, img.arial36, x, y, text, color: color);
    }
  }
}
