// lib/watermark/layouts/layout_dslr_corner.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

/// DSLR Corner — overlay kamera profesional. Braket sudut di 4 pojok,
/// panel info di bawah bergaya metadata EXIF kamera.
class LayoutDSLRCorner extends WatermarkLayoutBase {
  @override
  String get name => 'DSLR Corner';

  static const int _panelH = 100;
  static const int _padX   = 20;
  static const int _brLen  = 30; // panjang bracket
  static const int _brW    = 4;  // tebal bracket

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
    final int alphaBar = (opacity * 230).toInt().clamp(0, 255);

    // ── Panel bawah (info EXIF) ───────────────────────────────────
    final int panelY = h - _panelH;
    for (int row = panelY; row < h; row++) {
      final t = (row - panelY) / _panelH;
      final a = ((0.3 + t * 0.7) * alphaBar).toInt().clamp(0, 255);
      img.fillRect(src, x1: 0, y1: row, x2: w - 1, y2: row + 1,
          color: img.ColorRgba8(10, 10, 15, a));
    }

    // Garis atas panel (merah kamera)
    if (showBorder) {
      img.fillRect(src, x1: 0, y1: panelY, x2: w - 1, y2: panelY + 3,
          color: img.ColorRgba8(220, 50, 50, 255));
    }

    // ── Braket sudut ─────────────────────────────────────────────
    final int margin = 18;
    final col = img.ColorRgba8(220, 220, 220, 220);
    _bracket(src, x: margin, y: margin, right: false, bottom: false, color: col);
    _bracket(src, x: w - margin, y: margin, right: true, bottom: false, color: col);
    _bracket(src, x: margin, y: panelY - margin, right: false, bottom: true, color: col);
    _bracket(src, x: w - margin, y: panelY - margin, right: true, bottom: true, color: col);

    // ── Crosshair tengah kecil ─────────────────────────────────────
    final cx = w ~/ 2;
    final cy2 = panelY ~/ 2;
    img.fillRect(src, x1: cx - 10, y1: cy2, x2: cx + 10, y2: cy2 + 1,
        color: img.ColorRgba8(255, 255, 255, 80));
    img.fillRect(src, x1: cx, y1: cy2 - 10, x2: cx + 1, y2: cy2 + 10,
        color: img.ColorRgba8(255, 255, 255, 80));
    img.fillCircle(src, x: cx, y: cy2, radius: 4,
        color: img.ColorRgba8(220, 50, 50, 160));

    // ── Info di panel bawah ───────────────────────────────────────
    final font  = fontSize == 'large' ? img.arial24 : img.arial24;
    final small = img.arial14;

    int ty = panelY + 10;

    // Tanggal + jam di kiri
    _shadow(src, DateFormat('yyyy-MM-dd').format(timestamp),
        font: small, x: _padX, y: ty,
        color: img.ColorRgba8(180, 180, 180, 255));

    // Jam besar di kanan
    final String timeStr = DateFormat('HH:mm:ss').format(timestamp);
    final int timeW = timeStr.length * 14;
    _shadow(src, timeStr, font: font, x: w - _padX - timeW, y: ty - 4,
        color: img.ColorRgba8(255, 255, 255, 255));

    ty += 22;

    // Koordinat GPS
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final String coordStr =
          '${_toDMS(lat, true)}  ${_toDMS(lon, false)}'
          '${showAccuracy && acc != null ? '  ±${acc.toStringAsFixed(0)}m' : ''}';
      _shadow(src, coordStr, font: small, x: _padX, y: ty,
          color: img.ColorRgba8(80, 200, 255, 255));
      ty += 20;
    }

    // Alamat
    if (showAddress && _isValidAddr(address)) {
      final String short = address.length > 60
          ? '${address.substring(0, 58)}\u2026' : address;
      _shadow(src, short, font: small, x: _padX, y: ty,
          color: img.ColorRgba8(150, 150, 150, 255));
      ty += 20;
    }

    // Cuaca di pojok kanan bawah
    if (showWeather && weather.isNotEmpty) {
      final int ww = weather.length * 8;
      _shadow(src, weather, font: small, x: w - _padX - ww, y: panelY + 52,
          color: img.ColorRgba8(80, 220, 80, 255));
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  /// Gambar braket sudut
  void _bracket(img.Image src,
      {required int x, required int y, required bool right, required bool bottom,
       required img.Color color}) {
    final int dx = right ? -1 : 1;
    final int dy = bottom ? -1 : 1;
    // Garis horizontal
    img.fillRect(src,
        x1: right ? x - _brLen : x,
        y1: y,
        x2: right ? x : x + _brLen,
        y2: y + _brW * dy.abs(),
        color: color);
    // Garis vertikal
    img.fillRect(src,
        x1: right ? x - _brW : x,
        y1: bottom ? y - _brLen : y,
        x2: right ? x : x + _brW,
        y2: bottom ? y : y + _brLen,
        color: color);
  }

  void _shadow(img.Image src, String text,
      {required img.BitmapFont font, required int x, required int y,
       required img.Color color}) {
    img.drawString(src, text, font: font, x: x + 1, y: y + 1,
        color: img.ColorRgba8(0, 0, 0, 130));
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
}
