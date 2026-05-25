// lib/watermark/layouts/layout_hud.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutHUD extends WatermarkLayoutBase {
  @override
  String get name => 'HUD';

  static final _cyan    = img.ColorRgba8( 0, 200, 240, 255);
  static final _cyanDim = img.ColorRgba8( 0, 200, 240, 140);
  static final _white   = img.ColorRgba8(240, 242, 245, 255);
  static final _grey    = img.ColorRgba8(140, 148, 160, 255);
  static final _shadow  = img.ColorRgba8(  0,   0,   0, 180);
  static final _green   = img.ColorRgba8( 60, 200, 100, 255);
  static final _amber   = img.ColorRgba8(255, 180,  40, 255);
  static final _red     = img.ColorRgba8(220,  60,  60, 255);

  static const bool _positionBottom = true;

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
    final int lL  = (30 * scale).round();
    final int lS  = (20 * scale).round();
    final int padX = (20 * scale).round();
    final int padY = (12 * scale).round();

    // ── Hitung baris ─────────────────────────────────────────────
    int rows = 1; // date+time satu baris
    if (showCoordinates && hasPosition && lat != null && lon != null) rows++;
    if (showAccuracy && hasPosition && acc != null) rows++;
    if (showAddress && _validAddr(address)) rows++;
    if (showWeather && weather.isNotEmpty) rows++;

    final int panelH = padY + lL + (rows - 1) * lS + padY;
    final int y0 = _positionBottom ? src.height - panelH - (16 * scale).round() : (16 * scale).round();
    if (y0 < 0 || y0 + panelH > src.height) return WatermarkLayoutBase.encodeJpg(src);

    // ── Full-width gradient ───────────────────────────────────────
    for (int row = y0; row < y0 + panelH; row++) {
      if (row < 0 || row >= src.height) continue;
      final double t = (row - y0) / panelH;
      // HUD: dark navy dengan shimmer biru
      final int r = _lerp(4, 10, t);
      final int g = _lerp(8, 16, t);
      final int b = _lerp(20, 32, t);
      final int a = (_lerp(250, 220, t) * opacity).toInt().clamp(0, 255);
      img.fillRect(src, x1: 0, y1: row, x2: src.width, y2: row + 1,
          color: img.ColorRgba8(r, g, b, a));
    }

    // ── Scan-line HUD effect (1px garis tiap 4px) ─────────────────
    for (int row = y0; row < y0 + panelH; row += 4) {
      if (row >= src.height) break;
      img.fillRect(src, x1: 0, y1: row, x2: src.width, y2: row + 1,
          color: img.ColorRgba8(0, 200, 240, 8));
    }

    // ── Border atas + bawah cyan ──────────────────────────────────
    if (showBorder) {
      img.fillRect(src, x1: 0, y1: y0, x2: src.width, y2: y0 + 2, color: _cyanDim);
      img.fillRect(src, x1: 0, y1: y0 + panelH - 2, x2: src.width, y2: y0 + panelH, color: _cyanDim);
    }

    // ── Corner brackets ───────────────────────────────────────────
    _brackets(src, cx: 0, cy: y0, w: src.width, h: panelH);

    // ── Content ───────────────────────────────────────────────────
    int ty = y0 + padY;
    final int tx = padX;

    // Jam besar
    final timeStr = DateFormat('HH:mm:ss').format(timestamp);
    _sh(src, timeStr, font: fontL, x: tx, y: ty, color: _white);

    // Tanggal kanan
    final dateStr = DateFormat('dd/MM/yyyy').format(timestamp);
    _sh(src, dateStr, font: fontS,
        x: src.width - padX - dateStr.length * 8, y: ty + 8, color: _grey);
    ty += lL;

    // Separator
    img.fillRect(src, x1: padX, y1: ty, x2: src.width - padX, y2: ty + 1,
        color: img.ColorRgba8(0, 200, 240, 30));
    ty += 5;

    // Koordinat
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final coord = '${lat.abs().toStringAsFixed(5)}° ${lat >= 0 ? "N" : "S"}   '
          '${lon.abs().toStringAsFixed(5)}° ${lon >= 0 ? "E" : "W"}';
      _sh(src, coord, font: fontS, x: tx, y: ty, color: _cyan);
      ty += lS;
    }

    // Accuracy
    if (showAccuracy && hasPosition && acc != null) {
      final accColor = acc <= 5 ? _green : acc <= 20 ? _amber : _red;
      _sh(src, 'GPS Accuracy  ± ${acc.toStringAsFixed(0)} m', font: fontS, x: tx, y: ty, color: accColor);
      ty += lS;
    }

    // Address
    if (showAddress && _validAddr(address)) {
      final maxC = ((src.width - padX * 2) / 7).toInt().clamp(28, 80);
      final short = address.length > maxC ? '${address.substring(0, maxC - 1)}…' : address;
      _sh(src, short, font: fontS, x: tx, y: ty, color: _grey);
      ty += lS;
    }

    // Weather
    if (showWeather && weather.isNotEmpty) {
      img.fillRect(src, x1: tx - 2, y1: ty - 1, x2: tx + weather.length * 7 + 8, y2: ty + lS - 2,
          color: img.ColorRgba8(0, 200, 240, 22));
      _sh(src, weather, font: fontS, x: tx, y: ty, color: _cyan);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  void _sh(img.Image src, String text, {
    required img.BitmapFont font, required int x, required int y, required img.Color color,
  }) {
    img.drawString(src, text, font: font, x: x + 1, y: y + 1, color: _shadow);
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  void _brackets(img.Image src, {required int cx, required int cy, required int w, required int h}) {
    const sz = 12; const th = 2;
    final c = img.ColorRgba8(0, 200, 240, 180);
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

  int _lerp(int a, int b, double t) => (a + (b - a) * t).round().clamp(0, 255);
}
