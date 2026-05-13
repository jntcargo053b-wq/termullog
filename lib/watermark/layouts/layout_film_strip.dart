
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutFilmStrip extends WatermarkLayoutBase {
  @override
  String get name => 'Film Strip';
  
  static const int lineH = 28;
  static const int borderH = 4;
  static const int padX = 24;
  static const int maxAddressLen = 55;

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
  }) {
    int rows = 3;
    if (hasPosition) rows++;
    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) rows++;
    if (showWeather && weather.isNotEmpty) rows++;

    final int stripH = borderH + rows * lineH + 10;
    final bool isTop = watermarkPosition == 'top';
    final int y0 = isTop ? 0 : src.height - stripH;
    if (y0 < 0) return WatermarkLayoutBase.encodeJpg(src);

    // Background strip
    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: src.height - 1,
        color: img.ColorRgba8(0, 0, 8, 255));
    
    // Border atas dan bawah
    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + borderH, color: WatermarkLayoutBase.blue);
    img.fillRect(src, x1: 0, y1: src.height - borderH, x2: src.width - 1, y2: src.height - 1, color: WatermarkLayoutBase.blue);
    
    // Recording dot
    img.fillCircle(src, x: padX + 6, y: y0 + borderH + 18, radius: 7,
        color: img.ColorRgba8(220, 30, 30, 255));

    final font = img.arial24;
    int cy = y0 + borderH + 10;

    // Date & Time
    img.drawString(src, 
      '   ${DateFormat('yyyy-MM-dd').format(timestamp)}  ${DateFormat('HH:mm:ss').format(timestamp)}',
      font: font, x: padX, y: cy, color: WatermarkLayoutBase.white);
    cy += lineH;

    // GPS Coordinates
    if (hasPosition) {
      final accStr = showAccuracy ? '  ±${acc?.toStringAsFixed(0) ?? '?'}m' : '';
      img.drawString(src,
          '${lat!.toStringAsFixed(6)}  ${lon!.toStringAsFixed(6)}$accStr',
          font: font, x: padX, y: cy, color: WatermarkLayoutBase.blue);
      cy += lineH;
    }

    // Address
    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      String shortAddr = address.length > maxAddressLen 
          ? '${address.substring(0, maxAddressLen - 1)}…' : address;
      img.drawString(src, shortAddr, font: font, x: padX, y: cy, color: WatermarkLayoutBase.grey);
      cy += lineH;
    }

    // Weather
    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, weather, font: font, x: padX, y: cy, color: WatermarkLayoutBase.blue);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }
}
