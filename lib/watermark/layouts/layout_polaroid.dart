import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import '../wm_helpers.dart';
import 'watermark_layout_base.dart';

/// Layout Polaroid — border putih lebar di bawah, teks hitam di atasnya
///
///   ┌──────────────────────────────────────┐
///   │                                      │
///   │         [FOTO UTUH]                  │
///   │                                      │
///   ├──────────────────────────────────────┤ border putih tebal
///   │  Thu, 19 Jun 2025    10:07:07        │ teks hitam di bg putih
///   │  Stall No 05, Galta Gate…            │
///   │  26°54'N  75°48'E                    │
///   └──────────────────────────────────────┘
class LayoutPolaroid extends WatermarkLayoutBase {
  @override
  String get name => 'Polaroid';

  static const int _sideW  = 18;   // border kiri/kanan/atas
  static const int _botW   = 80;   // border bawah (lebih lebar, ciri khas polaroid)
  static const int _padX   = 28;
  static const int _padY   = 10;
  static const int _lineH  = 26;
  static const int _lineSm = 20;

  // Warna teks di area putih
  static final img.Color _cDark   = img.ColorRgb8(30, 30, 35);
  static final img.Color _cBlue   = img.ColorRgb8(30, 100, 200);
  static final img.Color _cMed    = img.ColorRgb8(90, 90, 100);

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
    final bool showAddr = address.isNotEmpty &&
        address != 'Tidak ada lokasi' &&
        !address.startsWith('GPS:');
    final int textW = src.width - _padX * 2 - _sideW * 2;
    final int maxChar = (textW / 8).floor().clamp(10, 200);
    final List<String> addrLines =
        showAddr ? wmWrapText(address, maxChar) : const [];

    // Hitung total tinggi canvas baru
    final int innerH = src.height; // foto asli
    final int totalH = _sideW + innerH + _botW;
    final int totalW = src.width + _sideW * 2;

    // Buat canvas baru dengan bg putih
    final canvas = img.Image(width: totalW, height: totalH);
    img.fill(canvas, color: img.ColorRgb8(248, 246, 240)); // putih ivory

    // Paste foto ke dalam frame
    img.compositeImage(canvas, src, dstX: _sideW, dstY: _sideW);

    // Bayangan lembut di tepi foto (efek polaroid nyata)
    _drawPhotoShadow(canvas, _sideW, _sideW, src.width, src.height);

    // ── Teks di area bawah ──────────────────────────────────────────────
    final int botY0 = _sideW + innerH; // y awal area bawah
    int cy = botY0 + _padY + 4;

    // Tanggal kiri, jam kanan
    final String dateStr =
        DateFormat('EEE, dd MMM yyyy').format(timestamp).toUpperCase();
    final String timeStr = DateFormat('HH:mm:ss').format(timestamp);
    _drawDark(canvas, dateStr, img.arial14, _padX + _sideW, cy, _cMed);
    final int timeX = totalW - _sideW - _padX - timeStr.length * 9;
    _drawDark(canvas, timeStr, img.arial14,
        timeX.clamp(_padX + _sideW, totalW - _sideW - _padX), cy, _cBlue);
    cy += _lineH;

    // Alamat
    for (final line in addrLines) {
      _drawDark(canvas, line, img.arial14, _padX + _sideW, cy, _cDark);
      cy += _lineSm;
    }

    // Koordinat
    if (hasPosition && lat != null && lon != null) {
      final coord =
          '${lat.abs().toStringAsFixed(5)}\u00b0${lat >= 0 ? 'N' : 'S'}  '
          '${lon.abs().toStringAsFixed(5)}\u00b0${lon >= 0 ? 'E' : 'W'}'
          '${showAccuracy && acc != null ? '  \u00b1${acc.toStringAsFixed(0)}m' : ''}';
      _drawDark(canvas, coord, img.arial14, _padX + _sideW, cy, _cMed);
    }

    return WatermarkLayoutBase.encodeJpg(canvas);
  }

  void _drawPhotoShadow(
      img.Image canvas, int fx, int fy, int fw, int fh) {
    const int sh = 3;
    for (int i = 1; i <= sh; i++) {
      final alpha = (60 * i ~/ sh).clamp(0, 60);
      // Bawah foto
      for (int x = fx; x < fx + fw; x++) {
        if (fy + fh + i < canvas.height) {
          final px = canvas.getPixel(x, fy + fh + i - 1);
          canvas.setPixel(x, fy + fh + i - 1, img.ColorRgba8(
            (px.r.toInt() * (255 - alpha) ~/ 255),
            (px.g.toInt() * (255 - alpha) ~/ 255),
            (px.b.toInt() * (255 - alpha) ~/ 255),
            255,
          ));
        }
      }
    }
  }

  // Teks hitam tanpa shadow (bg sudah putih)
  void _drawDark(img.Image src, String text, img.BitmapFont font,
      int x, int y, img.Color color) {
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }
}
