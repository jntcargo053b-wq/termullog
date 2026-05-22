// lib/watermark/layouts/layout_polaroid.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

/// Renders a photo inside an authentic Polaroid-style frame.
class LayoutPolaroid extends WatermarkLayoutBase {
  @override
  String get name => 'Polaroid';

  // ── Colour palette ───────────────────────────────────────────────
  static final _paper       = img.ColorRgba8(255, 252, 244, 255);
  static final _photoBorder = img.ColorRgba8(225, 215, 195, 255);
  static final _divider     = img.ColorRgba8(210, 198, 178, 255);
  static final _textPrimary = img.ColorRgba8( 38,  32,  24, 255);
  static final _textMuted   = img.ColorRgba8(128, 115,  95, 255);
  static final _textAccent  = img.ColorRgba8(152, 118,  58, 255);
  static final _mapWhite    = img.ColorRgba8(255, 252, 244, 255);
  static final _mapShadow   = img.ColorRgba8(  0,   0,   0,  50);

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
    bool showAddress     = true,
    bool showCoordinates = true,
    double opacity       = 0.85,
    bool showBorder      = true,
    String fontSize      = 'normal',
  }) {
    // ── Adaptive scaling ──────────────────────────────────────────
    final double scale = (src.width / 1080).clamp(0.7, 2.0);
    final double fsMultiplier = fontSize == 'small' ? 0.75 : fontSize == 'large' ? 1.4 : 1.0;

    final int padTop    = (26 * scale).round();
    final int padSide   = (30 * scale).round();
    final int padBottom = (152 * scale * fsMultiplier).round();

    final int canvasW = src.width  + padSide * 2;
    final int canvasH = src.height + padTop  + padBottom;
    final canvas = img.Image(width: canvasW, height: canvasH);

    // ── Background ────────────────────────────────────────────────
    img.fill(canvas, color: _paper);

    // ── Card shadow ───────────────────────────────────────────────
    for (int i = 1; i <= 3; i++) {
      final a = (10 - i * 3).clamp(0, 255);
      img.drawRect(canvas,
          x1: i, y1: i, x2: canvasW - 1 - i, y2: canvasH - 1 - i,
          color: img.ColorRgba8(0, 0, 0, a), thickness: 1);
    }

    // ── Photo border ──────────────────────────────────────────────
    if (showBorder) {
      img.drawRect(canvas,
          x1: padSide - 1, y1: padTop - 1,
          x2: padSide + src.width, y2: padTop + src.height,
          color: _photoBorder, thickness: 1);
    }

    // ── Paste photo ───────────────────────────────────────────────
    img.compositeImage(canvas, src, dstX: padSide, dstY: padTop, blend: img.BlendMode.alpha);

    // ── Vignette ──────────────────────────────────────────────────
    _applyVignette(canvas, src.width, src.height, padSide: padSide, padTop: padTop);

    // ── Pilih font ────────────────────────────────────────────────
    final font = fontSize == 'small' ? img.arial14 : img.arial24;
    final fontSmall = fontSize == 'small' ? img.arial14 : img.arial24;
    final int lineH = (30 * scale * fsMultiplier).round();
    final int lineHSmall = (18 * scale * fsMultiplier).round();

    // ── Caption area ──────────────────────────────────────────────
    final ruleY = padTop + src.height + (14 * scale).round();
    img.drawLine(canvas,
        x1: padSide, y1: ruleY,
        x2: canvasW - padSide, y2: ruleY,
        color: _divider, thickness: 1);

    int y = ruleY + (16 * scale).round();

    // ── Date · Time ───────────────────────────────────────────────
    final dateStr = DateFormat('dd MMM yyyy').format(timestamp).toUpperCase();
    final timeStr = DateFormat('HH:mm').format(timestamp);
    img.drawString(canvas, '$dateStr  ·  $timeStr',
        font: font, x: padSide, y: y, color: _textPrimary);
    y += lineH + 4;

    // ── Address ───────────────────────────────────────────────────
    if (showAddress && _validAddress(address)) {
      final wrapCols = ((canvasW - padSide * 2) ~/ 8).clamp(28, 58);
      final wrapped = WatermarkLayoutBase.wrapText(address, wrapCols);
      final lines = wrapped.split('\n');
      for (final line in lines.take(2)) {
        img.drawString(canvas, line, font: fontSmall, x: padSide, y: y, color: _textMuted);
        y += lineHSmall;
      }
    }

    // ── Coordinates ───────────────────────────────────────────────
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      img.drawString(canvas,
          '${lat.toStringAsFixed(5)},  ${lon.toStringAsFixed(5)}',
          font: fontSmall, x: padSide, y: y, color: _textAccent);
      y += lineHSmall;
    }

    // ── Weather & Accuracy ────────────────────────────────────────
    final parts = [
      if (showWeather && weather.isNotEmpty) weather,
      if (showAccuracy && hasPosition && acc != null) 'GPS ± ${acc.toStringAsFixed(0)} m',
    ];
    if (parts.isNotEmpty) {
      img.drawString(canvas, parts.join('   ·   '),
          font: fontSmall, x: padSide, y: canvasH - lineHSmall - 14, color: _textMuted);
    }

    // ── Mini map ──────────────────────────────────────────────────
    _drawMiniMap(canvas, canvasW: canvasW, canvasH: canvasH, padSide: padSide,
        showMiniMap: showMiniMap, mapBytes: mapBytes, scale: scale);

    return WatermarkLayoutBase.encodeJpg(canvas);
  }

  // ── Helpers ──────────────────────────────────────────────────────

  void _applyVignette(img.Image canvas, int srcW, int srcH, {required int padSide, required int padTop}) {
    const int steps = 20;
    const double maxAlpha = 95.0;
    final maxX = (srcW * 0.20).round();
    final maxY = (srcH * 0.20).round();

    for (int i = 0; i < steps; i++) {
      final t = i / (steps - 1);
      final a = (maxAlpha * t * t).round().clamp(0, 255);
      final shrink = 1.0 - t;
      final dx = (maxX * shrink).round();
      final dy = (maxY * shrink).round();
      final c = img.ColorRgba8(0, 0, 0, a);

      img.fillRect(canvas, x1: padSide,      y1: padTop + dy, x2: padSide + dx, y2: padTop + srcH - dy, color: c);
      img.fillRect(canvas, x1: padSide + srcW - dx, y1: padTop + dy, x2: padSide + srcW, y2: padTop + srcH - dy, color: c);
      img.fillRect(canvas, x1: padSide,      y1: padTop,      x2: padSide + srcW, y2: padTop + dy, color: c);
      img.fillRect(canvas, x1: padSide,      y1: padTop + srcH - dy, x2: padSide + srcW, y2: padTop + srcH, color: c);
    }
  }

  void _drawMiniMap(img.Image canvas, {
    required int canvasW,
    required int canvasH,
    required int padSide,
    required bool showMiniMap,
    Uint8List? mapBytes,
    required double scale,
  }) {
    if (!showMiniMap || mapBytes == null || mapBytes.isEmpty) return;
    try {
      final decoded = img.decodeImage(mapBytes);
      if (decoded == null) return;

      final mapW = (120 * scale).round();
      final mapH = (76 * scale).round();
      final mapPad = (4 * scale).round();
      final mapShadowOff = (5 * scale).round();
      final footerH = (18 * scale).round();

      final map = img.copyResize(decoded, width: mapW, height: mapH);
      final x = canvasW - mapW - padSide;
      final y = canvasH - mapH - footerH - (28 * scale).round();

      // Shadow
      img.fillRect(canvas,
          x1: x - mapPad + mapShadowOff, y1: y - mapPad + mapShadowOff,
          x2: x + mapW + mapPad + mapShadowOff, y2: y + mapH + mapPad + mapShadowOff,
          color: _mapShadow);
      // White frame
      img.fillRect(canvas,
          x1: x - mapPad, y1: y - mapPad, x2: x + mapW + mapPad, y2: y + mapH + mapPad,
          color: _mapWhite);
      // Border
      img.drawRect(canvas,
          x1: x - mapPad, y1: y - mapPad, x2: x + mapW + mapPad, y2: y + mapH + mapPad,
          color: _photoBorder, thickness: 1);
      // Map
      img.compositeImage(canvas, map, dstX: x, dstY: y);
    } catch (_) {}
  }

  bool _validAddress(String a) => a.isNotEmpty && a != 'Tidak ada lokasi' && !a.startsWith('GPS:');
}
