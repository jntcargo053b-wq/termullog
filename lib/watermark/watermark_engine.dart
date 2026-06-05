// lib/watermark/watermark_engine.dart
// TermulLog – Proof of Delivery Watermark Engine v3
// 3 layout profesional: Corporate, Dark Field, Government

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import '../core/constants.dart';
import 'watermark_params.dart';

class WatermarkEngine {
  // ────────────────────────────────────────────────────────────
  // PUBLIC API
  // ────────────────────────────────────────────────────────────

  static WatermarkParams createParams({
    required Uint8List imageBytes,
    required DateTime timestamp,
    required int layoutIndex,
    required String address,
    required String weather,
    required bool showWeather,
    required bool showAccuracy,
    required bool showMiniMap,
    required double? lat,
    required double? lon,
    required double? acc,
    required Uint8List? mapBytes,
    required int mapSize,
    required int mapZoomLevel,
    required bool showAddress,
    required bool showCoordinates,
    required double opacity,
    required bool showBorder,
    required String fontSize,
    required int imageQuality,
    required String dateFormat,
    required String timeFormat,
  }) {
    return WatermarkParams(
      imageBytes: imageBytes,
      timestamp: timestamp,
      layoutIndex: layoutIndex,
      address: address,
      weather: weather,
      showWeather: showWeather,
      showAccuracy: showAccuracy,
      showAddress: showAddress,
      showCoordinates: showCoordinates,
      opacity: opacity,
      showBorder: showBorder,
      lat: lat,
      lon: lon,
      acc: acc,
      fontScale: 1.0,
      imageQuality: imageQuality,
      appName: 'TermulLog',
      showMiniMap: showMiniMap,
      mapBytes: mapBytes,
      mapSize: mapSize,
      mapZoomLevel: mapZoomLevel,
      fontSize: fontSize,
      dateFormat: dateFormat,
      timeFormat: timeFormat,
    );
  }

  static WatermarkParams createParamsFromMap(Map<String, dynamic> map) {
    return WatermarkParams.fromMap(map);
  }

  static Future<Uint8List> applyFromMapAsync(Map<String, dynamic> map) async {
    final params = WatermarkParams.fromMap(map);
    return process(params);
  }

  // ────────────────────────────────────────────────────────────
  // CORE PROCESS
  // ────────────────────────────────────────────────────────────

