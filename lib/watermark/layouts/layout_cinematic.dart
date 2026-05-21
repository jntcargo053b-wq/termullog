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
    img.Image canvas = img.copyResize(src, width: src.width, height: src.height);
    
    final int barHeight = (src.height * 0.15).toInt();
    
    img.fillRect(canvas, x1: 0, y1: 0, x2: src.width, y2: barHeight, color: img.ColorRgb8(0, 0, 0));
    img.fillRect(canvas, x1: 0, y1: src.height - barHeight, x2: src.width, y2: src.height, color: img.ColorRgb8(0, 0, 0));
    
    final int yLine = src.height - barHeight - 20;
    for (int i = -40; i <= 40; i++) {
      final int xPos = (src.width ~/ 2) + i;
      if (xPos >= 0 && xPos < src.width && yLine >= 0 && yLine < src.height) {
        img.drawPixel(canvas, xPos, yLine, kColorGold);
      }
    }
    
    final int centerX = src.width ~/ 2;
    final int textYBase = src.height - barHeight + 20;
    
    final String dateStr = DateFormat('dd MMMM yyyy').format(timestamp).toUpperCase();
    _drawTextCentered(canvas, dateStr, centerX, textYBase, 14, kColorGold);
    
    final String timeStr = DateFormat('HH : mm : ss').format(timestamp);
    _drawTextCentered(canvas, timeStr, centerX, textYBase + 30, 28, kColorWhite);
    
    if (hasPosition && showCoordinates && lat != null && lon != null) {
      final String coordStr = '${lat.toStringAsFixed(4)}°  ${lon.toStringAsFixed(4)}°';
      _drawTextCentered(canvas, coordStr, centerX, textYBase + 65, 12, kColorGold);
    }
    
    return WatermarkLayoutBase.encodeJpg(canvas);
  }
  
  void _drawTextCentered(img.Image image, String text, int centerX, int y, int size, img.Color color) {
    int approxWidth = text.length * (size ~/ 2);
    int x = centerX - (approxWidth ~/ 2);
    if (size <= 14) {
      img.drawString(image, text, font: img.arial14, x: x, y: y, color: color);
    } else {
      img.drawString(image, text, font: img.arial24, x: x, y: y, color: color);
    }
  }
}
