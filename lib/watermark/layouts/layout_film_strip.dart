// lib/watermark/layouts/layout_film_strip.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:image/src/font/arial_14.dart';
import 'package:image/src/font/arial_24.dart';
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

/// Renders a photo inside an authentic 35 mm film-strip frame.
class LayoutFilmStrip extends WatermarkLayoutBase {
  @override
  String get name => 'Film Strip';

  // ── Colour palette ───────────────────────────────────────────────
  static final _filmBlack   = img.getColor( 10,  10,  10, 255);
  static final _railEdge    = img.getColor( 22,  20,  18, 255);
  static final _sprocket    = img.getColor(242, 236, 218, 255);
  static final _dateOrange  = img.getColor(255, 125,  18, 255);
  static final _addrCream   = img.getColor(195, 183, 162, 255);
  static final _coordAmber  = img.getColor(255, 158,  45, 255);
  static final _frameNum    = img.getColor( 90,  82,  68, 255);
  static final _footerMuted = img.getColor(130, 118,  98, 255);
  static final _mapBorder   = img.getColor( 40,  38,  34, 255);
  static final _mapShadow   = img.getColor(  0,   0,   0,  80);

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

    final int railH    = (52 * scale).round();
    final int captionH = (128 * scale * fsMultiplier).round();
    final int capPad   = (22 * scale).round();
    final int spW      = (14 * scale).round();
    final int spH      = (22 * scale).round();
    final int spEdge   = (20 * scale).round();
    final int spMinGap = (10 * scale).round();

    final int canvasW = src.width;
    final int canvasH = src.height + railH * 2 + captionH;
    final canvas = img.Image(width: canvasW, height: canvasH);

    // ── Base fill ────────────────────────────────────────────────
    img.fill(canvas, color: _filmBlack);

    // ── Top rail ─────────────────────────────────────────────────
    final int photoY = railH;
    _drawRail(canvas, canvasW, y: 0, railH: railH, spW: spW, spH: spH, spEdge: spEdge, spMinGap: spMinGap);

    // ── Photo ────────────────────────────────────────────────────
    img.compositeImage(canvas, src, dstX: 0, dstY: photoY, blend: img.BlendMode.alpha);
    _applyVignette(canvas, src, photoY);

    // ── Bottom rail ──────────────────────────────────────────────
    _drawRail(canvas, canvasW, y: photoY + src.height, railH: railH, spW: spW, spH: spH, spEdge: spEdge, spMinGap: spMinGap);

    // ── Font ─────────────────────────────────────────────────────
    final font = fontSize == 'small' ? img.arial14 : fontSize == 'large' ? img.arial24 : img.arial24;
    final fontSmall = fontSize == 'small' ? img.arial14 : fontSize == 'large' ? img.arial24 : img.arial14;
    final int lineH = (30 * scale * fsMultiplier).round();
    final int lineHSmall = (18 * scale * fsMultiplier).round();

    // ── Caption area ─────────────────────────────────────────────
    final captionY = photoY + src.height + railH;
    img.drawLine(canvas, x1: 0, y1: captionY, x2: canvasW, y2: captionY, color: _railEdge, thickness: 1);

    int y = captionY + (16 * scale).round();

    // ── Date · Time ──────────────────────────────────────────────
    final dateStr = DateFormat('dd MMM yyyy').format(timestamp).toUpperCase();
    final timeStr = DateFormat('HH:mm').format(timestamp);
    img.drawString(canvas, font, capPad, y, '$dateStr  ·  $timeStr', color: _dateOrange);

    final frameLabel = '◄ 24A ►';
    final frameX = canvasW - capPad - frameLabel.length * 8;
    img.drawString(canvas, fontSmall, frameX.clamp(0, canvasW - 60), y + (lineH - lineHSmall) ~/ 2 + 2, frameLabel, color: _frameNum);

    y += lineH + 4;

    // ── Address ──────────────────────────────────────────────────
    if (showAddress && _validAddress(address)) {
      final wrapCols = ((canvasW - capPad * 2 - 120 * scale - 16) ~/ 8).clamp(24, 52).toInt();
      for (final line in _wrap(address, wrapCols).take(2)) {
        img.drawString(canvas, fontSmall, capPad, y, line, color: _addrCream);
        y += lineHSmall;
      }
    }

