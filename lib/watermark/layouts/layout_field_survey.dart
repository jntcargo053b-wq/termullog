// lib/watermark/layouts/layout_field_survey.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

/// Field Survey — gaya teknik lapangan. Panel amber/oranye,
/// data terstruktur seperti form survei, koordinat DMS presisi.
class LayoutFieldSurvey extends WatermarkLayoutBase {
  @override
  String get name => 'Field Survey';

  static const int _padX  = 16;
  static const int _padY  = 12;
  static const int _rowH  = 22;

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

    // Hitung tinggi panel sesuai konten
    int rows = 2; // timestamp + separator
    if (showCoordinates && hasPosition) rows += 1;
    if (showAccuracy && hasPosition) rows += 1;
    if (showAddress && _isValidAddr(address)) rows += 2;
    if (showWeather && weather.isNotEmpty) rows += 1;
    final int panelH = _padY * 2 + rows * _rowH + 10;

    final bool isTop = watermarkPosition == 'top';
    final int y0 = isTop ? 0 : h - panelH;
    if (y0 < 0 || y0 >= h) return WatermarkLayoutBase.encodeJpg(src);

    final int alphaMain = (opacity * 245).toInt().clamp(0, 255);

    // ── Background panel gelap ─────────────────────────────────────
    img.fillRect(src, x1: 0, y1: y0, x2: w - 1, y2: y0 + panelH,
        color: img.ColorRgba8(12, 14, 18, alphaMain));

    // ── Strip amber atas/bawah ────────────────────────────────────
    final int stripH = 6;
    if (showBorder) {
      img.fillRect(src, x1: 0, y1: isTop ? y0 + panelH - stripH : y0,
          x2: w - 1,
          y2: isTop ? y0 + panelH : y0 + stripH,
          color: img.ColorRgba8(245, 160, 30, 255));
      // Diagonal stripe pattern pada strip
      for (int sx = 0; sx < w; sx += 20) {
        img.drawLine(src,
            x1: sx, y1: isTop ? y0 + panelH - stripH : y0,
            x2: sx + stripH, y2: isTop ? y0 + panelH : y0 + stripH,
            color: img.ColorRgba8(0, 0, 0, 80), thickness: 2);
      }
    }

    // ── Tag "FIELD SURVEY" di pojok ───────────────────────────────
    final int tagX = w - 98 - _padX;
    img.fillRect(src,
        x1: tagX - 4, y1: y0 + _padY - 2,
        x2: tagX + 96, y2: y0 + _padY + 14,
        color: img.ColorRgba8(245, 160, 30, 255));
    img.drawString(src, 'FIELD SURVEY',
        font: img.arial14, x: tagX, y: y0 + _padY,
        color: img.ColorRgba8(10, 10, 10, 255));

    final small = img.arial14;
    final big   = fontSize == 'large' ? img.arial24 : img.arial24;

    // ── Baris konten ─────────────────────────────────────────────
    int cy = y0 + _padY;

    // Timestamp
    _label(src, 'WAKTU', x: _padX, y: cy, color: img.ColorRgba8(245, 160, 30, 200));
    _shadow(src,
        DateFormat('HH:mm:ss').format(timestamp),
        font: big, x: _padX + 60, y: cy - 3,
        color: img.ColorRgba8(255, 255, 255, 255));
    cy += 30;

    // Tanggal
    _label(src, 'TANGGAL', x: _padX, y: cy, color: img.ColorRgba8(245, 160, 30, 200));
    _shadow(src,
        DateFormat('dd/MM/yyyy').format(timestamp),
        font: small, x: _padX + 68, y: cy,
        color: img.ColorRgba8(220, 220, 220, 255));
    cy += _rowH;

    // Garis separator
    img.fillRect(src, x1: _padX, y1: cy, x2: w - _padX, y2: cy + 1,
        color: img.ColorRgba8(245, 160, 30, 60));
    cy += 8;

    // Koordinat
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      _label(src, 'LAT/LON', x: _padX, y: cy, color: img.ColorRgba8(245, 160, 30, 200));
      _shadow(src,
          '${_toDMS(lat, true)}  ${_toDMS(lon, false)}',
          font: small, x: _padX + 68, y: cy,
          color: img.ColorRgba8(80, 210, 255, 255));
      cy += _rowH;
    }

    if (showAccuracy && hasPosition && acc != null) {
      _label(src, 'AKURASI', x: _padX, y: cy, color: img.ColorRgba8(245, 160, 30, 200));
      _shadow(src, '\u00b1${acc.toStringAsFixed(1)} meter',
          font: small, x: _padX + 68, y: cy,
          color: img.ColorRgba8(180, 180, 180, 255));
      cy += _rowH;
    }

    if (showAddress && _isValidAddr(address)) {
      _label(src, 'LOKASI', x: _padX, y: cy, color: img.ColorRgba8(245, 160, 30, 200));
      final parts = _splitAddr(address, (w ~/ 8) - 10);
      for (final line in parts.take(2)) {
        _shadow(src, line, font: small, x: _padX + 68, y: cy,
            color: img.ColorRgba8(190, 190, 190, 255));
        cy += _rowH - 2;
      }
      cy += 2;
    }

    if (showWeather && weather.isNotEmpty) {
      _label(src, 'CUACA', x: _padX, y: cy, color: img.ColorRgba8(245, 160, 30, 200));
      _shadow(src, weather, font: small, x: _padX + 68, y: cy,
          color: img.ColorRgba8(100, 220, 120, 255));
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  void _label(img.Image src, String text,
      {required int x, required int y, required img.Color color}) {
    img.drawString(src, text, font: img.arial14, x: x, y: y, color: color);
  }

  void _shadow(img.Image src, String text,
      {required img.BitmapFont font, required int x, required int y,
       required img.Color color}) {
    img.drawString(src, text, font: font, x: x + 1, y: y + 1,
        color: img.ColorRgba8(0, 0, 0, 120));
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  bool _isValidAddr(String a) =>
      a.isNotEmpty && a != 'Tidak ada lokasi' && !a.startsWith('GPS:');

  String _toDMS(double coord, bool isLat) {
    final d = coord.abs().floor();
    final m = ((coord.abs() - d) * 60).floor();
    final s = ((coord.abs() - d - m / 60) * 3600).toStringAsFixed(1);
    final dir = isLat ? (coord >= 0 ? 'N' : 'S') : (coord >= 0 ? 'E' : 'W');
    return '$d\u00b0$m\'$s"$dir';
  }

  List<String> _splitAddr(String text, int max) {
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
