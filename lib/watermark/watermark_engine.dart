// lib/watermark/watermark_engine.dart
// ============================================================
// WATERMARK ENGINE — POD Edition
// Scale-aware: semua ukuran proporsional terhadap resolusi foto
// ============================================================

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import 'watermark_params.dart';
import 'watermark_layout.dart';

class WatermarkEngine {
  /// Main entry point
  static Future<Uint8List> process(WatermarkParams params) async {
    try {
      final originalImg = img.decodeImage(params.imageBytes);
      if (originalImg == null) throw Exception('Failed to decode image');

      final W = originalImg.width;
      final H = originalImg.height;

      // Scale factor: referensi desain di 1080px lebar
      // foto 4000px → scale 3.7x, foto 1080px → 1.0x
      final double sc = (W / 1080.0).clamp(0.8, 4.0);

      final uiImage = await _decodeUiImage(params.imageBytes);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, W.toDouble(), H.toDouble()));

      canvas.drawImage(uiImage, Offset.zero, Paint());

      final layout = WatermarkLayout.values[params.layoutIndex];
      switch (layout) {
        case WatermarkLayout.podCorporate:
          _drawCorporate(canvas, W.toDouble(), H.toDouble(), sc, params);
          break;
        case WatermarkLayout.podDarkField:
          _drawDarkField(canvas, W.toDouble(), H.toDouble(), sc, params);
          break;
        case WatermarkLayout.podGovern:
          _drawGovernment(canvas, W.toDouble(), H.toDouble(), sc, params);
          break;
      }

      final picture = recorder.endRecording();
      final uiOut = await picture.toImage(W, H);
      final byteData = await uiOut.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to encode PNG');

      final jpegImg = img.decodeImage(byteData.buffer.asUint8List());
      if (jpegImg == null) throw Exception('Failed to decode processed image');

