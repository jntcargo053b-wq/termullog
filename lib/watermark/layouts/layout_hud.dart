// lib/watermark/layouts/layout_hud.dart
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'package:image/src/font/arial_12.dart';
import 'package:image/src/font/arial_14.dart';
import 'package:image/src/font/arial_24.dart';
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
    
    // Semi-transparent background
    for (int i = 0; i < 120; i++) {
      for (int j = 0; j < 200; j++) {
        img.drawPixel(src, x + j, y + i, img.getColor(0, 0, 0, 180));
      }
    }
    
    // Cyan border
    img.drawRect(src, x1: x, y1: y, x2: x + 200, y2: y + 120, color: kColorCyan, thickness: 1);
    
    y += 16;
    x += 12;
    
    // Time (large cyan)
    final String timeStr = DateFormat('HH:mm:ss').format(timestamp);
    img.drawString(src, img.arial24, x, y, timeStr, color: kColorCyan);
    y += 32;
    
    // Date
    final String dateStr = DateFormat('dd MMM yyyy').format(timestamp);
    img.drawString(src, img.arial14, x, y, dateStr, color: kColorCyan);
    y += 24;
    
    // Coordinates
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
