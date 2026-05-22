// lib/watermark/layouts/layout_time_mark_style.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutTimeMarkStyle extends WatermarkLayoutBase {
  @override
  String get name => 'TimeMark Style';

  static const bool _positionBottom = true;

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
    required bool showMiniMap,
    Uint8List? mapBytes,
    bool showAddress = true,
    bool showCoordinates = true,
    double opacity = 0.85,
    bool showBorder = true,
    String fontSize = 'normal',
  }) {
    final double scale = (src.width / 1080).clamp(0.7, 2.0);
    final int pad = (16 * scale).round();
    final int cardW = (280 * scale).round();
    final int cardH = (120 * scale).round();
    final int margin = (16 * scale).round();
    final int cx = src.width - cardW - margin;
    final int cy = _positionBottom ? src.height - cardH - margin : margin;
    final img.BitmapFont fontLarge = fontSize == 'small' ? img.arial14 : img.arial24;
    final img.BitmapFont fontSmall = fontSize == 'small' ? img.arial12 : img.arial14;

    final img.Color bgColor = img.ColorRgba8(0, 0, 0, (200 * opacity).toInt());
    
    // Perbaikan: fillRect dengan named parameter 'color'
    img.fillRect(src, x1: cx, y1: cy, x2: cx + cardW, y2: cy + cardH, color: bgColor);
    
    if (showBorder) {
      // Perbaikan: drawRect dengan named parameters
      img.drawRect(src, 
          x1: cx, y1: cy, 
          x2: cx + cardW, y2: cy + cardH, 
          color: WatermarkLayoutBase.blue, 
          thickness: 1);
    }

    int y = cy + pad;
    final String timeStr = DateFormat('HH:mm:ss').format(timestamp);
    img.drawString(src, timeStr, font: fontLarge, x: cx + pad, y: y, color: WatermarkLayoutBase.white);
    y += (28 * scale).round();
    final String dateStr = DateFormat('dd MMM yyyy').format(timestamp);
    img.drawString(src, dateStr, font: fontSmall, x: cx + pad, y: y, color: WatermarkLayoutBase.grey);
    y += (20 * scale).round();
    
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final String coord = '${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°';
      img.drawString(src, coord, font: fontSmall, x: cx + pad, y: y, color: WatermarkLayoutBase.blue);
      y += (20 * scale).round();
    }
    if (showAccuracy && hasPosition && acc != null) {
      final String accStr = '±${acc.toStringAsFixed(1)}m';
      img.drawString(src, accStr, font: fontSmall, x: cx + pad, y: y, color: WatermarkLayoutBase.grey);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }
}
