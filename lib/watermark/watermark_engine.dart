// lib/watermark/watermark_engine.dart
// TOTAL REBUILD – Pure Flutter Canvas rendering → image package untuk encode JPEG
// Arsitektur: decode foto → paint watermark via Canvas → encode JPEG
// Tidak ada isolate double-materialization, tidak ada layout dispatch bug.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import '../core/constants.dart';
import 'watermark_params.dart';

class WatermarkEngine {
  /// Entry point utama.
  /// Menerima [WatermarkParams] dan mengembalikan JPEG bytes dengan watermark.
  static Future<Uint8List> process(WatermarkParams p) async {
    // 1. Decode foto asli ke ui.Image
    final ui.Image original = await _decodeImage(p.imageBytes);
    final int W = original.width;
    final int H = original.height;

    // 2. Pixel ratio proporsional terhadap LEBAR foto (bukan shortSide).
    //    Watermark selalu horizontal dan terikat ke lebar — W adalah basis yang benar.
    //    Referensi: desain dibuat pada lebar 1080px.
    final double pr = (W / 1080.0).clamp(0.5, 4.0);

    // 3. Layout enum dari index
    final WatermarkLayout layout = WatermarkLayout.values[
        p.layoutIndex.clamp(0, WatermarkLayout.values.length - 1)];

    // 4. Paint watermark ke canvas
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);

    // Gambar foto asli
    canvas.drawImage(original, ui.Offset.zero, ui.Paint());

    // Render watermark sesuai layout
    _renderLayout(
      canvas: canvas,
      layout: layout,
      p: p,
      W: W,
      H: H,
      pr: pr,
    );

    // 5. Finalize picture → ui.Image
    final ui.Picture picture = recorder.endRecording();
    final ui.Image output = await picture.toImage(W, H);

