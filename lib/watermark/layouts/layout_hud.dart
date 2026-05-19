// lib/watermark/layouts/layout_hud.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

/// Heads-Up Display overlay — renders all elements directly over the photo.
class LayoutHUD extends WatermarkLayoutBase {
  @override
  String get name => 'HUD Modern';

  // ── Colour palette — phosphor green ─────────────────────────────
  static final _green       = img.ColorRgba8(  0, 255,  90, 255);
  static final _greenGlow   = img.ColorRgba8(  0, 255,  90,  55);
  static final _greenDim    = img.ColorRgba8(  0, 200,  70, 190);
  static final _greenFaint  = img.ColorRgba8(  0, 160,  55, 120);
  static final _greenGhost  = img.ColorRgba8(  0, 120,  40,  60);
  static final _panelBg     = img.ColorRgba8(  0,   6,   2, 195);
  static final _scanLine    = img.ColorRgba8(  0,   0,   0,  30);
  static final _accentBar   = img.ColorRgba8(  0, 255,  90, 255);
  static final _mapBg       = img.ColorRgba8(  0,  20,   8, 210);
  static final _mapGrid     = img.ColorRgba8(  0, 255,  90,  25);
  static final _mapDot      = img.ColorRgba8(  0, 255,  90, 230);

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
    bool showAddress     = true,
    bool showCoordinates = true,
    double opacity       = 0.85,
    bool showBorder      = true,
    String fontSize      = 'normal',
  }) {
    // ── Adaptive scaling ──────────────────────────────────────────
    final double scale = (src.width / 1080).clamp(0.7, 2.0);
    final double fsMultiplier = fontSize == 'small' ? 0.75 : fontSize == 'large' ? 1.4 : 1.0;

    final int topH    = (46 * scale).round();
    final int botH    = (100 * scale * fsMultiplier).round();
    final int padX    = (18 * scale).round();
    final int bracketArm   = (28 * scale).round();
    final int bracketThick = (2 * scale).round().clamp(1, 3);
    final int bracketInset = (14 * scale).round();

    if (src.height < topH + botH + 40) return WatermarkLayoutBase.encodeJpg(src);

    // ── Font ─────────────────────────────────────────────────────
    final font = fontSize == 'small' ? img.arial14 : fontSize == 'large' ? img.arial24 : img.arial24;
    final fontSmall = fontSize == 'small' ? img.arial14 : fontSize == 'large' ? img.arial24 : img.arial14;
    final int charW = fontSize == 'large' ? 14 : fontSize == 'small' ? 8 : 10;

    // ── Scanlines ────────────────────────────────────────────────
    for (int y = 0; y < src.height; y += 4) {
      img.fillRect(src, x1: 0, y1: y, x2: src.width - 1, y2: y, color: _scanLine);
    }

    // ── Top strip ────────────────────────────────────────────────
    img.fillRect(src, x1: 0, y1: 0, x2: src.width - 1, y2: topH - 1, color: _panelBg);
    img.drawLine(src, x1: 0, y1: topH, x2: src.width, y2: topH, color: _greenDim, thickness: 1);

    _drawGlow(src, 'ACTIVE', font: fontSmall, x: padX, y: (8 * scale).round(), color: _greenDim);

    final timeStr = DateFormat('HH:mm:ss').format(timestamp);
    final centerX = (src.width - timeStr.length * charW) ~/ 2;
    _drawGlow(src, timeStr, font: font, x: centerX, y: (12 * scale).round(), color: _green);

    final dateStr = DateFormat('yyyy-MM-dd').format(timestamp);
    final dateX = src.width - padX - dateStr.length * charW;
    _drawGlow(src, dateStr, font: fontSmall, x: dateX.clamp(0, src.width - 90), y: (10 * scale).round(), color: _greenDim);

    // ── Corner brackets ──────────────────────────────────────────
    _bracket(src, x: bracketInset, y: topH + bracketInset, fx: 1, fy: 1, arm: bracketArm, thick: bracketThick);
    _bracket(src, x: src.width - bracketInset, y: topH + bracketInset, fx: -1, fy: 1, arm: bracketArm, thick: bracketThick);
    _bracket(src, x: bracketInset, y: src.height - botH - bracketInset, fx: 1, fy: -1, arm: bracketArm, thick: bracketThick);
    _bracket(src, x: src.width - bracketInset, y: src.height - botH - bracketInset, fx: -1, fy: -1, arm: bracketArm, thick: bracketThick);

    // ── Center reticle ───────────────────────────────────────────
    final cx = src.width ~/ 2;
    final cy = (src.height - botH + topH) ~/ 2;
    final r1 = (20 * scale).round();
    final r2 = (36 * scale).round();
    final gap = (24 * scale).round();
    img.drawCircle(src, x: cx, y: cy, radius: r2, color: _greenGhost);
    img.drawCircle(src, x: cx, y: cy, radius: r1, color: _greenFaint);
    img.drawLine(src, x1: cx - r2, y1: cy, x2: cx - gap, y2: cy, color: _greenFaint, thickness: 1);
    img.drawLine(src, x1: cx + gap, y1: cy, x2: cx + r2, y2: cy, color: _greenFaint, thickness: 1);
    img.drawLine(src, x1: cx, y1: cy - r2, x2: cx, y2: cy - gap, color: _greenFaint, thickness: 1);
    img.drawLine(src, x1: cx, y1: cy + gap, x2: cx, y2: cy + r2, color: _greenFaint, thickness: 1);

    // ── Bottom strip ─────────────────────────────────────────────
    final y0 = src.height - botH;
    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: src.height - 1, color: _panelBg);
    img.drawLine(src, x1: 0, y1: y0, x2: src.width, y2: y0, color: _greenDim, thickness: 1);
    img.fillRect(src, x1: 0, y1: y0, x2: 2, y2: src.height - 1, color: _accentBar);

    int cy2 = y0 + (12 * scale).round();

    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final latStr = 'LAT  ${lat.toStringAsFixed(5)}';
      final lonStr = 'LON  ${lon.toStringAsFixed(5)}';
      _drawGlow(src, latStr, font: fontSmall, x: padX, y: cy2, color: _green);
      _drawGlow(src, lonStr, font: fontSmall, x: padX + latStr.length * charW + 16, y: cy2, color: _green);
      cy2 += (22 * scale * fsMultiplier).round();
    }

    if (showAddress && _validAddress(address)) {
      final wrapCols = ((src.width - padX * 2 - 140 * scale - 24) ~/ 7).clamp(20, 55).toInt();
      for (final line in _wrap(address, wrapCols).take(2)) {
        _drawGlow(src, line, font: fontSmall, x: padX, y: cy2, color: _greenFaint);
        cy2 += (18 * scale * fsMultiplier).round();
      }
    }

    if (showAccuracy && hasPosition && acc != null) {
      _drawGlow(src, 'GPS ± ${acc.toStringAsFixed(0)} m', font: fontSmall, x: padX, y: cy2, color: _greenGhost);
      cy2 += (18 * scale * fsMultiplier).round();
    }

    if (showWeather && weather.isNotEmpty) {
      final pillW = weather.length * charW + 16;
      img.fillRect(src, x1: padX - 2, y1: cy2 - 1, x2: padX + pillW, y2: cy2 + (18 * scale).round() - 2,
          color: img.ColorRgba8(0, 255, 90, 20));
      _drawGlow(src, weather, font: fontSmall, x: padX + 6, y: cy2, color: _green);
    }

    // ── Mini map ─────────────────────────────────────────────────
    _drawMiniMap(src, showMiniMap, mapBytes, y0: y0, botH: botH, padX: padX, scale: scale);

    return WatermarkLayoutBase.encodeJpg(src);
  }

  // ── Helpers ──────────────────────────────────────────────────────

  void _drawGlow(img.Image src, String text, {required img.BitmapFont font, required int x, required int y, required img.Color color}) {
    for (final d in [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
      img.drawString(src, text, font: font, x: x + d[0], y: y + d[1], color: _greenGlow);
    }
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  void _bracket(img.Image src, {required int x, required int y, required int fx, required int fy, required int arm, required int thick}) {
    img.fillRect(src, x1: x, y1: y, x2: x + fx * arm, y2: y + thick - 1, color: _green);
    img.fillRect(src, x1: x, y1: y, x2: x + thick - 1, y2: y + fy * arm, color: _green);
    img.fillRect(src, x1: x - 1, y1: y - 1, x2: x + 1, y2: y + 1, color: _greenGlow);
  }

  void _drawMiniMap(img.Image src, bool showMiniMap, Uint8List? mapBytes, {required int y0, required int botH, required int padX, required double scale}) {
    if (!showMiniMap || mapBytes == null || mapBytes.isEmpty) return;
    try {
      final decoded = img.decodeImage(mapBytes);
      if (decoded == null) return;

      final mapW = (116 * scale).round();
      final mapH = (72 * scale).round();
      final mapPad = (4 * scale).round();
      final map = img.copyResize(decoded, width: mapW, height: mapH);
      final x = src.width - mapW - padX;
      final y = y0 + (botH - mapH) ~/ 2;

      img.fillRect(src, x1: x - mapPad, y1: y - mapPad, x2: x + mapW + mapPad, y2: y + mapH + mapPad, color: _mapBg);
      img.drawLine(src, x1: x - mapPad, y1: y - mapPad, x2: x + mapW + mapPad, y2: y - mapPad, color: _green, thickness: 1);
      img.drawRect(src, x1: x - mapPad, y1: y - mapPad, x2: x + mapW + mapPad, y2: y + mapH + mapPad,
          color: img.ColorRgba8(0, 255, 90, 80), thickness: 1);
      img.compositeImage(src, map, dstX: x, dstY: y);

      final dotX = x + mapW ~/ 2;
      final dotY = y + mapH ~/ 2;
      img.fillRect(src, x1: dotX - 2, y1: dotY - 2, x2: dotX + 2, y2: dotY + 2, color: _mapDot);
      img.drawCircle(src, x: dotX, y: dotY, radius: 6, color: img.ColorRgba8(0, 255, 90, 120));
      img.drawCircle(src, x: dotX, y: dotY, radius: 11, color: img.ColorRgba8(0, 255, 90, 50));
    } catch (_) {}
  }

  bool _validAddress(String a) => a.isNotEmpty && a != 'Tidak ada lokasi' && !a.startsWith('GPS:');

  List<String> _wrap(String text, int maxCols) {
    final lines = <String>[];
    var buf = '';
    for (final word in text.split(' ')) {
      final candidate = buf.isEmpty ? word : '$buf $word';
      if (candidate.length > maxCols) {
        if (buf.isNotEmpty) lines.add(buf);
        buf = word;
      } else {
        buf = candidate;
      }
    }
    if (buf.isNotEmpty) lines.add(buf);
    return lines;
  }
}
