// lib/watermark/layouts/layout_leica.dart
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'package:image/src/font/arial_12.dart';
import 'package:image/src/font/arial_14.dart';
import 'package:image/src/font/arial_24.dart';
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
    
    // Perbaikan: fillCircle menggunakan positional parameters (versi 3.0.5)
    // Parameter: fillCircle(image, x0, y0, radius, color)
    img.fillCircle(
      src,                          // image
      src.width - margin - 12,      // x0
      y + 12,                       // y0
      6,                            // radius
      kColorRed                     // color
    );
    
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
    // Perbaikan: Menggunakan font yang sesuai dengan size
    if (size <= 12) {
      img.drawString(image, img.arial12, x, y, text, color: color);
    } else if (size <= 14) {
      img.drawString(image, img.arial14, x, y, text, color: color);
    } else {
      img.drawString(image, img.arial24, x, y, text, color: color);
    }
  }
}
