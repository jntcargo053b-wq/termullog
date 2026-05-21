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
    
    img.fillCircle(src, x: src.width - margin - 12, y: y + 12, radius: 6, color: kColorRed);
    
    final String dateStr = DateFormat('yyyy-MM-dd').format(timestamp);
    final String timeStr = DateFormat('HH:mm:ss').format(timestamp);
    
    img.drawString(src, dateStr, font: img.arial14, x: x, y: y, color: kColorWhite);
    y += 24;
    img.drawString(src, timeStr, font: img.arial14, x: x, y: y, color: kColorWhite);
    y += 24;
    
    if (hasPosition && showCoordinates && lat != null && lon != null) {
      final String coordStr = '${lat.toStringAsFixed(4)}° ${lon.toStringAsFixed(4)}°';
      img.drawString(src, coordStr, font: img.arial14, x: x, y: y, color: kColorLightGrey);
    }
    
    return WatermarkLayoutBase.encodeJpg(src);
  }
}
