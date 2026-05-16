import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

/// Layout Cinematic — map strip di atas, teks di bawah (atau sebaliknya jika isTop).
///
/// Struktur panel (isBottom / watermarkPosition == 'bottom'):
///   ┌─────────────────────────────┐
///   │  [MAP STRIP — full width]   │  mapStripH px
///   ├─────────────────────────────┤
///   │  HH : mm : ss    DD MMM YY  │  jam + tanggal satu baris
///   │  ─────────────────────────  │  divider biru
///   │  lat°N   lon°E              │  koordinat DMS
///   │  ACCURACY ±X m              │  (opsional)
///   │  Alamat baris 1             │  auto-wrap tidak dibatasi
///   │  Alamat baris 2             │
///   │  …                          │
///   │  Cuaca                      │  (opsional)
///   └─────────────────────────────┘
class LayoutCinematic extends WatermarkLayoutBase {
  @override
  String get name => 'Cinematic';

  // ── Konstanta layout ────────────────────────────────────────────────────
  static const int padX       = 28;
  static const int padY       = 14;
  static const int lineHLg    = 32;   // jam (arial24)
  static const int lineHSm    = 22;   // semua baris arial14
  static const int dividerGap = 8;    // jarak di atas & bawah garis biru
  static const int mapStripH  = 110;  // tinggi strip map
  static const int mapBorder  = 2;
  static const int recPillW   = 72;
  static const int recPillH   = 20;

  // ── Palet ───────────────────────────────────────────────────────────────
  static final img.Color cBlue     = img.ColorRgba8(30,  144, 255, 255);
  static final img.Color cWhite    = img.ColorRgba8(255, 255, 255, 255);
  static final img.Color cOffWhite = img.ColorRgba8(215, 215, 220, 255);
  static final img.Color cGrey     = img.ColorRgba8(170, 170, 175, 220);
  static final img.Color cRed      = img.ColorRgba8(255,  50,  50, 255);
  static final img.Color cPanelBg  = img.ColorRgba8( 18,  18,  20, 215);

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

    // ── Hitung baris alamat (tidak dibatasi) ─────────────────────────────
    final bool showAddr = address.isNotEmpty &&
        address != 'Tidak ada lokasi' &&
        !address.startsWith('GPS:');
    final int textW = src.width - padX * 2;
    final List<String> addrLines = showAddr ? _wrapText(address, textW) : [];

    // ── Hitung tinggi area teks ──────────────────────────────────────────
    // jam+tanggal (satu baris arial24 + sedikit serif arial14 di bawah),
    // divider, koordinat, accuracy, alamat, cuaca
    int textH = padY
        + lineHLg                        // jam & tanggal sejajar
        + dividerGap + 2 + dividerGap   // divider
        + (hasPosition ? lineHSm : 0)   // koordinat DMS
        + (hasPosition && showAccuracy && acc != null ? lineHSm : 0)
        + addrLines.length * lineHSm
        + (showWeather && weather.isNotEmpty ? lineHSm : 0)
        + padY;

    final int mapH   = hasMap ? mapStripH + mapBorder * 2 : 0;
    final int panelH = mapH + textH;

    // ── Posisi panel ─────────────────────────────────────────────────────
    final int panelY = isTop ? 0 : src.height - panelH;

    // ── 1. Panel background solid ────────────────────────────────────────
    _fillPanel(src, panelY, panelH);

    // ── 2. Gradient transisi ke foto (sisi panel yang menempel foto) ─────
    _applyEdgeGradient(src, panelY, panelH, isTop);

    // ── 3. Map strip ─────────────────────────────────────────────────────
    int textY; // y awal teks
    if (hasMap) {
      final int mapY = isTop ? panelY : panelY;          // map paling atas panel
      _drawMapStrip(src, mapBytes!, mapY, mapStripH);
      textY = isTop ? panelY + mapH : panelY + mapH;
    } else {
      textY = panelY;
    }

    // ── 4. Jam & Tanggal — satu baris ───────────────────────────────────
    int cy = textY + padY;

    final String timeStr = DateFormat('HH : mm : ss').format(timestamp);
    final String dateStr = DateFormat('EEE, dd MMM yyyy').format(timestamp).toUpperCase();

    _drawText(src, timeStr, img.arial24, padX, cy, cWhite, shadow: 2);

