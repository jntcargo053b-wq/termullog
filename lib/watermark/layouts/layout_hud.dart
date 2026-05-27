// lib/watermark/layouts/layout_hud.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutHUD extends WatermarkLayoutBase {
  @override
  String get name => 'HUD Modern';

  // Warna tema — semua sebagai konstanta ColorRgba8 langsung (tidak ada .withAlpha)
  static final _cyan     = img.ColorRgba8(  0, 210, 255, 255);
  static final _cyanDim  = img.ColorRgba8(  0, 210, 255, 140);
  static final _cyanFade = img.ColorRgba8(  0, 210, 255,  60);
  static final _cyanBg   = img.ColorRgba8(  0, 210, 255,  28);
  static final _scanLine = img.ColorRgba8(  0, 210, 255,  12);
  static final _white    = img.ColorRgba8(240, 245, 255, 255);
  static final _grey     = img.ColorRgba8(160, 170, 190, 255);
  static final _shadow   = img.ColorRgba8(  0,   0,   0, 200);
  static final _green    = img.ColorRgba8( 70, 220, 120, 255);
  static final _amber    = img.ColorRgba8(255, 190,  50, 255);
  static final _red      = img.ColorRgba8(240,  70,  70, 255);

  // Nilai int mentah untuk gradien — hindari .r/.g/.b (bertipe num di image 4.x)
  static const int _bgTopR = 8,  _bgTopG = 12, _bgTopB = 28, _bgTopA = 220;
  static const int _bgBotR = 4,  _bgBotG =  6, _bgBotB = 16, _bgBotA = 230;

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

    // Font: hanya arial14 / arial24 / arial48
    final img.BitmapFont fontLarge = img.arial24;
    final img.BitmapFont fontSmall = (fontSize == 'large') ? img.arial24 : img.arial14;

    // FIX: gunakan .lineHeight (bukan .height yang tidak ada di image 4.8)
    final int lineLarge = fontLarge.lineHeight + 4;
    final int lineSmall = fontSmall.lineHeight + 4;

    // Perkiraan lebar karakter (bukan .width yang = lebar atlas)
    final int charWLarge = _charWidth(fontLarge);
    final int charWSmall = _charWidth(fontSmall);

    final int padX      = (20 * scale).round();
    final int padY      = (12 * scale).round();
    final int marginBot = (16 * scale).round();

    // Hitung baris konten
    int rows = 0;
    if (showCoordinates && hasPosition && lat != null && lon != null) rows++;
    if (showAccuracy && hasPosition && acc != null) rows++;
    if (showAddress && _validAddr(address)) rows++;
    if (showWeather && weather.isNotEmpty) rows++;

    final int headerH    = lineLarge + lineSmall + 8;
    final int separatorH = 4;
    final int panelH     = padY * 2 + headerH + separatorH + rows * lineSmall;

    if (panelH > src.height) return WatermarkLayoutBase.encodeJpg(src);
    final int y0 = (src.height - panelH - marginBot).clamp(0, src.height - panelH);

    // ── 1. Background gradien (16-step batch) ────────────────────────────
    final int alphaTop = (_bgTopA * opacity).round().clamp(0, 255);
    final int alphaBot = (_bgBotA * opacity).round().clamp(0, 255);
    const int steps = 16;
    final int stepH = (panelH / steps).ceil();
    for (int s = 0; s < steps; s++) {
      final double t = s / (steps - 1);
      final int y1 = y0 + s * stepH;
      final int y2 = (y1 + stepH).clamp(0, y0 + panelH);
      if (y1 >= y2) continue;
      img.fillRect(src,
          x1: 0, y1: y1, x2: src.width, y2: y2,
          color: img.ColorRgba8(
            _lerp(_bgTopR, _bgBotR, t),
            _lerp(_bgTopG, _bgBotG, t),
            _lerp(_bgTopB, _bgBotB, t),
            _lerp(alphaTop, alphaBot, t),
          ));
    }

    // ── 2. Scan line (fillRect per 4px) ──────────────────────────────────
    for (int y = y0; y < y0 + panelH; y += 4) {
      final int y2 = (y + 1).clamp(0, y0 + panelH);
      img.fillRect(src, x1: 0, y1: y, x2: src.width, y2: y2, color: _scanLine);
    }

    // ── 3. Border atas & bawah ────────────────────────────────────────────
    if (showBorder) {
      img.fillRect(src, x1: 0, y1: y0,             x2: src.width, y2: y0 + 2,         color: _cyanDim);
      img.fillRect(src, x1: 0, y1: y0 + panelH - 2, x2: src.width, y2: y0 + panelH,   color: _cyanDim);
    }

    // ── 4. Kurung sudut HUD ───────────────────────────────────────────────
    _drawCorners(src, x1: 0, y1: y0, x2: src.width, y2: y0 + panelH, color: _cyanDim);

    // ── 5. Konten ─────────────────────────────────────────────────────────
    int cy = y0 + padY;

    // Waktu (kiri)
    final timeStr = DateFormat(timeFormat).format(timestamp);
    _drawShadowText(src, timeStr, font: fontLarge, x: padX, y: cy, color: _white);

    // Tanggal (kanan) — FIX: charWSmall untuk posisi akurat
    final dateStr  = DateFormat(dateFormat).format(timestamp);
    final dateW    = dateStr.length * charWSmall;
    final dateX    = (src.width - padX - dateW).clamp(padX, src.width - padX);
    _drawShadowText(src, dateStr, font: fontSmall, x: dateX, y: cy + 4, color: _grey);
    cy += lineLarge + 4;

    // Separator
    img.fillRect(src,
        x1: padX, y1: cy, x2: src.width - padX, y2: cy + 2,
        color: _cyanFade);
    cy += separatorH;

    // Koordinat
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final latDir   = lat >= 0 ? 'N' : 'S';
      final lonDir   = lon >= 0 ? 'E' : 'W';
      final coordStr =
          '${lat.abs().toStringAsFixed(5)} $latDir   ${lon.abs().toStringAsFixed(5)} $lonDir';
      _drawShadowText(src, coordStr, font: fontSmall, x: padX, y: cy, color: _cyan);
      cy += lineSmall;
    }

    // Akurasi
    if (showAccuracy && hasPosition && acc != null) {
      final accColor = acc <= 5 ? _green : acc <= 20 ? _amber : _red;
      _drawShadowText(src,
          'GPS Accuracy  +/- ${acc.toStringAsFixed(1)} m',
          font: fontSmall, x: padX, y: cy, color: accColor);
      cy += lineSmall;
    }

    // Alamat
    if (showAddress && _validAddr(address)) {
      final int maxChars = ((src.width - padX * 2) / charWSmall).floor().clamp(20, 80);
      final shortAddr = address.length > maxChars
          ? '${address.substring(0, maxChars - 1)}...'
          : address;
      _drawShadowText(src, shortAddr, font: fontSmall, x: padX, y: cy, color: _grey);
      cy += lineSmall;
    }

    // Cuaca
    if (showWeather && weather.isNotEmpty) {
      final int textW = weather.length * charWSmall;
      img.fillRect(src,
          x1: padX - 4,
          y1: cy - 2,
          x2: (padX + textW + 8).clamp(0, src.width),
          y2: cy + lineSmall - 2,
          color: _cyanBg);
      _drawShadowText(src, weather, font: fontSmall, x: padX, y: cy, color: _cyan);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  // Perkiraan lebar karakter (bukan .width = lebar atlas)
  int _charWidth(img.BitmapFont font) {
    if (font == img.arial48) return 28;
    if (font == img.arial24) return 14;
    return 8; // arial14
  }

  void _drawShadowText(img.Image src, String text, {
    required img.BitmapFont font,
    required int x,
    required int y,
    required img.Color color,
  }) {
    img.drawString(src, text, font: font, x: x + 1, y: y + 1, color: _shadow);
    img.drawString(src, text, font: font, x: x,     y: y,     color: color);
  }

  void _drawCorners(img.Image src, {
    required int x1, required int y1,
    required int x2, required int y2,
    required img.Color color,
  }) {
    const int sz = 14;
    const int th = 2;
    img.fillRect(src, x1: x1,      y1: y1,      x2: x1 + sz, y2: y1 + th, color: color);
    img.fillRect(src, x1: x1,      y1: y1,      x2: x1 + th, y2: y1 + sz, color: color);
    img.fillRect(src, x1: x2 - sz, y1: y1,      x2: x2,      y2: y1 + th, color: color);
    img.fillRect(src, x1: x2 - th, y1: y1,      x2: x2,      y2: y1 + sz, color: color);
    img.fillRect(src, x1: x1,      y1: y2 - th, x2: x1 + sz, y2: y2,      color: color);
    img.fillRect(src, x1: x1,      y1: y2 - sz, x2: x1 + th, y2: y2,      color: color);
    img.fillRect(src, x1: x2 - sz, y1: y2 - th, x2: x2,      y2: y2,      color: color);
    img.fillRect(src, x1: x2 - th, y1: y2 - sz, x2: x2,      y2: y2,      color: color);
  }

  bool _validAddr(String a) =>
      a.isNotEmpty &&
      a != 'Tidak ada lokasi' &&
      !a.startsWith('GPS:') &&
      !a.startsWith('Mencari');

  // FIX: terima int (bukan num) — caller tidak lagi pass .r/.g/.b langsung
  int _lerp(int a, int b, double t) =>
      (a + (b - a) * t).round().clamp(0, 255);
}
