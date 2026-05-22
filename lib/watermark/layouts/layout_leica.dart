import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'watermark_layout_base.dart';
import '../../core/constants.dart';

class LayoutLeica extends WatermarkLayoutBase {
  @override
  String get name => 'Leica';

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
    final int margin = 20;
    final int x = src.width - margin - 180;
    int y = src.height - margin - 80;

    img.fillCircle(src, src.width - margin - 12, y + 12, 6, kColorRed);

    final String dateStr = DateFormat('yyyy-MM-dd').format(timestamp);
    final String timeStr = DateFormat('HH:mm:ss').format(timestamp);

    _drawText(src, dateStr, x, y, 14, kColorWhite);
    y += 24;
    _drawText(src, timeStr, x, y, 14, kColorWhite);
    y += 24;

    if (hasPosition && showCoordinates && lat != null && lon != null) {
      final String coordStr = '${lat.toStringAsFixed(4)}° ${lon.toStringAsFixed(4)}°';
      _drawText(src, coordStr, x, y, 11, kColorLightGrey);
      y += 20;
    }

    if (showAccuracy && acc != null) {
      final String accStr = '±${acc.toStringAsFixed(1)}m';
      _drawText(src, accStr, x, y, 11, getAccuracyColor(acc));
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  void _drawText(img.Image image, String text, int x, int y, int size, int color) {
    if (size <= 12) {
      img.drawString(image, img.arial12, x, y, text, color: color);
    } else if (size <= 14) {
      img.drawString(image, img.arial14, x, y, text, color: color);
    } else {
      img.drawString(image, img.arial24, x, y, text, color: color);
    }
  }
}
