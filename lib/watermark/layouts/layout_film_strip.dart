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
  static const int lineH = 26;
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
  }) {
    final bool isTop = watermarkPosition == 'top';
    final int y0 = isTop ? 0 : src.height - panelH;
    if (y0 < 0) return WatermarkLayoutBase.encodeJpg(src);

    // ── Background hitam ──
    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + panelH,
        color: img.ColorRgba8(0, 0, 0, 200));

    // ── Border EMAS dengan glow ──
    // Glow atas
    img.fillRect(src, x1: 0, y1: y0 - 1, x2: src.width - 1, y2: y0 + 2,
        color: img.ColorRgba8(255, 180, 50, 30));
    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + 4,
        color: img.ColorRgba8(255, 180, 50, 255));

    // Glow bawah
    img.fillRect(src, x1: 0, y1: y0 + panelH - 3, x2: src.width - 1, y2: y0 + panelH + 1,
        color: img.ColorRgba8(255, 180, 50, 30));
    img.fillRect(src, x1: 0, y1: y0 + panelH - 4, x2: src.width - 1, y2: y0 + panelH,
        color: img.ColorRgba8(255, 180, 50, 255));

    final font = img.arial24;
    int cy = y0 + 12;

    // ── Pin merah di kiri ──
    img.fillCircle(src, x: padX + 6, y: cy + 10, radius: 5,
        color: img.ColorRgba8(255, 50, 50, 255));
    img.fillCircle(src, x: padX + 6, y: cy + 10, radius: 2,
        color: WatermarkLayoutBase.white);

    // ── Teks dengan shadow ──
    _drawWithShadow(src,
        '${DateFormat('yyyy-MM-dd').format(timestamp)}  ${DateFormat('HH:mm:ss').format(timestamp)}',
        font: font, x: padX + 16, y: cy, color: WatermarkLayoutBase.white);
    cy += lineH;

    if (hasPosition) {
      final accStr = showAccuracy ? '  ±${acc?.toStringAsFixed(0) ?? '?'}m' : '';
      _drawWithShadow(src,
          '${lat!.toStringAsFixed(6)}  ${lon!.toStringAsFixed(6)}$accStr',
          font: font, x: padX + 16, y: cy, color: img.ColorRgba8(255, 180, 50, 255));
      cy += lineH;
    }

    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      final shortAddr = address.length > maxAddrLen
          ? '${address.substring(0, maxAddrLen - 1)}…' : address;
      img.drawString(src, shortAddr, font: font, x: padX + 16, y: cy, color: WatermarkLayoutBase.grey);
      cy += lineH;
    }

    if (showWeather && weather.isNotEmpty) {
      // Chip cuaca
      img.fillRect(src, x1: padX + 12, y1: cy - 2, x2: padX + 200, y2: cy + 22,
          color: img.ColorRgba8(30, 144, 255, 30));
      img.drawString(src, weather, font: font, x: padX + 16, y: cy, color: WatermarkLayoutBase.blue);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  void _drawWithShadow(img.Image src, String text, {required img.BitmapFont font, required int x, required int y, required img.Color color}) {
    img.drawString(src, text, font: font, x: x + 1, y: y + 1, color: img.ColorRgba8(0, 0, 0, 100));
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }
}
