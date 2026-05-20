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
    final int panelH = 220;
    final int panelX = 16;
    final int panelY = src.height - panelH - 16;
    
    // Panel background
    for (int i = 0; i < panelH; i++) {
      for (int j = 0; j < panelW; j++) {
        img.drawPixel(src, panelX + j, panelY + i, img.ColorRgba8(0, 0, 20, 220));
      }
    }
    
    // Teal border
    img.drawRect(src, x1: panelX, y1: panelY, x2: panelX + panelW, y2: panelY + panelH,
        color: kColorTeal, thickness: 2);
    
    int x = panelX + 16;
    int y = panelY + 16;
    
    // Header
    _drawText(src, 'SURVEY DATA', x, y, 14, kColorTeal, bold: true);
    y += 28;
    
    // Rows
    _drawRow(src, 'DATE', DateFormat('dd MMM yyyy').format(timestamp), x, y);
    y += 24;
    _drawRow(src, 'TIME', DateFormat('HH:mm:ss').format(timestamp), x, y);
    y += 24;
    
    if (hasPosition && lat != null && lon != null) {
      _drawRow(src, 'LATITUDE', lat.toStringAsFixed(6), x, y);
      y += 24;
      _drawRow(src, 'LONGITUDE', lon.toStringAsFixed(6), x, y);
      y += 24;
      
      if (showAccuracy && acc != null) {
        _drawRow(src, 'ACCURACY', '±${acc.toStringAsFixed(1)}m', x, y);
        y += 24;
      }
    }
    
    if (showWeather && weather.isNotEmpty) {
      _drawRow(src, 'WEATHER', weather, x, y);
    }
    
    return WatermarkLayoutBase.encodeJpg(src);
  }
  
  void _drawRow(img.Image src, String label, String value, int x, int y) {
    _drawText(src, label, x, y, 11, kColorLightGrey);
    _drawText(src, value, x + 100, y, 11, kColorWhite);
  }
  
  void _drawText(img.Image img, String text, int x, int y, int size, img.Color color, {bool bold = false}) {
    if (size <= 12) {
      img.drawString(img, text, font: bold ? img.arial14 : img.arial12, x: x, y: y, color: color);
    } else if (size <= 14) {
      img.drawString(img, text, font: img.arial14, x: x, y: y, color: color);
    } else {
      img.drawString(img, text, font: img.arial24, x: x, y: y, color: color);
    }
  }
}
