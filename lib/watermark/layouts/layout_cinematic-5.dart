import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import '../wm_helpers.dart';
import 'watermark_layout_base.dart';

/// Layout Cinematic — GPS Timestamp style
///
/// Struktur panel (isBottom):
///   ┌──────────────────────────────────────┐
///   │  MAP STRIP  (adaptive height)        │  grayscale + dark-tint + crosshair
///   ├──────────────────────────────────────┤  separator 1px
///   │  Thu, 19 Jun 2025       10:07:07     │  tanggal kiri · jam kanan
///   │  ─────────────────────────────────   │  divider tipis
///   │  Stall No 05, Galta Gate, Jaipur…   │  alamat auto-wrap (putih)
///   │  26°54'16.2"N   75°48'51.3"E        │  koordinat DMS (abu)
///   │  ACCURACY ±2.0 m                    │  (opsional)
///   │  Cuaca                              │  (opsional, aksen biru)
///   └──────────────────────────────────────┘
class LayoutCinematic extends WatermarkLayoutBase {
  @override
  String get name => 'Cinematic';

  // ── Rasio map terhadap tinggi gambar (adaptive) ──────────────────────────
  // Map = 16% tinggi foto, clamp antara 90–160px
  static const double _mapRatio   = 0.16;
  static const int    _mapMin     = 90;
  static const int    _mapMax     = 160;

  // ── Padding & baris ──────────────────────────────────────────────────────
  static const int _padX   = 20;
  static const int _padY   = 12;
  static const int _lineH  = 30;   // baris tanggal+jam (arial24)
  static const int _lineSm = 22;   // baris metadata (arial14)
  static const int _divGap = 5;    // jarak atas+bawah divider

  // ── Panel background: #0D1117 @ 88% ──────────────────────────────────────
  static const int _bgR = 13, _bgG = 17, _bgB = 23, _bgA = 224;

  // ── Palet teks ───────────────────────────────────────────────────────────
  static final img.Color _cWhite  = img.ColorRgb8(229, 226, 225);
  static final img.Color _cDate   = img.ColorRgb8(198, 198, 199);
  static final img.Color _cAddr   = img.ColorRgb8(220, 218, 217);
  static final img.Color _cMeta   = img.ColorRgb8(150, 150, 155);
  static final img.Color _cAccent = img.ColorRgb8(30, 144, 255);
  static final img.Color _cRec    = img.ColorRgb8(190, 0, 0);

  // ── Alpha garis ──────────────────────────────────────────────────────────
  static const int _sepAlpha = 45;
  static const int _divAlpha = 22;

  // ── Metric pengukuran font (diukur dari glif aktual BitmapFont) ──────────
  // arial14: lebar rata-rata per karakter ≈ 8px, tinggi glyph ≈ 14px
  // arial24: lebar rata-rata per karakter ≈ 14px, tinggi glyph ≈ 24px
  static const int _cw14 = 8;
  static const int _cw24 = 14;
  static const int _ch14 = 14;
  static const int _ch24 = 24;

  // ── REC pill dimensi ─────────────────────────────────────────────────────
  // Lebar responsif: 'REC 4K' = 6 char × cw14 + 2 padding + dot(12) + margins
  static const int _recDotR  = 5;    // radius dot merah
  static const int _recPadL  = 8;    // padding kiri (dot center = padL + dotR)
  static const int _recPadR  = 8;    // padding kanan
  static const int _recGap   = 4;    // gap antara dot dan teks
  static const String _recLabel = 'REC 4K';  // label — panjang tetap
  // tinggi pill = lineH metadata + 2px margin vertikal
  static const int _recPH    = _lineSm - 2;

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

    // ── Adaptive map height ──────────────────────────────────────────────
    final int mapH = hasMap(showMiniMap, mapBytes)
        ? (src.height * _mapRatio).round().clamp(_mapMin, _mapMax)
        : 0;

