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
    final int barHeight = 70;
    final int yBar = src.height - barHeight;
    
    for (int i = 0; i < barHeight; i++) {
      final int alpha = (200 - (i * 2)).clamp(0, 255);
      for (int j = 0; j < src.width; j++) {
        img.drawPixel(src, j, yBar + i, img.ColorRgba8(0, 0, 0, alpha));
      }
    }
    
    final int margin = 20;
    int y = yBar + 25;
    
    final String dateTimeStr = DateFormat('dd MMM yyyy  •  HH:mm').format(timestamp);
    img.drawString(src, dateTimeStr, font: img.arial14, x: margin, y: y, color: kColorWhite);
    y += 28;
    
    if (hasPosition && showCoordinates && lat != null && lon != null) {
      final String coordStr = '📍 ${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°';
      img.drawString(src, coordStr, font: img.arial14, x: margin, y: y, color: kColorLightGrey);
    }
    
    return WatermarkLayoutBase.encodeJpg(src);
  }
}
