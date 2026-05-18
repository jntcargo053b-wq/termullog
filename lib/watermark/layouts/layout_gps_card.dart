// lib/watermark/layouts/layout_gps_card.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

/// GPS Card — kartu floating dengan koordinat sebagai hero element.
/// Background biru navy dengan aksen cyan, mirip UI navigasi modern.
class LayoutGpsCard extends WatermarkLayoutBase {
  @override
  String get name => 'GPS Card';

  static const int _padX  = 18;
  static const int _padY  = 14;
  static const int _lineH = 24;
  static const int _margin = 12;

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
    final w = src.width;
    final h = src.height;

    // Tinggi panel adaptif
    int lines = 2; // jam + tanggal
    if (showCoordinates && hasPosition) lines += 2; // lat + lon baris terpisah
    if (showAccuracy && hasPosition) lines += 1;
    if (showAddress && _isValidAddr(address)) lines += 2;
    if (showWeather && weather.isNotEmpty) lines += 1;
    final int panelH = _padY * 2 + lines * _lineH + 14;

    final bool isTop = watermarkPosition == 'top';
    final int y0 = isTop ? _margin : h - panelH - _margin;
    if (y0 < 0 || y0 + panelH > h) return WatermarkLayoutBase.encodeJpg(src);

    final int alphaCard = (opacity * 238).toInt().clamp(0, 255);

    // ── Card background: navy gradient ────────────────────────────
    for (int row = y0; row < y0 + panelH; row++) {
      final double t = (row - y0) / panelH;
      final int r = _lerp(8, 18, t);
      final int g = _lerp(22, 40, t);
      final int b = _lerp(55, 80, t);
      img.fillRect(src, x1: _margin, y1: row, x2: w - _margin - 1, y2: row + 1,
          color: img.ColorRgba8(r, g, b, alphaCard));
    }

    // ── Border card ───────────────────────────────────────────────
    if (showBorder) {
      img.drawRect(src,
          x1: _margin, y1: y0,
          x2: w - _margin - 1, y2: y0 + panelH - 1,
          color: img.ColorRgba8(0, 180, 240, 90), thickness: 1);
      // Glow efek kiri
      img.fillRect(src, x1: _margin, y1: y0, x2: _margin + 4, y2: y0 + panelH,
          color: img.ColorRgba8(0, 200, 255, 200));
    }

    // ── Icon pin GPS (sederhana) ──────────────────────────────────
    final int pinX = w - _margin - _padX - 20;
    final int pinY = y0 + _padY;
    img.fillCircle(src, x: pinX, y: pinY + 6, radius: 8,
        color: img.ColorRgba8(0, 200, 255, 220));
    img.fillCircle(src, x: pinX, y: pinY + 6, radius: 4,
        color: img.ColorRgba8(255, 255, 255, 220));
    // Ekor pin
    img.fillRect(src, x1: pinX - 1, y1: pinY + 13, x2: pinX + 2, y2: pinY + 20,
        color: img.ColorRgba8(0, 200, 255, 180));

    final small = img.arial14;
    final big   = img.arial24;

    int cy = y0 + _padY;
    final int textX = _margin + _padX;

    // ── Jam + tanggal ─────────────────────────────────────────────
    _shadow(src, DateFormat('HH:mm').format(timestamp),
        font: big, x: textX, y: cy,
        color: img.ColorRgba8(255, 255, 255, 255));
    _shadow(src, DateFormat('ss').format(timestamp),
        font: small, x: textX + 60, y: cy + 10,
        color: img.ColorRgba8(0, 200, 255, 255));

    cy += 30;

    _shadow(src, DateFormat('EEE, dd MMM yyyy').format(timestamp),
        font: small, x: textX, y: cy,
        color: img.ColorRgba8(140, 170, 210, 255));
    cy += _lineH;

    // Separator
    img.fillRect(src, x1: textX, y1: cy, x2: w - _margin - _padX, y2: cy + 1,
        color: img.ColorRgba8(0, 180, 240, 60));
    cy += 8;

    // ── Koordinat GPS (2 baris) ───────────────────────────────────
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      // Latitude
      img.drawString(src, 'LAT', font: small, x: textX, y: cy,
          color: img.ColorRgba8(0, 200, 255, 150));
      _shadow(src, '${lat.abs().toStringAsFixed(6)}\u00b0 ${lat >= 0 ? 'N' : 'S'}',
          font: small, x: textX + 36, y: cy,
          color: img.ColorRgba8(255, 255, 255, 255));
      cy += _lineH - 2;

      // Longitude
      img.drawString(src, 'LON', font: small, x: textX, y: cy,
          color: img.ColorRgba8(0, 200, 255, 150));
      _shadow(src, '${lon.abs().toStringAsFixed(6)}\u00b0 ${lon >= 0 ? 'E' : 'W'}',
          font: small, x: textX + 36, y: cy,
          color: img.ColorRgba8(255, 255, 255, 255));
      cy += _lineH - 2;
    }

    if (showAccuracy && hasPosition && acc != null) {
      img.drawString(src, 'ACC', font: small, x: textX, y: cy,
          color: img.ColorRgba8(0, 200, 255, 150));
      _shadow(src, '\u00b1${acc.toStringAsFixed(0)} meter',
          font: small, x: textX + 36, y: cy,
          color: img.ColorRgba8(160, 190, 220, 255));
      cy += _lineH;
    }

    // Separator
    if (showAddress && _isValidAddr(address)) {
      img.fillRect(src, x1: textX, y1: cy, x2: w - _margin - _padX, y2: cy + 1,
          color: img.ColorRgba8(0, 180, 240, 40));
      cy += 6;
    }

    // ── Alamat ────────────────────────────────────────────────────
    if (showAddress && _isValidAddr(address)) {
      final int maxLen = (w - _margin * 2 - _padX * 2) ~/ 8;
      for (final line in _splitAddr(address, maxLen).take(2)) {
        if (cy > y0 + panelH - 10) break;
        _shadow(src, line, font: small, x: textX, y: cy,
            color: img.ColorRgba8(150, 175, 210, 255));
        cy += 20;
      }
    }

    // ── Cuaca ─────────────────────────────────────────────────────
    if (showWeather && weather.isNotEmpty && cy < y0 + panelH - 10) {
      img.fillRect(src,
          x1: textX - 2, y1: cy - 2,
          x2: textX + weather.length * 8 + 4, y2: cy + 16,
          color: img.ColorRgba8(0, 200, 255, 25));
      _shadow(src, weather, font: small, x: textX, y: cy,
          color: img.ColorRgba8(0, 220, 255, 255));
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  void _shadow(img.Image src, String text,
      {required img.BitmapFont font, required int x, required int y,
       required img.Color color}) {
    img.drawString(src, text, font: font, x: x + 1, y: y + 1,
        color: img.ColorRgba8(0, 0, 0, 130));
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  int _lerp(int a, int b, double t) => (a + (b - a) * t).round().clamp(0, 255);
  bool _isValidAddr(String a) =>
      a.isNotEmpty && a != 'Tidak ada lokasi' && !a.startsWith('GPS:');

  List<String> _splitAddr(String text, int max) {
    if (max < 5) max = 5;
    if (text.length <= max) return [text];
    final parts = text.split(',');
    if (parts.length >= 2) {
      final l1 = parts.take(2).join(',').trim();
      final rest = parts.skip(2).join(',').trim();
      return [l1, if (rest.isNotEmpty)
        (rest.length > max ? '${rest.substring(0, max - 1)}\u2026' : rest)];
    }
    return ['${text.substring(0, max - 1)}\u2026'];
  }
}
