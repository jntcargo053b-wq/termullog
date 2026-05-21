// lib/watermark/layouts/layout_leica.dart
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
    
    // Leica red dot
    img.fillCircle(src, x: src.width - margin - 12, y: y + 12, radius: 6, color: kColorRed);
    
    // Text
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
    
    // Accuracy
    if (showAccuracy && acc != null) {
      final String accStr = '±${acc.toStringAsFixed(1)}m';
      _drawText(src, accStr, x, y, 11, getAccuracyColor(acc));
    }
    
    return WatermarkLayoutBase.encodeJpg(src);
  }
  
  void _drawText(img.Image image, String text, int x, int y, int size, img.Color color) {
    if (size <= 12) {
      img.drawString(image, text, font: img.arial12, x: x, y: y, color: color);
    } else if (size <= 14) {
      img.drawString(image, text, font: img.arial14, x: x, y: y, color: color);
    } else {
      img.drawString(image, text, font: img.arial24, x: x, y: y, color: color);
    }
  }
}
