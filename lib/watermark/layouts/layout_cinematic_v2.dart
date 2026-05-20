// lib/watermark/layouts/layout_cinematic_v2.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutCinematicV2 extends WatermarkLayoutBase {
  @override
  String get name => 'Cinematic V2';

  static const int _padX = 36;

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
    // ── Adaptive scaling ──────────────────────────────────────────
    final double scale = (src.width / 1080).clamp(0.7, 2.0);
    final double fsMultiplier = fontSize == 'small' ? 0.75 : fontSize == 'large' ? 1.4 : 1.0;

    final int gradH = (180 * scale).round();
    final int padX = (_padX * scale).round();
    final int lineH = (28 * scale * fsMultiplier).round();
    final int lineHSmall = (22 * scale * fsMultiplier).round();

    // ✅ STEP 1: Hitung Y posisi via resolveYStart — logika posisi TERPUSAT
    final int gradY0 = WatermarkLayoutBase.resolveYStart(
      watermarkPosition: watermarkPosition,
      imageHeight: src.height,
      contentHeight: gradH,
    );
    if (gradY0 < 0 || gradY0 >= src.height) return WatermarkLayoutBase.encodeJpg(src);

    // ✅ STEP 2: Gradient direction diturunkan dari Y posisi, BUKAN dari string 'top'/'bottom'
    // Ini adalah "position-aware rendering": gradient SELALU fade dari tepi gambar ke tengah.
    // isTopEdge dihitung dari posisi Y, bukan membandingkan string watermarkPosition.
    final bool isTopEdge = WatermarkLayoutBase.isAtTopEdge(gradY0, src.height);

    // ── Gradient background ───────────────────────────────────────
    _applyGradient(src, gradY0: gradY0, gradH: gradH, isTop: isTopEdge, opacity: opacity);

    // ── Divider line ──────────────────────────────────────────────
    final int divY = isTopEdge ? gradH - (40 * scale).round() : gradY0 + (36 * scale).round();
    if (showBorder) {
      // Glow
      img.fillRect(src, x1: padX - 2, y1: divY - 1, x2: src.width - padX + 2, y2: divY + 3,
          color: img.ColorRgba8(30, 144, 255, 40));
      // Main line
      img.fillRect(src, x1: padX, y1: divY, x2: src.width - padX, y2: divY + 2,
          color: img.ColorRgba8(30, 144, 255, 200));
    }

    // ── Pilih font ────────────────────────────────────────────────
    final font = fontSize == 'small' ? img.arial14 : img.arial24;
    final fontSmall = fontSize == 'small' ? img.arial14 : img.arial24;

    int cy = isTopEdge ? (16 * scale).round() : gradY0 + (12 * scale).round();

    // ── Jam (dengan shadow) ───────────────────────────────────────
    _shadowText(src, DateFormat('HH : mm : ss').format(timestamp),
        font: font, x: padX, y: cy, color: WatermarkLayoutBase.white);
    cy += lineH;

    // ── Tanggal ───────────────────────────────────────────────────
    _shadowText(src, DateFormat('dd  MMMM  yyyy').format(timestamp),
        font: font, x: padX, y: cy, color: WatermarkLayoutBase.blue);
    cy += lineH + (8 * scale).round();

    // ── Koordinat ─────────────────────────────────────────────────
    if (showCoordinates && hasPosition) {
      img.drawString(src,
          '${lat!.toStringAsFixed(5)}°N   ${lon!.toStringAsFixed(5)}°E',
          font: fontSmall, x: padX, y: cy, color: WatermarkLayoutBase.offWhite);
      cy += lineHSmall;

      // ── Akurasi ─────────────────────────────────────────────────
      if (showAccuracy) {
        img.drawString(src,
            'ACCURACY  ±${acc?.toStringAsFixed(0) ?? '?'} M',
            font: fontSmall, x: padX, y: cy, color: WatermarkLayoutBase.grey);
        cy += lineHSmall;
      }
    }

    // ── Alamat ────────────────────────────────────────────────────
    if (showAddress && address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      final maxChars = (src.width / 7).toInt().clamp(30, 55);
      final shortAddr = address.length > maxChars
          ? '${address.substring(0, maxChars - 1)}…' : address;
      img.drawString(src, shortAddr,
          font: fontSmall, x: padX, y: cy, color: WatermarkLayoutBase.grey);
      cy += lineHSmall;
    }

    // ── Cuaca ─────────────────────────────────────────────────────
    if (showWeather && weather.isNotEmpty) {
      // Chip background
      img.fillRect(src,
          x1: padX - 4, y1: cy - 2,
          x2: padX + weather.length * 7 + 12, y2: cy + lineHSmall - 4,
          color: img.ColorRgba8(30, 144, 255, 30));
      img.drawString(src, weather,
          font: fontSmall, x: padX + 4, y: cy + 2, color: WatermarkLayoutBase.blue);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  // ─── ASYNC (fallback ke sync) ──────────────────────────────────
  @override
  Future<Uint8List> applyAsync({
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
  }) async {
    return apply(
      src: src, timestamp: timestamp, hasPosition: hasPosition,
      lat: lat, lon: lon, acc: acc, address: address, weather: weather,
      showWeather: showWeather, showAccuracy: showAccuracy,
      watermarkPosition: watermarkPosition, showMiniMap: showMiniMap,
      mapBytes: mapBytes,
      showAddress: showAddress,
      showCoordinates: showCoordinates,
      opacity: opacity,
      showBorder: showBorder,
      fontSize: fontSize,
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────
  void _shadowText(img.Image src, String text, {
    required img.BitmapFont font,
    required int x, required int y,
    required img.Color color,
  }) {
    img.drawString(src, text, font: font, x: x + 1, y: y + 1,
        color: img.ColorRgba8(0, 0, 0, 120));
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  void _applyGradient(img.Image src, {
    required int gradY0,
    required int gradH,
    // ✅ isTopEdge diturunkan dari Y posisi (bukan perbandingan string langsung).
    // Gradient SELALU fade dari tepi gambar ke tengah — ini position-aware rendering,
    // BUKAN pemilihan jenis layout berdasarkan posisi.
    required bool isTopEdge,
    required double opacity,
  }) {
    for (int y = gradY0; y < gradY0 + gradH; y++) {
      if (y < 0 || y >= src.height) continue;
      final t = isTopEdge ? 1.0 - (y - gradY0) / gradH : (y - gradY0) / gradH;
      final alpha = (t * 220 * opacity).toInt().clamp(0, 220);
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
