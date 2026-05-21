// lib/watermark/layouts/layout_documentary.dart
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
    // Bottom bar
    final int barHeight = 70;
    final int yBar = src.height - barHeight;
    
    // Dark gradient bar
    for (int i = 0; i < barHeight; i++) {
      final int alpha = (200 - (i * 2)).clamp(0, 255);
      for (int j = 0; j < src.width; j++) {
        img.drawPixel(src, j, yBar + i, img.ColorRgba8(0, 0, 0, alpha));
      }
    }
    
    final int margin = 20;
    int y = yBar + 25;
    
    // Date and time
    final String dateTimeStr = DateFormat('dd MMM yyyy  •  HH:mm').format(timestamp);
    _drawText(src, dateTimeStr, margin, y, 14, kColorWhite);
    y += 28;
    
    // Coordinates
    if (hasPosition && showCoordinates && lat != null && lon != null) {
      final String coordStr = '📍 ${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°';
      _drawText(src, coordStr, margin, y, 12, kColorLightGrey);
      y += 24;
    }
    
    // Weather
    if (showWeather && weather.isNotEmpty) {
      _drawText(src, '☁️ $weather', margin, y, 12, kColorLightGrey);
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
