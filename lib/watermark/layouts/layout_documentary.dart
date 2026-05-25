// lib/watermark/layouts/layout_documentary.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutDocumentary extends WatermarkLayoutBase {
  @override
  String get name => 'Documentary';

  static final _accentBlue  = img.ColorRgba8( 30, 144, 255, 255);
  static final _white        = img.ColorRgba8(240, 242, 245, 255);
  static final _lightGrey    = img.ColorRgba8(160, 170, 185, 255);
  static final _dimGrey      = img.ColorRgba8(110, 118, 130, 255);
  static final _shadow       = img.ColorRgba8(  0,   0,   0, 150);
  static final _headerBg     = img.ColorRgba8( 20,  60, 120, 230);

  static const bool _positionTop = false; // bottom-left card

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
    bool showAddress = true,
    bool showCoordinates = true,
    double opacity = 0.85,
    bool showBorder = true,
    String fontSize = 'normal',
  }) {
    final double scale = (src.width / 1080).clamp(0.7, 2.0);
    final img.BitmapFont fontL = img.arial24;
    final img.BitmapFont fontS = img.arial14;
    final int lH  = (28 * scale).round();
    final int lS  = (20 * scale).round();
    final int padX = (14 * scale).round();
    final int padY = (10 * scale).round();
    final int headerH = (32 * scale).round();

    // ── Hitung baris ──────────────────────────────────────────────
    int rows = 2; // date + time
    if (showCoordinates && hasPosition && lat != null && lon != null) rows += 1;
    if (showAccuracy && hasPosition && acc != null) rows += 1;
    if (showAddress && _validAddr(address)) rows += 2;
    if (showWeather && weather.isNotEmpty) rows += 1;

    final int innerH = headerH + padY + rows * lS + padY;
    final int cardW  = (src.width * 0.55).clamp(240.0, 420.0).toInt();
    final int cardH  = innerH;
    final int margin = (14 * scale).round();
    final int cx = margin;
    final int cy = _positionTop ? margin : src.height - cardH - margin;
    if (cy < 0 || cy + cardH > src.height) return WatermarkLayoutBase.encodeJpg(src);

    // ── Gradient latar ────────────────────────────────────────────
    for (int row = cy; row < cy + cardH; row++) {
      if (row < 0 || row >= src.height) continue;
      final double t = (row - cy) / cardH;
      final int r = _lerp(8, 16, t);
      final int g = _lerp(14, 24, t);
      final int b = _lerp(28, 40, t);
      final int a = (_lerp(240, 210, t) * opacity).toInt().clamp(0, 255);
      img.fillRect(src, x1: cx, y1: row, x2: cx + cardW, y2: row + 1,
          color: img.ColorRgba8(r, g, b, a));
    }

    // ── Header biru ───────────────────────────────────────────────
    img.fillRect(src, x1: cx, y1: cy, x2: cx + cardW, y2: cy + headerH,
        color: _headerBg);
    // Aksen kiri kuning
    img.fillRect(src, x1: cx, y1: cy, x2: cx + 4, y2: cy + headerH,
        color: img.ColorRgba8(255, 185, 30, 255));

    // Teks header
    _shadow2(src, 'DOCUMENTARY', font: fontS, x: cx + 10, y: cy + (headerH - 14) ~/ 2,
        color: _white);

    // Label waktu kanan header
    final timeNow = DateFormat('HH:mm:ss').format(timestamp);
    final timeW = timeNow.length * 8;
    _shadow2(src, timeNow, font: fontS,
        x: (cx + cardW - timeW - padX).clamp(cx + 60, cx + cardW - 4),
        y: cy + (headerH - 14) ~/ 2, color: _accentBlue);

    // ── Border ────────────────────────────────────────────────────
    if (showBorder) {
      img.drawRect(src, x1: cx, y1: cy, x2: cx + cardW, y2: cy + cardH,
          color: img.ColorRgba8(30, 144, 255, 60), thickness: 1);
    }

    // ── Brackets corner ───────────────────────────────────────────
    _brackets(src, cx: cx, cy: cy, w: cardW, h: cardH);

    int ty = cy + headerH + padY;
    final int tx = cx + padX;

    // ── Date ──────────────────────────────────────────────────────
    final dateStr = DateFormat('EEE, dd MMMM yyyy').format(timestamp);
    _shadow2(src, dateStr, font: fontS, x: tx, y: ty, color: _white);
    ty += lS;

    // ── Separator ─────────────────────────────────────────────────
    img.fillRect(src, x1: tx, y1: ty, x2: cx + cardW - padX, y2: ty + 1,
        color: img.ColorRgba8(255, 255, 255, 18));
    ty += 6;

    // ── Coordinates ───────────────────────────────────────────────
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final coord = '${lat.abs().toStringAsFixed(5)}° ${lat >= 0 ? "N" : "S"}   '
          '${lon.abs().toStringAsFixed(5)}° ${lon >= 0 ? "E" : "W"}';
      _shadow2(src, coord, font: fontS, x: tx, y: ty, color: _accentBlue);
      ty += lS;
    } else if (!hasPosition) {
      _shadow2(src, 'GPS: Acquiring...', font: fontS, x: tx, y: ty, color: _dimGrey);
      ty += lS;
    }

    // ── Accuracy ──────────────────────────────────────────────────
    if (showAccuracy && hasPosition && acc != null) {
      _shadow2(src, 'Accuracy  ±${acc.toStringAsFixed(0)} m',
          font: fontS, x: tx, y: ty, color: _dimGrey);
      ty += lS;
    }

    // ── Separator ─────────────────────────────────────────────────
    if (_validAddr(address) || weather.isNotEmpty) {
      img.fillRect(src, x1: tx, y1: ty, x2: cx + cardW - padX, y2: ty + 1,
          color: img.ColorRgba8(255, 255, 255, 14));
      ty += 6;
    }

    // ── Address ───────────────────────────────────────────────────
    if (showAddress && _validAddr(address)) {
      final maxChars = ((cardW - padX * 2) / 7).toInt().clamp(28, 52);
      for (final line in _splitAddr(address, maxChars).take(2)) {
        if (ty + lS > cy + cardH - 4) break;
        _shadow2(src, line, font: fontS, x: tx, y: ty, color: _lightGrey);
        ty += lS;
      }
    }

    // ── Weather ───────────────────────────────────────────────────
    if (showWeather && weather.isNotEmpty && ty + lS <= cy + cardH - 2) {
      img.fillRect(src,
          x1: tx - 2, y1: ty - 1,
          x2: tx + weather.length * 7 + 6, y2: ty + lS - 2,
          color: img.ColorRgba8(30, 144, 255, 28));
      _shadow2(src, weather, font: fontS, x: tx, y: ty, color: _accentBlue);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  // ── Helpers ──────────────────────────────────────────────────────

  void _shadow2(img.Image src, String text, {
    required img.BitmapFont font, required int x, required int y, required img.Color color,
  }) {
    img.drawString(src, text, font: font, x: x + 1, y: y + 1, color: _shadow);
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  void _brackets(img.Image src, {required int cx, required int cy, required int w, required int h}) {
    const sz = 8; const th = 2;
    final c = img.ColorRgba8(30, 144, 255, 160);
    img.fillRect(src, x1: cx,     y1: cy,     x2: cx+sz, y2: cy+th,  color: c);
    img.fillRect(src, x1: cx,     y1: cy,     x2: cx+th, y2: cy+sz,  color: c);
    img.fillRect(src, x1: cx+w-sz,y1: cy,     x2: cx+w,  y2: cy+th,  color: c);
    img.fillRect(src, x1: cx+w-th,y1: cy,     x2: cx+w,  y2: cy+sz,  color: c);
    img.fillRect(src, x1: cx,     y1: cy+h-th,x2: cx+sz, y2: cy+h,   color: c);
    img.fillRect(src, x1: cx,     y1: cy+h-sz,x2: cx+th, y2: cy+h,   color: c);
    img.fillRect(src, x1: cx+w-sz,y1: cy+h-th,x2: cx+w, y2: cy+h,   color: c);
    img.fillRect(src, x1: cx+w-th,y1: cy+h-sz,x2: cx+w, y2: cy+h,   color: c);
  }

  bool _validAddr(String a) =>
      a.isNotEmpty && a != 'Tidak ada lokasi' && !a.startsWith('GPS:');

  List<String> _splitAddr(String addr, int maxChars) {
    final parts = addr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return [addr.length > maxChars ? '${addr.substring(0, maxChars - 1)}…' : addr];
    final l1 = parts.first;
    final rest = parts.skip(1).join(', ');
    return [
      l1.length > maxChars ? '${l1.substring(0, maxChars - 1)}…' : l1,
      if (rest.isNotEmpty) rest.length > maxChars ? '${rest.substring(0, maxChars - 1)}…' : rest,
    ];
  }

  int _lerp(int a, int b, double t) => (a + (b - a) * t).round().clamp(0, 255);
}
