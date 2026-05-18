// lib/watermark/layouts/layout_cinematic.dart
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

/// Cinematic — letterbox hitam atas+bawah, aksen garis kuning emas,
/// teks tersebar di bar bawah seperti subtitle film dokumenter.
class LayoutCinematic extends WatermarkLayoutBase {
  @override
  String get name => 'Cinematic';

  static const int _barTop    = 56;
  static const int _barBottom = 108;
  static const int _padX      = 24;

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
    final int alphaBar = (opacity * 240).toInt().clamp(0, 255);

    // ── Bar atas ──────────────────────────────────────────────────
    img.fillRect(src, x1: 0, y1: 0, x2: w - 1, y2: _barTop,
        color: img.ColorRgba8(0, 0, 0, alphaBar));

    // ── Bar bawah dengan gradient ─────────────────────────────────
    final int y0 = h - _barBottom;
    for (int row = y0; row < h; row++) {
      final t = (row - y0) / _barBottom;
      final a = (((1.0 - t * 0.4) * opacity) * 255).toInt().clamp(0, 255);
      img.fillRect(src, x1: 0, y1: row, x2: w - 1, y2: row + 1,
          color: img.ColorRgba8(0, 0, 0, a));
    }

    // ── Garis aksen kuning emas ───────────────────────────────────
    if (showBorder) {
      img.fillRect(src, x1: 0, y1: _barTop, x2: w - 1, y2: _barTop + 3,
          color: img.ColorRgba8(230, 175, 45, 220));
      img.fillRect(src, x1: 0, y1: y0 - 3, x2: w - 1, y2: y0,
          color: img.ColorRgba8(230, 175, 45, 220));
    }

    // ── Perforasi film (persegi kecil di bar atas) ────────────────
    final int dotGap  = math.max(40, w ~/ 14);
    const int dotSize = 8;
    final int dotY    = (_barTop - dotSize) ~/ 2;
    for (int dx = dotGap ~/ 2; dx < w; dx += dotGap) {
      img.fillRect(src, x1: dx, y1: dotY, x2: dx + dotSize, y2: dotY + dotSize,
          color: img.ColorRgba8(255, 255, 255, 30));
    }

    final font  = fontSize == 'large' ? img.arial24 : img.arial24;
    final small = img.arial14;

    // ── Bar atas: label cuaca/status + tanggal ────────────────────
    final String topLabel = (showWeather && weather.isNotEmpty)
        ? weather
        : DateFormat('EEEE').format(timestamp).toUpperCase();
    _shadow(src, topLabel, font: small, x: _padX, y: (_barTop - 16) ~/ 2,
        color: img.ColorRgba8(230, 175, 45, 255));

    final String dateStr = DateFormat('dd MMM yyyy').format(timestamp).toUpperCase();
    final int dateW = dateStr.length * 8;
    _shadow(src, dateStr, font: small, x: w - _padX - dateW, y: (_barTop - 14) ~/ 2,
        color: img.ColorRgba8(200, 200, 200, 220));

    // ── Bar bawah: jam besar tengah ───────────────────────────────
    int cy = y0 + 12;

    final String timeStr = DateFormat('HH:mm').format(timestamp);
    final int timeW = timeStr.length * 14;
    _shadow(src, timeStr, font: font, x: (w - timeW) ~/ 2, y: cy,
        color: img.ColorRgba8(255, 255, 255, 255));

    final String secStr = ':${DateFormat('ss').format(timestamp)}';
    _shadow(src, secStr, font: small,
        x: (w + timeW) ~/ 2 + 4, y: cy + 10,
        color: img.ColorRgba8(230, 175, 45, 255));

    cy += (fontSize == 'large') ? 36 : 30;

    img.fillRect(src, x1: _padX, y1: cy, x2: w - _padX, y2: cy + 1,
        color: img.ColorRgba8(255, 255, 255, 40));
    cy += 8;

    // Koordinat
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final String acc2 = (showAccuracy && acc != null)
          ? '   ±${acc.toStringAsFixed(0)} m' : '';
      _shadow(src, '${_fmtLat(lat)}   ${_fmtLon(lon)}$acc2',
          font: small, x: _padX, y: cy,
          color: img.ColorRgba8(100, 200, 255, 255));
      cy += 20;
    }

    // Alamat
    if (showAddress && _isValidAddress(address)) {
      final int maxLen = math.max(10, (w ~/ 8) - 6);
      for (final line in _wrapAddr(address, maxLen).take(2)) {
        if (cy > h - 10) break;
        _shadow(src, line, font: small, x: _padX, y: cy,
            color: img.ColorRgba8(185, 185, 185, 255));
        cy += 18;
      }
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  void _shadow(img.Image src, String text,
      {required img.BitmapFont font, required int x, required int y,
       required img.Color color}) {
    img.drawString(src, text, font: font, x: x + 1, y: y + 1,
        color: img.ColorRgba8(0, 0, 0, 120));
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  bool _isValidAddress(String a) =>
      a.isNotEmpty && a != 'Tidak ada lokasi' && !a.startsWith('GPS:');
  String _fmtLat(double v) =>
      '${v.abs().toStringAsFixed(5)}°${v >= 0 ? 'N' : 'S'}';
  String _fmtLon(double v) =>
      '${v.abs().toStringAsFixed(5)}°${v >= 0 ? 'E' : 'W'}';
  List<String> _wrapAddr(String text, int max) {
    if (text.length <= max) return [text];
    final parts = text.split(',');
    if (parts.length >= 2) {
      final l1 = parts.take(2).join(',').trim();
      final rest = parts.skip(2).join(',').trim();
      return [
        l1,
        if (rest.isNotEmpty)
          (rest.length > max ? '${rest.substring(0, max - 1)}\u2026' : rest),
      ];
    }
    return ['${text.substring(0, max - 1)}\u2026'];
  }
}