    // Tanggal di kanan, vertikal center terhadap jam
    final int dateX = src.width - padX - _estimateTextWidth(dateStr, img.arial14);
    final int dateY = cy + (lineHLg - lineHSm) ~/ 2 + 4;
    _drawText(src, dateStr, img.arial14, dateX.clamp(padX, src.width - padX), dateY, cBlue, shadow: 1);
    cy += lineHLg;

    // ── 5. Divider biru ──────────────────────────────────────────────────
    cy += dividerGap;
    img.fillRect(src, x1: padX, y1: cy, x2: src.width - padX, y2: cy + 2, color: cBlue);
    cy += 2 + dividerGap;

    // ── 6. Koordinat DMS ─────────────────────────────────────────────────
    if (hasPosition && lat != null && lon != null) {
      final latDms = _toDMS(lat.abs(), lat >= 0 ? 'N' : 'S');
      final lonDms = _toDMS(lon.abs(), lon >= 0 ? 'E' : 'W');
      _drawText(src, '$latDms   $lonDms', img.arial14, padX, cy, cOffWhite, shadow: 1);
      cy += lineHSm;

      if (showAccuracy && acc != null) {
        _drawText(src, 'ACCURACY  ±${acc.toStringAsFixed(1)} m',
            img.arial14, padX, cy, cGrey, shadow: 1);
        cy += lineHSm;
      }
    }

    // ── 7. Alamat (semua baris, auto-expand) ─────────────────────────────
    for (final line in addrLines) {
      _drawText(src, line, img.arial14, padX, cy, cGrey, shadow: 1);
      cy += lineHSm;
    }

    // ── 8. Cuaca ─────────────────────────────────────────────────────────
    if (showWeather && weather.isNotEmpty) {
      _drawText(src, weather, img.arial14, padX, cy, cBlue, shadow: 1);
    }

    // ── 9. REC indicator (pojok kanan, sejajar jam) ──────────────────────
    _drawRec(src, textY + padY + (lineHLg - recPillH) ~/ 2);