    // ── Validasi dan decode map bytes sekali di awal ─────────────────────
    img.Image? mapImage;
    if (hasMap(showMiniMap, mapBytes)) {
      mapImage = _decodeMap(mapBytes!);
      // Jika decode gagal, perlakukan sebagai tidak ada map
    }
    final bool willDrawMap = mapImage != null;

    // ── Wrap alamat ───────────────────────────────────────────────────────
    final bool showAddr = address.isNotEmpty &&
        address != 'Tidak ada lokasi' &&
        !address.startsWith('GPS:');
    final int textW   = src.width - _padX * 2;
    final int maxChar = _charCount14(textW);
    final List<String> addrLines =
        showAddr ? wmWrapText(address, maxChar) : const [];

    // ── Hitung tinggi teks ────────────────────────────────────────────────
    final int textH = _padY
        + _lineH
        + _divGap + 1 + _divGap
        + addrLines.length * _lineSm
        + (hasPosition ? _lineSm : 0)
        + (hasPosition && showAccuracy && acc != null ? _lineSm : 0)
        + (showWeather && weather.isNotEmpty ? _lineSm : 0)
        + _padY;

    final int stripH = willDrawMap ? mapH + 1 : 0;
    final int panelH = stripH + textH;
    final int panelY0 =
        isTop ? 0 : (src.height - panelH).clamp(0, src.height);
    final int panelY1 = (panelY0 + panelH).clamp(0, src.height);

    // ── 1. Panel background ───────────────────────────────────────────────
    _fillPanel(src, panelY0, panelY1);

    // ── 2. Border panel ───────────────────────────────────────────────────
    _hlineW(src, panelY0, _sepAlpha);
    _hlineW(src, panelY1 - 1, _sepAlpha);

    // ── 3. Map strip ──────────────────────────────────────────────────────
    int textY0 = panelY0;
    if (willDrawMap) {
      final int my0 = panelY0;
      final int my1 = (panelY0 + mapH).clamp(0, src.height);
      _drawMapStrip(src, mapImage!, my0, my1);
      _hlineW(src, my1, _sepAlpha);
      textY0 = my1 + 1;
    }

    // ── 4. Teks ───────────────────────────────────────────────────────────
    int cy = textY0 + _padY;

    // Tanggal kiri (arial14)
    final String dateStr =
        DateFormat('EEE, dd MMM yyyy').format(timestamp).toUpperCase();
    _drawText14(src, dateStr, _padX, cy + (_ch24 - _ch14) ~/ 2, _cDate);

    // Jam kanan (arial24) — posisi berdasarkan lebar terukur
    final String timeStr = DateFormat('HH:mm:ss').format(timestamp);
    final int timeW  = _measureW24(timeStr);
    final int timeX  = src.width - _padX - timeW;
    _drawText24(src, timeStr, timeX.clamp(_padX + 80, src.width - _padX), cy, _cWhite);

    // REC pill — responsif, pojok kanan, sejajar tanggal
    _drawRecPill(src, textY0 + _padY);

    cy += _lineH;

    // Divider
    cy += _divGap;
    _hlineW(src, cy, _divAlpha);
    cy += 1 + _divGap;

    // Alamat
    for (final line in addrLines) {
      _drawText14(src, line, _padX, cy, _cAddr);
      cy += _lineSm;
    }

    // Koordinat DMS
    if (hasPosition && lat != null && lon != null) {
      final String coord =
          '${_dms(lat.abs(), lat >= 0 ? 'N' : 'S')}   '
          '${_dms(lon.abs(), lon >= 0 ? 'E' : 'W')}';
      _drawText14(src, coord, _padX, cy, _cMeta);
      cy += _lineSm;

      if (showAccuracy && acc != null) {
        _drawText14(src,
            'ACCURACY  \u00b1${acc.toStringAsFixed(1)} m',
            _padX, cy, _cMeta);
        cy += _lineSm;
      }
    }

