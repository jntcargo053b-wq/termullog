// lib/watermark/layouts/layout_leica.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

/// Minimal Leica-inspired corner timestamp — bottom right, clean & compact.
class LayoutLeica extends WatermarkLayoutBase {
  @override
  String get name => 'Leica';

  // ── Palette ──────────────────────────────────────────────────────
  static final _red       = img.ColorRgba8(210,  30,  30, 255);
  static final _redGlow   = img.ColorRgba8(220,  60,  60, 120);
  static final _white     = img.ColorRgba8(240, 242, 245, 255);
  static final _cream     = img.ColorRgba8(210, 205, 190, 255);
  static final _dim       = img.ColorRgba8(140, 138, 130, 255);
  static final _shadow    = img.ColorRgba8(  0,   0,   0, 170);

  static const bool _positionBottom = true; // bottom right

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
    final int lL  = (28 * scale).round();
    final int lS  = (18 * scale).round();
    final int padX = (14 * scale).round();
    final int padY = (10 * scale).round();

    // ── Hitung tinggi ─────────────────────────────────────────────
    int rows = 2; // time + date
    if (showCoordinates && hasPosition && lat != null && lon != null) rows += 1;
    if (showAccuracy && hasPosition && acc != null) rows += 1;
    if (showWeather && weather.isNotEmpty) rows += 1;

    final int cardH = padY + lL + lS + (rows - 2) * lS + padY + 4;
    final int cardW = (src.width * 0.32).clamp(180.0, 300.0).toInt();
    final int margin = (16 * scale).round();
    final int cx = src.width - cardW - margin;
    final int cy = _positionBottom ? src.height - cardH - margin : margin;
    if (cx < 0 || cy < 0 || cy + cardH > src.height) return WatermarkLayoutBase.encodeJpg(src);

    // ── Gradient latar (gelap solid di kanan) ─────────────────────
    for (int row = cy; row < cy + cardH; row++) {
      if (row < 0 || row >= src.height) continue;
      final double t = (row - cy) / cardH;
      final int r = _lerp(6, 14, t);
      final int g = _lerp(6, 14, t);
      final int b = _lerp(6, 14, t);
      final int a = (_lerp(235, 200, t) * opacity).toInt().clamp(0, 255);
      img.fillRect(src, x1: cx, y1: row, x2: cx + cardW, y2: row + 1,
          color: img.ColorRgba8(r, g, b, a));
    }

    // ── Aksen kiri merah ──────────────────────────────────────────
    img.fillRect(src, x1: cx, y1: cy, x2: cx + 3, y2: cy + cardH,
        color: _red);

    // ── Dot merah (lens badge) ─────────────────────────────────────
    final int dotX = cx + cardW - (18 * scale).round();
    final int dotY = cy + (18 * scale).round();
    img.fillCircle(src, x: dotX, y: dotY, radius: (7 * scale).round(), color: _redGlow);
    img.fillCircle(src, x: dotX, y: dotY, radius: (5 * scale).round(), color: _red);

    // ── Border bawah ──────────────────────────────────────────────
    if (showBorder) {
      img.drawRect(src, x1: cx, y1: cy, x2: cx + cardW, y2: cy + cardH,
          color: img.ColorRgba8(255, 255, 255, 25), thickness: 1);
    }

    // ── Content ───────────────────────────────────────────────────
    int ty = cy + padY;
    final int tx = cx + padX + 4;

    // Jam besar
    final timeStr = DateFormat('HH:mm:ss').format(timestamp);
    _sh(src, timeStr, font: fontL, x: tx, y: ty, color: _white);
    ty += lL;

    // Tanggal
    final dateStr = DateFormat('yyyy-MM-dd').format(timestamp);
    _sh(src, dateStr, font: fontS, x: tx, y: ty, color: _cream);
    ty += lS + 4;

    // Separator tipis
    img.fillRect(src, x1: tx, y1: ty, x2: cx + cardW - padX, y2: ty + 1,
        color: img.ColorRgba8(255, 255, 255, 22));
    ty += 6;

    // Koordinat
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final latStr = '${lat.abs().toStringAsFixed(4)}° ${lat >= 0 ? "N" : "S"}';
      final lonStr = '${lon.abs().toStringAsFixed(4)}° ${lon >= 0 ? "E" : "W"}';
      _sh(src, '$latStr  $lonStr', font: fontS, x: tx, y: ty, color: _dim);
      ty += lS;
    }

    // Accuracy
    if (showAccuracy && hasPosition && acc != null) {
      final accColor = acc <= 5
          ? img.ColorRgba8(60, 200, 100, 255)
          : acc <= 20
              ? img.ColorRgba8(255, 180, 40, 255)
              : img.ColorRgba8(220, 60, 60, 255);
      _sh(src, '± ${acc.toStringAsFixed(0)} m', font: fontS, x: tx, y: ty, color: accColor);
      ty += lS;
    }

    // Weather
    if (showWeather && weather.isNotEmpty && ty < cy + cardH - 2) {
      _sh(src, weather, font: fontS, x: tx, y: ty, color: _dim);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  void _sh(img.Image src, String text, {
    required img.BitmapFont font, required int x, required int y, required img.Color color,
  }) {
    img.drawString(src, text, font: font, x: x + 1, y: y + 1, color: _shadow);
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  int _lerp(int a, int b, double t) => (a + (b - a) * t).round().clamp(0, 255);
}