    // 6. Ambil RGBA bytes → image package → encode JPEG
    final ByteData? byteData =
        await output.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) throw Exception('WatermarkEngine: toByteData failed');

    final Uint8List pixels = byteData.buffer.asUint8List(
        byteData.offsetInBytes, byteData.lengthInBytes);

    final img.Image imgOut = img.Image.fromBytes(
      width: W,
      height: H,
      bytes: pixels.buffer,
      numChannels: 4,
    );

    final Uint8List jpegBytes = Uint8List.fromList(
      img.encodeJpg(imgOut, quality: p.imageQuality.clamp(60, 100)),
    );

    // 7. Cleanup
    original.dispose();
    output.dispose();
    picture.dispose();

    return jpegBytes;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DISPATCH LAYOUT
  // ─────────────────────────────────────────────────────────────────────────

  static void _renderLayout({
    required ui.Canvas canvas,
    required WatermarkLayout layout,
    required WatermarkParams p,
    required int W,
    required int H,
    required double pr,
  }) {
    switch (layout) {
      case WatermarkLayout.timemarkClassic:
        _drawTimemarkClassic(canvas, p, W, H, pr);
        break;
      case WatermarkLayout.timemarkMinimal:
        _drawTimemarkMinimal(canvas, p, W, H, pr);
        break;
      case WatermarkLayout.timemarkCard:
        _drawTimemarkCard(canvas, p, W, H, pr);
        break;
      case WatermarkLayout.timemarkHUD:
        _drawTimemarkHUD(canvas, p, W, H, pr);
        break;
      case WatermarkLayout.timemarkFilm:
        _drawTimemarkFilm(canvas, p, W, H, pr);
        break;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LAYOUT 1: TIMEMARK CLASSIC
  // Jam besar merah + strip GPS hitam transparan di bawah foto
  // ─────────────────────────────────────────────────────────────────────────

  static void _drawTimemarkClassic(
      ui.Canvas canvas, WatermarkParams p, int W, int H, double pr) {
    final double stripH = 88 * pr;
    final double padH = 12 * pr;
    final double stripY = H - stripH;

    // Background strip hitam
    final bgPaint = ui.Paint()
      ..color = const ui.Color(0xDD000000).withOpacity(p.opacity.clamp(0.5, 1.0));
    canvas.drawRect(ui.Rect.fromLTWH(0, stripY, W.toDouble(), stripH), bgPaint);

    // Garis aksen merah di atas strip
    canvas.drawRect(
      ui.Rect.fromLTWH(0, stripY, W.toDouble(), 3 * pr),
      ui.Paint()..color = const ui.Color(0xFFE63946),
    );

    // ── Kolom kiri: JAM BESAR ──
    final timeStr = DateFormat('HH:mm:ss').format(p.timestamp);
    final timePainter = _makePainter(
      timeStr,
      size: 32 * pr,
      color: const ui.Color(0xFFFFFFFF),
      bold: true,
    );
    timePainter.layout(maxWidth: W * 0.5);
    timePainter.paint(canvas, ui.Offset(16 * pr, stripY + padH));

    // Tanggal di bawah jam
    final dateStr = DateFormat('EEE, dd MMM yyyy').format(p.timestamp);
    final datePainter = _makePainter(
      dateStr,
      size: 13 * pr,
      color: const ui.Color(0xFFAAAAAA),
    );
    datePainter.layout(maxWidth: W * 0.5);
    datePainter.paint(canvas, ui.Offset(16 * pr, stripY + padH + 38 * pr));

    // App name kecil
    final appPainter = _makePainter(
      p.appName,
      size: 10 * pr,
      color: const ui.Color(0xFF666666),
      letterSpacing: 1.5,
    );
    appPainter.layout(maxWidth: W * 0.3);
    appPainter.paint(canvas, ui.Offset(16 * pr, stripY + padH + 56 * pr));

    // ── Kolom kanan: GPS & INFO ──
    final rightX = W * 0.52;
    double ry = stripY + padH;

    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final coord =
          '${p.lat!.abs().toStringAsFixed(5)}° ${p.lat! >= 0 ? "N" : "S"}  '
          '${p.lon!.abs().toStringAsFixed(5)}° ${p.lon! >= 0 ? "E" : "W"}';
      final cp = _makePainter(coord, size: 12 * pr, color: const ui.Color(0xFF1E90FF));
      cp.layout(maxWidth: W * 0.46);
      cp.paint(canvas, ui.Offset(rightX, ry));
      ry += 18 * pr;
    }

    if (p.showAccuracy && p.acc != null) {
      final accColor = p.acc! <= 5
          ? const ui.Color(0xFF3CB86A)
          : p.acc! <= 20
              ? const ui.Color(0xFFFFB820)
              : const ui.Color(0xFFE63946);
      final ap = _makePainter('± ${p.acc!.toStringAsFixed(0)} m', size: 11 * pr, color: accColor);
      ap.layout(maxWidth: W * 0.46);
      ap.paint(canvas, ui.Offset(rightX, ry));
      ry += 16 * pr;
    }

    if (p.showAddress && p.address.isNotEmpty && !p.address.startsWith('GPS:')) {
      final addr = _truncate(p.address, 45);
      final addrP = _makePainter(addr, size: 11 * pr, color: const ui.Color(0xFF999999));
      addrP.layout(maxWidth: W * 0.46);
      addrP.paint(canvas, ui.Offset(rightX, ry));
      ry += 16 * pr;
    }

    if (p.showWeather && p.weather.isNotEmpty) {
      final wp = _makePainter(p.weather, size: 11 * pr, color: const ui.Color(0xFF1E90FF));
      wp.layout(maxWidth: W * 0.46);
      wp.paint(canvas, ui.Offset(rightX, ry));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LAYOUT 2: TIMEMARK MINIMAL – pojok kanan bawah
  // ─────────────────────────────────────────────────────────────────────────

  static void _drawTimemarkMinimal(
      ui.Canvas canvas, WatermarkParams p, int W, int H, double pr) {
    final double padR = 14 * pr;
    final double padB = 14 * pr;
    final double cardW = 200 * pr;
    final double cardH = 58 * pr;

    final double cx = W - cardW - padR;
    final double cy = H - cardH - padB;

    // Rounded rect bg
    final rr = ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(cx, cy, cardW, cardH),
      ui.Radius.circular(8 * pr),
    );
    canvas.drawRRect(rr, ui.Paint()..color = ui.Color.fromRGBO(0, 0, 0, p.opacity * 0.85));

    // Aksen garis merah kiri
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(cx, cy, 3 * pr, cardH),
        ui.Radius.circular(2 * pr),
      ),
      ui.Paint()..color = const ui.Color(0xFFE63946),
    );

    final timeStr = DateFormat('HH:mm:ss').format(p.timestamp);
    final tp = _makePainter(timeStr, size: 20 * pr, color: const ui.Color(0xFFFFFFFF), bold: true);
    tp.layout(maxWidth: cardW - 20 * pr);
    tp.paint(canvas, ui.Offset(cx + 10 * pr, cy + 8 * pr));

    final dateStr = DateFormat('dd/MM/yyyy').format(p.timestamp);
    final dp = _makePainter(dateStr, size: 11 * pr, color: const ui.Color(0xFF888888));
    dp.layout(maxWidth: cardW - 20 * pr);
    dp.paint(canvas, ui.Offset(cx + 10 * pr, cy + 32 * pr));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LAYOUT 3: GLASS CARD – panel kaca transparan dengan info lengkap
  // ─────────────────────────────────────────────────────────────────────────

  static void _drawTimemarkCard(
      ui.Canvas canvas, WatermarkParams p, int W, int H, double pr) {
    const double kCardWidthRatio = 0.42;
    final double cardW = (W * kCardWidthRatio).clamp(200.0, 520.0);

    // Hitung tinggi card dinamis
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

    // Background glass dark
    final bg = ui.Paint()
      ..color = ui.Color.fromRGBO(8, 12, 24, p.opacity.clamp(0.6, 0.96));
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(cx, cy, cardW, cardH), ui.Radius.circular(10 * pr)),
      bg,
    );

    // Border tipis biru
    if (p.showBorder) {
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
            ui.Rect.fromLTWH(cx, cy, cardW, cardH), ui.Radius.circular(10 * pr)),
        ui.Paint()
          ..color = const ui.Color(0x401E90FF)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1 * pr,
      );
    }

    // Aksen kiri biru
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(cx, cy + 12 * pr, 3 * pr, cardH - 24 * pr),
          ui.Radius.circular(2 * pr)),
      ui.Paint()..color = const ui.Color(0xFF1E90FF),
    );

    final double tx = cx + 14 * pr;
    double ty = cy + 14 * pr;

    // Jam besar
    final timeStr = DateFormat('HH:mm:ss').format(p.timestamp);
    final tp = _makePainter(timeStr, size: 22 * pr, color: const ui.Color(0xFFFFFFFF), bold: true);
    tp.layout(maxWidth: cardW - 20 * pr);
    tp.paint(canvas, ui.Offset(tx, ty));
    ty += 26 * pr;

    // Tanggal
    final dateStr = DateFormat('EEE, dd MMM yyyy').format(p.timestamp);
    final dp = _makePainter(dateStr, size: 12 * pr, color: const ui.Color(0xFF777F8E));
    dp.layout(maxWidth: cardW - 20 * pr);
    dp.paint(canvas, ui.Offset(tx, ty));
    ty += lineH + 2 * pr;

    // Garis separator
    canvas.drawLine(
      ui.Offset(tx, ty),
      ui.Offset(cx + cardW - 14 * pr, ty),
      ui.Paint()..color = const ui.Color(0x201E90FF)..strokeWidth = 1,
    );
    ty += 6 * pr;

    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final coord =
          '${p.lat!.abs().toStringAsFixed(5)}°${p.lat! >= 0 ? "N" : "S"} '
          '${p.lon!.abs().toStringAsFixed(5)}°${p.lon! >= 0 ? "E" : "W"}';
      final cp = _makePainter(coord, size: 11 * pr, color: const ui.Color(0xFF1E90FF));
      cp.layout(maxWidth: cardW - 20 * pr);
      cp.paint(canvas, ui.Offset(tx, ty));
      ty += lineH;
    }

    if (p.showAccuracy && p.acc != null) {
      final accColor = p.acc! <= 5
          ? const ui.Color(0xFF3CB86A)
          : p.acc! <= 20
              ? const ui.Color(0xFFFFB820)
              : const ui.Color(0xFFE63946);
      final ap = _makePainter('± ${p.acc!.toStringAsFixed(1)} m', size: 11 * pr, color: accColor);
      ap.layout(maxWidth: cardW - 20 * pr);
      ap.paint(canvas, ui.Offset(tx, ty));
      ty += lineH;
    }

    if (p.showAddress && p.address.isNotEmpty) {
      final addr = _truncate(p.address, 48);
      final addrP = _makePainter(addr, size: 10.5 * pr, color: const ui.Color(0xFF6A7280));
      addrP.layout(maxWidth: cardW - 20 * pr);
      addrP.paint(canvas, ui.Offset(tx, ty));
      ty += lineH;
    }

    if (p.showWeather && p.weather.isNotEmpty) {
      final wp = _makePainter(p.weather, size: 11 * pr, color: const ui.Color(0xFF1E90FF));
      wp.layout(maxWidth: cardW - 20 * pr);
      wp.paint(canvas, ui.Offset(tx, ty));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LAYOUT 4: HUD OVERLAY
  // Crosshair ring + data panel pojok kanan atas
  // ─────────────────────────────────────────────────────────────────────────

  static void _drawTimemarkHUD(
      ui.Canvas canvas, WatermarkParams p, int W, int H, double pr) {
    // Crosshair di tengah (faint)
    final centerX = W / 2.0;
    final centerY = H / 2.0;
    final crossPaint = ui.Paint()
      ..color = const ui.Color(0x401E90FF)
      ..strokeWidth = 1.5 * pr
      ..style = ui.PaintingStyle.stroke;
    // Ring
    canvas.drawCircle(ui.Offset(centerX, centerY), 28 * pr, crossPaint);
    // Cross lines
    canvas.drawLine(ui.Offset(centerX - 40 * pr, centerY),
        ui.Offset(centerX - 32 * pr, centerY), crossPaint);
    canvas.drawLine(ui.Offset(centerX + 32 * pr, centerY),
        ui.Offset(centerX + 40 * pr, centerY), crossPaint);
    canvas.drawLine(ui.Offset(centerX, centerY - 40 * pr),
        ui.Offset(centerX, centerY - 32 * pr), crossPaint);
    canvas.drawLine(ui.Offset(centerX, centerY + 32 * pr),
        ui.Offset(centerX, centerY + 40 * pr), crossPaint);

    // Panel pojok kanan atas
    final double padR = 12 * pr;
    final double padT = 40 * pr;
    final double cardW = 180 * pr;

    // Waktu
    final timeStr = DateFormat('HH:mm:ss').format(p.timestamp);
    final tp = _makePainter(timeStr, size: 18 * pr, color: const ui.Color(0xFF00E5FF), bold: true);
    tp.layout(maxWidth: cardW);
    tp.paint(canvas, ui.Offset(W - tp.width - padR, padT));

    // Tanggal
    final dateStr = DateFormat('dd/MM/yyyy').format(p.timestamp);
    final dp = _makePainter(dateStr, size: 11 * pr, color: const ui.Color(0xFF006080));
    dp.layout(maxWidth: cardW);
    dp.paint(canvas, ui.Offset(W - dp.width - padR, padT + 24 * pr));

    // GPS strip bawah
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final coord =
          '${p.lat!.abs().toStringAsFixed(4)}°${p.lat! >= 0 ? "N" : "S"} '
          '${p.lon!.abs().toStringAsFixed(4)}°${p.lon! >= 0 ? "E" : "W"}';
      final cp = _makePainter(coord, size: 11 * pr, color: const ui.Color(0xFF00E5FF));
      cp.layout(maxWidth: W * 0.8);
      final oy = H - 24 * pr;
      canvas.drawRect(
        ui.Rect.fromLTWH(0, oy - 4 * pr, cp.width + 24 * pr, 20 * pr),
        ui.Paint()..color = const ui.Color(0xCC000D1A),
      );
      cp.paint(canvas, ui.Offset(12 * pr, oy));
    }

    // App name pojok kiri atas
    final appPainter = _makePainter(p.appName,
        size: 10 * pr,
        color: const ui.Color(0xFF00697A),
        letterSpacing: 2.0);
    appPainter.layout(maxWidth: 200 * pr);
    appPainter.paint(canvas, ui.Offset(14 * pr, 20 * pr));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LAYOUT 5: FILM STRIP
  // Border film perforated + timestamp pojok kanan bawah
  // ─────────────────────────────────────────────────────────────────────────

  static void _drawTimemarkFilm(
      ui.Canvas canvas, WatermarkParams p, int W, int H, double pr) {
    final double borderW = 28 * pr;
    final double holeR = 5 * pr;
    final double holeSpacing = 18 * pr;

    // Border oranye-hitam atas dan bawah
    final filmPaint = ui.Paint()..color = const ui.Color(0xFF1A1000);
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, W.toDouble(), borderW), filmPaint);
    canvas.drawRect(
        ui.Rect.fromLTWH(0, H - borderW, W.toDouble(), borderW), filmPaint);

    // Lubang perforasi
    final holePaint = ui.Paint()..color = const ui.Color(0xFFFF9500);
    final holeCount = (W / holeSpacing).floor();
    for (int i = 0; i < holeCount; i++) {
      final hx = i * holeSpacing + holeSpacing / 2;
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
            ui.Rect.fromLTWH(hx - holeR, borderW * 0.25, holeR * 2, borderW * 0.5),
            ui.Radius.circular(2 * pr)),
        holePaint,
      );
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
            ui.Rect.fromLTWH(
                hx - holeR, H - borderW + borderW * 0.25, holeR * 2, borderW * 0.5),
            ui.Radius.circular(2 * pr)),
        holePaint,
      );
    }

    // Info card pojok kanan bawah (dalam area foto, di atas border)
    const double cardWidthRatio = 0.38;
    final double cardW = (W * cardWidthRatio).clamp(170.0, 400.0);
    final double cardH = 72 * pr;
    final double margin = 10 * pr;
    final double cx = W - cardW - margin;
    final double cy = H - borderW - cardH - margin;

    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(cx, cy, cardW, cardH), ui.Radius.circular(6 * pr)),
      ui.Paint()..color = ui.Color.fromRGBO(0, 0, 0, p.opacity * 0.82),
    );

    // Garis aksen oranye
    canvas.drawRect(
      ui.Rect.fromLTWH(cx, cy, cardW, 2.5 * pr),
      ui.Paint()..color = const ui.Color(0xFFFF9500),
    );

    final double tx = cx + 10 * pr;
    final timeStr = DateFormat('HH:mm:ss').format(p.timestamp);
    final tp = _makePainter(timeStr, size: 20 * pr, color: const ui.Color(0xFFFFD95A), bold: true);
    tp.layout(maxWidth: cardW - 16 * pr);
    tp.paint(canvas, ui.Offset(tx, cy + 8 * pr));

    final dateStr = DateFormat('EEE, dd MMM yyyy').format(p.timestamp);
    final dp = _makePainter(dateStr, size: 11 * pr, color: const ui.Color(0xFFB89040));
    dp.layout(maxWidth: cardW - 16 * pr);
    dp.paint(canvas, ui.Offset(tx, cy + 32 * pr));

    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final coord = '${p.lat!.toStringAsFixed(4)}, ${p.lon!.toStringAsFixed(4)}';
      final cp = _makePainter(coord, size: 10 * pr, color: const ui.Color(0xFF7A6020));
      cp.layout(maxWidth: cardW - 16 * pr);
      cp.paint(canvas, ui.Offset(tx, cy + 50 * pr));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  static TextPainter _makePainter(
    String text, {
    required double size,
    required ui.Color color,
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
        shadows: [
          Shadow(
              blurRadius: 4,
              color: const ui.Color(0x88000000),
              offset: const Offset(1, 1)),
        ],
      ),
    );
    return TextPainter(
      text: span,
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
  }

  static String _truncate(String s, int maxLen) =>
      s.length > maxLen ? '${s.substring(0, maxLen - 1)}…' : s;

  static Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final Completer<ui.Image> c = Completer();
    ui.decodeImageFromList(bytes, (image) => c.complete(image));
    return c.future;
  }
}
