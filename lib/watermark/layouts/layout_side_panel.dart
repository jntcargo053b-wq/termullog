// lib/watermark/layouts/layout_side_panel.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

/// Side Panel — panel vertikal di sisi kanan gambar.
/// Foto dipertahankan, panel baru ditambahkan di samping kanan.
/// Warna deep purple/indigo dengan aksen lavender.
class LayoutSidePanel extends WatermarkLayoutBase {
  @override
  String get name => 'Side Panel';

  static const int _panelW = 200;
  static const int _padX   = 14;
  static const int _padY   = 18;
  static const int _lineH  = 22;

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
    bool showAddress    = true,
    bool showCoordinates = true,
    double opacity      = 0.85,
    bool showBorder     = true,
    String fontSize     = 'normal',
  }) {
    final int srcW = src.width;
    final int srcH = src.height;
    final int newW  = srcW + _panelW;

    // Canvas baru: foto asli + panel kanan
    final canvas = img.Image(width: newW, height: srcH);

    // Background seluruh canvas (gelap)
    img.fillRect(canvas, x1: 0, y1: 0, x2: newW - 1, y2: srcH - 1,
        color: img.ColorRgba8(10, 8, 22, 255));

    // Salin foto ke kiri
    img.compositeImage(canvas, src, dstX: 0, dstY: 0,
        blend: img.BlendMode.direct);

    // ── Panel kanan ───────────────────────────────────────────────
    final int px = srcW;
    final int alphaPanel = (opacity * 255).toInt().clamp(0, 255);

    for (int row = 0; row < srcH; row++) {
      final double t = row / srcH;
      final int r = _lerp(14, 28, t);
      final int g = _lerp(10, 20, t);
      final int b = _lerp(40, 70, t);
      img.fillRect(canvas, x1: px, y1: row, x2: newW - 1, y2: row + 1,
          color: img.ColorRgba8(r, g, b, alphaPanel));
    }

    // Garis pembatas foto ↔ panel
    if (showBorder) {
      img.fillRect(canvas, x1: px, y1: 0, x2: px + 3, y2: srcH,
          color: img.ColorRgba8(140, 100, 255, 200));
    }

    final small = img.arial14;
    final big   = img.arial24;

    // Header di panel: logo / nama
    final int hdrY = _padY;
    img.fillRect(canvas,
        x1: px + _padX - 2, y1: hdrY - 4,
        x2: px + _panelW - _padX, y2: hdrY + 20,
        color: img.ColorRgba8(140, 100, 255, 40));
    img.drawString(canvas, 'TERMULLOG',
        font: small, x: px + _padX, y: hdrY,
        color: img.ColorRgba8(160, 130, 255, 255));

    // Garis bawah header
    img.fillRect(canvas, x1: px + _padX, y1: hdrY + 22, x2: px + _panelW - _padX, y2: hdrY + 23,
        color: img.ColorRgba8(140, 100, 255, 120));

    int cy = hdrY + 32;

    // Jam besar
    _shadow(canvas, DateFormat('HH:mm').format(timestamp),
        font: big, x: px + _padX, y: cy,
        color: img.ColorRgba8(255, 255, 255, 255));
    cy += 28;

    // Detik
    _shadow(canvas, DateFormat('ss').format(timestamp) + '\"',
        font: small, x: px + _padX, y: cy,
        color: img.ColorRgba8(140, 100, 255, 255));
    cy += 20;

    // Tanggal
    _shadow(canvas, DateFormat('dd').format(timestamp),
        font: big, x: px + _padX, y: cy,
        color: img.ColorRgba8(220, 210, 255, 255));
    cy += 28;

    _shadow(canvas, DateFormat('MMM').format(timestamp).toUpperCase(),
        font: small, x: px + _padX, y: cy,
        color: img.ColorRgba8(160, 140, 220, 255));
    cy += 20;

    _shadow(canvas, DateFormat('yyyy').format(timestamp),
        font: small, x: px + _padX, y: cy,
        color: img.ColorRgba8(120, 100, 180, 255));
    cy += 28;

    // Separator
    img.fillRect(canvas, x1: px + _padX, y1: cy, x2: px + _panelW - _padX, y2: cy + 1,
        color: img.ColorRgba8(140, 100, 255, 80));
    cy += 12;

    // Koordinat (wrap jika perlu)
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      img.drawString(canvas, 'LAT', font: small, x: px + _padX, y: cy,
          color: img.ColorRgba8(140, 100, 255, 200));
      cy += 16;
      _shadow(canvas, '${lat.abs().toStringAsFixed(5)}\u00b0',
          font: small, x: px + _padX + 4, y: cy,
          color: img.ColorRgba8(180, 160, 255, 255));
      _shadow(canvas, lat >= 0 ? 'N' : 'S',
          font: small, x: px + _panelW - _padX - 14, y: cy,
          color: img.ColorRgba8(140, 100, 255, 255));
      cy += 20;

      img.drawString(canvas, 'LON', font: small, x: px + _padX, y: cy,
          color: img.ColorRgba8(140, 100, 255, 200));
      cy += 16;
      _shadow(canvas, '${lon.abs().toStringAsFixed(5)}\u00b0',
          font: small, x: px + _padX + 4, y: cy,
          color: img.ColorRgba8(180, 160, 255, 255));
      _shadow(canvas, lon >= 0 ? 'E' : 'W',
          font: small, x: px + _panelW - _padX - 14, y: cy,
          color: img.ColorRgba8(140, 100, 255, 255));
      cy += 22;
    }

    if (showAccuracy && hasPosition && acc != null) {
      _shadow(canvas, '\u00b1${acc.toStringAsFixed(0)}m',
          font: small, x: px + _padX, y: cy,
          color: img.ColorRgba8(120, 100, 160, 255));
      cy += 20;
    }

    // Separator
    img.fillRect(canvas, x1: px + _padX, y1: cy, x2: px + _panelW - _padX, y2: cy + 1,
        color: img.ColorRgba8(140, 100, 255, 60));
    cy += 10;

    // Alamat (wrap per kata pendek)
    if (showAddress && _isValidAddr(address)) {
      img.drawString(canvas, 'LOKASI', font: small, x: px + _padX, y: cy,
          color: img.ColorRgba8(140, 100, 255, 180));
      cy += 18;
      final int maxChars = (_panelW - _padX * 2) ~/ 8;
      for (final line in _wrapText(address, maxChars).take(4)) {
        if (cy > srcH - 40) break;
        _shadow(canvas, line, font: small, x: px + _padX, y: cy,
            color: img.ColorRgba8(160, 150, 200, 255));
        cy += 18;
      }
    }

    // Cuaca di bawah
    if (showWeather && weather.isNotEmpty) {
      final int wY = srcH - _padY - 18;
      img.fillRect(canvas,
          x1: px + _padX - 2, y1: wY - 3,
          x2: px + _panelW - _padX, y2: wY + 17,
          color: img.ColorRgba8(0, 200, 150, 20));
      _shadow(canvas, weather, font: small, x: px + _padX, y: wY,
          color: img.ColorRgba8(0, 220, 170, 255));
    }

    return WatermarkLayoutBase.encodeJpg(canvas);
  }

  void _shadow(img.Image src, String text,
      {required img.BitmapFont font, required int x, required int y,
       required img.Color color}) {
    img.drawString(src, text, font: font, x: x + 1, y: y + 1,
        color: img.ColorRgba8(0, 0, 0, 140));
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  int _lerp(int a, int b, double t) => (a + (b - a) * t).round().clamp(0, 255);
  bool _isValidAddr(String a) =>
      a.isNotEmpty && a != 'Tidak ada lokasi' && !a.startsWith('GPS:');

  List<String> _wrapText(String text, int maxLen) {
    if (maxLen < 4) maxLen = 4;
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final parts = clean.split(',');
    final lines = <String>[];
    for (final p in parts) {
      final t = p.trim();
      if (t.isEmpty) continue;
      if (t.length <= maxLen) {
        lines.add(t);
      } else {
        lines.add('${t.substring(0, maxLen - 1)}\u2026');
      }
    }
    return lines;
  }
}
