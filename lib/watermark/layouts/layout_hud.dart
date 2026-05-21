// lib/watermark/layouts/layout_hud.dart
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
    
    for (int i = 0; i < 120; i++) {
      for (int j = 0; j < 220; j++) {
        img.drawPixel(src, x + j, y + i, img.ColorRgba8(0, 0, 0, 180));
      }
    }
    
    img.drawRect(src, x1: x, y1: y, x2: x + 220, y2: y + 120, color: kColorCyan, thickness: 1);
    
    y += 16;
    x += 12;
    
    final String timeStr = DateFormat('HH:mm:ss').format(timestamp);
    img.drawString(src, timeStr, font: img.arial24, x: x, y: y, color: kColorCyan);
    y += 32;
    
    final String dateStr = DateFormat('dd MMM yyyy').format(timestamp);
    img.drawString(src, dateStr, font: img.arial14, x: x, y: y, color: kColorCyan);
    y += 24;
    
    if (hasPosition && showCoordinates && lat != null && lon != null) {
      final String coordStr = '${lat.toStringAsFixed(5)}° ${lon.toStringAsFixed(5)}°';
      img.drawString(src, coordStr, font: img.arial14, x: x, y: y, color: kColorWhite);
      y += 20;
      
      if (showAccuracy && acc != null) {
        final String accStr = '±${acc.toStringAsFixed(1)}m';
        img.drawString(src, accStr, font: img.arial14, x: x, y: y, color: getAccuracyColor(acc));
      }
    }
    
    return WatermarkLayoutBase.encodeJpg(src);
  }
}
