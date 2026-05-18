// lib/watermark/layouts/layout_nama_baru.dart
//
// ═══════════════════════════════════════════════════════════════════
//  LAYOUT: Modern Clean Card
//  Desain bersih, background navy gelap, accent bar vertikal teal,
//  tanpa garis keras, tipografi tersusun rapi — tidak ada panel hitam
// ═══════════════════════════════════════════════════════════════════

import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutNamaBaru extends WatermarkLayoutBase {
  @override
  String get name => 'Modern Clean Card';

  // ── Konstanta layout ─────────────────────────────────────────────
  static const int _panelH   = 140;  // tinggi panel watermark
  static const int _accentW  = 4;    // lebar accent bar vertikal
  static const int _accentGap = 12;  // jarak accent → teks
  static const int _padX     = 16;   // padding horizontal luar
  static const int _padY     = 14;   // padding vertikal
  static const int _lineH    = 26;   // baris teks utama
  static const int _lineS    = 20;   // baris teks sekunder
  static const int _mapSz    = 100;  // ukuran mini map
  static const int _maxAddr  = 50;   // maks karakter per baris alamat

  // ── Palet warna (tidak ada pure black / garis kasar) ────────────
  //   Background : Navy gelap lembut #0D1117 → #141E2E
  //   Accent     : Electric Teal #00D4AA
  //   Teks utama : Putih bersih
  //   Teks sub   : Abu-abu kebiruan
  //   Highlight  : Cyan #00B8D4

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
    final int y0     = isTop ? 0 : src.height - _panelH;
    if (y0 < 0 || y0 >= src.height) return WatermarkLayoutBase.encodeJpg(src);

    final int w = src.width;

    // ── 1. Gradient background navy (bukan hitam datar) ──────────
    _gradientBg(src, y0: y0, w: w, isTop: isTop);

    // ── 2. Accent bar vertikal teal di sisi kiri ─────────────────
    final int barX  = _padX;
    final int barY1 = y0 + _padY;
    final int barY2 = y0 + _panelH - _padY;

    // Glow lembut di belakang bar
    img.fillRect(src,
        x1: barX - 1, y1: barY1 + 6,
        x2: barX + _accentW + 2, y2: barY2 - 6,
        color: img.ColorRgba8(0, 212, 170, 45));
    // Bar utama
    img.fillRect(src,
        x1: barX, y1: barY1,
        x2: barX + _accentW - 1, y2: barY2,
        color: img.ColorRgba8(0, 212, 170, 255));

    // ── 3. Area teks ──────────────────────────────────────────────
    final int textX = barX + _accentW + _accentGap;

    // Cadangkan ruang untuk mini map jika aktif
    final bool hasMap = showMiniMap && mapBytes != null && mapBytes.isNotEmpty;
    final int mapReserve = hasMap ? (_mapSz + 20) : 0;
    final int textEndX   = w - _padX - mapReserve;

    int cy = y0 + _padY;

    // ── Baris 1: Tanggal (kiri) + Jam besar (kanan) ───────────────
    final String dateStr = DateFormat('EEE, dd MMM yyyy').format(timestamp);
    final String timeStr = DateFormat('HH:mm:ss').format(timestamp);

    _txt(src, dateStr,
        font: img.arial14, x: textX, y: cy + 5,
        color: img.ColorRgba8(160, 175, 195, 255));

    // Jam → cetak sedekat mungkin ke tepi kanan area teks
    final int timeX = (textEndX - timeStr.length * 8).clamp(textX + 100, textEndX - 10);
    _txt(src, timeStr,
        font: img.arial24, x: timeX, y: cy,
        color: img.ColorRgba8(245, 248, 255, 255),
        shadow: true);

    cy += _lineH;

    // ── Divider sangat tipis ──────────────────────────────────────
    img.fillRect(src,
        x1: textX, y1: cy,
        x2: textEndX - 8, y2: cy + 1,
        color: img.ColorRgba8(255, 255, 255, 20));
    cy += 7;

    // ── Baris 2: Koordinat GPS ────────────────────────────────────
    if (hasPosition && lat != null && lon != null) {
      // Titik kecil teal sebagai marker (bukan lingkaran besar)
      img.fillCircle(src,
          x: textX - 7, y: cy + 6, radius: 3,
          color: img.ColorRgba8(0, 212, 170, 255));

      final String coord =
          '${_fmtLat(lat)}   ${_fmtLon(lon)}';
      _txt(src, coord,
          font: img.arial14, x: textX, y: cy,
          color: img.ColorRgba8(0, 184, 212, 255),
          shadow: true);
      cy += _lineS;

      if (showAccuracy && acc != null) {
        _txt(src, 'Akurasi  ±${acc.toStringAsFixed(0)} m',
            font: img.arial14, x: textX, y: cy,
            color: img.ColorRgba8(130, 150, 170, 255));
        cy += _lineS;
      }
    }

    // ── Baris 3: Alamat ───────────────────────────────────────────
    if (address.isNotEmpty &&
        address != 'Tidak ada lokasi' &&
        !address.startsWith('GPS:')) {
      for (final line in _wrapAddr(address, _maxAddr).take(2)) {
        if (cy > y0 + _panelH - 12) break;
        _txt(src, line,
            font: img.arial14, x: textX, y: cy,
            color: img.ColorRgba8(160, 175, 195, 255));
        cy += 18;
      }
    }

    // ── Baris 4: Cuaca ────────────────────────────────────────────
    if (showWeather && weather.isNotEmpty && cy < y0 + _panelH - 12) {
      // Chip latar sangat tipis
      img.fillRect(src,
          x1: textX - 3, y1: cy - 2,
          x2: textX + weather.length * 7 + 6, y2: cy + 16,
          color: img.ColorRgba8(0, 184, 212, 22));
      _txt(src, weather,
          font: img.arial14, x: textX, y: cy,
          color: img.ColorRgba8(0, 184, 212, 255));
    }

    // ── 4. Mini Map ───────────────────────────────────────────────
    if (hasMap) {
      _miniMap(src, mapBytes: mapBytes!, y0: y0, w: w);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  // ─────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────

  void _gradientBg(img.Image src,
      {required int y0, required int w, required bool isTop}) {
    // Navy gelap: r=13 g=17 b=23 → r=20 g=27 b=40
    for (int row = y0; row < y0 + _panelH; row++) {
      if (row < 0 || row >= src.height) continue;
      final double t = isTop
          ? (row - y0) / _panelH
          : 1.0 - (row - y0) / _panelH;
      final int r = _lerp(13, 20, t);
      final int g = _lerp(17, 27, t);
      final int b = _lerp(23, 40, t);
      final int a = _lerp(232, 190, t);
      img.fillRect(src,
          x1: 0, y1: row, x2: w - 1, y2: row + 1,
          color: img.ColorRgba8(r, g, b, a));
    }
  }

  void _txt(img.Image src, String text, {
    required img.BitmapFont font,
    required int x, required int y,
    required img.Color color,
    bool shadow = false,
  }) {
    if (shadow) {
      img.drawString(src, text, font: font,
          x: x + 1, y: y + 1,
          color: img.ColorRgba8(0, 0, 0, 100));
    }
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  void _miniMap(img.Image src, {
    required Uint8List mapBytes, required int y0, required int w,
  }) {
    try {
      final m = img.decodeImage(mapBytes);
      if (m == null) return;
      final resized = img.copyResize(m, width: _mapSz, height: _mapSz);
      final int mx = w - _mapSz - _padX;
      final int my = y0 + (_panelH - _mapSz) ~/ 2;
      if (mx < 0 || my < 0) return;
      // Frame accent
      img.fillRect(src,
          x1: mx - 2, y1: my - 2,
          x2: mx + _mapSz + 1, y2: my + _mapSz + 1,
          color: img.ColorRgba8(0, 212, 170, 180));
      img.compositeImage(src, resized,
          dstX: mx, dstY: my, blend: img.BlendMode.alpha);
      // Inner glow tipis
      img.drawRect(src,
          x1: mx, y1: my,
          x2: mx + _mapSz - 1, y2: my + _mapSz - 1,
          color: img.ColorRgba8(255, 255, 255, 15), thickness: 1);
    } catch (_) {}
  }

  String _fmtLat(double v) =>
      '${v.abs().toStringAsFixed(5)}° ${v >= 0 ? "N" : "S"}';

  String _fmtLon(double v) =>
      '${v.abs().toStringAsFixed(5)}° ${v >= 0 ? "E" : "W"}';

  List<String> _wrapAddr(String text, int max) {
    if (text.length <= max) return [text];
    final parts = text.split(',');
    if (parts.length >= 2) {
      final l1   = parts.take(2).join(',').trim();
      final rest = parts.skip(2).join(',').trim();
      final l2   = rest.length > max ? '${rest.substring(0, max - 1)}…' : rest;
      return [l1, if (l2.isNotEmpty) l2];
    }
    return ['${text.substring(0, max - 1)}…'];
  }

  int _lerp(int a, int b, double t) =>
      (a + (b - a) * t).round().clamp(0, 255);
}