      return Uint8List.fromList(img.encodeJpg(jpegImg, quality: params.imageQuality));
    } catch (e) {
      debugPrint('WatermarkEngine.process error: $e');
      rethrow;
    }
  }

  static Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    return completer.future.timeout(const Duration(seconds: 10),
        onTimeout: () => throw Exception('Image decode timeout'));
  }

  // ═══════════════════════════════════════════════════════════════
  // CORPORATE — Panel putih bersih, header biru navy
  // ═══════════════════════════════════════════════════════════════
  static void _drawCorporate(Canvas c, double W, double H, double sc, WatermarkParams p) {
    final double headerH = 56 * sc;
    final double rowH    = 28 * sc;
    final double padL    = 18 * sc;
    final double footerH = 26 * sc;

    int rows = 1; // date always
    if (p.showCoordinates && p.lat != null) rows += 2;
    if (p.showAccuracy && p.acc != null) rows++;
    if (p.showAddress && p.address.isNotEmpty) rows++;
    if (p.showWeather && p.weather.isNotEmpty) rows++;

    final double panelH = headerH + 10 * sc + rows * rowH + 10 * sc + footerH;
    final double panelY = H - panelH;

    // Panel background
    c.drawRect(Rect.fromLTWH(0, panelY, W, panelH),
        Paint()..color = const Color(0xFFF0F4FF).withOpacity(p.opacity.clamp(0.7, 1.0)));

    // Header biru navy
    c.drawRect(Rect.fromLTWH(0, panelY, W, headerH),
        Paint()..color = const Color(0xFF0D2B5E));

    // Accent strip kiri (biru muda)
    c.drawRect(Rect.fromLTWH(0, panelY, 6 * sc, headerH),
        Paint()..color = const Color(0xFF4A90E2));

    // App name header
    _tp('TERMULLOG', 18 * sc, panelY + 10 * sc, const Color(0xFFFFFFFF),
        bold: true, letterSpacing: 3.0, x: padL + 8 * sc).paint(c);
    _tp('PROOF OF DELIVERY', 9 * sc, panelY + 34 * sc, const Color(0xFF90B4E8),
        x: padL + 8 * sc, letterSpacing: 1.5).paint(c);

    // Timestamp kanan atas
    final ts = DateFormat('HH:mm:ss').format(p.timestamp);
    final tsDate = DateFormat('dd MMM yyyy').format(p.timestamp);
    _tpRight(ts, 20 * sc, panelY + 8 * sc, const Color(0xFFFFFFFF), W, padL, bold: true).paint(c);
    _tpRight(tsDate, 10 * sc, panelY + 34 * sc, const Color(0xFF90B4E8), W, padL).paint(c);

    // Divider
    c.drawRect(Rect.fromLTWH(0, panelY + headerH, W, 1.5 * sc),
        Paint()..color = const Color(0xFFCDD4E8));

    // Rows
    double ry = panelY + headerH + 10 * sc;

    if (p.showCoordinates && p.lat != null && p.lon != null) {
      _rowLV(c, 'LATITUDE',
          '${p.lat!.abs().toStringAsFixed(6)}°  ${p.lat! >= 0 ? 'N' : 'S'}',
          padL, ry, sc, valueColor: const Color(0xFF1565C0), bold: true);
      ry += rowH;
      _rowLV(c, 'LONGITUDE',
          '${p.lon!.abs().toStringAsFixed(6)}°  ${p.lon! >= 0 ? 'E' : 'W'}',
          padL, ry, sc, valueColor: const Color(0xFF1565C0), bold: true);
      ry += rowH;
    }

    if (p.showAccuracy && p.acc != null) {
      final ac = _accColor(p.acc!);
      _rowLV(c, 'ACCURACY', '± ${p.acc!.toStringAsFixed(1)} m', padL, ry, sc, valueColor: ac);
      ry += rowH;
    }

    if (p.showAddress && p.address.isNotEmpty) {
      _rowLV(c, 'ADDRESS', p.address, padL, ry, sc, maxValueW: W - padL * 2 - 80 * sc);
      ry += rowH;
    }

    if (p.showWeather && p.weather.isNotEmpty) {
      _rowLV(c, 'WEATHER', p.weather, padL, ry, sc, valueColor: const Color(0xFF006064));
      ry += rowH;
    }

    _rowLV(c, 'DATE', DateFormat('EEEE, dd MMMM yyyy').format(p.timestamp),
        padL, ry, sc);

    // Footer hash
    c.drawRect(Rect.fromLTWH(0, H - footerH, W, 1.5 * sc),
        Paint()..color = const Color(0xFFCDD4E8));
    _tp('# ${_hash(p)}', 8 * sc, H - footerH + 8 * sc,
        const Color(0xFFAAB0C8), x: padL, letterSpacing: 1.2).paint(c);

    // Border atas
    if (p.showBorder) {
      c.drawRect(Rect.fromLTWH(0, panelY, W, 4 * sc),
          Paint()..color = const Color(0xFF4A90E2));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // DARK FIELD — Card gelap kiri bawah, accent cyan
  // ═══════════════════════════════════════════════════════════════
  static void _drawDarkField(Canvas c, double W, double H, double sc, WatermarkParams p) {
    final double cardW = (W * 0.58).clamp(300 * sc, W * 0.9);
    final double rowH  = 26 * sc;
    final double margin = 20 * sc;
    final double padI  = 18 * sc;

    int rows = 0;
    if (p.showCoordinates && p.lat != null) rows++;
    if (p.showAccuracy && p.acc != null) rows++;
    if (p.showAddress && p.address.isNotEmpty) rows++;
    if (p.showWeather && p.weather.isNotEmpty) rows++;

    final double cardH = 56 * sc + 14 * sc + rows * rowH + 16 * sc;
    final double cx = margin;
    final double cy = H - cardH - margin;

    final double bgOpacity = p.opacity.clamp(0.75, 0.95);

    // Background card
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx, cy, cardW, cardH), Radius.circular(14 * sc)),
      Paint()..color = Color.fromRGBO(6, 14, 28, bgOpacity),
    );

    // Accent strip kiri
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx, cy + 16 * sc, 4 * sc, cardH - 32 * sc), Radius.circular(2 * sc)),
      Paint()..color = const Color(0xFF00D4FF),
    );

    // Border
    if (p.showBorder) {
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(cx, cy, cardW, cardH), Radius.circular(14 * sc)),
        Paint()
          ..color = const Color(0x5500D4FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * sc,
      );
    }

    final double tx = cx + padI + 4 * sc;
    double ty = cy + 12 * sc;

    // Jam besar
    _tp(DateFormat('HH:mm:ss').format(p.timestamp), 28 * sc, ty,
        Colors.white, bold: true, x: tx).paint(c);
    ty += 36 * sc;

    // Tanggal cyan
    _tp(DateFormat('dd MMMM yyyy').format(p.timestamp), 12 * sc, ty,
        const Color(0xFF00D4FF), x: tx).paint(c);
    ty += 18 * sc;

    // Divider
    c.drawLine(Offset(tx, ty), Offset(cx + cardW - padI, ty),
        Paint()..color = const Color(0x3300D4FF)..strokeWidth = 1.5 * sc);
    ty += 14 * sc;

    if (p.showCoordinates && p.lat != null && p.lon != null) {
      _tp(
        '${p.lat!.abs().toStringAsFixed(5)}° ${p.lat! >= 0 ? 'N' : 'S'}   '
        '${p.lon!.abs().toStringAsFixed(5)}° ${p.lon! >= 0 ? 'E' : 'W'}',
        11 * sc, ty, const Color(0xFF4AC8FF), x: tx,
      ).paint(c);
      ty += rowH;
    }

    if (p.showAccuracy && p.acc != null) {
      final ac = _accColor(p.acc!, dark: true);
      _tp('± ${p.acc!.toStringAsFixed(1)} m  GPS', 11 * sc, ty, ac, x: tx).paint(c);
      ty += rowH;
    }

    if (p.showAddress && p.address.isNotEmpty) {
      _tp(p.address, 10 * sc, ty, const Color(0xFF8ABADF),
          x: tx, maxW: cardW - padI * 2).paint(c);
      ty += rowH;
    }

    if (p.showWeather && p.weather.isNotEmpty) {
      _tp(p.weather, 10 * sc, ty, const Color(0xFF00B8A0), x: tx).paint(c);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // GOVERNMENT — Full-width panel, dua kolom, gold accent
  // ═══════════════════════════════════════════════════════════════
  static void _drawGovernment(Canvas c, double W, double H, double sc, WatermarkParams p) {
    final double headerH = 60 * sc;
    final double rowH    = 28 * sc;
    final double padL    = 18 * sc;
    final double footerH = 28 * sc;

    // Hitung rows per kolom
    final List<MapEntry<String, String>> leftRows = [];
    final List<MapEntry<String, String>> rightRows = [];

    leftRows.add(MapEntry('TIME', DateFormat('HH:mm:ss').format(p.timestamp)));
    leftRows.add(MapEntry('DATE', DateFormat('dd MMMM yyyy').format(p.timestamp)));

    if (p.showCoordinates && p.lat != null) {
      leftRows.add(MapEntry('LATITUDE',
          '${p.lat!.abs().toStringAsFixed(6)}° ${p.lat! >= 0 ? 'N' : 'S'}'));
    }
    if (p.showCoordinates && p.lon != null) {
      rightRows.add(MapEntry('LONGITUDE',
          '${p.lon!.abs().toStringAsFixed(6)}° ${p.lon! >= 0 ? 'E' : 'W'}'));
    }
    if (p.showAccuracy && p.acc != null) {
      rightRows.add(MapEntry('ACCURACY', '± ${p.acc!.toStringAsFixed(1)} m'));
    }
    if (p.showAddress && p.address.isNotEmpty) {
      rightRows.add(MapEntry('ADDRESS', p.address));
    }
    if (p.showWeather && p.weather.isNotEmpty) {
      rightRows.add(MapEntry('WEATHER', p.weather));
    }

    final int maxRows = leftRows.length > rightRows.length ? leftRows.length : rightRows.length;
    final double panelH = headerH + 10 * sc + maxRows * rowH + 10 * sc + footerH;
    final double panelY = H - panelH;

    // Background putih keabu-an
    c.drawRect(Rect.fromLTWH(0, panelY, W, panelH),
        Paint()..color = const Color(0xFFF4F6FB).withOpacity(p.opacity.clamp(0.7, 1.0)));

    // Header biru tua
    c.drawRect(Rect.fromLTWH(0, panelY, W, headerH),
        Paint()..color = const Color(0xFF1A237E));

    // Gold strip kiri
    c.drawRect(Rect.fromLTWH(0, panelY, 7 * sc, headerH),
        Paint()..color = const Color(0xFFFFD700));

    // Gold strip kanan
    c.drawRect(Rect.fromLTWH(W - 7 * sc, panelY, 7 * sc, headerH),
        Paint()..color = const Color(0xFFFFD700));

    // App name
    _tp('TERMULLOG', 20 * sc, panelY + 10 * sc, Colors.white,
        bold: true, letterSpacing: 4.0, x: padL + 10 * sc).paint(c);
    _tp('DOKUMEN TERVERIFIKASI', 9 * sc, panelY + 37 * sc, const Color(0xFFFFD700),
        x: padL + 10 * sc, letterSpacing: 2.0).paint(c);

    // Verification code kanan
    _tpRight('✓ ${_verCode(p)}', 11 * sc, panelY + 14 * sc, const Color(0xFFFFD700), W, padL).paint(c);
    _tpRight(_hash(p), 9 * sc, panelY + 32 * sc, const Color(0xFF9099CC), W, padL).paint(c);

    // Divider header
    c.drawRect(Rect.fromLTWH(0, panelY + headerH, W, 2 * sc),
        Paint()..color = const Color(0xFFCDD4E8));

    // Kolom kiri
    double ry = panelY + headerH + 10 * sc;
    for (final e in leftRows) {
      Color? vc;
      if (e.key == 'TIME') vc = const Color(0xFF1A2050);
      if (e.key == 'LATITUDE') vc = const Color(0xFF1565C0);
      _rowLV(c, e.key, e.value, padL, ry, sc, valueColor: vc, bold: e.key == 'TIME',
          maxValueW: W / 2 - padL * 2);
      ry += rowH;
    }

    // Garis pemisah kolom
    c.drawLine(
      Offset(W / 2, panelY + headerH + 8 * sc),
      Offset(W / 2, H - footerH - 8 * sc),
      Paint()..color = const Color(0xFFCDD4E8)..strokeWidth = 1.0 * sc,
    );

    // Kolom kanan
    double ry2 = panelY + headerH + 10 * sc;
    for (final e in rightRows) {
      Color? vc;
      if (e.key == 'LONGITUDE') vc = const Color(0xFF1565C0);
      if (e.key == 'ACCURACY') vc = _accColor(p.acc ?? 99);
      if (e.key == 'WEATHER') vc = const Color(0xFF006064);
      _rowLV(c, e.key, e.value, W / 2 + padL, ry2, sc, valueColor: vc,
          maxValueW: W / 2 - padL * 2);
      ry2 += rowH;
    }

    // Footer
    c.drawRect(Rect.fromLTWH(0, H - footerH, W, 2 * sc),
        Paint()..color = const Color(0xFFFFD700));
    _tp('REF: ${_hash(p)}', 8 * sc, H - footerH + 8 * sc,
        const Color(0xFF8090B8), x: padL, letterSpacing: 1.2).paint(c);
    _tpRight(DateFormat('dd/MM/yyyy HH:mm').format(p.timestamp),
        8 * sc, H - footerH + 8 * sc, const Color(0xFF8090B8), W, padL).paint(c);

    if (p.showBorder) {
      c.drawRect(Rect.fromLTWH(0, panelY, W, 4 * sc),
          Paint()..color = const Color(0xFFFFD700));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════

  static void _rowLV(
    Canvas c,
    String label,
    String value,
    double x,
    double y,
    double sc, {
    Color? valueColor,
    bool bold = false,
    double? maxValueW,
  }) {
    // Label kecil abu
    final lp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: const Color(0xFF8090B0),
          fontSize: 8 * sc,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    lp.layout();
    lp.paint(c, Offset(x, y));

    // Value
    final vp = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: valueColor ?? const Color(0xFF1A2050),
          fontSize: 12 * sc,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
    vp.layout(maxWidth: maxValueW ?? 400 * sc);
    vp.paint(c, Offset(x, y + 10 * sc));
  }

  // TextPainter builder (fluent)
  static _TPHelper _tp(
    String text,
    double size,
    double y,
    Color color, {
    bool bold = false,
    double letterSpacing = 0,
    double x = 14,
    double? maxW,
  }) =>
      _TPHelper(text, size, y, color, bold: bold, letterSpacing: letterSpacing, x: x, maxW: maxW);

  static _TPHelper _tpRight(
    String text,
    double size,
    double y,
    Color color,
    double W,
    double pad, {
    bool bold = false,
  }) =>
      _TPHelper.right(text, size, y, color, W, pad, bold: bold);

  static Color _accColor(double acc, {bool dark = false}) {
    if (acc <= 5) return dark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32);
    if (acc <= 20) return dark ? const Color(0xFFFF9800) : const Color(0xFFE65100);
    return dark ? const Color(0xFFEF5350) : const Color(0xFFC62828);
  }

  static String _hash(WatermarkParams p) {
    int h = 0x811C9DC5;
    for (final c in '${p.timestamp.millisecondsSinceEpoch}${p.lat}${p.lon}'.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).toUpperCase().padLeft(8, '0');
  }

  static String _verCode(WatermarkParams p) {
    final s = '${p.timestamp.day}${p.timestamp.month}${p.timestamp.year}${(p.lat ?? 0).abs().floor()}';
    return s.hashCode.toRadixString(16).substring(0, 6).toUpperCase();
  }
}

// Internal helper untuk builder pattern
class _TPHelper {
  final String text;
  final double size, y, x;
  final Color color;
  final bool bold;
  final double letterSpacing;
  final double? maxW;
  final double? rightW;
  final double? rightPad;

  _TPHelper(this.text, this.size, this.y, this.color,
      {this.bold = false, this.letterSpacing = 0, this.x = 14, this.maxW})
      : rightW = null,
        rightPad = null;

  _TPHelper.right(this.text, this.size, this.y, this.color, this.rightW, this.rightPad,
      {this.bold = false})
      : x = 0,
        letterSpacing = 0,
        maxW = null;

  void paint(Canvas c) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: letterSpacing,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
    tp.layout(maxWidth: maxW ?? (rightW != null ? rightW! / 2 : 9999));

    if (rightW != null) {
      tp.paint(c, Offset(rightW! - tp.width - (rightPad ?? 14), y));
    } else {
      tp.paint(c, Offset(x, y));
    }
  }
}