    return WatermarkLayoutBase.encodeJpg(src);
  }

  // ── Panel background ─────────────────────────────────────────────────────
  void _fillPanel(img.Image src, int y0, int h) {
    final int y1 = (y0 + h).clamp(0, src.height);
    final int y0c = y0.clamp(0, src.height);
    for (int y = y0c; y < y1; y++) {
      for (int x = 0; x < src.width; x++) {
        final px = src.getPixel(x, y);
        final int a = cPanelBg.a.toInt();
        src.setPixel(x, y, img.ColorRgba8(
          (px.r * (255 - a) ~/ 255) + (cPanelBg.r.toInt() * a ~/ 255),
          (px.g * (255 - a) ~/ 255) + (cPanelBg.g.toInt() * a ~/ 255),
          (px.b * (255 - a) ~/ 255) + (cPanelBg.b.toInt() * a ~/ 255),
          255,
        ));
      }
    }
  }

  // ── Gradient tipis di sisi panel yang menempel foto ──────────────────────
  void _applyEdgeGradient(img.Image src, int panelY, int panelH, bool isTop) {
    const int fadeH = 24;
    // Sisi yang menempel foto:
    // isTop  → bawah panel (panelY + panelH - fadeH .. panelY + panelH)
    // isBot  → atas panel  (panelY .. panelY + fadeH)
    final int fadeStart = isTop ? panelY + panelH - fadeH : panelY;
    final int fadeEnd   = isTop ? panelY + panelH         : panelY + fadeH;

    for (int y = fadeStart; y < fadeEnd; y++) {
      if (y < 0 || y >= src.height) continue;
      double t = (y - fadeStart) / fadeH; // 0→1
      if (!isTop) t = 1.0 - t;            // isBottom: opak di atas, transparan di bawah
      final int overlay = (t * 215).toInt().clamp(0, 215);
      for (int x = 0; x < src.width; x++) {
        final px = src.getPixel(x, y);
        src.setPixel(x, y, img.ColorRgba8(
          (px.r * (255 - overlay)) ~/ 255,
          (px.g * (255 - overlay)) ~/ 255,
          (px.b * (255 - overlay)) ~/ 255,
          255,
        ));
      }
    }
  }

  // ── Map strip full-width ──────────────────────────────────────────────────
  void _drawMapStrip(img.Image src, Uint8List mapBytes, int mapY, int stripH) {
    img.Image? mapImg;
    try { mapImg = img.decodeImage(mapBytes); } catch (_) {}
    if (mapImg == null) return;

    try {
      final resized = img.copyResize(mapImg,
          width: src.width, height: stripH,
          interpolation: img.Interpolation.average);

      // Batas atas/bawah map
      final int y0 = mapY.clamp(0, src.height);
      final int y1 = (mapY + stripH).clamp(0, src.height);
      if (y1 <= y0) return;

      img.compositeImage(src, resized, dstX: 0, dstY: y0, blend: img.BlendMode.alpha);

      // Blue-dark tint supaya tetap terasa cinematic
      for (int y = y0; y < y1; y++) {
        for (int x = 0; x < src.width; x++) {
          final px = src.getPixel(x, y);
          src.setPixel(x, y, img.ColorRgba8(
            (px.r * 0.70).toInt().clamp(0, 255),
            (px.g * 0.70).toInt().clamp(0, 255),
            (px.b * 0.85).toInt().clamp(0, 255),
            255,
          ));
        }
      }

      // Garis pemisah biru di bawah map strip
      final int sepY = (y1 - mapBorder).clamp(0, src.height - 1);
      img.fillRect(src,
          x1: 0, y1: sepY,
          x2: src.width, y2: sepY + mapBorder,
          color: img.ColorRgba8(30, 144, 255, 200));

      // Crosshair / dot posisi di tengah
      final int cx = src.width ~/ 2;
      final int cy = y0 + (y1 - y0) ~/ 2;
      img.fillCircle(src, x: cx, y: cy, radius: 8, color: img.ColorRgba8(30, 144, 255, 180));
      img.fillCircle(src, x: cx, y: cy, radius: 4, color: cWhite);

    } catch (_) {}
  }

  // ── REC indicator ────────────────────────────────────────────────────────
  void _drawRec(img.Image src, int pillY) {
    final int pillX = src.width - recPillW - padX;
    if (pillX < 0 || pillY < 0 || pillY + recPillH > src.height) return;

    img.fillRect(src,
        x1: pillX, y1: pillY,
        x2: pillX + recPillW, y2: pillY + recPillH,
        color: img.ColorRgba8(0, 0, 0, 160));
    img.drawRect(src,
        x1: pillX, y1: pillY,
        x2: pillX + recPillW, y2: pillY + recPillH,
        color: img.ColorRgba8(255, 255, 255, 30),
        thickness: 1);
    img.fillCircle(src,
        x: pillX + 12, y: pillY + recPillH ~/ 2,
        radius: 5, color: cRed);
    _drawText(src, 'REC 4K', img.arial14, pillX + 22, pillY + 4, cWhite, shadow: 1);
  }

  // ── Teks dengan drop-shadow ───────────────────────────────────────────────
  void _drawText(
    img.Image src, String text, img.BitmapFont font,
    int x, int y, img.Color color, {int shadow = 1}
  ) {
    final sh = img.ColorRgba8(0, 0, 0, 180);
    for (int dx = -shadow; dx <= shadow; dx++) {
      for (int dy = -shadow; dy <= shadow; dy++) {
        if (dx == 0 && dy == 0) continue;
        img.drawString(src, text, font: font, x: x + dx, y: y + dy, color: sh);
      }
    }
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  // ── Konversi desimal → DMS ────────────────────────────────────────────────
  String _toDMS(double deg, String dir) {
    final int d = deg.floor();
    final double minFull = (deg - d) * 60;
    final int m = minFull.floor();
    final double s = (minFull - m) * 60;
    return "$d°${m.toString().padLeft(2, '0')}'${s.toStringAsFixed(1).padLeft(4, '0')}\"$dir";
  }

  // ── Estimasi lebar teks arial14 (~8px/char) ───────────────────────────────
  int _estimateTextWidth(String text, img.BitmapFont font) {
    return text.length * (font == img.arial24 ? 14 : 8);
  }

  // ── Word-wrap tanpa batas baris (auto-expand) ─────────────────────────────
  List<String> _wrapText(String text, int maxWidth) {
    const int charW = 8;
    final int maxChars = (maxWidth / charW).floor().clamp(20, 200);

    final words  = text.split(' ');
    final lines  = <String>[];
    var   current = '';

    for (final word in words) {
      final candidate = current.isEmpty ? word : '$current $word';
      if (candidate.length <= maxChars) {
        current = candidate;
      } else {
        if (current.isNotEmpty) lines.add(current);
        current = word.length > maxChars
            ? '${word.substring(0, maxChars - 2)}..'
            : word;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines;
  }
}
