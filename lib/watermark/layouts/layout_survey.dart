// lib/watermark/layouts/layout_survey.dart
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
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
    final int panelW = 280;
    final int panelH = 200;
    final int panelX = 16;
    final int panelY = src.height - panelH - 16;
    
    for (int i = 0; i < panelH; i++) {
      for (int j = 0; j < panelW; j++) {
        img.drawPixel(src, panelX + j, panelY + i, img.ColorRgba8(0, 0, 20, 220));
      }
    }
    
    img.drawRect(src, x1: panelX, y1: panelY, x2: panelX + panelW, y2: panelY + panelH,
        color: kColorTeal, thickness: 2);
    
    int x = panelX + 16;
    int y = panelY + 16;
    
    img.drawString(src, 'SURVEY DATA', font: img.arial14, x: x, y: y, color: kColorTeal);
    y += 28;
    
    img.drawString(src, 'DATE : ${DateFormat('dd MMM yyyy').format(timestamp)}', font: img.arial14, x: x, y: y, color: kColorWhite);
    y += 24;
    img.drawString(src, 'TIME : ${DateFormat('HH:mm:ss').format(timestamp)}', font: img.arial14, x: x, y: y, color: kColorWhite);
    y += 24;
    
    if (hasPosition && lat != null && lon != null) {
      img.drawString(src, 'LATITUDE : ${lat.toStringAsFixed(6)}', font: img.arial14, x: x, y: y, color: kColorWhite);
      y += 24;
      img.drawString(src, 'LONGITUDE : ${lon.toStringAsFixed(6)}', font: img.arial14, x: x, y: y, color: kColorWhite);
      y += 24;
      
      if (showAccuracy && acc != null) {
        img.drawString(src, 'ACCURACY : ±${acc.toStringAsFixed(1)}m', font: img.arial14, x: x, y: y, color: kColorWhite);
      }
    }
    
    return WatermarkLayoutBase.encodeJpg(src);
  }
}