    // ── Coordinates ──────────────────────────────────────────────
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      img.drawString(canvas, fontSmall, capPad, y, '${lat.toStringAsFixed(5)},  ${lon.toStringAsFixed(5)}', color: _coordAmber);
      y += lineHSmall;
    }

    // ── Weather & Accuracy ───────────────────────────────────────
    final parts = [
      if (showWeather && weather.isNotEmpty) weather,
      if (showAccuracy && hasPosition && acc != null) 'GPS ± ${acc.toStringAsFixed(0)} m',
    ];
    if (parts.isNotEmpty) {
      img.drawString(canvas, fontSmall, capPad, captionY + captionH - lineHSmall - 12, parts.join('   ·   '), color: _footerMuted);
    }

    // ── Mini map ─────────────────────────────────────────────────
    _drawMiniMap(canvas, canvasW, captionY, captionH, capPad, showMiniMap, mapBytes, scale);

    return WatermarkLayoutBase.encodeJpg(canvas);
  }

  // ── Helpers ──────────────────────────────────────────────────────

  void _drawRail(img.Image canvas, int canvasW, {required int y, required int railH, required int spW, required int spH, required int spEdge, required int spMinGap}) {
    img.drawLine(canvas, x1: 0, y1: y, x2: canvasW, y2: y, color: _railEdge, thickness: 1);
    img.drawLine(canvas, x1: 0, y1: y + railH - 1, x2: canvasW, y2: y + railH - 1, color: _railEdge, thickness: 1);

    final usable = canvasW - spEdge * 2;
    final count = ((usable + spMinGap) / (spW + spMinGap)).floor();
    if (count <= 0) return;

    final totalHoles = count * spW;
    final totalGaps = usable - totalHoles;
    final gap = (count > 1) ? totalGaps / (count - 1) : 0.0;
    final holeY = y + (railH - spH) ~/ 2;

    for (int i = 0; i < count; i++) {
      final holeX = (spEdge + i * (spW + gap)).round();
      img.fillRect(canvas, x1: holeX, y1: holeY, x2: holeX + spW, y2: holeY + spH, color: _sprocket);
      img.drawRect(canvas, x1: holeX, y1: holeY, x2: holeX + spW, y2: holeY + spH,
          color: img.getColor(0, 0, 0, 80), thickness: 1);
    }
  }

  void _applyVignette(img.Image canvas, img.Image src, int photoY) {
    const int steps = 16;
    const double maxAlpha = 110.0;
    final maxX = (src.width * 0.22).round();
    final maxY = (src.height * 0.22).round();

    for (int i = 0; i < steps; i++) {
      final t = i / (steps - 1);
      final a = (maxAlpha * t * t).round().clamp(0, 255);
      final sh = 1.0 - t;
      final dx = (maxX * sh).round();
      final dy = (maxY * sh).round();
      final c = img.getColor(0, 0, 0, a);

      img.fillRect(canvas, x1: 0, y1: photoY + dy, x2: dx, y2: photoY + src.height - dy, color: c);
      img.fillRect(canvas, x1: src.width - dx, y1: photoY + dy, x2: src.width, y2: photoY + src.height - dy, color: c);
      img.fillRect(canvas, x1: 0, y1: photoY, x2: src.width, y2: photoY + dy, color: c);
      img.fillRect(canvas, x1: 0, y1: photoY + src.height - dy, x2: src.width, y2: photoY + src.height, color: c);
    }
  }

  void _drawMiniMap(img.Image canvas, int canvasW, int captionY, int captionH, int capPad,
      bool showMiniMap, Uint8List? mapBytes, double scale) {
    if (!showMiniMap || mapBytes == null || mapBytes.isEmpty) return;
    try {
      final decoded = img.decodeImage(mapBytes);
      if (decoded == null) return;

      final mapW = (112 * scale).round();
      final mapH = (68 * scale).round();
      final mapPad = (3 * scale).round();
      final mapOff = (4 * scale).round();

      final map = img.copyResize(decoded, width: mapW, height: mapH);
      final x = canvasW - mapW - capPad;
      final y = captionY + (captionH - mapH) ~/ 2;

      img.fillRect(canvas,
          x1: x - mapPad + mapOff, y1: y - mapPad + mapOff,
          x2: x + mapW + mapPad + mapOff, y2: y + mapH + mapPad + mapOff,
          color: _mapShadow);
      img.fillRect(canvas, x1: x - mapPad, y1: y - mapPad, x2: x + mapW + mapPad, y2: y + mapH + mapPad,
          color: _mapBorder);
      img.compositeImage(canvas, map, dstX: x, dstY: y);
      img.drawLine(canvas, x1: x - mapPad, y1: y - mapPad, x2: x + mapW + mapPad, y2: y - mapPad,
          color: _dateOrange, thickness: 1);
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
