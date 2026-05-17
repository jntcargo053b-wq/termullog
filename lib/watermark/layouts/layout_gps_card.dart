import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import '../wm_helpers.dart';
import 'watermark_layout_base.dart';

/// Layout GPS Card — mirip referensi foto GPS Timestamp
///
///   ┌──────────────────────────────────────┐
///   │  MAP STRIP full-width (adaptive)     │
///   ├──────────────────────────────────────┤
///   │  🗓 Thu, 19 Jun 2025  🕐 10:07:07   │
///   │  ─────────────────────────────────   │
///   │  Alamat baris 1                      │
///   │  Alamat baris 2                      │
///   │  26°54'N  75°48'E  ±2.0m            │
///   └──────────────────────────────────────┘
class LayoutGpsCard extends WatermarkLayoutBase {
  @override
  String get name => 'GPS Card';

  static const double _mapRatio = 0.18;
  static const int    _mapMin   = 100;
  static const int    _mapMax   = 180;
  static const int    _padX     = 20;
  static const int    _padY     = 14;
  static const int    _lineH    = 32;
  static const int    _lineSm   = 22;
  static const int    _divGap   = 6;

  // BG: #111318 @ 90%
  static const int _bgR = 17, _bgG = 19, _bgB = 24, _bgA = 230;

