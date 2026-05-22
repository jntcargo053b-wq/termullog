import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'watermark_layout_base.dart';
import '../../core/constants.dart';

class LayoutHUD extends WatermarkLayoutBase {
  @override
  String get name => 'HUD';

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
    final int margin = 16;
    int x = margin;
    int y = margin;

    img.fillRect(src, x, y, x + 200, y + 120, 0xB4000000); // semi-transparan hitam
    img.drawRect(src, x1: x, y1: y, x2: x + 200, y2: y + 120, color: kColorCyan);

    y += 16;
    x += 12;

    final String timeStr = DateFormat('HH:mm:ss').format(timestamp);
    img.drawString(src, img.arial24, x, y, timeStr, color: kColorCyan);
    y += 32;

    final String dateStr = DateFormat('dd MMM yyyy').format(timestamp);
    img.drawString(src, img.arial14, x, y, dateStr, color: kColorCyan);
    y += 24;

    if (hasPosition && showCoordinates && lat != null && lon != null) {
      final String coordStr = '${lat.toStringAsFixed(5)}° ${lon.toStringAsFixed(5)}°';
      img.drawString(src, img.arial12, x, y, coordStr, color: kColorWhite);
      y += 20;
      if (showAccuracy && acc != null) {
        final String accStr = '±${acc.toStringAsFixed(1)}m';
        img.drawString(src, img.arial12, x, y, accStr, color: getAccuracyColor(acc));
      }
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }
}
