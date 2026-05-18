// lib/watermark/layouts/layout_cinematic_v2.dart
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

/// Cinematic V2 — versi warm-tone: letterbox amber/coklat gelap,
/// teks tata letak dua kolom (kiri = waktu, kanan = lokasi),
/// aksen diagonal stripe di sudut kiri bawah.
class LayoutCinematicV2 extends WatermarkLayoutBase {
  @override
  String get name => 'Cinematic V2';

  static const int _barTop    = 52;
  static const int _barBottom = 130;
  static const int _padX      = 22;

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
    final int w = src.width;
    final int h = src.height;
    final int alphaBar = (opacity * 235).toInt().clamp(0, 255);

    // ── Bar atas warm-dark ────────────────────────────────────────
    for (int row = 0; row < _barTop; row++) {
      final double t = row / _barTop;
      final int r = _lerp(18, 8, t);
      final int g = _lerp(12, 6, t);
      final int b = _lerp(8, 4, t);
      final int a = (alphaBar * (1.0 - t * 0.3)).toInt().clamp(0, 255);
      img.fillRect(src, x1: 0, y1: row, x2: w - 1, y2: row + 1,
          color: img.ColorRgba8(r, g, b, a));
    }

    // ── Bar bawah warm gradient ───────────────────────────────────
    final int y0 = h - _barBottom;
    for (int row = y0; row < h; row++) {
      final double t = (row - y0) / _barBottom;
      final int r = _lerp(20, 10, t);
      final int g = _lerp(12, 6, t);
      final int b = _lerp(6, 3, t);
      final int a = (_lerp(160, alphaBar, t) * 1.0).toInt().clamp(0, 255);
      img.fillRect(src, x1: 0, y1: row, x2: w - 1, y2: row + 1,
          color: img.ColorRgba8(r, g, b, a));
    }

    // ── Garis aksen amber tipis ───────────────────────────────────
    if (showBorder) {
      img.fillRect(src, x1: 0, y1: _barTop, x2: w - 1, y2: _barTop + 2,
          color: img.ColorRgba8(210, 140, 40, 200));
      img.fillRect(src, x1: 0, y1: y0 - 2, x2: w - 1, y2: y0,
          color: img.ColorRgba8(210, 140, 40, 200));
    }

    // ── Bar atas: episode / cuaca ─────────────────────────────────
    final String epLabel = showWeather && weather.isNotEmpty
        ? weather
        : DateFormat('EEEE').format(timestamp).toUpperCase();
    _shadow(src, epLabel, font: img.arial14, x: _padX, y: (_barTop - 14) ~/ 2,
        color: img.ColorRgba8(210, 155, 60, 255));

    // Jam kecil di kanan atas
    final String miniTime = DateFormat('HH:mm:ss').format(timestamp);
    final int mtW = miniTime.length * 8;
    _shadow(src, miniTime, font: img.arial14, x: w - _padX - mtW, y: (_barTop - 14) ~/ 2,
        color: img.ColorRgba8(190, 190, 190, 210));

    // ── Bar bawah: tata letak 2 kolom ─────────────────────────────
    final int midX  = w ~/ 2;
    final int colR  = midX + 16;
    int cyL = y0 + 14;
    int cyR = y0 + 14;

    // KOLOM KIRI — waktu + tanggal
    final String timeStr = DateFormat('HH:mm').format(timestamp);
    _shadow(src, timeStr, font: img.arial24, x: _padX, y: cyL,
        color: img.ColorRgba8(255, 245, 225, 255));
    cyL += 30;

    _shadow(src, DateFormat('dd MMM yyyy').format(timestamp),
        font: img.arial14, x: _padX, y: cyL,
        color: img.ColorRgba8(185, 155, 100, 255));
    cyL += 20;

    _shadow(src, DateFormat('EEEE').format(timestamp),
        font: img.arial14, x: _padX, y: cyL,
        color: img.ColorRgba8(130, 110, 70, 255));
    cyL += 20;

    // KOLOM KANAN — GPS info
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      _shadow(src, '${_fmtLat(lat)}',
          font: img.arial14, x: colR, y: cyR,
          color: img.ColorRgba8(210, 180, 100, 255));
      cyR += 20;
      _shadow(src, '${_fmtLon(lon)}',
          font: img.arial14, x: colR, y: cyR,
          color: img.ColorRgba8(210, 180, 100, 255));
      cyR += 20;
      if (showAccuracy && acc != null) {
        _shadow(src, '\u00b1${acc.toStringAsFixed(0)} m',
            font: img.arial14, x: colR, y: cyR,
            color: img.ColorRgba8(150, 130, 80, 255));
        cyR += 20;
      }
    }

    // Divider vertikal
    final int divTop  = y0 + 10;
    final int divBot  = math.max(cyL, cyR) + 4;
    if (divBot > divTop) {
      img.fillRect(src, x1: midX - 1, y1: divTop, x2: midX + 1, y2: divBot,
          color: img.ColorRgba8(210, 140, 40, 80));
    }

    // Separator horizontal
    final int sepY = math.max(cyL, cyR) + 6;
    if (sepY < h - 10) {
      img.fillRect(src, x1: _padX, y1: sepY, x2: w - _padX, y2: sepY + 1,
          color: img.ColorRgba8(210, 140, 40, 60));
    }

    // Alamat full-width di bawah separator
    int cy = sepY + 8;
    if (showAddress && _isValidAddr(address) && cy < h - 10) {
      final int maxLen = math.max(10, (w ~/ 8) - 4);
      for (final line in _wrapAddr(address, maxLen).take(2)) {
        if (cy > h - 10) break;
        _shadow(src, line, font: img.arial14, x: _padX, y: cy,
            color: img.ColorRgba8(170, 155, 120, 255));
        cy += 20;
      }
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  @override
  Future<Uint8List> applyAsync({
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
  }) async {
    return apply(
      src: src, timestamp: timestamp, hasPosition: hasPosition,
      lat: lat, lon: lon, acc: acc, address: address, weather: weather,
      showWeather: showWeather, showAccuracy: showAccuracy,
      watermarkPosition: watermarkPosition, showMiniMap: showMiniMap,
      mapBytes: mapBytes, showAddress: showAddress,
      showCoordinates: showCoordinates, opacity: opacity,
      showBorder: showBorder, fontSize: fontSize,
    );
  }

  void _shadow(img.Image src, String text,
      {required img.BitmapFont font, required int x, required int y,
       required img.Color color}) {
    img.drawString(src, text, font: font, x: x + 1, y: y + 1,
        color: img.ColorRgba8(0, 0, 0, 130));
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  int _lerp(int a, int b, double t) => (a + (b - a) * t).round().clamp(0, 255);
  bool _isValidAddr(String a) =>
      a.isNotEmpty && a != 'Tidak ada lokasi' && !a.startsWith('GPS:');
  String _fmtLat(double v) =>
      '${v.abs().toStringAsFixed(5)}\u00b0 ${v >= 0 ? 'N' : 'S'}';
  String _fmtLon(double v) =>
      '${v.abs().toStringAsFixed(5)}\u00b0 ${v >= 0 ? 'E' : 'W'}';
  List<String> _wrapAddr(String text, int max) {
    if (text.length <= max) return [text];
    final parts = text.split(',');
    if (parts.length >= 2) {
      final l1 = parts.take(2).join(',').trim();
      final rest = parts.skip(2).join(',').trim();
      return [l1, if (rest.isNotEmpty)
        (rest.length > max ? '${rest.substring(0, max - 1)}\u2026' : rest)];
    }
    return ['${text.substring(0, max - 1)}\u2026'];
  }
}
