// lib/watermark/layouts/layout_survey.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutSurvey extends WatermarkLayoutBase {
  @override
  String get name => 'Survey';

  // ── Palette ──────────────────────────────────────────────────────
  static final _cyan       = img.ColorRgba8( 0, 184, 212, 255);
  static final _cyanDim    = img.ColorRgba8( 0, 184, 212, 140);
  static final _cyanHdr    = img.ColorRgba8( 0, 120, 160, 220);
  static final _white      = img.ColorRgba8(240, 242, 245, 255);
  static final _lightGrey  = img.ColorRgba8(160, 170, 185, 255);
  static final _dimGrey    = img.ColorRgba8(100, 110, 125, 255);
  static final _shadow     = img.ColorRgba8(  0,   0,   0, 150);
  static final _accGreen   = img.ColorRgba8( 60, 200, 100, 255);
  static final _accAmber   = img.ColorRgba8(255, 180,  40, 255);
  static final _accRed     = img.ColorRgba8(220,  60,  60, 255);

  static const bool _positionTop = true; // top right

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
    final img.BitmapFont fontS = img.arial14;
    final img.BitmapFont fontL = img.arial24;
    final int lS = (20 * scale).round();
    final int lL = (28 * scale).round();
    final int padX = (12 * scale).round();
    final int padY = (10 * scale).round();
    final int headerH = (34 * scale).round();
    final int labelW = (45 * scale).round();

    // ── Build rows ────────────────────────────────────────────────
    final rows = <_Row>[];
    rows.add(_Row('DATE', DateFormat('dd MMM yyyy').format(timestamp), _white));
    rows.add(_Row('TIME', DateFormat('HH:mm:ss').format(timestamp), _white));

    if (showCoordinates && hasPosition && lat != null && lon != null) {
      rows.add(_Row('LAT', '${lat.abs().toStringAsFixed(6)}° ${lat >= 0 ? "N" : "S"}', _cyan));
      rows.add(_Row('LON', '${lon.abs().toStringAsFixed(6)}° ${lon >= 0 ? "E" : "W"}', _cyan));
    }
    if (showAccuracy && hasPosition && acc != null) {
      final accColor = acc <= 5 ? _accGreen : acc <= 20 ? _accAmber : _accRed;
      rows.add(_Row('ACC', '± ${acc.toStringAsFixed(0)} m', accColor));
    }
    if (showAddress && _validAddr(address)) {
      final maxChars = 30;
      final short = address.length > maxChars ? '${address.substring(0, maxChars - 1)}…' : address;
      rows.add(_Row('ADDR', short, _lightGrey));
    }
    if (showWeather && weather.isNotEmpty) {
      rows.add(_Row('WX', weather, _cyan));
    }

    final int cardW = (src.width * 0.42).clamp(220.0, 360.0).toInt();
    final int cardH = headerH + padY + rows.length * (lS + 2) + padY;
    final int margin = (14 * scale).round();
    final int cx = _positionTop ? src.width - cardW - margin : margin;
    final int cy = _positionTop ? margin : src.height - cardH - margin;
    if (cx < 0 || cy < 0 || cy + cardH > src.height) return WatermarkLayoutBase.encodeJpg(src);

    // ── Gradient latar ────────────────────────────────────────────
    for (int row = cy; row < cy + cardH; row++) {
      if (row < 0 || row >= src.height) continue;
      final double t = (row - cy) / cardH;
      final int r = _lerp(6, 18, t);
      final int g = _lerp(10, 22, t);
      final int b = _lerp(18, 36, t);
      final int a = (_lerp(245, 215, t) * opacity).toInt().clamp(0, 255);
      img.fillRect(src, x1: cx, y1: row, x2: cx + cardW, y2: row + 1,
          color: img.ColorRgba8(r, g, b, a));
    }

    // ── Header cyan ───────────────────────────────────────────────
    img.fillRect(src, x1: cx, y1: cy, x2: cx + cardW, y2: cy + headerH,
        color: _cyanHdr);
    // Stripe kiri
    img.fillRect(src, x1: cx, y1: cy, x2: cx + 4, y2: cy + headerH,
        color: img.ColorRgba8(0, 230, 255, 255));

    _sh(src, 'SURVEY DATA', font: fontS, x: cx + 10, y: cy + (headerH - 14) ~/ 2, color: _white);
    // Pin emoji sim
    img.fillCircle(src, x: cx + cardW - (20 * scale).round(), y: cy + headerH ~/ 2,
        radius: (5 * scale).round(), color: img.ColorRgba8(255, 80, 80, 255));

    // ── Border + divider ──────────────────────────────────────────
    if (showBorder) {
      img.drawRect(src, x1: cx, y1: cy, x2: cx + cardW, y2: cy + cardH,
          color: img.ColorRgba8(0, 184, 212, 70), thickness: 1);
    }
    // Horizontal line bawah header
    img.fillRect(src, x1: cx, y1: cy + headerH, x2: cx + cardW, y2: cy + headerH + 1,
        color: _cyanDim);

    // ── Rows ──────────────────────────────────────────────────────
    int ty = cy + headerH + padY;
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      // Alternating row bg
      if (i.isEven) {
        img.fillRect(src, x1: cx + 2, y1: ty - 1, x2: cx + cardW - 2, y2: ty + lS,
            color: img.ColorRgba8(255, 255, 255, 8));
      }
      // Label
      _sh(src, row.label, font: fontS, x: cx + padX, y: ty + 1, color: _dimGrey);
      // Separator titik
      img.fillRect(src, x1: cx + padX + labelW, y1: ty + lS ~/ 2, x2: cx + padX + labelW + 1, y2: ty + lS ~/ 2 + 1,
          color: _dimGrey);
      // Value
      _sh(src, row.value, font: fontS, x: cx + padX + labelW + 6, y: ty + 1, color: row.color);

      ty += lS + 2;

      // Row divider
      if (i < rows.length - 1) {
        img.fillRect(src, x1: cx + padX, y1: ty - 1, x2: cx + cardW - padX, y2: ty,
            color: img.ColorRgba8(255, 255, 255, 10));
      }
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

class _Row {
  final String label;
  final String value;
  final img.Color color;
  const _Row(this.label, this.value, this.color);
}
