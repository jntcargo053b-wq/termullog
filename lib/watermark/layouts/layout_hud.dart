// lib/watermark/layouts/layout_hud.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutHUD extends WatermarkLayoutBase {
  @override
  String get name => 'HUD Modern';

  static const int panelH = 140;
  static const int padX = 16;
  static const int lineH = 26;
  static const int maxAddrLen = 45;

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

    // ── Background gradient hijau ──
    for (int y = y0; y < y0 + panelH; y++) {
      final t = (y - y0) / panelH;
      final r = 0;
      final g = (40 + t * 30).toInt().clamp(0, 70);
      final b = (20 + t * 15).toInt().clamp(0, 35);
      final a = (180 + t * 50).toInt().clamp(180, 230);
      img.fillRect(src, x1: 0, y1: y, x2: src.width - 1, y2: y + 1,
          color: img.ColorRgba8(r, g, b, a));
    }

    // ── Garis aksen kiri hijau glow ──
    img.fillRect(src, x1: 0, y1: y0 - 1, x2: 2, y2: y0 + panelH,
        color: img.ColorRgba8(0, 255, 100, 40));
    img.fillRect(src, x1: 0, y1: y0, x2: 4, y2: y0 + panelH,
        color: img.ColorRgba8(0, 255, 100, 255));

    final font = img.arial24;
    int cy = y0 + 12;

    // ── Waktu — hijau terang ──
    _drawWithShadow(src, DateFormat('HH:mm:ss').format(timestamp),
        font: font, x: padX + 8, y: cy, color: img.ColorRgba8(0, 255, 100, 255));
    cy += lineH;

    // ── Tanggal — putih ──
    img.drawString(src, DateFormat('yyyy-MM-dd').format(timestamp),
        font: font, x: padX + 8, y: cy, color: WatermarkLayoutBase.white);
    cy += lineH;

    // ── Koordinat — putih ──
    if (hasPosition) {
      img.drawString(src, '${lat!.toStringAsFixed(6)}  ${lon!.toStringAsFixed(6)}',
          font: font, x: padX + 8, y: cy, color: WatermarkLayoutBase.white);
      cy += lineH;
    }

    // ── Akurasi — abu-abu ──
    if (showAccuracy && hasPosition) {
      img.drawString(src, '±${acc?.toStringAsFixed(0) ?? '?'}m',
          font: font, x: padX + 8, y: cy, color: WatermarkLayoutBase.grey);
      cy += lineH;
    }

    // ── Alamat — abu-abu ──
    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      final shortAddr = address.length > maxAddrLen
          ? '${address.substring(0, maxAddrLen - 1)}…' : address;
      img.drawString(src, shortAddr, font: font, x: padX + 8, y: cy, color: WatermarkLayoutBase.grey);
      cy += lineH;
    }

    // ── Cuaca — chip ──
    if (showWeather && weather.isNotEmpty) {
      img.fillRect(src, x1: padX + 4, y1: cy - 2, x2: padX + 180, y2: cy + 22,
          color: img.ColorRgba8(0, 255, 100, 25));
      img.drawString(src, weather, font: font, x: padX + 8, y: cy,
          color: img.ColorRgba8(0, 255, 100, 255));
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  void _drawWithShadow(img.Image src, String text, {required img.BitmapFont font, required int x, required int y, required img.Color color}) {
    img.drawString(src, text, font: font, x: x + 1, y: y + 1, color: img.ColorRgba8(0, 0, 0, 100));
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }
}
