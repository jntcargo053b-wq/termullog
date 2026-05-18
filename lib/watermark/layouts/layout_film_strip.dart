// lib/watermark/layouts/layout_film_strip.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutFilmStrip extends WatermarkLayoutBase {
  @override
  String get name => 'Film Strip';

  static const int panelH = 120;
  static const int padX = 24;
  static const int lineH = 32;
  static const int maxAddrLen = 42;

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
    final bool isTop = watermarkPosition == 'top';
    final int y0 = isTop ? 0 : src.height - panelH;
    if (y0 < 0) return WatermarkLayoutBase.encodeJpg(src);

    // Background hitam
    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + panelH,
        color: img.ColorRgba8(0, 0, 0, 220));

    // Border emas
    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + 6,
        color: img.ColorRgba8(255, 180, 50, 255));
    img.fillRect(src, x1: 0, y1: y0 + panelH - 6, x2: src.width - 1, y2: y0 + panelH,
        color: img.ColorRgba8(255, 180, 50, 255));

    int cy = y0 + 14;
    // Gunakan fontSize untuk memilih font (contoh sederhana)
    final font = fontSize == 'small' ? img.arial14 : fontSize == 'large' ? img.arial24 : img.arial24;
    final int actualLineH = fontSize == 'small' ? 22 : fontSize == 'large' ? 36 : lineH;

    img.drawString(src, DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp),
        font: font, x: padX, y: cy, color: WatermarkLayoutBase.white);
    cy += actualLineH;

    if (hasPosition && showCoordinates) {
      img.drawString(src, '${lat!.toStringAsFixed(6)}  ${lon!.toStringAsFixed(6)}',
          font: font, x: padX, y: cy, color: img.ColorRgba8(255, 180, 50, 255));
      cy += actualLineH;
    }

    if (showAddress && address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      final shortAddr = address.length > maxAddrLen
          ? '${address.substring(0, maxAddrLen - 1)}…' : address;
      img.drawString(src, shortAddr, font: font, x: padX, y: cy, color: WatermarkLayoutBase.grey);
      cy += actualLineH;
    }

    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, weather, font: font, x: padX, y: cy, color: WatermarkLayoutBase.blue);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }
}