  static Future<Uint8List> process(WatermarkParams p) async {
    final ui.Image original = await _decodeImage(p.imageBytes);
    final int W = original.width;
    final int H = original.height;
    // pixel ratio relatif terhadap lebar referensi 1080px
    final double pr = (W / 1080.0).clamp(0.4, 3.5);

    final layout = WatermarkLayout.values[
        p.layoutIndex.clamp(0, WatermarkLayout.values.length - 1)];

    // Decode mini map jika ada
    ui.Image? miniMapImage;
    if (p.showMiniMap && p.mapBytes != null && p.mapBytes!.isNotEmpty) {
      try {
        miniMapImage = await _decodeImage(p.mapBytes!);
      } catch (_) {}
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(original, Offset.zero, ui.Paint());

    switch (layout) {
      case WatermarkLayout.podCorporate:
        _drawCorporate(canvas, p, W, H, pr, miniMapImage);
        break;
      case WatermarkLayout.podDarkField:
        _drawDarkField(canvas, p, W, H, pr, miniMapImage);
        break;
      case WatermarkLayout.podGovern:
        _drawGovernment(canvas, p, W, H, pr, miniMapImage);
        break;
    }

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

    original.dispose();
    output.dispose();
    picture.dispose();
    miniMapImage?.dispose();

    return Uint8List.fromList(jpegBytes);
  }

  // ══════════════════════════════════════════════════════════════
  // LAYOUT 1: CORPORATE REPORT
  // Panel putih solid di bawah foto. Header biru, rows terstruktur,
  // hash verifikasi di footer. Gaya laporan perusahaan profesional.
  // ══════════════════════════════════════════════════════════════
  static void _drawCorporate(
    ui.Canvas canvas,
    WatermarkParams p,
    int W,
    int H,
    double pr,
    ui.Image? miniMapImage,
  ) {
    // ── Dimensi panel ──────────────────────────────────────────
    final double fs = _fsBase(p.fontSize);

    // Hitung tinggi panel berdasarkan jumlah baris
    final List<_Row> rows = _buildRows(p, fs, pr);
    final double headerH = 48 * pr;
    final double rowH = (fs * 1.7 * pr).clamp(22.0 * pr, 36.0 * pr);
    final double footerH = 32 * pr;
    final double padV = 10 * pr;
    final double panelH = headerH + padV + rows.length * rowH + padV + footerH;
    final double panelY = H - panelH;

    // ── Background panel putih ─────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, panelY, W.toDouble(), panelH),
      Paint()..color = const Color(0xFFF8FAFF),
    );

    // ── Header bar biru tua ────────────────────────────────────
    final Paint headerPaint = Paint()..color = const Color(0xFF0D2B5E);
    canvas.drawRect(
      Rect.fromLTWH(0, panelY, W.toDouble(), headerH),
      headerPaint,
    );

    // Accent strip kiri (biru muda)
    canvas.drawRect(
      Rect.fromLTWH(0, panelY, 5 * pr, headerH),
      Paint()..color = const Color(0xFF4A90E2),
    );

    // App name – kiri header
    _paint(canvas,
      text: p.appName.toUpperCase(),
      x: 16 * pr, y: panelY + 10 * pr,
      color: Colors.white,
      size: _fs(15, fs, pr),
      bold: true,
      letterSpacing: 3.0,
    );

    // Label "PROOF OF DELIVERY" – kanan header
    final podLabel = 'PROOF OF DELIVERY';
    final podPainter = _makePainter(podLabel, _fs(9, fs, pr), const Color(0xFF90B4E8),
        letterSpacing: 1.5);
    podPainter.layout(maxWidth: W * 0.5);
    podPainter.paint(canvas, Offset(W - podPainter.width - 16 * pr, panelY + 14 * pr));

    // ── Divider ───────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, panelY + headerH, W.toDouble(), 1.5 * pr),
      Paint()..color = const Color(0xFFDDE4F0),
    );

    // ── Rows data ─────────────────────────────────────────────
    final double padL = 16 * pr;
    double ry = panelY + headerH + padV;

    // Mini map – tampil di kanan jika ada
    double contentW = W.toDouble();
    if (miniMapImage != null && p.showMiniMap) {
      final double mapSz = (panelH - headerH - footerH - 8 * pr).clamp(80 * pr, 200 * pr);
      final double mx = W - mapSz - 12 * pr;
      final double my = panelY + headerH + 4 * pr;
      // Border map
      canvas.drawRect(
        Rect.fromLTWH(mx - 2 * pr, my - 2 * pr, mapSz + 4 * pr, mapSz + 4 * pr),
        Paint()..color = const Color(0xFFDDE4F0),
      );
      canvas.drawImageRect(
        miniMapImage,
        Rect.fromLTWH(0, 0, miniMapImage.width.toDouble(), miniMapImage.height.toDouble()),
        Rect.fromLTWH(mx, my, mapSz, mapSz),
        Paint(),
      );
      contentW = mx - 8 * pr;
    }

    for (final row in rows) {
      // Label abu
      _paint(canvas,
        text: row.label,
        x: padL, y: ry,
        color: const Color(0xFF6B7A99),
        size: _fs(9.5, fs, pr),
        bold: false,
        letterSpacing: 0.8,
      );
      // Value
      _paint(canvas,
        text: row.value,
        x: padL + 120 * pr, y: ry,
        color: row.color ?? const Color(0xFF1A2B4A),
        size: _fs(10.5, fs, pr),
        bold: row.bold,
        maxWidth: contentW - padL - 130 * pr,
      );
      ry += rowH;
    }

