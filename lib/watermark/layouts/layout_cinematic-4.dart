import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

/// Layout "Cinematic / Optic Narrative"
///
/// Mengikuti desain referensi GPS Timestamp (updated_gps_timestamp_view):
///
///   ┌─────────────────────────────────┐  ← panel bg rgba(0,0,0,0.82), border putih 1px
///   │  MAP STRIP  (full-width, 110px) │  grayscale + blue-tint, crosshair tengah
///   ├─────────────────────────────────┤  separator putih 1px opacity-15
///   │  🗓 Thu, 19 Jun 2025            │  ← baris tanggal  (JetBrains-style)
///   │  🕐 10:07:07.829                │  ← baris jam
///   │  ────────────────────           │  divider putih opacity-10
///   │  Stall No 05, Galta Gate, …    │  ← alamat full, auto-wrap, putih terang
///   │  26°54'16.2"N   75°48'51.3"E   │  ← koordinat DMS  (lebih kecil)
///   │  ACCURACY ±X m                  │  (opsional)
///   │  🌤 Cuaca                       │  (opsional)
///   └─────────────────────────────────┘
class LayoutCinematic extends WatermarkLayoutBase {
  @override
  String get name => 'Cinematic';

  // ── Dimensi panel ───────────────────────────────────────────────────────
  static const int mapStripH  = 110;  // tinggi strip map
  static const int padX       = 20;   // margin kiri/kanan
  static const int padYInner  = 14;   // padding atas/bawah area teks
  static const int lineHLg    = 28;   // baris tanggal / jam (arial24)
  static const int lineHSm    = 20;   // baris metadata (arial14)
  static const int divGap     = 6;    // jarak atas-bawah divider

  // ── Palet "Optic Narrative" ─────────────────────────────────────────────
  // Panel BG  = #131313 @ 82% → blend alpha 209
  static const int _bgR = 19, _bgG = 19, _bgB = 19, _bgA = 209;
  // Separator = white @ 15%
  static const int _sepA = 38;
  // Divider   = white @ 10%
  static const int _divA = 25;

  static final img.Color cWhite    = img.ColorRgba8(229, 226, 225, 255); // on-surface
  static final img.Color cDate     = img.ColorRgba8(198, 198, 199, 255); // secondary-fixed-dim
  static final img.Color cAddr     = img.ColorRgba8(229, 226, 225, 230); // on-surface sedikit redup
  static final img.Color cMeta     = img.ColorRgba8(165, 165, 168, 200); // redup
  static final img.Color cAccent   = img.ColorRgba8(255, 180, 168, 255); // primary (#ffb4a8)
  static final img.Color cRec      = img.ColorRgba8(190,   0,   0, 255); // primary-container
  static final img.Color cCross    = img.ColorRgba8(255, 180, 168, 220); // crosshair

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
    final bool isTop  = watermarkPosition == 'top';
    final bool hasMap = showMiniMap && mapBytes != null && mapBytes.isNotEmpty;

    // ── Siapkan baris alamat (tidak dibatasi) ───────────────────────────
    final bool showAddr = address.isNotEmpty &&
        address != 'Tidak ada lokasi' &&
        !address.startsWith('GPS:');
    final int textAreaW = src.width - padX * 2;
    final List<String> addrLines =
        showAddr ? _wrap(address, textAreaW) : const [];

    // ── Hitung tinggi area teks ─────────────────────────────────────────
    //   tanggal + jam + divider + alamat[] + koordinat + accuracy + cuaca + paddings
    int textH = padYInner
        + lineHLg             // tanggal
        + lineHLg             // jam
        + divGap + 1 + divGap // divider
        + addrLines.length * lineHSm
        + (hasPosition ? lineHSm : 0)
        + (hasPosition && showAccuracy && acc != null ? lineHSm : 0)
        + (showWeather && weather.isNotEmpty ? lineHSm : 0)
        + padYInner;

    final int stripH  = hasMap ? mapStripH + 1 : 0; // +1 px separator
    final int panelH  = stripH + textH;
    final int panelY0 = isTop ? 0 : (src.height - panelH).clamp(0, src.height);
    final int panelY1 = (panelY0 + panelH).clamp(0, src.height);

    // ── 1. Panel background solid ───────────────────────────────────────
    _blendRect(src, panelY0, panelY1);

    // ── 2. Border atas/bawah panel (white 15%) ──────────────────────────
    _hline(src, panelY0, _sepA);           // garis atas panel
    _hline(src, panelY1 - 1, _sepA);      // garis bawah panel

    // ── 3. Map strip ────────────────────────────────────────────────────
    int textY0 = panelY0;
    if (hasMap) {
      final int my0 = panelY0;
      final int my1 = (panelY0 + mapStripH).clamp(0, src.height);
      _drawMap(src, mapBytes!, my0, my1);
      // separator tipis bawah map
      _hline(src, my1, _sepA);
      textY0 = my1 + 1;
    }

