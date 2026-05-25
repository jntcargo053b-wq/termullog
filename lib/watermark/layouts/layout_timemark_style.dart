// lib/watermark/layouts/layout_timemark_style.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutTimeMarkStyle extends WatermarkLayoutBase {
  @override
  String get name => 'TimeMark Style';

  static final _blue    = img.ColorRgba8( 30, 144, 255, 255);
  static final _blueDim = img.ColorRgba8( 30, 144, 255, 150);
  static final _red     = img.ColorRgba8(220,  45,  45, 255);
  static final _white   = img.ColorRgba8(240, 242, 245, 255);
  static final _grey    = img.ColorRgba8(140, 148, 160, 255);
  static final _shadow  = img.ColorRgba8(  0,   0,   0, 160);
  static final _green   = img.ColorRgba8( 60, 200, 100, 255);
  static final _amber   = img.ColorRgba8(255, 180,  40, 255);
  static final _redAcc  = img.ColorRgba8(220,  60,  60, 255);

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
    String mapSize = 'medium',
    String dateFormat = 'dd MMM yyyy',
    String timeFormat = 'HH:mm:ss',
  }) {
    final double scale = (src.width / 1080).clamp(0.7, 2.0);
    final img.BitmapFont fontL = img.arial24;
    final img.BitmapFont fontS = img.arial14;
    final int lL  = (30 * scale).round().clamp(26, 60);
    final int lS  = (20 * scale).round().clamp(18, 40);
    final int pad = (14 * scale).round();

    // ── Hitung tinggi card ────────────────────────────────────────
    int rows = 2; // time + date
    if (showCoordinates && hasPosition && lat != null && lon != null) rows++;
    if (showAccuracy && hasPosition && acc != null) rows++;
    if (showAddress && _validAddr(address)) rows++;
    if (showWeather && weather.isNotEmpty) rows++;

    final int cardW = (src.width * 0.38).clamp(220.0, 360.0).toInt();
    final int cardH = pad + lL + lS + (rows - 2) * lS + pad;
    final int margin = (16 * scale).round();
    final int cx = src.width - cardW - margin;
    final int cy = _positionBottom ? src.height - cardH - margin : margin;
    if (cx < 0 || cy < 0 || cy + cardH > src.height) return WatermarkLayoutBase.encodeJpg(src);

    // ── Gradient latar ────────────────────────────────────────────
    for (int row = cy; row < cy + cardH; row++) {
      if (row < 0 || row >= src.height) continue;
      final double t = (row - cy) / cardH;
      final int r = _lerp(8, 18, t);
      final int g = _lerp(12, 22, t);
      final int b = _lerp(22, 38, t);
      final int a = (_lerp(240, 210, t) * opacity).toInt().clamp(0, 255);
      img.fillRect(src, x1: cx, y1: row, x2: cx + cardW, y2: row + 1,
          color: img.ColorRgba8(r, g, b, a));
    }

    // ── Aksen kiri + dot merah (GPS pin sim) ──────────────────────
    img.fillRect(src, x1: cx, y1: cy, x2: cx + 3, y2: cy + cardH, color: _blue);
    img.fillCircle(src, x: cx + (18 * scale).round(), y: cy + (18 * scale).round(),
        radius: (6 * scale).round(), color: _red);
    img.fillCircle(src, x: cx + (18 * scale).round(), y: cy + (18 * scale).round(),
        radius: (4 * scale).round(), color: img.ColorRgba8(255, 80, 80, 255));

    // ── Border ────────────────────────────────────────────────────
    if (showBorder) {
      img.drawRect(src, x1: cx, y1: cy, x2: cx + cardW, y2: cy + cardH,
          color: img.ColorRgba8(30, 144, 255, 55), thickness: 1);
    }

    // ── Content ───────────────────────────────────────────────────
    final int tx = cx + pad + (10 * scale).round();
    int ty = cy + pad;

    // Jam besar
    final timeStr = DateFormat('HH:mm:ss').format(timestamp);
    _sh(src, timeStr, font: fontL, x: tx, y: ty, color: _white);
    ty += lL;

    // Tanggal
    final dateStr = DateFormat('EEE, dd MMM yyyy').format(timestamp);
    _sh(src, dateStr, font: fontS, x: tx, y: ty, color: _grey);
    ty += lS;

    // Separator
    img.fillRect(src, x1: tx, y1: ty, x2: cx + cardW - pad, y2: ty + 1,
        color: img.ColorRgba8(255, 255, 255, 20));
    ty += 5;

    // Koordinat
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final coord = '${lat.abs().toStringAsFixed(4)}° ${lat >= 0 ? "N" : "S"}  '
          '${lon.abs().toStringAsFixed(4)}° ${lon >= 0 ? "E" : "W"}';
      _sh(src, coord, font: fontS, x: tx, y: ty, color: _blue);
      ty += lS;
    }

    // Accuracy
    if (showAccuracy && hasPosition && acc != null) {
      final accColor = acc <= 5 ? _green : acc <= 20 ? _amber : _redAcc;
      _sh(src, '± ${acc.toStringAsFixed(0)} m', font: fontS, x: tx, y: ty, color: accColor);
      ty += lS;
    }

    // Address
    if (showAddress && _validAddr(address) && ty < cy + cardH - 2) {
      final maxC = ((cardW - pad - 16) / 7).toInt().clamp(20, 40);
      final short = address.length > maxC ? '${address.substring(0, maxC - 1)}…' : address;
      _sh(src, short, font: fontS, x: tx, y: ty, color: _grey);
      ty += lS;
    }

    // Weather
    if (showWeather && weather.isNotEmpty && ty < cy + cardH - 2) {
      img.fillRect(src,
          x1: tx - 2, y1: ty - 1, x2: tx + weather.length * 7 + 6, y2: ty + lS - 2,
          color: img.ColorRgba8(30, 144, 255, 28));
      _sh(src, weather, font: fontS, x: tx, y: ty, color: _blue);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  void _sh(img.Image src, String text, {
    required img.BitmapFont font, required int x, required int y, required img.Color color,
  }) {
    img.drawString(src, text, font: font, x: x + 1, y: y + 1, color: _shadow);
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  bool _validAddr(String a) =>
      a.isNotEmpty && a != 'Tidak ada lokasi' && !a.startsWith('GPS:');

  int _lerp(int a, int b, double t) => (a + (b - a) * t).round().clamp(0, 255);
}