    // ── Footer: hash verifikasi ────────────────────────────────
    final double footerY = H - footerH;
    canvas.drawRect(
      Rect.fromLTWH(0, footerY, W.toDouble(), footerH),
      Paint()..color = const Color(0xFFEBF0FB),
    );
    // Garis atas footer
    canvas.drawRect(
      Rect.fromLTWH(0, footerY, W.toDouble(), 1 * pr),
      Paint()..color = const Color(0xFFDDE4F0),
    );

    final String hash = _verifyHash(p);
    _paint(canvas,
      text: '# $hash',
      x: padL, y: footerY + 9 * pr,
      color: const Color(0xFF8C9BB8),
      size: _fs(8.5, fs, pr),
      bold: false,
      letterSpacing: 1.2,
    );

    final String generated = DateFormat('dd/MM/yyyy HH:mm:ss').format(p.timestamp);
    final genPainter = _makePainter('Generated: $generated', _fs(8.5, fs, pr), const Color(0xFF8C9BB8));
    genPainter.layout(maxWidth: W * 0.5);
    genPainter.paint(canvas, Offset(W - genPainter.width - 16 * pr, footerY + 9 * pr));

    // ── Border atas panel ──────────────────────────────────────
    if (p.showBorder) {
      canvas.drawRect(
        Rect.fromLTWH(0, panelY, W.toDouble(), 3 * pr),
        Paint()..color = const Color(0xFF4A90E2),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════
  // LAYOUT 2: DARK FIELD
  // Overlay gelap transparan di pojok kiri bawah foto.
  // Accent cyan. Modern, lapangan, tidak menutupi foto berlebihan.
  // ══════════════════════════════════════════════════════════════
  static void _drawDarkField(
    ui.Canvas canvas,
    WatermarkParams p,
    int W,
    int H,
    double pr,
    ui.Image? miniMapImage,
  ) {
    final double fs = _fsBase(p.fontSize);

    final List<_Row> rows = _buildRows(p, fs, pr);
    final double cardW = (W * 0.52).clamp(260.0, 560.0);
    final double rowH = (fs * 1.6 * pr).clamp(20.0 * pr, 32.0 * pr);
    final double timeBH = 52 * pr;
    final double padV = 12 * pr;
    final double padH = 14 * pr;
    final double cardH = timeBH + padV + rows.length * rowH + padV + 24 * pr;
    final double margin = 16 * pr;
    final double cx = margin;
    final double cy = H - cardH - margin;

    // ── Shadow belakang card ───────────────────────────────────
    final shadowPaint = Paint()
      ..color = const Color(0x55000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx + 4, cy + 4, cardW, cardH),
        Radius.circular(14 * pr),
      ),
      shadowPaint,
    );

    // ── Card background ────────────────────────────────────────
    final double bgAlpha = p.opacity.clamp(0.65, 0.94);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx, cy, cardW, cardH),
        Radius.circular(14 * pr),
      ),
      Paint()..color = Color.fromRGBO(6, 14, 28, bgAlpha),
    );

    // Accent garis kiri (cyan)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx, cy + 14 * pr, 3.5 * pr, cardH - 28 * pr),
        Radius.circular(2 * pr),
      ),
      Paint()..color = const Color(0xFF00D4FF),
    );

    // ── Border (opsional) ──────────────────────────────────────
    if (p.showBorder) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx, cy, cardW, cardH),
          Radius.circular(14 * pr),
        ),
        Paint()
          ..color = const Color(0x3500D4FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 * pr,
      );
    }

    // ── Timestamp besar ────────────────────────────────────────
    final double tx = cx + padH + 8 * pr;
    double ty = cy + 10 * pr;

    final timePainter = _makePainter(
      DateFormat(p.timeFormat).format(p.timestamp),
      _fs(26, fs, pr),
      const Color(0xFFFFFFFF),
      bold: true,
    );
    timePainter.layout(maxWidth: cardW - padH * 2 - 8 * pr);
    timePainter.paint(canvas, Offset(tx, ty));
    ty += timeBH - 8 * pr;

    final datePainter = _makePainter(
      DateFormat(p.dateFormat).format(p.timestamp),
      _fs(11, fs, pr),
      const Color(0xFF00D4FF),
    );
    datePainter.layout(maxWidth: cardW - padH * 2);
    datePainter.paint(canvas, Offset(tx, ty));
    ty += 16 * pr;

    // Divider
    canvas.drawLine(
      Offset(tx, ty),
      Offset(cx + cardW - padH, ty),
      Paint()..color = const Color(0x2500D4FF)..strokeWidth = 1 * pr,
    );
    ty += padV * 0.6;

    // ── Rows data ──────────────────────────────────────────────
    for (final row in rows) {
      // Dot indicator kiri
      canvas.drawCircle(
        Offset(tx - 6 * pr, ty + rowH * 0.38),
        2.5 * pr,
        Paint()..color = (row.color ?? const Color(0xFF00D4FF)).withOpacity(0.7),
      );
      _paint(canvas,
        text: row.label,
        x: tx + 2 * pr, y: ty,
        color: const Color(0xFF607090),
        size: _fs(9, fs, pr),
        bold: false,
      );
      _paint(canvas,
        text: row.value,
        x: tx + 2 * pr, y: ty + (rowH * 0.44),
        color: row.color ?? const Color(0xFFD0E4FF),
        size: _fs(10.5, fs, pr),
        bold: row.bold,
        maxWidth: cardW - padH * 2 - 8 * pr,
      );
      ty += rowH;
    }

    // ── App label di pojok kanan bawah card ───────────────────
    final appPainter = _makePainter(
      p.appName,
      _fs(8, fs, pr),
      const Color(0xFF2A4070),
      letterSpacing: 2.0,
    );
    appPainter.layout(maxWidth: cardW * 0.5);
    appPainter.paint(canvas,
        Offset(cx + cardW - appPainter.width - padH, cy + cardH - 16 * pr));

    // ── Mini map pojok kanan bawah foto ────────────────────────
    if (miniMapImage != null && p.showMiniMap) {
      final double mapSz = (80 * pr).clamp(60.0, 140.0);
      final double mx = W - mapSz - margin;
      final double my = H - mapSz - margin;
      // Rounded border
      final RRect mapRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(mx, my, mapSz, mapSz),
        Radius.circular(8 * pr),
      );
      canvas.clipRRect(mapRect);
      canvas.drawImageRect(
        miniMapImage,
        Rect.fromLTWH(0, 0, miniMapImage.width.toDouble(), miniMapImage.height.toDouble()),
        Rect.fromLTWH(mx, my, mapSz, mapSz),
        Paint(),
      );
      // restore clip (tidak diperlukan karena canvas tidak save/restore, tapi save dulu)
    }
  }

  // ══════════════════════════════════════════════════════════════
  // LAYOUT 3: GOVERNMENT / FORMAL
  // Strip biru tua formal di bawah foto. Dua kolom terstruktur.
  // Tanda verifikasi & hash. Mirip surat dinas resmi.
  // ══════════════════════════════════════════════════════════════
  static void _drawGovernment(
    ui.Canvas canvas,
    WatermarkParams p,
    int W,
    int H,
    double pr,
    ui.Image? miniMapImage,
  ) {
    final double fs = _fsBase(p.fontSize);
    final List<_Row> rows = _buildRows(p, fs, pr);

    final double headerH = 44 * pr;
    final double rowH = (fs * 1.65 * pr).clamp(20.0 * pr, 34.0 * pr);
    final double colGap = 12 * pr;
    final double padV = 10 * pr;
    final double footerH = 30 * pr;

    // Split rows jadi 2 kolom jika banyak
    final int half = (rows.length / 2).ceil();
    final List<_Row> col1 = rows.sublist(0, half);
    final List<_Row> col2 = rows.length > half ? rows.sublist(half) : <_Row>[];
    final int maxRows = col1.length;

    final double panelH = headerH + padV + maxRows * rowH + padV + footerH;
    final double panelY = H - panelH;
    final double padL = 16 * pr;

    // ── Background putih gading ────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, panelY, W.toDouble(), panelH),
      Paint()..color = const Color(0xFFF5F7FC),
    );

    // ── Header strip biru tua ──────────────────────────────────
    final Paint govBlue = Paint()..color = const Color(0xFF1A237E);
    canvas.drawRect(
      Rect.fromLTWH(0, panelY, W.toDouble(), headerH),
      govBlue,
    );

    // Gold accent strip kiri
    canvas.drawRect(
      Rect.fromLTWH(0, panelY, 6 * pr, headerH),
      Paint()..color = const Color(0xFFFFD700),
    );

    // App name
    _paint(canvas,
      text: p.appName.toUpperCase(),
      x: 18 * pr, y: panelY + 8 * pr,
      color: Colors.white,
      size: _fs(14, fs, pr),
      bold: true,
      letterSpacing: 3.5,
    );

    // Verified badge (teks)
    final verifPainter = _makePainter(
      '✓ VERIFIED DOCUMENT',
      _fs(9, fs, pr),
      const Color(0xFFFFD700),
      letterSpacing: 1.2,
    );
    verifPainter.layout(maxWidth: W * 0.5);
    verifPainter.paint(canvas,
        Offset(W - verifPainter.width - 16 * pr, panelY + 15 * pr));

    // ── Divider ────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, panelY + headerH, W.toDouble(), 1.5 * pr),
      Paint()..color = const Color(0xFFCDD4E8),
    );

    // ── Dua kolom data ─────────────────────────────────────────
    final double colW = (W / 2) - padL - colGap / 2;

    void renderCol(List<_Row> colRows, double startX) {
      double ry = panelY + headerH + padV;
      for (final row in colRows) {
        // Label
        _paint(canvas,
          text: row.label.toUpperCase(),
          x: startX, y: ry,
          color: const Color(0xFF5A6490),
          size: _fs(8, fs, pr),
          bold: false,
          letterSpacing: 0.9,
        );
        // Value
        _paint(canvas,
          text: row.value,
          x: startX, y: ry + (rowH * 0.42),
          color: row.color ?? const Color(0xFF1A2050),
          size: _fs(11, fs, pr),
          bold: row.bold,
          maxWidth: colW,
        );
        ry += rowH;
      }
    }

    renderCol(col1, padL);
    if (col2.isNotEmpty) renderCol(col2, W / 2 + colGap / 2);

    // Garis pemisah kolom vertikal
    if (col2.isNotEmpty) {
      final double divX = W / 2;
      canvas.drawLine(
        Offset(divX, panelY + headerH + padV),
        Offset(divX, H - footerH - padV),
        Paint()..color = const Color(0xFFCDD4E8)..strokeWidth = 1 * pr,
      );
    }

    // Mini map – pojok kanan bawah dalam content area
    if (miniMapImage != null && p.showMiniMap && col2.isEmpty) {
      final double mapSz = (maxRows * rowH - 8 * pr).clamp(60 * pr, 120 * pr);
      final double mx = W - mapSz - padL;
      final double my = panelY + headerH + padV;
      canvas.drawRect(
        Rect.fromLTWH(mx - 2 * pr, my - 2 * pr, mapSz + 4 * pr, mapSz + 4 * pr),
        Paint()..color = const Color(0xFFCDD4E8),
      );
      canvas.drawImageRect(
        miniMapImage,
        Rect.fromLTWH(0, 0, miniMapImage.width.toDouble(), miniMapImage.height.toDouble()),
        Rect.fromLTWH(mx, my, mapSz, mapSz),
        Paint(),
      );
    }

    // ── Footer ─────────────────────────────────────────────────
    final double footerY = H - footerH;
    canvas.drawRect(
      Rect.fromLTWH(0, footerY, W.toDouble(), 1 * pr),
      Paint()..color = const Color(0xFFCDD4E8),
    );

    final String hash = _verifyHash(p);
    final String generated = DateFormat('dd/MM/yyyy HH:mm:ss').format(p.timestamp);
    _paint(canvas,
      text: 'REF: $hash',
      x: padL, y: footerY + 7 * pr,
      color: const Color(0xFF8090B8),
      size: _fs(8, fs, pr),
      letterSpacing: 1.0,
    );
    final genP = _makePainter(generated, _fs(8, fs, pr), const Color(0xFF8090B8));
    genP.layout(maxWidth: W * 0.5);
    genP.paint(canvas, Offset(W - genP.width - padL, footerY + 7 * pr));

    // ── Border atas ────────────────────────────────────────────
    if (p.showBorder) {
      canvas.drawRect(
        Rect.fromLTWH(0, panelY, W.toDouble(), 3.5 * pr),
        Paint()..color = const Color(0xFFFFD700),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════

  /// Bangun daftar baris data berdasarkan toggle settings
  static List<_Row> _buildRows(WatermarkParams p, double fs, double pr) {
    final rows = <_Row>[];

    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final latStr =
          '${p.lat!.abs().toStringAsFixed(6)}° ${p.lat! >= 0 ? 'N' : 'S'}';
      final lonStr =
          '${p.lon!.abs().toStringAsFixed(6)}° ${p.lon! >= 0 ? 'E' : 'W'}';
      rows.add(_Row(
        label: 'LATITUDE',
        value: latStr,
        color: const Color(0xFF1565C0),
        bold: true,
      ));
      rows.add(_Row(
        label: 'LONGITUDE',
        value: lonStr,
        color: const Color(0xFF1565C0),
        bold: true,
      ));
    }

    if (p.showAccuracy && p.acc != null) {
      final Color accColor = p.acc! <= 5
          ? const Color(0xFF2E7D32)
          : p.acc! <= 20
              ? const Color(0xFFE65100)
              : const Color(0xFFC62828);
      rows.add(_Row(
        label: 'GPS ACCURACY',
        value: '± ${p.acc!.toStringAsFixed(1)} m',
        color: accColor,
        bold: false,
      ));
    }

    if (p.showAddress && p.address.isNotEmpty) {
      rows.add(_Row(
        label: 'ADDRESS',
        value: p.address,
        color: null,
        bold: false,
      ));
    }

    if (p.showWeather && p.weather.isNotEmpty) {
      rows.add(_Row(
        label: 'WEATHER',
        value: p.weather,
        color: const Color(0xFF006064),
        bold: false,
      ));
    }

    return rows;
  }

  /// Hash verifikasi sederhana (8 karakter hex dari timestamp + koordinat)
  static String _verifyHash(WatermarkParams p) {
    final input =
        '${p.timestamp.millisecondsSinceEpoch}|${p.lat ?? 0}|${p.lon ?? 0}|${p.address}';
    int hash = 0x811C9DC5;
    for (final c in input.codeUnits) {
      hash ^= c;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).toUpperCase().padLeft(8, '0');
  }

  static double _fsBase(String fontSizePref) {
    switch (fontSizePref.toLowerCase()) {
      case 'small':  return 0.85;
      case 'large':  return 1.2;
      default:       return 1.0;
    }
  }

  static double _fs(double base, double fsMultiplier, double pr) {
    return (base * fsMultiplier * pr).clamp(7.0, 72.0);
  }

  static void _paint(
    ui.Canvas canvas, {
    required String text,
    required double x,
    required double y,
    required Color color,
    required double size,
    bool bold = false,
    double letterSpacing = 0.0,
    double? maxWidth,
  }) {
    final tp = _makePainter(text, size, color,
        bold: bold, letterSpacing: letterSpacing);
    tp.layout(maxWidth: maxWidth ?? double.infinity);
    tp.paint(canvas, Offset(x, y));
  }

  static TextPainter _makePainter(
    String text,
    double size,
    Color color, {
    bool bold = false,
    double letterSpacing = 0.0,
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: letterSpacing,
          height: 1.2,
          shadows: const [
            Shadow(
              blurRadius: 3,
              color: Color(0x55000000),
              offset: Offset(0.5, 0.5),
            ),
          ],
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    );
  }

  static Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    return completer.future;
  }
}

// ── Data class row ────────────────────────────────────────────
class _Row {
  final String label;
  final String value;
  final Color? color;
  final bool bold;

  const _Row({
    required this.label,
    required this.value,
    this.color,
    required this.bold,
  });
}