    // ── 4. Teks ─────────────────────────────────────────────────────────
    int cy = textY0 + padYInner;

    // Tanggal
    _txt(src, DateFormat('EEE, dd MMM yyyy').format(timestamp),
        img.arial24, padX, cy, cDate, sh: 1);
    cy += lineHLg;

    // Jam
    _txt(src, DateFormat('HH:mm:ss').format(timestamp),
        img.arial24, padX, cy, cWhite, sh: 1);
    cy += lineHLg;

    // REC pill: pojok kanan sejajar tanggal-jam
    final int recPillY = textY0 + padYInner + (lineHLg * 2 - 20) ~/ 2;
    _drawRec(src, recPillY);

    // Divider putih tipis
    cy += divGap;
    _hlineRange(src, cy, padX, src.width - padX, _divA);
    cy += 1 + divGap;

    // Alamat (prioritas, warna terang)
    for (final line in addrLines) {
      _txt(src, line, img.arial14, padX, cy, cAddr, sh: 1);
      cy += lineHSm;
    }

    // Koordinat DMS
    if (hasPosition && lat != null && lon != null) {
      final String coord =
          '${_dms(lat.abs(), lat >= 0 ? 'N' : 'S')}   '
          '${_dms(lon.abs(), lon >= 0 ? 'E' : 'W')}';
      _txt(src, coord, img.arial14, padX, cy, cMeta, sh: 1);
      cy += lineHSm;

      if (showAccuracy && acc != null) {
        _txt(src, 'ACCURACY  \u00b1${acc.toStringAsFixed(1)} m',
            img.arial14, padX, cy, cMeta, sh: 1);
        cy += lineHSm;
      }
    }

