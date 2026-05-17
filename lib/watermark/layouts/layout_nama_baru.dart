import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutNamaBaru extends WatermarkLayoutBase {
  @override
  String get name => 'Nama Layout Baru';
  
  // ============================================================
  // KONSTANTA LAYOUT (sesuaikan)
  // ============================================================
  static const int panelH = 120;       // tinggi watermark
  static const int padX = 16;          // padding horizontal
  static const int lineH = 28;         // tinggi per baris teks
  static const int maxAddrLen = 45;    // panjang maksimal alamat

  // ============================================================
  // METHOD apply() — WAJIB diimplementasikan
  // ============================================================
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

    // ── Gambar background ──────────────────────────────────────
    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + panelH,
        color: img.ColorRgba8(0, 0, 0, 200));

    // ── Gambar teks ─────────────────────────────────────────────
    final font = img.arial24;
    int cy = y0 + 10;

    img.drawString(src, DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp),
        font: font, x: padX, y: cy, color: WatermarkLayoutBase.white);
    cy += lineH;

    if (hasPosition) {
      img.drawString(src, '${lat!.toStringAsFixed(6)}, ${lon!.toStringAsFixed(6)}',
          font: font, x: padX, y: cy, color: WatermarkLayoutBase.blue);
      cy += lineH;
    }

    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      String addr = address.length > maxAddrLen 
          ? '${address.substring(0, maxAddrLen - 1)}…' : address;
      img.drawString(src, addr, font: font, x: padX, y: cy, color: WatermarkLayoutBase.grey);
      cy += lineH;
    }

    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, weather, font: font, x: padX, y: cy, color: WatermarkLayoutBase.blue);
    }

    // ── Mini map (opsional) ─────────────────────────────────────
    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) {
      try {
        final mapImage = img.decodeImage(mapBytes);
        if (mapImage != null) {
          final resized = img.copyResize(mapImage, width: 120, height: 80);
          final mapX = src.width - 120 - padX;
          final mapY = y0 + 20;
          img.compositeImage(src, resized, dstX: mapX, dstY: mapY, blend: img.BlendMode.alpha);
        }
      } catch (_) {}
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }
}