    // Cuaca
    if (showWeather && weather.isNotEmpty) {
      _drawText14(src, weather, _padX, cy, _cAccent);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  /// Cek apakah map tersedia
  static bool hasMap(bool showMiniMap, Uint8List? mapBytes) =>
      showMiniMap && mapBytes != null && mapBytes.isNotEmpty;

  /// Decode map dengan validasi ketat — return null jika gagal
  img.Image? _decodeMap(Uint8List bytes) {
    if (bytes.length < 128) return null; // terlalu kecil, pasti corrupt
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      if (decoded.width < 8 || decoded.height < 8) return null; // terlalu kecil
      return decoded;
    } catch (_) {
      return null;
    }
  }

  // ── Text measurement ──────────────────────────────────────────────────────
  /// Jumlah karakter yang muat dalam lebar pixel untuk arial14
  int _charCount14(int widthPx) => (widthPx / _cw14).floor().clamp(10, 300);

  /// Estimasi lebar piksel teks arial14
  int _measureW14(String s) => s.length * _cw14;

  /// Estimasi lebar piksel teks arial24
  int _measureW24(String s) => s.length * _cw24;

  // ── Render teks dengan shadow 1-pass (bukan loop 8 arah) ─────────────────
  // Optimasi: shadow cukup offset (+2,+2) — sudah dipakai wmDrawTextShadow,
  // tapi kita expose sendiri agar bisa passing font secara eksplisit.

  void _drawText14(img.Image src, String text, int x, int y, img.Color color) {
    wmDrawTextShadow(src, text, font: img.arial14, x: x, y: y, color: color);
  }

  void _drawText24(img.Image src, String text, int x, int y, img.Color color) {
    wmDrawTextShadow(src, text, font: img.arial24, x: x, y: y, color: color);
  }