  static final img.Color _cWhite  = img.ColorRgb8(230, 228, 226);
  static final img.Color _cBlue   = img.ColorRgb8(30, 144, 255);
  static final img.Color _cGrey   = img.ColorRgb8(160, 160, 165);
  static final img.Color _cGreen  = img.ColorRgb8(0, 200, 120);

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
  }) {
    final bool isTop = watermarkPosition == 'top';
    final bool hasMap = showMiniMap && mapBytes != null && mapBytes.isNotEmpty;

    final img.Image? mapImg = hasMap ? _decodeMap(mapBytes!) : null;
    final int mapH = mapImg != null
        ? (src.height * _mapRatio).round().clamp(_mapMin, _mapMax)
        : 0;

    final bool showAddr = address.isNotEmpty &&
        address != 'Tidak ada lokasi' &&
        !address.startsWith('GPS:');
    final int maxChar = ((src.width - _padX * 2) / 8).floor().clamp(10, 200);
    final List<String> addrLines =
        showAddr ? wmWrapText(address, maxChar) : const [];

    final int textH = _padY
        + _lineH
        + _divGap + 1 + _divGap
        + addrLines.length * _lineSm
        + (hasPosition ? _lineSm : 0)
        + (showWeather && weather.isNotEmpty ? _lineSm : 0)
        + _padY;

    final int stripH = mapImg != null ? mapH + 1 : 0;
    final int panelH = stripH + textH;
    final int y0 = isTop ? 0 : (src.height - panelH).clamp(0, src.height);
    final int y1 = (y0 + panelH).clamp(0, src.height);

    // Panel BG
    _fillPanel(src, y0, y1);
    // Border
    _hline(src, y0, 50);
    _hline(src, y1 - 1, 50);

    // Map
    int textY = y0;
    if (mapImg != null) {
      _drawMap(src, mapImg, y0, y0 + mapH);
      _hline(src, y0 + mapH, 50);
      textY = y0 + mapH + 1;
    }

    int cy = textY + _padY;

    // Tanggal + Jam satu baris
    final String dateStr = DateFormat('EEE, dd MMM yyyy').format(timestamp);
    final String timeStr = DateFormat('HH:mm:ss').format(timestamp);
    wmDrawTextShadow(src, dateStr, font: img.arial14,
        x: _padX, y: cy + 9, color: _cGrey);
    final int timeX = src.width - _padX - timeStr.length * 14;
    wmDrawTextShadow(src, timeStr, font: img.arial24,
        x: timeX.clamp(_padX + 80, src.width - _padX), y: cy, color: _cWhite);
    cy += _lineH;

    // Divider
    cy += _divGap;
    _hline(src, cy, 20);
    cy += 1 + _divGap;

    // Alamat
    for (final line in addrLines) {
      wmDrawTextShadow(src, line, font: img.arial14,
          x: _padX, y: cy, color: _cWhite);
      cy += _lineSm;
    }

    // Koordinat + accuracy satu baris
    if (hasPosition && lat != null && lon != null) {
      final String coord = '${_dms(lat.abs(), lat >= 0 ? 'N' : 'S')}  '
          '${_dms(lon.abs(), lon >= 0 ? 'E' : 'W')}'
          '${showAccuracy && acc != null ? '  \u00b1${acc.toStringAsFixed(0)}m' : ''}';
      wmDrawTextShadow(src, coord, font: img.arial14,
          x: _padX, y: cy, color: _cGrey);
      cy += _lineSm;
    }

    // Cuaca
    if (showWeather && weather.isNotEmpty) {
      wmDrawTextShadow(src, weather, font: img.arial14,
          x: _padX, y: cy, color: _cGreen);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  void _fillPanel(img.Image src, int y0, int y1) {
    final int bgR = _bgR * _bgA ~/ 255, inv = 255 - _bgA;
    final int bgG = _bgG * _bgA ~/ 255;
    final int bgB = _bgB * _bgA ~/ 255;
    for (int y = y0.clamp(0, src.height); y < y1.clamp(0, src.height); y++) {
      for (int x = 0; x < src.width; x++) {
        final px = src.getPixel(x, y);
        src.setPixel(x, y, img.ColorRgba8(
          (px.r.toInt() * inv ~/ 255) + bgR,
          (px.g.toInt() * inv ~/ 255) + bgG,
          (px.b.toInt() * inv ~/ 255) + bgB,
          255,
        ));
      }
    }
  }

  void _hline(img.Image src, int y, int alpha) {
    if (y < 0 || y >= src.height) return;
    for (int x = 0; x < src.width; x++) {
      final px = src.getPixel(x, y);
      src.setPixel(x, y, img.ColorRgba8(
        (px.r.toInt() * (255 - alpha) ~/ 255) + alpha,
        (px.g.toInt() * (255 - alpha) ~/ 255) + alpha,
        (px.b.toInt() * (255 - alpha) ~/ 255) + alpha,
        255,
      ));
    }
  }

  void _drawMap(img.Image src, img.Image mapImg, int y0, int y1) {
    final int h = y1 - y0;
    if (h <= 0) return;
    final resized = img.copyResize(mapImg,
        width: src.width, height: h,
        interpolation: img.Interpolation.average);
    img.compositeImage(src, resized, dstX: 0, dstY: y0);
    // Grayscale + tint
    final List<int> fade = List.generate(
        src.width ~/ 5,
        (i) => ((1.0 - i / (src.width ~/ 5)) * 90).round().clamp(0, 90));
    for (int y = y0; y < y1 && y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final px = src.getPixel(x, y);
        final int lum =
            (px.r.toInt() * 299 + px.g.toInt() * 587 + px.b.toInt() * 114) ~/
            1000;
        int r = lum * 54 ~/ 100, g = lum * 54 ~/ 100, b = lum * 70 ~/ 100;
        if (x < fade.length) {
          final ov = fade[x];
          r = r * (255 - ov) ~/ 255;
          g = g * (255 - ov) ~/ 255;
          b = b * (255 - ov) ~/ 255;
        } else if (x >= src.width - fade.length) {
          final ov = fade[src.width - 1 - x];
          r = r * (255 - ov) ~/ 255;
          g = g * (255 - ov) ~/ 255;
          b = b * (255 - ov) ~/ 255;
        }
        src.setPixel(x, y, img.ColorRgba8(r, g, b, 255));
      }
    }
    final int cx = src.width ~/ 2, cy = y0 + h ~/ 2;
    img.drawCircle(src, x: cx, y: cy, radius: 12,
        color: img.ColorRgba8(30, 144, 255, 120));
    img.fillCircle(src, x: cx, y: cy, radius: 5,
        color: img.ColorRgba8(30, 144, 255, 230));
    img.fillCircle(src, x: cx, y: cy, radius: 2,
        color: img.ColorRgb8(255, 255, 255));
  }

  img.Image? _decodeMap(Uint8List bytes) {
    if (bytes.length < 128) return null;
    try {
      final d = img.decodeImage(bytes);
      if (d == null || d.width < 8 || d.height < 8) return null;
      return d;
    } catch (_) { return null; }
  }

  String _dms(double deg, String dir) {
    final int d = deg.floor();
    final double mf = (deg - d) * 60;
    final int m = mf.floor();
    return "$d\u00b0${m.toString().padLeft(2, '0')}'$dir";
  }
}
