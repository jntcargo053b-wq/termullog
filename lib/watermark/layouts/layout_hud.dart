import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutHUD extends WatermarkLayoutBase {
  @override
  String get name => 'HUD';
  
  static const int padX = 36;
  static const int padY = 20;
  static const int lineH = 28;
  static const int accentH = 6;
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
    int rows = 2;
    if (hasPosition) rows += 1;
    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) rows += 1;
    if (showWeather && weather.isNotEmpty) rows += 1;

    final int panelH = padY * 2 + rows * lineH + (rows - 1) * 6 + accentH;
    final bool isTop = watermarkPosition == 'top';
    final int y0 = isTop ? 0 : src.height - panelH;
    if (y0 < 0) return WatermarkLayoutBase.encodeJpg(src);

    // Apply glass effect
    _applyGlassEffect(src, y0, panelH, isTop);

    // Top accent line
    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + 2,
        color: img.ColorRgba8(30, 144, 255, 120));
    // Bottom accent bar
    img.fillRect(src, x1: 0, y1: src.height - accentH, 
        x2: src.width - 1, y2: src.height - 1, color: WatermarkLayoutBase.blue);

    final font = img.arial24;
    int cy = y0 + padY;

    // Date & Time
    img.drawString(src,
        '${DateFormat('dd MMM yyyy').format(timestamp)}   ${DateFormat('HH:mm:ss').format(timestamp)}',
        font: font, x: padX, y: cy, color: WatermarkLayoutBase.white);
    cy += lineH + 6;

    // GPS
    if (hasPosition) {
      final accStr = showAccuracy ? '   ±${acc?.toStringAsFixed(0) ?? '?'}m' : '';
      img.drawString(src,
          '${lat!.toStringAsFixed(5)}, ${lon!.toStringAsFixed(5)}$accStr',
          font: font, x: padX, y: cy, color: WatermarkLayoutBase.blue);
      cy += lineH + 6;
    }

    // Address
    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      String sh = address.length > maxAddressLen 
          ? '${address.substring(0, maxAddressLen - 1)}…' : address;
      img.drawString(src, sh, font: font, x: padX, y: cy, color: WatermarkLayoutBase.grey);
      cy += lineH + 6;
    }

    // Weather
    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, weather, font: font, x: padX, y: cy, color: WatermarkLayoutBase.white);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  void _applyGlassEffect(img.Image src, int y0, int panelH, bool isTop) {
    final int yEnd = isTop ? y0 + panelH : src.height - accentH;
    for (int y = y0; y < yEnd; y++) {
      final progress = (y - y0) / panelH.clamp(0.0, 1.0);
      final alpha = (140 + (progress * 80)).toInt().clamp(0, 220);
      for (int x = 0; x < src.width; x++) {
        final px = src.getPixel(x, y);
        src.setPixel(x, y, img.ColorRgba8(
          ((px.r * (255 - alpha)) ~/ 255),
          ((px.g * (255 - alpha)) ~/ 255),
          ((px.b * (255 - alpha)) ~/ 255), 255));
      }
    }
  }
}
