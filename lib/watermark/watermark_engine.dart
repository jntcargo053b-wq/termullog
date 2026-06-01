```dart
// lib/watermark/watermark_engine.dart
// FULL PRODUCTION – Mendukung mini map, format tanggal/waktu, font size, dan 5 layout.
// Kompatibel dengan preview_screen.dart via createParams() dan applyFromMapAsync().

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import '../core/constants.dart';
import 'watermark_params.dart';

class WatermarkEngine {
  // ----------------------------------------------------------------------
  // API untuk preview_screen
  // ----------------------------------------------------------------------

  /// Membuat WatermarkParams dari Map (biasanya dari pengaturan preview).
  static WatermarkParams createParams(Map<String, dynamic> map) {
    return WatermarkParams.fromMap(map);
  }

  /// Proses watermark langsung dari Map (dengan imageBytes sudah di dalam map).
  static Future<Uint8List> applyFromMapAsync(Map<String, dynamic> map) async {
    final params = WatermarkParams.fromMap(map);
    return process(params);
  }

  // ----------------------------------------------------------------------
  // Proses utama
  // ----------------------------------------------------------------------

  static Future<Uint8List> process(WatermarkParams p) async {
    // 1. Decode foto asli
    final ui.Image original = await _decodeImage(p.imageBytes);
    final int W = original.width;
    final int H = original.height;

    // 2. Pixel ratio berdasarkan lebar (desain referensi 1080px)
    final double pr = (W / 1080.0).clamp(0.5, 4.0);

    // 3. Layout
    final WatermarkLayout layout = WatermarkLayout.values[
        p.layoutIndex.clamp(0, WatermarkLayout.values.length - 1)];

    // 4. Decode mini map jika ada
    ui.Image? miniMapImage;
    if (p.showMiniMap && p.mapBytes != null && p.mapBytes!.isNotEmpty) {
      try {
        miniMapImage = await _decodeImage(p.mapBytes!);
      } catch (e) {
        debugPrint('Mini map decode error: $e');
      }
    }

    // 5. Paint ke canvas
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(original, Offset.zero, ui.Paint());

    _renderLayout(canvas, layout, p, W, H, pr, miniMapImage);

    // 6. Konversi ke JPEG
    final picture = recorder.endRecording();
    final output = await picture.toImage(W, H);
    final byteData = await output.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) throw Exception('Failed to get pixel data');

    final pixels = byteData.buffer.asUint8List();
    final imgOut = img.Image.fromBytes(
      width: W,
      height: H,
      bytes: pixels.buffer,
      numChannels: 4,
    );
    final jpegBytes = img.encodeJpg(imgOut, quality: p.imageQuality.clamp(60, 100));

    // 7. Cleanup
    original.dispose();
    output.dispose();
    picture.dispose();
    miniMapImage?.dispose();

    return Uint8List.fromList(jpegBytes);
  }

  // ----------------------------------------------------------------------
  // Layout dispatch
  // ----------------------------------------------------------------------

  static void _renderLayout(
    ui.Canvas canvas,
    WatermarkLayout layout,
    WatermarkParams p,
    int W,
    int H,
    double pr,
    ui.Image? miniMapImage,
  ) {
    switch (layout) {
      case WatermarkLayout.timemarkClassic:
        _drawClassic(canvas, p, W, H, pr, miniMapImage);
        break;
      case WatermarkLayout.timemarkMinimal:
        _drawMinimal(canvas, p, W, H, pr, miniMapImage);
        break;
      case WatermarkLayout.timemarkCard:
        _drawCard(canvas, p, W, H, pr, miniMapImage);
        break;
      case WatermarkLayout.timemarkHUD:
        _drawHUD(canvas, p, W, H, pr, miniMapImage);
        break;
      case WatermarkLayout.timemarkFilm:
        _drawFilm(canvas, p, W, H, pr, miniMapImage);
        break;
    }
  }

  // ----------------------------------------------------------------------
  // LAYOUT 1: CLASSIC (strip bawah, jam besar di kiri, info di kanan)
  // ----------------------------------------------------------------------

  static void _drawClassic(
    ui.Canvas canvas,
    WatermarkParams p,
    int W,
    int H,
    double pr,
    ui.Image? miniMapImage,
  ) {
    final double stripH = 88 * pr;
    final double padH = 12 * pr;
    final double stripY = H - stripH;

    // Background strip hitam transparan
    canvas.drawRect(
      Rect.fromLTWH(0, stripY, W.toDouble(), stripH),
      ui.Paint()
        ..color = const Color(0xDD000000).withOpacity(p.opacity.clamp(0.5, 1.0)),
    );

    // Garis aksen merah di atas strip
    canvas.drawRect(
      Rect.fromLTWH(0, stripY, W.toDouble(), 3 * pr),
      ui.Paint()..color = const Color(0xFFE63946),
    );

    // ---- Kolom kiri: waktu besar ----
    final String timeStr = DateFormat(p.timeFormat).format(p.timestamp);
    final double timeFontSize = _getFontSize(32, p.fontSize, pr);
    final ui.TextPainter timePainter = _makePainter(
      timeStr,
      timeFontSize,
      Colors.white,
      bold: true,
    );
    timePainter.layout(maxWidth: W * 0.5);
    timePainter.paint(canvas, Offset(16 * pr, stripY + padH));

    // Tanggal
    final String dateStr = DateFormat(p.dateFormat).format(p.timestamp);
    final double dateFontSize = _getFontSize(13, p.fontSize, pr);
    final ui.TextPainter datePainter = _makePainter(
      dateStr,
      dateFontSize,
      const Color(0xFFAAAAAA),
    );
    datePainter.layout(maxWidth: W * 0.5);
    datePainter.paint(canvas, Offset(16 * pr, stripY + padH + 38 * pr));

    // App name kecil
    final double appFontSize = _getFontSize(10, p.fontSize, pr);
    final ui.TextPainter appPainter = _makePainter(
      p.appName,
      appFontSize,
      const Color(0xFF666666),
      letterSpacing: 1.5,
    );
    appPainter.layout(maxWidth: W * 0.3);
    appPainter.paint(canvas, Offset(16 * pr, stripY + padH + 56 * pr));

    // ---- Kolom kanan: info GPS ----
    final double rightX = W * 0.52;
    double ry = stripY + padH;
    final double infoFontSize = _getFontSize(11, p.fontSize, pr);

    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final coord =
          '${p.lat!.abs().toStringAsFixed(5)}° ${p.lat! >= 0 ? "N" : "S"}  '
          '${p.lon!.abs().toStringAsFixed(5)}° ${p.lon! >= 0 ? "E" : "W"}';
      final cp = _makePainter(coord, infoFontSize, const Color(0xFF1E90FF));
      cp.layout(maxWidth: W * 0.46);
      cp.paint(canvas, Offset(rightX, ry));
      ry += 18 * pr;
    }

    if (p.showAccuracy && p.acc != null) {
      final accColor = p.acc! <= 5
          ? const Color(0xFF3CB86A)
          : p.acc! <= 20
              ? const Color(0xFFFFB820)
              : const Color(0xFFE63946);
      final ap = _makePainter(
        '± ${p.acc!.toStringAsFixed(0)} m',
        infoFontSize,
        accColor,
      );
      ap.layout(maxWidth: W * 0.46);
      ap.paint(canvas, Offset(rightX, ry));
      ry += 16 * pr;
    }

    if (p.showAddress && p.address.isNotEmpty && !p.address.startsWith('GPS:')) {
      final addr = _truncate(p.address, 45);
      final addrP = _makePainter(addr, infoFontSize, const Color(0xFF999999));
      addrP.layout(maxWidth: W * 0.46);
      addrP.paint(canvas, Offset(rightX, ry));
      ry += 16 * pr;
    }

    if (p.showWeather && p.weather.isNotEmpty) {
      final wp = _makePainter(p.weather, infoFontSize, const Color(0xFF1E90FF));
      wp.layout(maxWidth: W * 0.46);
      wp.paint(canvas, Offset(rightX, ry));
    }

    // ---- Mini map (jika ada) ----
    if (miniMapImage != null && p.showMiniMap) {
      final double mapSize = (p.mapSize * pr).clamp(40.0, 200.0);
      final double mapX = 16 * pr;
      final double mapY = stripY - mapSize - 8 * pr; // di atas strip
      if (mapY >= 8 * pr) {
        canvas.drawImageRect(
          miniMapImage,
          Rect.fromLTWH(0, 0, miniMapImage.width.toDouble(), miniMapImage.height.toDouble()),
          Rect.fromLTWH(mapX, mapY, mapSize, mapSize),
          ui.Paint(),
        );
        // Border tipis putih
        canvas.drawRect(
          Rect.fromLTWH(mapX, mapY, mapSize, mapSize),
          ui.Paint()
            ..color = const Color(0xAAFFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  // ----------------------------------------------------------------------
  // LAYOUT 2: MINIMAL (pojok kanan bawah)
  // ----------------------------------------------------------------------

  static void _drawMinimal(
    ui.Canvas canvas,
    WatermarkParams p,
    int W,
    int H,
    double pr,
    ui.Image? miniMapImage,
  ) {
    final double padR = 14 * pr;
    final double padB = 14 * pr;
    final double cardW = 200 * pr;
    final double cardH = 58 * pr;
    final double cx = W - cardW - padR;
    final double cy = H - cardH - padB;

    // Background rounded
    final rr = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx, cy, cardW, cardH),
      Radius.circular(8 * pr),
    );
    canvas.drawRRect(
      rr,
      ui.Paint()..color = const Color(0xDD000000).withOpacity(p.opacity * 0.85),
    );
    // Garis aksen merah kiri
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx, cy, 3 * pr, cardH),
        Radius.circular(2 * pr),
      ),
      ui.Paint()..color = const Color(0xFFE63946),
    );

    final double timeFontSize = _getFontSize(20, p.fontSize, pr);
    final ui.TextPainter tp = _makePainter(
      DateFormat(p.timeFormat).format(p.timestamp),
      timeFontSize,
      Colors.white,
      bold: true,
    );
    tp.layout(maxWidth: cardW - 20 * pr);
    tp.paint(canvas, Offset(cx + 10 * pr, cy + 8 * pr));

    final double dateFontSize = _getFontSize(11, p.fontSize, pr);
    final ui.TextPainter dp = _makePainter(
      DateFormat(p.dateFormat).format(p.timestamp),
      dateFontSize,
      const Color(0xFF888888),
    );
    dp.layout(maxWidth: cardW - 20 * pr);
    dp.paint(canvas, Offset(cx + 10 * pr, cy + 32 * pr));

    // Mini map tidak ditampilkan di layout minimal (terlalu kecil)
  }

  // ----------------------------------------------------------------------
  // LAYOUT 3: CARD (glass card kanan bawah, info lengkap, bisa ada mini map)
  // ----------------------------------------------------------------------

  static void _drawCard(
    ui.Canvas canvas,
    WatermarkParams p,
    int W,
    int H,
    double pr,
    ui.Image? miniMapImage,
  ) {
    const double cardWidthRatio = 0.42;
    final double cardW = (W * cardWidthRatio).clamp(200.0, 520.0);
    double lineH = 18 * pr;
    int lineCount = 3; // time + date + separator
    if (p.showCoordinates && p.lat != null) lineCount++;
    if (p.showAccuracy && p.acc != null) lineCount++;
    if (p.showAddress && p.address.isNotEmpty) lineCount++;
    if (p.showWeather && p.weather.isNotEmpty) lineCount++;
    final double cardH = 20 * pr + lineCount * lineH + 16 * pr;
    final double margin = 14 * pr;
    final double cx = W - cardW - margin;
    final double cy = H - cardH - margin;

    // Background glass
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx, cy, cardW, cardH),
        Radius.circular(10 * pr),
      ),
      ui.Paint()..color = const Color.fromRGBO(8, 12, 24, p.opacity.clamp(0.6, 0.96)),
    );

    // Border opsional
    if (p.showBorder) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx, cy, cardW, cardH),
          Radius.circular(10 * pr),
        ),
        ui.Paint()
          ..color = const Color(0x401E90FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 * pr,
      );
    }

    // Aksen biru kiri
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx, cy + 12 * pr, 3 * pr, cardH - 24 * pr),
        Radius.circular(2 * pr),
      ),
      ui.Paint()..color = const Color(0xFF1E90FF),
    );

    final double tx = cx + 14 * pr;
    double ty = cy + 14 * pr;

    // Jam besar
    final double timeFontSize = _getFontSize(22, p.fontSize, pr);
    final ui.TextPainter tp = _makePainter(
      DateFormat(p.timeFormat).format(p.timestamp),
      timeFontSize,
      Colors.white,
      bold: true,
    );
    tp.layout(maxWidth: cardW - 20 * pr);
    tp.paint(canvas, Offset(tx, ty));
    ty += 26 * pr;

    // Tanggal
    final double dateFontSize = _getFontSize(12, p.fontSize, pr);
    final ui.TextPainter dp = _makePainter(
      DateFormat(p.dateFormat).format(p.timestamp),
      dateFontSize,
      const Color(0xFF777F8E),
    );
    dp.layout(maxWidth: cardW - 20 * pr);
    dp.paint(canvas, Offset(tx, ty));
    ty += lineH + 2 * pr;

    // Separator
    canvas.drawLine(
      Offset(tx, ty),
      Offset(cx + cardW - 14 * pr, ty),
      ui.Paint()..color = const Color(0x201E90FF)..strokeWidth = 1,
    );
    ty += 6 * pr;

    final double infoFontSize = _getFontSize(11, p.fontSize, pr);

    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final coord =
          '${p.lat!.abs().toStringAsFixed(5)}°${p.lat! >= 0 ? "N" : "S"} '
          '${p.lon!.abs().toStringAsFixed(5)}°${p.lon! >= 0 ? "E" : "W"}';
      final cp = _makePainter(coord, infoFontSize, const Color(0xFF1E90FF));
      cp.layout(maxWidth: cardW - 20 * pr);
      cp.paint(canvas, Offset(tx, ty));
      ty += lineH;
    }

    if (p.showAccuracy && p.acc != null) {
      final accColor = p.acc! <= 5
          ? const Color(0xFF3CB86A)
          : p.acc! <= 20
              ? const Color(0xFFFFB820)
              : const Color(0xFFE63946);
      final ap = _makePainter('± ${p.acc!.toStringAsFixed(1)} m', infoFontSize, accColor);
      ap.layout(maxWidth: cardW - 20 * pr);
      ap.paint(canvas, Offset(tx, ty));
      ty += lineH;
    }

    if (p.showAddress && p.address.isNotEmpty) {
      final addr = _truncate(p.address, 48);
      final addrP = _makePainter(addr, infoFontSize, const Color(0xFF6A7280));
      addrP.layout(maxWidth: cardW - 20 * pr);
      addrP.paint(canvas, Offset(tx, ty));
      ty += lineH;
    }

    if (p.showWeather && p.weather.isNotEmpty) {
      final wp = _makePainter(p.weather, infoFontSize, const Color(0xFF1E90FF));
      wp.layout(maxWidth: cardW - 20 * pr);
      wp.paint(canvas, Offset(tx, ty));
    }

    // Mini map di dalam card (pojok kiri bawah card)
    if (miniMapImage != null && p.showMiniMap) {
      final double mapSize = (p.mapSize * pr).clamp(40.0, 120.0);
      final double mapX = cx + 14 * pr;
      final double mapY = cy + cardH - mapSize - 12 * pr;
      if (mapY > cy + 40 * pr) {
        canvas.drawImageRect(
          miniMapImage,
          Rect.fromLTWH(0, 0, miniMapImage.width.toDouble(), miniMapImage.height.toDouble()),
          Rect.fromLTWH(mapX, mapY, mapSize, mapSize),
          ui.Paint(),
        );
        // Border tipis
        canvas.drawRect(
          Rect.fromLTWH(mapX, mapY, mapSize, mapSize),
          ui.Paint()
            ..color = const Color(0xAA1E90FF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  // ----------------------------------------------------------------------
  // LAYOUT 4: HUD (crosshair tengah, info di pojok kanan atas)
  // ----------------------------------------------------------------------

  static void _drawHUD(
    ui.Canvas canvas,
    WatermarkParams p,
    int W,
    int H,
    double pr,
    ui.Image? miniMapImage,
  ) {
    final double centerX = W / 2.0;
    final double centerY = H / 2.0;
    final crossPaint = ui.Paint()
      ..color = const Color(0x401E90FF)
      ..strokeWidth = 1.5 * pr
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(centerX, centerY), 28 * pr, crossPaint);
    canvas.drawLine(Offset(centerX - 40 * pr, centerY), Offset(centerX - 32 * pr, centerY), crossPaint);
    canvas.drawLine(Offset(centerX + 32 * pr, centerY), Offset(centerX + 40 * pr, centerY), crossPaint);
    canvas.drawLine(Offset(centerX, centerY - 40 * pr), Offset(centerX, centerY - 32 * pr), crossPaint);
    canvas.drawLine(Offset(centerX, centerY + 32 * pr), Offset(centerX, centerY + 40 * pr), crossPaint);

    final double padR = 12 * pr;
    final double padT = 40 * pr;
    final double cardW = 180 * pr;

    final double timeFontSize = _getFontSize(18, p.fontSize, pr);
    final ui.TextPainter tp = _makePainter(
      DateFormat(p.timeFormat).format(p.timestamp),
      timeFontSize,
      const Color(0xFF00E5FF),
      bold: true,
    );
    tp.layout(maxWidth: cardW);
    tp.paint(canvas, Offset(W - tp.width - padR, padT));

    final double dateFontSize = _getFontSize(11, p.fontSize, pr);
    final ui.TextPainter dp = _makePainter(
      DateFormat(p.dateFormat).format(p.timestamp),
      dateFontSize,
      const Color(0xFF006080),
    );
    dp.layout(maxWidth: cardW);
    dp.paint(canvas, Offset(W - dp.width - padR, padT + 24 * pr));

    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final coord =
          '${p.lat!.abs().toStringAsFixed(4)}°${p.lat! >= 0 ? "N" : "S"} '
          '${p.lon!.abs().toStringAsFixed(4)}°${p.lon! >= 0 ? "E" : "W"}';
      final cp = _makePainter(coord, dateFontSize, const Color(0xFF00E5FF));
      cp.layout(maxWidth: W * 0.8);
      final double oy = H - 24 * pr;
      canvas.drawRect(
        Rect.fromLTWH(0, oy - 4 * pr, cp.width + 24 * pr, 20 * pr),
        ui.Paint()..color = const Color(0xCC000D1A),
      );
      cp.paint(canvas, Offset(12 * pr, oy));
    }

    final double appFontSize = _getFontSize(10, p.fontSize, pr);
    final ui.TextPainter appPainter = _makePainter(
      p.appName,
      appFontSize,
      const Color(0xFF00697A),
      letterSpacing: 2.0,
    );
    appPainter.layout(maxWidth: 200 * pr);
    appPainter.paint(canvas, Offset(14 * pr, 20 * pr));

    // HUD tidak menampilkan mini map
  }

  // ----------------------------------------------------------------------
  // LAYOUT 5: FILM (border perforated, info di pojok kanan bawah)
  // ----------------------------------------------------------------------

  static void _drawFilm(
    ui.Canvas canvas,
    WatermarkParams p,
    int W,
    int H,
    double pr,
    ui.Image? miniMapImage,
  ) {
    final double borderW = 28 * pr;
    final double holeR = 5 * pr;
    final double holeSpacing = 18 * pr;

    // Border atas dan bawah
    canvas.drawRect(
      Rect.fromLTWH(0, 0, W.toDouble(), borderW),
      ui.Paint()..color = const Color(0xFF1A1000),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, H - borderW, W.toDouble(), borderW),
      ui.Paint()..color = const Color(0xFF1A1000),
    );

    // Lubang perforasi
    final holePaint = ui.Paint()..color = const Color(0xFFFF9500);
    final int holeCount = (W / holeSpacing).floor();
    for (int i = 0; i < holeCount; i++) {
      final double hx = i * holeSpacing + holeSpacing / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(hx - holeR, borderW * 0.25, holeR * 2, borderW * 0.5),
          Radius.circular(2 * pr),
        ),
        holePaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(hx - holeR, H - borderW + borderW * 0.25, holeR * 2, borderW * 0.5),
          Radius.circular(2 * pr),
        ),
        holePaint,
      );
    }

    // Card info di kanan bawah (dalam area foto)
    const double cardWidthRatio = 0.38;
    final double cardW = (W * cardWidthRatio).clamp(170.0, 400.0);
    final double cardH = 72 * pr;
    final double margin = 10 * pr;
    final double cx = W - cardW - margin;
    final double cy = H - borderW - cardH - margin;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx, cy, cardW, cardH),
        Radius.circular(6 * pr),
      ),
      ui.Paint()..color = const Color.fromRGBO(0, 0, 0, p.opacity * 0.82),
    );
    canvas.drawRect(
      Rect.fromLTWH(cx, cy, cardW, 2.5 * pr),
      ui.Paint()..color = const Color(0xFFFF9500),
    );

    final double tx = cx + 10 * pr;

    final double timeFontSize = _getFontSize(20, p.fontSize, pr);
    final ui.TextPainter tp = _makePainter(
      DateFormat(p.timeFormat).format(p.timestamp),
      timeFontSize,
      const Color(0xFFFFD95A),
      bold: true,
    );
    tp.layout(maxWidth: cardW - 16 * pr);
    tp.paint(canvas, Offset(tx, cy + 8 * pr));

    final double dateFontSize = _getFontSize(11, p.fontSize, pr);
    final ui.TextPainter dp = _makePainter(
      DateFormat(p.dateFormat).format(p.timestamp),
      dateFontSize,
      const Color(0xFFB89040),
    );
    dp.layout(maxWidth: cardW - 16 * pr);
    dp.paint(canvas, Offset(tx, cy + 32 * pr));

    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final coord = '${p.lat!.toStringAsFixed(4)}, ${p.lon!.toStringAsFixed(4)}';
      final cp = _makePainter(coord, dateFontSize, const Color(0xFF7A6020));
      cp.layout(maxWidth: cardW - 16 * pr);
      cp.paint(canvas, Offset(tx, cy + 50 * pr));
    }

    // Mini map tidak ditampilkan di film strip
  }

  // ----------------------------------------------------------------------
  // HELPERS
  // ----------------------------------------------------------------------

  /// Menyesuaikan ukuran font berdasarkan preferensi fontSize ('small'/'normal'/'large') dan pr.
  static double _getFontSize(double baseSize, String fontSizePref, double pr) {
    double multiplier = 1.0;
    switch (fontSizePref.toLowerCase()) {
      case 'small':
        multiplier = 0.85;
        break;
      case 'large':
        multiplier = 1.25;
        break;
      default:
        multiplier = 1.0;
    }
    return (baseSize * multiplier * pr).clamp(8.0, 80.0);
  }

  static ui.TextPainter _makePainter(
    String text,
    double size,
    ui.Color color, {
    bool bold = false,
    double letterSpacing = 0.0,
  }) {
    final span = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        letterSpacing: letterSpacing,
        height: 1.2,
        shadows: const [
          Shadow(blurRadius: 4, color: Color(0x88000000), offset: Offset(1, 1)),
        ],
      ),
    );
    return ui.TextPainter(
      text: span,
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
  }

  static String _truncate(String s, int maxLen) {
    if (s.length <= maxLen) return s;
    return '${s.substring(0, maxLen - 1)}…';
  }

  static Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromList(bytes, completer.complete);
    return completer.future;
  }
}
```
