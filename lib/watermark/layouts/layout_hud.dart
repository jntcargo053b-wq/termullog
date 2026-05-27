// lib/watermark/layouts/layout_hud.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutHUD extends WatermarkLayoutBase {
  @override
  String get name => 'HUD Modern';

  // Warna tema HUD (cyan neon, navy gelap)
  static final _cyan    = img.ColorRgba8(  0, 210, 255, 255);
  static final _cyanDim = img.ColorRgba8(  0, 210, 255, 140);
  static final _white   = img.ColorRgba8(240, 245, 255, 255);
  static final _grey    = img.ColorRgba8(160, 170, 190, 255);
  static final _shadow  = img.ColorRgba8(  0,   0,   0, 200);
  static final _green   = img.ColorRgba8( 70, 220, 120, 255);
  static final _amber   = img.ColorRgba8(255, 190,  50, 255);
  static final _red     = img.ColorRgba8(240,  70,  70, 255);
  static final _bgTop   = img.ColorRgba8(  8,  12,  28, 220);
  static final _bgBottom= img.ColorRgba8(  4,   6,  16, 230);
  static final _scanLine= img.ColorRgba8(  0, 210, 255,  12);

  // --------------------------------------------------------------
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
    String mapSize = 'medium',
    String dateFormat = 'dd MMM yyyy',
    String timeFormat = 'HH:mm:ss',
  }) {
    final double scale = (src.width / 1080).clamp(0.7, 2.0);
    // Pilih font sesuai fontSize
    final img.BitmapFont fontLarge = (fontSize == 'large') ? img.arial24 : (fontSize == 'small') ? img.arial20 : img.arial24;
    final img.BitmapFont fontSmall = (fontSize == 'large') ? img.arial20 : (fontSize == 'small') ? img.arial12 : img.arial14;
    final int lineLarge = (fontLarge.height + 4).round();
    final int lineSmall = (fontSmall.height + 4).round();
    final int padX = (20 * scale).round();
    final int padY = (12 * scale).round();
    final int marginTop = (16 * scale).round();
    final int marginBottom = (16 * scale).round();

    // Hitung jumlah baris konten (selain header waktu)
    int rows = 0;
    if (showCoordinates && hasPosition && lat != null && lon != null) rows++;
    if (showAccuracy && hasPosition && acc != null) rows++;
    if (showAddress && _validAddr(address)) rows++;
    if (showWeather && weather.isNotEmpty) rows++;

    // Tinggi panel: header (waktu + tanggal) + separator + baris info + padding
    final int headerHeight = lineLarge + lineSmall + 8; // waktu + tanggal + spasi
    final int separatorHeight = 4;
    final int contentHeight = rows * lineSmall;
    final int panelH = padY * 2 + headerHeight + separatorHeight + contentHeight;
    final int y0 = src.height - panelH - marginBottom;
    if (y0 < 0 || y0 + panelH > src.height) return WatermarkLayoutBase.encodeJpg(src);

    // ── 1. Latar belakang gradien ─────────────────────────────────
    for (int y = y0; y < y0 + panelH; y++) {
      final double t = (y - y0) / panelH;
      final int r = _lerp(_bgTop.r, _bgBottom.r, t);
      final int g = _lerp(_bgTop.g, _bgBottom.g, t);
      final int b = _lerp(_bgTop.b, _bgBottom.b, t);
      final int a = (_lerp(_bgTop.a, _bgBottom.a, t) * opacity).toInt().clamp(0, 255);
      img.drawLine(src, x1: 0, y1: y, x2: src.width, y2: y, color: img.ColorRgba8(r, g, b, a));
    }

    // ── 2. Efek scan line (garis tipis setiap 4px) ─────────────────
    for (int y = y0; y < y0 + panelH; y += 4) {
      img.drawLine(src, x1: 0, y1: y, x2: src.width, y2: y, color: _scanLine);
    }

    // ── 3. Border atas dan bawah (cyan) ───────────────────────────
    if (showBorder) {
      img.drawLine(src, x1: 0, y1: y0, x2: src.width, y2: y0, color: _cyanDim, thickness: 2);
      img.drawLine(src, x1: 0, y1: y0 + panelH - 2, x2: src.width, y2: y0 + panelH - 2, color: _cyanDim, thickness: 2);
    }

    // ── 4. Kurung sudut (HUD signature) ───────────────────────────
    _drawCorners(src, x1: 0, y1: y0, x2: src.width, y2: y0 + panelH, color: _cyanDim);

    // ── 5. Konten ─────────────────────────────────────────────────
    int cy = y0 + padY;
    final int tx = padX;

    // Waktu besar (kiri) & tanggal (kanan)
    final timeStr = DateFormat(timeFormat).format(timestamp);
    _drawShadowText(src, timeStr, font: fontLarge, x: tx, y: cy, color: _white);
    final dateStr = DateFormat(dateFormat).format(timestamp);
    final dateWidth = dateStr.length * (fontSmall.width).round();
    _drawShadowText(src, dateStr, font: fontSmall, x: src.width - tx - dateWidth, y: cy + 4, color: _grey);
    cy += lineLarge + 4;

    // Separator garis tipis
    img.drawLine(src, x1: tx, y1: cy, x2: src.width - tx, y2: cy, color: _cyanDim.withAlpha(60));
    cy += separatorHeight;

    // Koordinat
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final latDir = lat >= 0 ? "N" : "S";
      final lonDir = lon >= 0 ? "E" : "W";
      final coordStr = "${lat.abs().toStringAsFixed(5)}° $latDir   ${lon.abs().toStringAsFixed(5)}° $lonDir";
      _drawShadowText(src, coordStr, font: fontSmall, x: tx, y: cy, color: _cyan);
      cy += lineSmall;
    }

    // Akurasi (dengan warna sesuai level)
    if (showAccuracy && hasPosition && acc != null) {
      final accColor = acc <= 5 ? _green : acc <= 20 ? _amber : _red;
      _drawShadowText(src, "GPS Accuracy  ± ${acc.toStringAsFixed(1)} m", font: fontSmall, x: tx, y: cy, color: accColor);
      cy += lineSmall;
    }

    // Alamat
    if (showAddress && _validAddr(address)) {
      final maxChars = ((src.width - tx * 2) / (fontSmall.width * 0.6)).toInt().clamp(30, 70);
      String shortAddr = address;
      if (address.length > maxChars) shortAddr = address.substring(0, maxChars - 3) + '…';
      _drawShadowText(src, shortAddr, font: fontSmall, x: tx, y: cy, color: _grey);
      cy += lineSmall;
    }

    // Cuaca (dengan latar highlight cyan transparan)
    if (showWeather && weather.isNotEmpty) {
      final weatherText = weather;
      final textWidth = weatherText.length * (fontSmall.width).round();
      // Highlight background
      img.fillRect(src, x1: tx - 4, y1: cy - 2, x2: tx + textWidth + 8, y2: cy + lineSmall - 2,
          color: img.ColorRgba8(0, 210, 255, 28));
      _drawShadowText(src, weatherText, font: fontSmall, x: tx, y: cy, color: _cyan);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  // Helper untuk teks dengan bayangan
  void _drawShadowText(img.Image src, String text, {
    required img.BitmapFont font, required int x, required int y, required img.Color color,
  }) {
    img.drawString(src, text, font: font, x: x + 1, y: y + 1, color: _shadow);
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  // Kurung sudut kiri-kanan (seperti head-up display)
  void _drawCorners(img.Image src, {required int x1, required int y1, required int x2, required int y2, required img.Color color}) {
    const int size = 14;
    const int thick = 2;
    // Kiri atas
    img.fillRect(src, x1: x1, y1: y1, x2: x1 + size, y2: y1 + thick, color: color);
    img.fillRect(src, x1: x1, y1: y1, x2: x1 + thick, y2: y1 + size, color: color);
    // Kanan atas
    img.fillRect(src, x1: x2 - size, y1: y1, x2: x2, y2: y1 + thick, color: color);
    img.fillRect(src, x1: x2 - thick, y1: y1, x2: x2, y2: y1 + size, color: color);
    // Kiri bawah
    img.fillRect(src, x1: x1, y1: y2 - thick, x2: x1 + size, y2: y2, color: color);
    img.fillRect(src, x1: x1, y1: y2 - size, x2: x1 + thick, y2: y2, color: color);
    // Kanan bawah
    img.fillRect(src, x1: x2 - size, y1: y2 - thick, x2: x2, y2: y2, color: color);
    img.fillRect(src, x1: x2 - thick, y1: y2 - size, x2: x2, y2: y2, color: color);
  }

  bool _validAddr(String a) =>
      a.isNotEmpty && a != 'Tidak ada lokasi' && !a.startsWith('GPS:') && !a.startsWith('Mencari');

  int _lerp(int a, int b, double t) => (a + (b - a) * t).round().clamp(0, 255);
}
