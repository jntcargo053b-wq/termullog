import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import '../wm_helpers.dart';
import 'watermark_layout_base.dart';

/// Layout Side Panel — strip vertikal di kiri foto
///
///   ┌────┬─────────────────────────────┐
///   │ T  │                             │
///   │ I  │                             │
///   │ M  │       [FOTO]                │
///   │ E  │                             │
///   │    │                             │
///   │ 10 │                             │
///   │:07 │                             │
///   │    │                             │
///   │ 📍 │                             │
///   │ .. │                             │
///   └────┴─────────────────────────────┘
class LayoutSidePanel extends WatermarkLayoutBase {
  @override
  String get name => 'Side Panel';

  static const int _panelW = 52;   // lebar panel kiri
  static const int _padY   = 14;
  static const int _padX   = 8;

  // BG panel: navy gelap
  static const int _bgR = 10, _bgG = 15, _bgB = 30, _bgA = 245;

  static final img.Color _cWhite  = img.ColorRgb8(230, 230, 235);
  static final img.Color _cBlue   = img.ColorRgb8(30, 144, 255);
  static final img.Color _cGrey   = img.ColorRgb8(140, 140, 150);
  static final img.Color _cAccent = img.ColorRgb8(255, 180, 0);

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
    // Panel kiri: blend BG ke foto
    _fillPanel(src, 0, src.height);

    // Garis aksen kanan panel
    img.fillRect(src,
        x1: _panelW - 2, y1: 0,
        x2: _panelW, y2: src.height,
        color: _cBlue);

    int cy = _padY;

    // Jam vertikal besar: tiap digit satu baris
    final String timeStr = DateFormat('HH:mm').format(timestamp);
    for (int i = 0; i < timeStr.length; i++) {
      wmDrawTextShadow(src, timeStr[i], font: img.arial24,
          x: _padX - 2, y: cy, color: _cWhite);
      cy += 26;
    }

    cy += 10;

    // Tanggal — diputar 90° tidak bisa di image lib, tampilkan 2-3 char per baris
    final String day  = DateFormat('dd').format(timestamp);
    final String mon  = DateFormat('MMM').format(timestamp).toUpperCase();
    wmDrawTextShadow(src, day,  font: img.arial14, x: _padX, y: cy, color: _cAccent);
    cy += 18;
    wmDrawTextShadow(src, mon,  font: img.arial14, x: _padX - 2, y: cy, color: _cGrey);
    cy += 18;
    final String year = DateFormat('yy').format(timestamp);
    wmDrawTextShadow(src, year, font: img.arial14, x: _padX, y: cy, color: _cGrey);
    cy += 24;

    // Divider
    img.fillRect(src,
        x1: _padX, y1: cy,
        x2: _panelW - 6, y2: cy + 1,
        color: img.ColorRgba8(255, 255, 255, 60));
    cy += 10;

    // Ikon GPS + koordinat singkat
    if (hasPosition && lat != null && lon != null) {
      wmDrawTextShadow(src, '\u25cf', font: img.arial14,
          x: _padX + 4, y: cy, color: _cBlue);
      cy += 16;
      // Lat: 3 karakter per baris
      final String latS = lat.abs().toStringAsFixed(2);
      for (int i = 0; i < latS.length && i < 6; i += 2) {
        final chunk = latS.substring(i, (i + 2).clamp(0, latS.length));
        wmDrawTextShadow(src, chunk, font: img.arial14,
            x: _padX, y: cy, color: _cGrey);
        cy += 16;
      }
      wmDrawTextShadow(src, lat >= 0 ? 'N' : 'S', font: img.arial14,
          x: _padX + 4, y: cy, color: _cBlue);
      cy += 18;
      final String lonS = lon.abs().toStringAsFixed(2);
      for (int i = 0; i < lonS.length && i < 6; i += 2) {
        final chunk = lonS.substring(i, (i + 2).clamp(0, lonS.length));
        wmDrawTextShadow(src, chunk, font: img.arial14,
            x: _padX, y: cy, color: _cGrey);
        cy += 16;
      }
      wmDrawTextShadow(src, lon >= 0 ? 'E' : 'W', font: img.arial14,
          x: _padX + 4, y: cy, color: _cBlue);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  void _fillPanel(img.Image src, int y0, int y1) {
    final int bgR = _bgR * _bgA ~/ 255, inv = 255 - _bgA;
    final int bgG = _bgG * _bgA ~/ 255;
    final int bgB = _bgB * _bgA ~/ 255;
    for (int y = y0.clamp(0, src.height); y < y1.clamp(0, src.height); y++) {
      for (int x = 0; x < _panelW; x++) {
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
}
