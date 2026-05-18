// lib/watermark/layouts/layout_polaroid.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

/// Polaroid — bingkai foto instan. Canvas ivory/putih dengan
/// border tebal semua sisi, area teks luas di bawah foto.
class LayoutPolaroid extends WatermarkLayoutBase {
  @override
  String get name => 'Polaroid';

  static const int _borderTop    = 20;
  static const int _borderSide   = 20;
  static const int _borderBottom = 110;
  static const int _padX         = 12;

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
    final int srcW = src.width;
    final int srcH = src.height;
    final int newW = srcW + _borderSide * 2;
    final int newH = srcH + _borderTop + _borderBottom;

    // ── Canvas ivory ──────────────────────────────────────────────
    final canvas = img.Image(width: newW, height: newH);
    img.fillRect(canvas, x1: 0, y1: 0, x2: newW - 1, y2: newH - 1,
        color: img.ColorRgba8(250, 247, 238, 255));

    // Vignette subtle di sudut canvas
    for (final corner in [
      [0, 0], [newW - 1, 0], [0, newH - 1], [newW - 1, newH - 1]
    ]) {
      for (int i = 0; i < 20; i++) {
        final int cx = corner[0] == 0 ? i : newW - 1 - i;
        final int cy = corner[1] == 0 ? i : newH - 1 - i;
        img.fillRect(canvas, x1: cx - 1, y1: cy - 1, x2: cx + 1, y2: cy + 1,
            color: img.ColorRgba8(0, 0, 0, (20 - i).clamp(0, 20)));
      }
    }

    // ── Border luar (sedikit bayangan) ────────────────────────────
    if (showBorder) {
      img.drawRect(canvas, x1: 0, y1: 0, x2: newW - 1, y2: newH - 1,
          color: img.ColorRgba8(200, 195, 180, 255), thickness: 1);
    }

    // ── Shadow foto ───────────────────────────────────────────────
    for (int s = 6; s > 0; s--) {
      final int alpha = (6 - s) * 6;
      img.fillRect(canvas,
          x1: _borderSide + s, y1: _borderTop + s,
          x2: _borderSide + srcW + s, y2: _borderTop + srcH + s,
          color: img.ColorRgba8(0, 0, 0, alpha));
    }

    // ── Foto ──────────────────────────────────────────────────────
    img.compositeImage(canvas, src,
        dstX: _borderSide, dstY: _borderTop, blend: img.BlendMode.direct);

    // ── Area teks bawah ───────────────────────────────────────────
    final int textBase = srcH + _borderTop;
    final small = img.arial14;
    final big   = fontSize == 'large' ? img.arial24 : img.arial24;

    final textColor  = img.ColorRgba8(40, 35, 25, 255);
    final greyColor  = img.ColorRgba8(110, 100, 85, 255);
    final accentColor = img.ColorRgba8(80, 120, 180, 255);

    // Jam + tanggal
    int cy = textBase + 14;
    img.drawString(canvas,
        DateFormat('HH:mm').format(timestamp),
        font: big, x: _borderSide + _padX, y: cy,
        color: textColor);

    final String dateStr = DateFormat('dd MMM yyyy').format(timestamp);
    final int dateW = dateStr.length * 8;
    img.drawString(canvas, dateStr,
        font: small, x: newW - _borderSide - _padX - dateW, y: cy + 6,
        color: greyColor);

    cy += 30;

    // Garis tipis
    img.fillRect(canvas,
        x1: _borderSide + _padX, y1: cy,
        x2: newW - _borderSide - _padX, y2: cy + 1,
        color: img.ColorRgba8(180, 170, 150, 255));
    cy += 8;

    // Koordinat
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      img.drawString(canvas,
          '${_fmtCoord(lat, true)}  ${_fmtCoord(lon, false)}'
          '${showAccuracy && acc != null ? '  \u00b1${acc.toStringAsFixed(0)}m' : ''}',
          font: small, x: _borderSide + _padX, y: cy,
          color: accentColor);
      cy += 20;
    }

    // Alamat
    if (showAddress && _isValidAddr(address)) {
      final int maxLen = (newW - _borderSide * 2 - _padX * 2) ~/ 8;
      for (final line in _splitAddr(address, maxLen).take(2)) {
        if (cy > newH - 10) break;
        img.drawString(canvas, line,
            font: small, x: _borderSide + _padX, y: cy,
            color: greyColor);
        cy += 18;
      }
    }

    // Cuaca
    if (showWeather && weather.isNotEmpty && cy < newH - 10) {
      img.drawString(canvas, weather,
          font: small, x: _borderSide + _padX, y: cy,
          color: img.ColorRgba8(60, 130, 80, 255));
    }

    return WatermarkLayoutBase.encodeJpg(canvas);
  }

  bool _isValidAddr(String a) =>
      a.isNotEmpty && a != 'Tidak ada lokasi' && !a.startsWith('GPS:');
  String _fmtCoord(double v, bool isLat) =>
      '${v.abs().toStringAsFixed(5)}\u00b0${v >= 0 ? (isLat ? 'N' : 'E') : (isLat ? 'S' : 'W')}';

  List<String> _splitAddr(String text, int max) {
    if (max < 5) max = 5;
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
