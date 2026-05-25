// lib/watermark/layouts/layout_gps_card.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutGpsCard extends WatermarkLayoutBase {
  @override
  String get name => 'GPS Card';

  static final _blue     = img.ColorRgba8( 30, 144, 255, 255);
  static final _blueDim  = img.ColorRgba8( 30, 144, 255, 140);
  static final _white    = img.ColorRgba8(240, 242, 245, 255);
  static final _grey     = img.ColorRgba8(150, 158, 170, 255);
  static final _shadow   = img.ColorRgba8(  0,   0,   0, 150);

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
    final img.BitmapFont fontS = img.arial14;
    final img.BitmapFont fontL = img.arial24;
    final int lL   = (28 * scale).round();
    final int lS   = (20 * scale).round();
    final int padX = (14 * scale).round();
    final int padY = (10 * scale).round();

    // ── Map size ──────────────────────────────────────────────────
    final bool hasMap = showMiniMap && mapBytes != null && mapBytes.isNotEmpty;
    final int mapSz   = hasMap
        ? (mapSize == 'small'  ? (60 * scale).round()
         : mapSize == 'large'  ? (110 * scale).round()
         :                       (84 * scale).round())
        : 0;

    // ── Rows ──────────────────────────────────────────────────────
    int rows = 2; // date + time
    if (showCoordinates && hasPosition && lat != null && lon != null) rows++;
    if (showAccuracy && hasPosition && acc != null) rows++;
    if (showAddress && _validAddr(address)) rows++;
    if (showWeather && weather.isNotEmpty) rows++;

    final int panelW = (src.width * 0.88).clamp(260.0, 900.0).toInt();
    final int panelH = padY + lL + (rows - 1) * lS + padY;
    final int y0 = _positionBottom ? src.height - panelH - (16 * scale).round() : (16 * scale).round();
    final int x0 = (src.width - panelW) ~/ 2;
    if (y0 < 0 || x0 < 0) return WatermarkLayoutBase.encodeJpg(src);

    // ── Gradient latar ────────────────────────────────────────────
    for (int row = y0; row < y0 + panelH; row++) {
      if (row < 0 || row >= src.height) continue;
      final double t = (row - y0) / panelH;
      final int r = _lerp(8, 18, t);
      final int g = _lerp(12, 22, t);
      final int b = _lerp(22, 38, t);
      final int a = (_lerp(242, 210, t) * opacity).toInt().clamp(0, 255);
      img.fillRect(src, x1: x0, y1: row, x2: x0 + panelW, y2: row + 1,
          color: img.ColorRgba8(r, g, b, a));
    }

    // ── Border bawah biru ─────────────────────────────────────────
    if (showBorder) {
      img.fillRect(src, x1: x0, y1: y0 + panelH - 3, x2: x0 + panelW, y2: y0 + panelH,
          color: _blue);
      img.drawRect(src, x1: x0, y1: y0, x2: x0 + panelW, y2: y0 + panelH - 1,
          color: img.ColorRgba8(30, 144, 255, 50), thickness: 1);
    }

    // ── Aksen kiri ────────────────────────────────────────────────
    img.fillRect(src, x1: x0, y1: y0, x2: x0 + 4, y2: y0 + panelH,
        color: _blue);

    // ── Text area (reserve untuk map) ─────────────────────────────
    final int textEndX = x0 + panelW - padX - (hasMap ? mapSz + 12 : 0);
    int ty = y0 + padY;
    final int tx = x0 + padX + 6;

    // Jam besar
    final timeStr = DateFormat('HH:mm:ss').format(timestamp);
    _sh(src, timeStr, font: fontL, x: tx, y: ty, color: _white);

    // Tanggal inline kanan
    final dateStr = DateFormat('EEE, dd MMM yyyy').format(timestamp);
    _sh(src, dateStr, font: fontS,
        x: (textEndX - dateStr.length * 7 - 4).clamp(tx + 120, textEndX - 4),
        y: ty + 8, color: _grey);
    ty += lL;

    // Separator
    img.fillRect(src, x1: tx, y1: ty, x2: textEndX, y2: ty + 1,
        color: img.ColorRgba8(255, 255, 255, 20));
    ty += 6;

    // Koordinat
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final coord = '${lat.abs().toStringAsFixed(5)}° ${lat >= 0 ? "N" : "S"}   '
          '${lon.abs().toStringAsFixed(5)}° ${lon >= 0 ? "E" : "W"}';
      _sh(src, coord, font: fontS, x: tx, y: ty, color: _blue);
      ty += lS;
    }

    // Accuracy
    if (showAccuracy && hasPosition && acc != null) {
      final accColor = acc <= 5
          ? img.ColorRgba8(60, 200, 100, 255)
          : acc <= 20
              ? img.ColorRgba8(255, 180, 40, 255)
              : img.ColorRgba8(220, 60, 60, 255);
      _sh(src, 'Accuracy  ± ${acc.toStringAsFixed(0)} m', font: fontS, x: tx, y: ty, color: accColor);
      ty += lS;
    }

    // Address
    if (showAddress && _validAddr(address)) {
      final maxC = ((textEndX - tx) / 7).toInt().clamp(24, 52);
      final short = address.length > maxC ? '${address.substring(0, maxC - 1)}…' : address;
      _sh(src, short, font: fontS, x: tx, y: ty, color: _grey);
      ty += lS;
    }

    // Weather
    if (showWeather && weather.isNotEmpty) {
      img.fillRect(src,
          x1: tx - 2, y1: ty - 1, x2: tx + weather.length * 7 + 6, y2: ty + lS - 2,
          color: img.ColorRgba8(30, 144, 255, 28));
      _sh(src, weather, font: fontS, x: tx, y: ty, color: _blue);
    }

    // ── Mini map ──────────────────────────────────────────────────
    if (hasMap) {
      try {
        final decoded = img.decodeImage(mapBytes!);
        if (decoded != null) {
          final resized = img.copyResize(decoded, width: mapSz, height: mapSz);
          final int mx = x0 + panelW - mapSz - padX;
          final int my = y0 + (panelH - mapSz) ~/ 2;
          img.fillRect(src, x1: mx - 3, y1: my - 3, x2: mx + mapSz + 2, y2: my + mapSz + 2,
              color: img.ColorRgba8(255, 255, 255, 30));
          img.compositeImage(src, resized, dstX: mx, dstY: my, blend: img.BlendMode.alpha);
          img.drawRect(src, x1: mx, y1: my, x2: mx + mapSz, y2: my + mapSz,
              color: _blueDim, thickness: 1);
        }
      } catch (_) {}
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  void _sh(img.Image src, String text, {
    required img.BitmapFont font, required int x, required int y, required img.Color color,
  }) {
    img.drawString(src, text, font: font, x: x + 1, y: y + 1,
        color: img.ColorRgba8(0, 0, 0, 150));
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  bool _validAddr(String a) =>
      a.isNotEmpty && a != 'Tidak ada lokasi' && !a.startsWith('GPS:');

  int _lerp(int a, int b, double t) => (a + (b - a) * t).round().clamp(0, 255);
}
