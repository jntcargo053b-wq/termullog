// lib/watermark/layouts/layout_simple.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import '../../core/constants.dart';

class LayoutSimple {
  String get name => 'Simple';

  img.Image apply({
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
    required Uint8List? mapBytes,
    required bool showAddress,
    required bool showCoordinates,
    required double opacity,
    required bool showBorder,
    required String fontSize,
  }) {
    final timeStr = DateFormat('HH:mm:ss').format(timestamp);
    final dateStr = DateFormat('dd/MM/yyyy').format(timestamp);
    final int yPos = watermarkPosition == 'bottom' ? src.height - 50 : 20;
    
    // Gunakan font default dari package image
    final defaultFont = img.getDefaultFont();
    
    // Gambar teks timestamp
    img.drawString(src, '$dateStr  $timeStr', x: 10, y: yPos, 
        color: kColorWhite, font: defaultFont);
    
    // Gambar koordinat
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      img.drawString(src, '${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°', 
          x: 10, y: yPos + 25, color: kColorCyan, font: defaultFont);
    }
    
    // Gambar akurasi
    if (showAccuracy && acc != null) {
      img.drawString(src, '±${acc.toStringAsFixed(1)}m', 
          x: 10, y: yPos + 45, color: kColorGrey, font: defaultFont);
    }
    
    // Gambar cuaca
    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, weather, 
          x: 10, y: yPos + 65, color: kColorGold, font: defaultFont);
    }
    
    return src;
  }
  
  static Uint8List encodeJpg(img.Image image, {int quality = kJpegQuality}) {
    return Uint8List.fromList(img.encodeJpg(image, quality: quality));
  }
}
