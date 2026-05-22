import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'package:image/src/font/arial_12.dart';
import 'package:image/src/font/arial_14.dart';
import 'watermark_layout_base.dart';
import '../../core/constants.dart';

class LayoutSurvey extends WatermarkLayoutBase {
  @override
  String get name => 'Survey';

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
    final int panelW = 300;
    final int panelY = margin;
    final int panelX = src.width - margin - panelW;

    int contentLines = 4;
    if (hasPosition && showCoordinates) contentLines += 2;
    if (showAccuracy && acc != null) contentLines += 1;
    if (showAddress && address.isNotEmpty) contentLines += 1;
    if (showWeather && weather.isNotEmpty) contentLines += 1;

    final int panelH = 40 + (contentLines * 24);
    // Untuk image 3.0.5, kita gunakan img.getColor untuk membuat warna dengan opacity
    final img.Color bgColor = img.getColor(0, 0, 0, (opacity * 255).toInt());

    img.fillRect(src, panelX, panelY, panelX + panelW, panelY + panelH, bgColor);
    if (showBorder) {
      img.drawRect(src, x1: panelX, y1: panelY, x2: panelX + panelW, y2: panelY + panelH, color: kColorCyan, thickness: 2);
    }

    int textY = panelY + 20;
    int textX = panelX + 15;

    img.drawString(src, img.arial14, textX, textY, '📍 SURVEY DATA', color: kColorCyan);
    textY += 28;

    img.drawLine(src, textX, textY, panelX + panelW - 15, textY, kColorCyan);
    textY += 16;

    final String dateStr = DateFormat('yyyy-MM-dd').format(timestamp);
    final String timeStr = DateFormat('HH:mm:ss').format(timestamp);
    img.drawString(src, img.arial12, textX, textY, 'Date: $dateStr', color: kColorWhite);
    textY += 20;
    img.drawString(src, img.arial12, textX, textY, 'Time: $timeStr', color: kColorWhite);
    textY += 20;

    if (hasPosition && showCoordinates && lat != null && lon != null) {
      img.drawString(src, img.arial12, textX, textY, 'Lat: ${lat.toStringAsFixed(6)}°', color: kColorWhite);
      textY += 20;
      img.drawString(src, img.arial12, textX, textY, 'Lon: ${lon.toStringAsFixed(6)}°', color: kColorWhite);
      textY += 20;
      if (showAccuracy && acc != null) {
        img.drawString(src, img.arial12, textX, textY, 'Accuracy: ±${acc.toStringAsFixed(1)}m', color: getAccuracyColor(acc));
        textY += 20;
      }
    }

    if (showAddress && address.isNotEmpty) {
      final truncated = address.length > 35 ? '${address.substring(0, 32)}...' : address;
      img.drawString(src, img.arial12, textX, textY, truncated, color: kColorLightGrey);
      textY += 20;
    }

    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, img.arial12, textX, textY, weather, color: kColorLightGrey);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }
}