    // Cuaca
    if (showWeather && weather.isNotEmpty) {
      _txt(src, weather, img.arial14, padX, cy, cAccent, sh: 1);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  // ── Blend rect panel BG ─────────────────────────────────────────────────
  void _blendRect(img.Image src, int y0, int y1) {
    for (int y = y0.clamp(0, src.height); y < y1.clamp(0, src.height); y++) {
      for (int x = 0; x < src.width; x++) {
        final px = src.getPixel(x, y);
        src.setPixel(x, y, img.ColorRgba8(
          (px.r.toInt() * (255 - _bgA) ~/ 255) + (_bgR * _bgA ~/ 255),
          (px.g.toInt() * (255 - _bgA) ~/ 255) + (_bgG * _bgA ~/ 255),
          (px.b.toInt() * (255 - _bgA) ~/ 255) + (_bgB * _bgA ~/ 255),
          255,
        ));
      }
    }
  }

  // ── Garis horizontal full-width ─────────────────────────────────────────
  void _hline(img.Image src, int y, int alpha) {
    if (y < 0 || y >= src.height) return;
    for (int x = 0; x < src.width; x++) {
      final px = src.getPixel(x, y);
      src.setPixel(x, y, img.ColorRgba8(
        (px.r.toInt() * (255 - alpha) ~/ 255) + (255 * alpha ~/ 255),
        (px.g.toInt() * (255 - alpha) ~/ 255) + (255 * alpha ~/ 255),
        (px.b.toInt() * (255 - alpha) ~/ 255) + (255 * alpha ~/ 255),
        255,
      ));
    }
  }

  // ── Garis horizontal sebagian lebar ────────────────────────────────────
  void _hlineRange(img.Image src, int y, int x0, int x1, int alpha) {
    if (y < 0 || y >= src.height) return;
    for (int x = x0; x < x1 && x < src.width; x++) {
      final px = src.getPixel(x, y);
      src.setPixel(x, y, img.ColorRgba8(
        (px.r.toInt() * (255 - alpha) ~/ 255) + (255 * alpha ~/ 255),
        (px.g.toInt() * (255 - alpha) ~/ 255) + (255 * alpha ~/ 255),
        (px.b.toInt() * (255 - alpha) ~/ 255) + (255 * alpha ~/ 255),
        255,
      ));
    }
  }

  // ── Map strip ───────────────────────────────────────────────────────────
  void _drawMap(img.Image src, Uint8List mapBytes, int y0, int y1) {
    img.Image? mapImg;
    try { mapImg = img.decodeImage(mapBytes); } catch (_) {}
    if (mapImg == null) return;

    final int h = y1 - y0;
    if (h <= 0) return;

    try {
      final resized = img.copyResize(mapImg,
          width: src.width, height: h,
          interpolation: img.Interpolation.average);

      img.compositeImage(src, resized, dstX: 0, dstY: y0);

      // Grayscale + blue-dark tint (meniru `grayscale opacity-80` + bg-black/40)
      for (int y = y0; y < y1 && y < src.height; y++) {
        for (int x = 0; x < src.width; x++) {
          final px = src.getPixel(x, y);
          // Grayscale
          final int lum = (px.r.toInt() * 299 +
                           px.g.toInt() * 587 +
                           px.b.toInt() * 114) ~/
                          1000;
          // Blue tint: gelapkan + geser ke biru sedikit
          final int r = (lum * 55 ~/ 100).clamp(0, 255);
          final int g = (lum * 55 ~/ 100).clamp(0, 255);
          final int b = (lum * 70 ~/ 100).clamp(0, 255);
          src.setPixel(x, y, img.ColorRgba8(r, g, b, 255));
        }
      }

      // Gradient gelap kiri & kanan (dari-black/40)
      final int fadeW = src.width ~/ 5;
      for (int y = y0; y < y1 && y < src.height; y++) {
        for (int xi = 0; xi < fadeW; xi++) {
          final double t = 1.0 - xi / fadeW;
          final int ov = (t * 100).toInt().clamp(0, 100);
          for (final int x in [xi, src.width - 1 - xi]) {
            if (x < 0 || x >= src.width) continue;
            final px = src.getPixel(x, y);
            src.setPixel(x, y, img.ColorRgba8(
              (px.r.toInt() * (255 - ov) ~/ 255),
              (px.g.toInt() * (255 - ov) ~/ 255),
              (px.b.toInt() * (255 - ov) ~/ 255),
              255,
            ));
          }
        }
      }

      // Crosshair tengah (ikon location_on style)
      final int cx = src.width ~/ 2;
      final int cy = y0 + h ~/ 2;
      // Lingkaran luar accent
      img.drawCircle(src, x: cx, y: cy, radius: 12,
          color: img.ColorRgba8(cCross.r.toInt(), cCross.g.toInt(),
                                cCross.b.toInt(), 160));
      img.fillCircle(src, x: cx, y: cy, radius: 5, color: cCross);
      img.fillCircle(src, x: cx, y: cy, radius: 2, color: cWhite);

    } catch (_) {}
  }

  // ── REC indicator ────────────────────────────────────────────────────────
  void _drawRec(img.Image src, int py) {
    const int pw = 76, ph = 20;
    final int px0 = src.width - pw - padX;
    if (px0 < 0 || py < 0 || py + ph > src.height) return;

    // BG
    for (int y = py; y < py + ph && y < src.height; y++) {
      for (int x = px0; x < px0 + pw && x < src.width; x++) {
        final p = src.getPixel(x, y);
        src.setPixel(x, y, img.ColorRgba8(
          (p.r.toInt() * 25 ~/ 255),
          (p.g.toInt() * 25 ~/ 255),
          (p.b.toInt() * 25 ~/ 255),
          255,
        ));
      }
    }
    // Border putih tipis
    img.drawRect(src, x1: px0, y1: py,
        x2: px0 + pw, y2: py + ph,
        color: img.ColorRgba8(255, 255, 255, 40), thickness: 1);
    // Dot merah
    img.fillCircle(src, x: px0 + 11, y: py + ph ~/ 2,
        radius: 5, color: cRec);
    // Label
    _txt(src, 'REC 4K', img.arial14, px0 + 21, py + 4, cWhite, sh: 0);
  }

  // ── Teks + shadow ───────────────────────────────────────────────────────
  void _txt(img.Image src, String text, img.BitmapFont font,
      int x, int y, img.Color color, {int sh = 1}) {
    if (sh > 0) {
      final shadow = img.ColorRgba8(0, 0, 0, 190);
      for (int dx = -sh; dx <= sh; dx++) {
        for (int dy = -sh; dy <= sh; dy++) {
          if (dx == 0 && dy == 0) continue;
          img.drawString(src, text, font: font,
              x: x + dx, y: y + dy, color: shadow);
        }
      }
    }
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  // ── DMS ─────────────────────────────────────────────────────────────────
  String _dms(double deg, String dir) {
    final int d = deg.floor();
    final double mf = (deg - d) * 60;
    final int m = mf.floor();
    final double s = (mf - m) * 60;
    return "$d\u00b0${m.toString().padLeft(2,'0')}'${s.toStringAsFixed(1).padLeft(4,'0')}\"$dir";
  }

  // ── Word-wrap (tidak dibatasi baris) ────────────────────────────────────
  List<String> _wrap(String text, int maxWidth) {
    const int cw = 8; // estimasi arial14
    final int mc = (maxWidth / cw).floor().clamp(20, 200);
    final lines = <String>[];
    var cur = '';
    for (final w in text.split(' ')) {
      final cand = cur.isEmpty ? w : '$cur $w';
      if (cand.length <= mc) {
        cur = cand;
      } else {
        if (cur.isNotEmpty) lines.add(cur);
        cur = w.length > mc ? '${w.substring(0, mc - 2)}..' : w;
      }
    }
    if (cur.isNotEmpty) lines.add(cur);
    return lines;
  }
}
