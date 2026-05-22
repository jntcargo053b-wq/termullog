import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'watermark_layout_base.dart';
import '../../core/constants.dart';

class LayoutDocumentary extends WatermarkLayoutBase {
  @override
  String get name => 'Documentary';

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
    final int padding = 15;
    final int x = margin;
    final int y = margin;
    final int panelWidth = 280;
    final int panelHeight = hasPosition ? 180 : 120;

    final int bgColor = (0x00000000 | ((opacity * 255).toInt() << 24)) & 0xCC000000;
    img.fillRect(src, x, y, x + panelWidth, y + panelHeight, bgColor);

    if (showBorder) {
      img.drawRect(src, x1: x, y1: y, x2: x + panelWidth, y2: y + panelHeight, color: kColorWhite);
    }

    int textY = y + padding;
    int textX = x + padding;

    img.drawString(src, img.arial14, textX, textY, '📍 DOCUMENTARY', color: kColorWhite);
    textY += 28;

    final String dateStr = DateFormat('dd MMM yyyy').format(timestamp);
    final String timeStr = DateFormat('HH:mm:ss').format(timestamp);
    img.drawString(src, img.arial12, textX, textY, '$dateStr | $timeStr', color: kColorLightGrey);
    textY += 24;

    if (hasPosition && showCoordinates && lat != null && lon != null) {
      final String coordStr = '${lat.toStringAsFixed(6)}°, ${lon.toStringAsFixed(6)}°';
      img.drawString(src, img.arial12, textX, textY, coordStr, color: kColorLightGrey);
      textY += 20;
      if (showAccuracy && acc != null) {
        final String accStr = 'Accuracy: ±${acc.toStringAsFixed(1)}m';
        img.drawString(src, img.arial12, textX, textY, accStr, color: getAccuracyColor(acc));
        textY += 20;
      }
    }

    if (showAddress && address.isNotEmpty) {
      final truncated = address.length > 40 ? '${address.substring(0, 37)}...' : address;
      img.drawString(src, img.arial12, textX, textY, truncated, color: kColorLightGrey);
      textY += 20;
    }

    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, img.arial12, textX, textY, weather, color: kColorLightGrey);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }
}
