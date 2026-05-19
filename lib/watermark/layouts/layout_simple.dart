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
    
    // Buat font sederhana menggunakan arial (ukuran 16)
    final font = img.ArialFontData.asFont(16);
    final smallFont = img.ArialFontData.asFont(12);
    
    // Gambar teks timestamp
    img.drawString(src, '$dateStr  $timeStr', font: font, x: 10, y: yPos, color: kColorWhite);
    
    // Gambar koordinat
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      img.drawString(src, '${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°', 
          font: smallFont, x: 10, y: yPos + 25, color: kColorCyan);
    }
    
    // Gambar akurasi
    if (showAccuracy && acc != null) {
      img.drawString(src, '±${acc.toStringAsFixed(1)}m', 
          font: smallFont, x: 10, y: yPos + 45, color: kColorGrey);
    }
    
    // Gambar cuaca
    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, weather, 
          font: smallFont, x: 10, y: yPos + 65, color: kColorGold);
    }
    
    // Gambar alamat
    if (showAddress && address.isNotEmpty && address != 'Tidak ada lokasi') {
      String shortAddress = address.length > 35 ? '${address.substring(0, 32)}...' : address;
      img.drawString(src, shortAddress, 
          font: smallFont, x: 10, y: yPos + 85, color: kColorWhite70);
    }
    
    return src;
  }
  
  static Uint8List encodeJpg(img.Image image, {int quality = kJpegQuality}) {
    return Uint8List.fromList(img.encodeJpg(image, quality: quality));
  }
}