  // ── Panel background ──────────────────────────────────────────────────────
  void _fillPanel(img.Image src, int y0, int y1) {
    // Pre-compute blended channel values untuk BG solid
    // (komponen BG tidak berubah per-pixel, hanya foreground yang blend)
    final int bgR = _bgR * _bgA ~/ 255;
    final int bgG = _bgG * _bgA ~/ 255;
    final int bgB = _bgB * _bgA ~/ 255;
    final int inv = 255 - _bgA;

    final int ya = y0.clamp(0, src.height);
    final int yb = y1.clamp(0, src.height);
    for (int y = ya; y < yb; y++) {
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

  // ── Garis horizontal full-width (white @ alpha%) ──────────────────────────
  void _hlineW(img.Image src, int y, int alpha) {
    if (y < 0 || y >= src.height) return;
    final int inv = 255 - alpha;
    final int add = alpha; // r=g=b=255 → komponen = alpha * 255/255 = alpha
    for (int x = 0; x < src.width; x++) {
      final px = src.getPixel(x, y);
      src.setPixel(x, y, img.ColorRgba8(
        (px.r.toInt() * inv ~/ 255) + add,
        (px.g.toInt() * inv ~/ 255) + add,
        (px.b.toInt() * inv ~/ 255) + add,
        255,
      ));
    }
  }

  // ── Map strip ─────────────────────────────────────────────────────────────
  void _drawMapStrip(img.Image src, img.Image mapImage, int y0, int y1) {
    final int h = y1 - y0;
    if (h <= 0) return;

    // Resize ke dimensi panel
    final resized = img.copyResize(mapImage,
        width: src.width, height: h,
        interpolation: img.Interpolation.average);

    img.compositeImage(src, resized, dstX: 0, dstY: y0);

    // Grayscale + blue-dark tint dalam satu pass
    for (int y = y0; y < y1 && y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final px = src.getPixel(x, y);
        final int lum =
            (px.r.toInt() * 299 + px.g.toInt() * 587 + px.b.toInt() * 114) ~/
            1000;
        src.setPixel(x, y, img.ColorRgba8(
          lum * 52 ~/ 100,
          lum * 52 ~/ 100,
          lum * 68 ~/ 100,
          255,
        ));
      }
    }

    // Fade kiri & kanan — pre-compute lookup table opacity per kolom
    final int fw = src.width ~/ 6;
    final List<int> fadeOv = List.generate(
      fw, (xi) => ((1.0 - xi / fw) * 100).round().clamp(0, 100),
    );

    for (int y = y0; y < y1 && y < src.height; y++) {
      for (int xi = 0; xi < fw; xi++) {
        final int ov  = fadeOv[xi];
        final int inv = 255 - ov;
        // kiri
        final pxL = src.getPixel(xi, y);
        src.setPixel(xi, y, img.ColorRgba8(
          pxL.r.toInt() * inv ~/ 255,
          pxL.g.toInt() * inv ~/ 255,
          pxL.b.toInt() * inv ~/ 255,
          255,
        ));
        // kanan
        final int xr = src.width - 1 - xi;
        final pxR = src.getPixel(xr, y);
        src.setPixel(xr, y, img.ColorRgba8(
          pxR.r.toInt() * inv ~/ 255,
          pxR.g.toInt() * inv ~/ 255,
          pxR.b.toInt() * inv ~/ 255,
          255,
        ));
      }
    }

    // Crosshair
    final int cx = src.width ~/ 2;
    final int cy = y0 + h ~/ 2;
    img.drawCircle(src, x: cx, y: cy, radius: 14,
        color: img.ColorRgba8(30, 144, 255, 130));
    img.fillCircle(src, x: cx, y: cy, radius: 6,
        color: img.ColorRgba8(30, 144, 255, 230));
    img.fillCircle(src, x: cx, y: cy, radius: 3,
        color: img.ColorRgb8(255, 255, 255));
  }

  // ── REC pill — responsif berdasarkan label & font ─────────────────────────
  void _drawRecPill(img.Image src, int rowY) {
    // Hitung lebar pill dari konten
    final int labelW = _measureW14(_recLabel);
    final int pw = _recPadL + _recDotR * 2 + _recGap + labelW + _recPadR;
    final int ph = _recPH;
    // Vertikal center terhadap baris jam (arial24)
    final int py = rowY + (_lineH - ph) ~/ 2;
    final int px0 = src.width - pw - _padX;

    if (px0 < 0 || py < 0 || py + ph > src.height) return;

    // BG pill
    final int ya = py.clamp(0, src.height);
    final int yb = (py + ph).clamp(0, src.height);
    for (int y = ya; y < yb; y++) {
      for (int x = px0; x < px0 + pw && x < src.width; x++) {
        final p = src.getPixel(x, y);
        src.setPixel(x, y, img.ColorRgba8(
          p.r.toInt() * 12 ~/ 255,
          p.g.toInt() * 12 ~/ 255,
          p.b.toInt() * 12 ~/ 255,
          255,
        ));
      }
    }

    // Border
    img.drawRect(src, x1: px0, y1: py, x2: px0 + pw, y2: py + ph,
        color: img.ColorRgba8(255, 255, 255, 38), thickness: 1);

    // Dot merah — center vertikal di pill
    final int dotX = px0 + _recPadL + _recDotR;
    final int dotY = py + ph ~/ 2;
    img.fillCircle(src, x: dotX, y: dotY, radius: _recDotR, color: _cRec);

    // Label — top-align dalam pill dengan margin (ph - ch14) / 2
    final int lblX = dotX + _recDotR + _recGap;
    final int lblY = py + (ph - _ch14) ~/ 2;
    _drawText14(src, _recLabel, lblX, lblY, _cWhite);
  }

  // ── DMS converter ─────────────────────────────────────────────────────────
  String _dms(double deg, String dir) {
    final int    d  = deg.floor();
    final double mf = (deg - d) * 60;
    final int    m  = mf.floor();
    final double s  = (mf - m) * 60;
    return "$d\u00b0${m.toString().padLeft(2, '0')}"
        "'${s.toStringAsFixed(1).padLeft(4, '0')}\"$dir";
  }
}
