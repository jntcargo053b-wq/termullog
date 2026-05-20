// lib/watermark/layouts/layout_cinematic.dart
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'watermark_layout_base.dart';
import '../../core/constants.dart';

class LayoutCinematic extends WatermarkLayoutBase {
  @override
  String get name => 'Cinematic';

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
    // Add cinematic letterbox bars (top and bottom)
    final int barHeight = (src.height * 0.15).toInt();
    final int imgHeight = src.height - (barHeight * 2);
    final img.Image result = img.Image(width: src.width, height: imgHeight);
    
    // Fill black background
    img.fill(result, color: img.ColorRgb8(0, 0, 0));
    
    // Copy image to center
    img.compositeImage(result, src, dstX: 0, dstY: 0);
    
    // Gold accent line at bottom
    final int yLine = imgHeight - 60;
    for (int i = -40; i <= 40; i++) {
      if (yLine + i > 0 && yLine + i < imgHeight) {
        img.drawPixel(result, (src.width ~/ 2) + i, yLine, kColorGold);
      }
    }
    
    // Draw centered text
    final int centerX = src.width ~/ 2;
    
    // Date
    final String dateStr = DateFormat('dd MMMM yyyy').format(timestamp).toUpperCase();
    _drawTextCentered(result, dateStr, centerX, imgHeight - 100, 14, kColorGold);
    
    // Time
    final String timeStr = DateFormat('HH : mm : ss').format(timestamp);
    _drawTextCentered(result, timeStr, centerX, imgHeight - 65, 36, kColorWhite);
    
    // Coordinates
    if (hasPosition && showCoordinates && lat != null && lon != null) {
      final String coordStr = '${lat.toStringAsFixed(4)}°  ${lon.toStringAsFixed(4)}°';
      _drawTextCentered(result, coordStr, centerX, imgHeight - 35, 11, kColorGold);
    }
    
    return WatermarkLayoutBase.encodeJpg(result);
  }
  
  void _drawTextCentered(img.Image img, String text, int centerX, int y, int size, img.Color color) {
    int approxWidth = text.length * (size ~/ 2);
    int x = centerX - (approxWidth ~/ 2);
    if (size <= 14) {
      img.drawString(img, text, font: img.arial14, x: x, y: y, color: color);
    } else if (size <= 24) {
      img.drawString(img, text, font: img.arial24, x: x, y: y, color: color);
    } else {
      img.drawString(img, text, font: img.arial36, x: x, y: y, color: color);
    }
  }
}
