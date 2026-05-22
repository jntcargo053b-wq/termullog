// lib/watermark/layouts/layout_dslr_corner.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

/// Layout DSLR Corner — pojok bergaya metadata kamera DSLR profesional.
/// Card panel dengan aksen merah, jam besar, tanggal, koordinat, alamat
/// dan bracket sudut bergaya optical viewfinder.
class LayoutDSLRCorner extends WatermarkLayoutBase {
  @override
  String get name => 'DSLR Corner';

  static const int _accentH   = 4;
  static const int _bracketSz = 10;
  static const int _bracketTh = 2;
  static const int _sepH      = 1;

  static final _red    = img.ColorRgba8(220,  45,  45, 255);
  static final _amber  = img.ColorRgba8(255, 180,  40, 255);
  static final _cyan   = img.ColorRgba8( 80, 210, 240, 255);
  static final _dim    = img.ColorRgba8(140, 145, 155, 255);
  static final _white  = img.ColorRgba8(240, 242, 245, 255);

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
    required bool showMiniMap,
    Uint8List? mapBytes,
    bool showAddress    = true,
    bool showCoordinates = true,
    double opacity      = 0.85,
    bool showBorder     = true,
    String fontSize     = 'normal',
  }) {
    // ── Adaptive scaling ──────────────────────────────────────────
    final double scale = (src.width / 1080).clamp(0.7, 2.0);

    // ── Pilih font + hitung ukuran dinamis ────────────────────────
    final bool isLargeFont = fontSize == 'large';
    final bool isSmallFont = fontSize == 'small';
    final img.BitmapFont fontL = img.arial24; // jam (selalu arial24)
    final img.BitmapFont fontS = isSmallFont ? img.arial14 : img.arial24;

    // Padding & margin ikut skala foto
    final int padX = (14 * scale).round();
    final int padY = (10 * scale).round();

    // Tinggi baris: ikut fontSize + skala
    final int lHL = isLargeFont ? (38 * scale).round()
        : isSmallFont ? (20 * scale).round()
        : (28 * scale).round();
    final int lH  = isLargeFont ? (28 * scale).round()
        : isSmallFont ? (16 * scale).round()
        : (20 * scale).round();
    final int sepSpace = (5 * scale).round();

    // ── Hitung jumlah baris ──────────────────────────────────────
    int rowCount = 2 + 1; // jam + tanggal + sep1
    if (showCoordinates && hasPosition) rowCount += 2;
    if (showAccuracy && hasPosition) rowCount += 1;
    if ((showCoordinates || showAccuracy) && hasPosition &&
        (showAddress && _cleanAddr(address).isNotEmpty || (showWeather && weather.isNotEmpty))) {
      rowCount += 1; // sep2
    }
    final cleanAddr = _cleanAddr(address);
    if (showAddress && cleanAddr.isNotEmpty) {
      rowCount += _splitAddr(cleanAddr, (src.width * 0.25).toInt()).length;
    }
    if (showWeather && weather.isNotEmpty) rowCount += 1;

    // ── Hitung tinggi card ───────────────────────────────────────
    final int innerH = lHL + lH + _sepH + sepSpace
        + (showCoordinates && hasPosition ? lH * 2 : 0)
        + (showAccuracy && hasPosition ? lH : 0)
        + ((showCoordinates || showAccuracy) && hasPosition &&
           (showAddress && cleanAddr.isNotEmpty || (showWeather && weather.isNotEmpty))
           ? _sepH + sepSpace : 0)
        + (showAddress && cleanAddr.isNotEmpty
            ? _splitAddr(cleanAddr, (src.width * 0.25).toInt()).length * lH : 0)
        + (showWeather && weather.isNotEmpty ? lH : 0);

    final int cardH = _accentH + padY * 2 + innerH + 6;

    // ── Lebar card: proporsional thd lebar foto & fontSize ───────
    final int cardW = isLargeFont
        ? (src.width * 0.50).clamp(320, 460).toInt()
        : isSmallFont
            ? (src.width * 0.30).clamp(180, 280).toInt()
            : (src.width * 0.38).clamp(220, 340).toInt();

    // ── Posisi ───────────────────────────────────────────────────
    final bool isTop = false;
    final int margin = (src.width * 0.02).clamp(8, 20).toInt();
    final int cx = src.width - cardW - margin;
    final int cy = isTop ? margin : src.height - cardH - margin;
    if (cx < 0 || cy < 0 || cy + cardH > src.height) {
      return WatermarkLayoutBase.encodeJpg(src);
    }

    final int alpha = (opacity * 235).round().clamp(0, 255);

    // ── Gradient latar ───────────────────────────────────────────
    for (int row = cy + _accentH; row < cy + cardH; row++) {
      final double t = (row - cy - _accentH) / (cardH - _accentH);
      final int r = _lerp(8, 18, t);
      final int g = _lerp(10, 20, t);
      final int b = _lerp(14, 30, t);
      final int a = (alpha * (1.0 - t * 0.08)).round().clamp(0, 255);
      img.fillRect(src, x1: cx, y1: row, x2: cx + cardW - 1, y2: row + 1,
          color: img.ColorRgba8(r, g, b, a));
    }

    // ── Aksen merah ──────────────────────────────────────────────
    img.fillRect(src, x1: cx, y1: cy, x2: cx + cardW - 1, y2: cy + _accentH - 1, color: _red);
    img.fillRect(src, x1: cx, y1: cy, x2: cx + 20, y2: cy + _accentH - 1,
        color: img.ColorRgba8(255, 100, 100, 255));

    // ── Border ───────────────────────────────────────────────────
    if (showBorder) {
      img.drawRect(src, x1: cx, y1: cy, x2: cx + cardW - 1, y2: cy + cardH - 1,
          color: img.ColorRgba8(255, 255, 255, 35), thickness: 1);
    }

    // ── Bracket ──────────────────────────────────────────────────
    _drawBrackets(src, cx: cx, cy: cy, w: cardW, h: cardH);

    // ── Teks ─────────────────────────────────────────────────────
    final int tx = cx + padX;
    int ty = cy + _accentH + padY;

    // Jam
    final String timeStr = DateFormat('HH:mm:ss').format(timestamp);
    _shadow(src, timeStr, font: fontL, x: tx, y: ty, color: _white);

    // REC
    final int recX = cx + cardW - (isSmallFont ? 28 : 38);
    img.fillRect(src, x1: recX - 2, y1: ty + 2, x2: recX + 26, y2: ty + 16,
        color: img.ColorRgba8(180, 20, 20, 180));
    img.drawString(src, 'REC', font: fontS, x: recX, y: ty + 2, color: _white);
    img.fillCircle(src, x: recX - 8, y: ty + 9, radius: 4,
        color: img.ColorRgba8(255, 50, 50, 255));
    ty += lHL;

    // Tanggal
    final String dateStr = DateFormat('yyyy:MM:dd').format(timestamp);
    _shadow(src, dateStr, font: fontS, x: tx, y: ty, color: _amber);
    final String dayStr = DateFormat('EEE').format(timestamp).toUpperCase();
    _shadow(src, dayStr, font: fontS,
        x: cx + cardW - dayStr.length * 7 - padX, y: ty, color: _dim);
    ty += lH;

    // Sep1
    _sep(src, x1: tx, x2: cx + cardW - padX, y: ty);
    ty += _sepH + sepSpace;

    // Koordinat
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      _label(src, 'LAT', x: tx, y: ty, fontS: fontS);
      _shadow(src, _fmtCoord(lat, isLat: true), font: fontS, x: tx + 30, y: ty, color: _cyan);
      ty += lH;
      _label(src, 'LON', x: tx, y: ty, fontS: fontS);
      _shadow(src, _fmtCoord(lon, isLat: false), font: fontS, x: tx + 30, y: ty, color: _cyan);
      ty += lH;
    } else if (!hasPosition) {
      _shadow(src, 'GPS: acquiring…', font: fontS, x: tx, y: ty, color: _dim);
      ty += lH;
    }

    // Akurasi
    if (showAccuracy && hasPosition && acc != null) {
      _label(src, 'ACC', x: tx, y: ty, fontS: fontS);
      _shadow(src, '±${acc.toStringAsFixed(0)} m', font: fontS, x: tx + 30, y: ty, color: _dim);
      ty += lH;
    }

    // Sep2
    if ((showCoordinates || showAccuracy) && hasPosition &&
        (showAddress && cleanAddr.isNotEmpty || (showWeather && weather.isNotEmpty))) {
      _sep(src, x1: tx, x2: cx + cardW - padX, y: ty);
      ty += _sepH + sepSpace;
    }

    // Alamat
    if (showAddress && cleanAddr.isNotEmpty) {
      for (final line in _splitAddr(cleanAddr, cardW - padX * 2)) {
        if (ty > cy + cardH - lH - 4) break;
        _shadow(src, line, font: fontS, x: tx, y: ty, color: _dim);
        ty += lH;
      }
    }

    // Cuaca
    if (showWeather && weather.isNotEmpty && ty < cy + cardH - 4) {
      img.fillRect(src, x1: tx - 2, y1: ty - 1,
          x2: tx + weather.length * 7 + 6, y2: ty + lH - 2,
          color: img.ColorRgba8(0, 100, 200, 40));
      _shadow(src, weather, font: fontS, x: tx, y: ty,
          color: img.ColorRgba8(120, 200, 255, 255));
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  // ─── Helpers ──────────────────────────────────────────────────
  void _shadow(img.Image src, String text, {
    required img.BitmapFont font, required int x, required int y, required img.Color color,
  }) {
    img.drawString(src, text, font: font, x: x + 1, y: y + 1, color: img.ColorRgba8(0, 0, 0, 160));
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  void _label(img.Image src, String text, {required int x, required int y, required img.BitmapFont fontS}) {
    img.drawString(src, text, font: fontS, x: x, y: y, color: img.ColorRgba8(180, 50, 50, 255));
  }

  void _sep(img.Image src, {required int x1, required int x2, required int y}) {
    img.fillRect(src, x1: x1, y1: y, x2: x2, y2: y + _sepH - 1, color: img.ColorRgba8(255, 255, 255, 25));
  }

  void _drawBrackets(img.Image src, {required int cx, required int cy, required int w, required int h}) {
    final c = img.ColorRgba8(220, 45, 45, 200);
    final sz = _bracketSz, th = _bracketTh;
    img.fillRect(src, x1: cx,      y1: cy,      x2: cx + sz, y2: cy + th, color: c);
    img.fillRect(src, x1: cx,      y1: cy,      x2: cx + th, y2: cy + sz, color: c);
    img.fillRect(src, x1: cx+w-sz, y1: cy,      x2: cx + w,  y2: cy + th, color: c);
    img.fillRect(src, x1: cx+w-th, y1: cy,      x2: cx + w,  y2: cy + sz, color: c);
    img.fillRect(src, x1: cx,      y1: cy+h-th, x2: cx + sz, y2: cy + h,  color: c);
    img.fillRect(src, x1: cx,      y1: cy+h-sz, x2: cx + th, y2: cy + h,  color: c);
    img.fillRect(src, x1: cx+w-sz, y1: cy+h-th, x2: cx + w,  y2: cy + h,  color: c);
    img.fillRect(src, x1: cx+w-th, y1: cy+h-sz, x2: cx + w,  y2: cy + h,  color: c);
  }

  String _fmtCoord(double v, {required bool isLat}) {
    final dir = isLat ? (v >= 0 ? 'N' : 'S') : (v >= 0 ? 'E' : 'W');
    return '${v.abs().toStringAsFixed(5)}° $dir';
  }

  String _cleanAddr(String raw) {
    if (raw.isEmpty || raw == 'Tidak ada lokasi' || raw.startsWith('GPS:')) return '';
    return raw;
  }

  List<String> _splitAddr(String addr, int maxWidth) {
    final int maxChars = (maxWidth / 7).toInt().clamp(20, 50);
    final parts = addr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return [];
    final l1 = parts.first;
    final rest = parts.skip(1).join(', ');
    return [
      l1.length > maxChars ? '${l1.substring(0, maxChars - 1)}…' : l1,
      if (rest.isNotEmpty)
        rest.length > maxChars ? '${rest.substring(0, maxChars - 1)}…' : rest,
    ];
  }

  int _lerp(int a, int b, double t) => (a + (b - a) * t).round().clamp(0, 255);
}
