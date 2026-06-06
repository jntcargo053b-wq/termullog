// lib/watermark/watermark_engine.dart
// ============================================================
// WATERMARK ENGINE — Timemark Style Edition
// Tiga layout referensi Timemark untuk foto hasil akhir
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
  static Future<Uint8List> process(WatermarkParams params) async {
    try {
      final originalImg = img.decodeImage(params.imageBytes);
      if (originalImg == null) throw Exception('Failed to decode image');

      final W = originalImg.width;
      final H = originalImg.height;
      final double sc = (W / 1080.0).clamp(0.8, 4.0);

      final uiImage = await _decodeUiImage(params.imageBytes);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, W.toDouble(), H.toDouble()));
      canvas.drawImage(uiImage, Offset.zero, Paint());

      final layout = WatermarkLayout.values[params.layoutIndex];
      switch (layout) {
        case WatermarkLayout.podCorporate:
          _drawTimemarkLight(canvas, W.toDouble(), H.toDouble(), sc, params);
          break;
        case WatermarkLayout.podDarkField:
          _drawTimemarkDark(canvas, W.toDouble(), H.toDouble(), sc, params);
          break;
        case WatermarkLayout.podGovern:
          _drawTimemarkClean(canvas, W.toDouble(), H.toDouble(), sc, params);
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
  // LAYOUT 1 — Timemark Light
  // Panel putih bawah: [NAMA | JAM BESAR | LOGO] + tanggal + koordinat
  // Branding pojok kanan bawah: "Termullog\nCamera"
  // Kode verifikasi vertikal sisi kanan
  // ═══════════════════════════════════════════════════════════════
  static void _drawTimemarkLight(Canvas c, double W, double H, double sc, WatermarkParams p) {
    const double refW = 1080.0;
    final double panelH = _lightPanelHeight(sc, p);
    final double panelY = H - panelH;

    // Panel putih semi-transparan
    final panelPaint = Paint()..color = Colors.white.withOpacity(p.opacity.clamp(0.88, 1.0));
    c.drawRect(Rect.fromLTWH(0, panelY, W, panelH), panelPaint);

    // Garis aksen kuning kiri atas panel
    c.drawRect(Rect.fromLTWH(0, panelY, 8 * sc, 90 * sc),
        Paint()..color = const Color(0xFFF5C518));

    // ─── Baris 1: NAMA | JAM | LOGO/APPNAME ───
    final double row1Y = panelY + 12 * sc;
    final double badgeW = 160 * sc;
    final double badgeH = 60 * sc;
    final double badgeR = 12 * sc;

    // Badge kuning (nama user / app name)
    final rrectBadge = RRect.fromRectAndRadius(
        Rect.fromLTWH(16 * sc, row1Y, badgeW, badgeH), Radius.circular(badgeR));
    c.drawRRect(rrectBadge, Paint()..color = const Color(0xFFF5C518));
    _tp(p.appName.isNotEmpty ? p.appName : 'termullog',
        22 * sc, row1Y + 14 * sc, const Color(0xFF1A1A1A),
        bold: true, x: 16 * sc + badgeW / 2, centerX: true, maxW: badgeW - 16 * sc).paint(c);

    // Jam besar (bold biru/hitam)
    final String timeStr = DateFormat('HH:mm').format(p.timestamp);
    _tp(timeStr, 58 * sc, row1Y + 2 * sc, const Color(0xFF1565C0),
        bold: true, x: 16 * sc + badgeW + 20 * sc).paint(c);

    // App brand pojok kanan (warna seperti Timemark)
    final double brandX = W - 200 * sc;
    _tp('Termullog', 26 * sc, row1Y + 8 * sc, const Color(0xFFF5C518),
        bold: true, x: brandX).paint(c);
    _tp('Camera', 16 * sc, row1Y + 38 * sc, const Color(0xFFFFFFFF),
        x: brandX).paint(c);

    // ─── Baris 2: Tanggal ───
    final double row2Y = panelY + 90 * sc;
    c.drawRect(Rect.fromLTWH(0, row2Y, W, 1.5 * sc),
        Paint()..color = const Color(0xFFE0E0E0));

    final double padL = 16 * sc;
    final String dateStr = DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(p.timestamp);
    _tp(dateStr, 20 * sc, row2Y + 10 * sc, const Color(0xFF222222),
        bold: true, x: padL).paint(c);

    // ─── Baris 3: Koordinat ───
    double row3Y = row2Y + 44 * sc;
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final String coord =
          '${p.lat!.abs().toStringAsFixed(6)}°${p.lat! < 0 ? 'S' : 'N'}, '
          '${p.lon!.abs().toStringAsFixed(6)}°${p.lon! < 0 ? 'W' : 'E'}';
      _tp(coord, 18 * sc, row3Y, const Color(0xFF444444), x: padL).paint(c);
      row3Y += 30 * sc;
    }

    // ─── Baris 4: Alamat (jika aktif) ───
    if (p.showAddress && p.address.isNotEmpty) {
      _tp(p.address, 15 * sc, row3Y, const Color(0xFF666666),
          x: padL, maxW: W - padL * 2 - 80 * sc).paint(c);
      row3Y += 24 * sc;
    }

    // ─── Baris 5: Weather ───
    if (p.showWeather && p.weather.isNotEmpty) {
      _tp(p.weather, 14 * sc, row3Y, const Color(0xFF006064), x: padL).paint(c);
    }

    // ─── Footer: Shield + tagline ───
    final double footerY = H - 40 * sc;
    c.drawRect(Rect.fromLTWH(0, footerY, W, 1 * sc),
        Paint()..color = const Color(0xFFE0E0E0));
    _tp('🛡 Termullog menjamin keaslian waktu', 13 * sc, footerY + 6 * sc,
        const Color(0xFF888888), x: padL).paint(c);

    // ─── Kode verifikasi vertikal sisi kanan ───
    final String verCode = _verCode(p);
    _drawVerticalText(c, '© $verCode  Termullog Verified',
        13 * sc, W - 22 * sc, H - panelH / 2, const Color(0xFF888888), sc);

    // Border atas panel (kuning tipis)
    if (p.showBorder) {
      c.drawRect(Rect.fromLTWH(0, panelY, W, 4 * sc),
          Paint()..color = const Color(0xFFF5C518));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // LAYOUT 2 — Timemark Dark
  // Panel gelap full-width bawah: jam besar kiri | tanggal+hari kanan
  // Alamat multi-line, kode foto bawah
  // Branding "Timemark" pojok kanan atas
  // ═══════════════════════════════════════════════════════════════
  static void _drawTimemarkDark(Canvas c, double W, double H, double sc, WatermarkParams p) {
    final double panelH = _darkPanelHeight(sc, p);
    final double panelY = H - panelH;
    final double padL = 30 * sc;

    // Panel gelap dengan gradient (simulasi gradient via dua layer)
    c.drawRect(Rect.fromLTWH(0, panelY, W, panelH),
        Paint()..color = Color.fromRGBO(18, 18, 18, p.opacity.clamp(0.82, 0.96)));

    // Garis kuning atas panel
    c.drawRect(Rect.fromLTWH(0, panelY, W, 3 * sc),
        Paint()..color = const Color(0xFFF5C518));

    // ─── Branding pojok kanan atas foto (di luar panel) ───
    _tp('Termullog', 26 * sc, panelY - 100 * sc, const Color(0xFFF5C518),
        bold: true, x: W - 220 * sc).paint(c);
    _tp('Foto 100% akurat', 16 * sc, panelY - 64 * sc, Colors.white,
        x: W - 220 * sc).paint(c);

    // ─── Kode verifikasi vertikal sisi kanan ───
    final String verCode = _verCode(p);
    _drawVerticalText(c, '© $verCode  Termullog Verified',
        13 * sc, W - 22 * sc, panelY - panelH * 0.3, const Color(0xFFAAAAAA), sc);

    // ─── Jam besar kiri ───
    final String timeStr = DateFormat('HH:mm').format(p.timestamp);
    _tp(timeStr, 72 * sc, panelY + 18 * sc, Colors.white, bold: true, x: padL).paint(c);

    // Separator vertikal
    final double sepX = padL + 180 * sc;
    c.drawLine(Offset(sepX, panelY + 20 * sc), Offset(sepX, panelY + 110 * sc),
        Paint()..color = Colors.white54..strokeWidth = 2 * sc);

    // ─── Tanggal dan hari (kanan separator) ───
    final double dateX = sepX + 20 * sc;
    final String dateNum = DateFormat('dd MMMM yyyy').format(p.timestamp);
    final String dayName = DateFormat('EEEE', 'id_ID').format(p.timestamp);
    _tp(dateNum, 22 * sc, panelY + 28 * sc, Colors.white, x: dateX).paint(c);
    _tp(dayName, 20 * sc, panelY + 56 * sc, Colors.white70, x: dateX).paint(c);

    // ─── Alamat ───
    double addrY = panelY + 126 * sc;
    if (p.showAddress && p.address.isNotEmpty) {
      _tp(p.address, 18 * sc, addrY, Colors.white,
          x: padL, maxW: W - padL * 2).paint(c);
      addrY += 30 * sc;
    }

    // ─── Koordinat baris tambahan ───
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final String coord =
          '${p.lat!.abs().toStringAsFixed(6)}°${p.lat! < 0 ? 'S' : 'N'}, '
          '${p.lon!.abs().toStringAsFixed(6)}°${p.lon! < 0 ? 'W' : 'E'}';
      _tp(coord, 15 * sc, addrY, Colors.white54, x: padL).paint(c);
      addrY += 24 * sc;
    }

    if (p.showWeather && p.weather.isNotEmpty) {
      _tp(p.weather, 15 * sc, addrY, const Color(0xFF80CBC4), x: padL).paint(c);
    }

    // ─── Footer: shield + kode foto ───
    final double footerY = H - 42 * sc;
    c.drawRect(Rect.fromLTWH(0, footerY, W, 1 * sc),
        Paint()..color = Colors.white24);
    _tp('🛡 Kode Foto: ', 13 * sc, footerY + 8 * sc, Colors.white54, x: padL).paint(c);
    _tp(verCode, 13 * sc, footerY + 8 * sc, Colors.white,
        bold: true, x: padL + 130 * sc).paint(c);
  }

  // ═══════════════════════════════════════════════════════════════
  // LAYOUT 3 — Timemark Clean
  // Branding pojok kanan atas, jam besar + bar vertikal + alamat bawah
  // Style bersih transparan di bawah foto
  // ═══════════════════════════════════════════════════════════════
  static void _drawTimemarkClean(Canvas c, double W, double H, double sc, WatermarkParams p) {
    final double panelH = _cleanPanelHeight(sc, p);
    final double panelY = H - panelH;
    final double padL = 24 * sc;

    // Panel gelap bawah
    c.drawRect(Rect.fromLTWH(0, panelY, W, panelH),
        Paint()..color = Color.fromRGBO(10, 10, 20, p.opacity.clamp(0.78, 0.94)));

    // Branding pojok kanan atas foto
    _tp('Termullog', 24 * sc, 28 * sc, const Color(0xFFF5C518),
        bold: true, x: W - 210 * sc).paint(c);
    _tp('Camera', 15 * sc, 58 * sc, Colors.white70, x: W - 210 * sc).paint(c);

    // ─── Jam besar ───
    final String timeStr = DateFormat('HH:mm').format(p.timestamp);
    _tp(timeStr, 64 * sc, panelY + 14 * sc, Colors.white, bold: true, x: padL).paint(c);

    // Bar vertikal aksen
    c.drawRect(Rect.fromLTWH(padL + 160 * sc, panelY + 14 * sc, 3 * sc, 70 * sc),
        Paint()..color = const Color(0xFFF5C518));

    // Tanggal & hari
    final double dateX = padL + 175 * sc;
    _tp(DateFormat('dd MMMM yyyy').format(p.timestamp),
        18 * sc, panelY + 22 * sc, Colors.white70, x: dateX).paint(c);
    _tp(DateFormat('EEEE', 'id_ID').format(p.timestamp),
        16 * sc, panelY + 48 * sc, Colors.white54, x: dateX).paint(c);

    // Garis pemisah
    c.drawRect(Rect.fromLTWH(padL, panelY + 92 * sc, W - padL * 2, 1 * sc),
        Paint()..color = Colors.white24);

    // Alamat
    double infoY = panelY + 104 * sc;
    if (p.showAddress && p.address.isNotEmpty) {
      _tp(p.address, 16 * sc, infoY, Colors.white70,
          x: padL, maxW: W - padL * 2).paint(c);
      infoY += 26 * sc;
    }

    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final String coord =
          '${p.lat!.abs().toStringAsFixed(6)}°${p.lat! < 0 ? 'S' : 'N'}, '
          '${p.lon!.abs().toStringAsFixed(6)}°${p.lon! < 0 ? 'W' : 'E'}';
      _tp(coord, 14 * sc, infoY, Colors.white54, x: padL).paint(c);
      infoY += 22 * sc;
    }

    if (p.showWeather && p.weather.isNotEmpty) {
      _tp(p.weather, 14 * sc, infoY, const Color(0xFF80CBC4), x: padL).paint(c);
    }

    // Kode verifikasi footer
    final String verCode = _verCode(p);
    final double footerY = H - 38 * sc;
    c.drawRect(Rect.fromLTWH(0, footerY, W, 1 * sc),
        Paint()..color = Colors.white12);
    _tp('🛡 Kode Foto: $verCode', 12 * sc, footerY + 8 * sc, Colors.white38, x: padL).paint(c);

    if (p.showBorder) {
      c.drawRect(Rect.fromLTWH(0, panelY, W, 3 * sc),
          Paint()..color = const Color(0xFFF5C518));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // DYNAMIC PANEL HEIGHT CALCULATORS
  // Mirrors preview logic so final image never has empty whitespace.
  // ═══════════════════════════════════════════════════════════════

  /// Layout 1 — Timemark Light
  /// Base structure: badge+time row (90*sc) + divider + date row (44*sc)
  /// Optional: coordinates (30*sc), address (24*sc), weather (20*sc)
  /// Footer strip always present (40*sc)
  static double _lightPanelHeight(double sc, WatermarkParams p) {
    double h = 90 * sc; // header block (badge + jam)
    h += 44 * sc;       // divider + tanggal
    if (p.showCoordinates && p.lat != null && p.lon != null) h += 30 * sc;
    if (p.showAddress && p.address.isNotEmpty) h += 24 * sc;
    if (p.showWeather && p.weather.isNotEmpty) h += 20 * sc;
    h += 40 * sc; // footer strip
    return h.clamp(140 * sc, 220 * sc);
  }

  /// Layout 2 — Timemark Dark
  /// Base structure: jam+tanggal block (126*sc = 18+108)
  /// Optional: address (30*sc), coordinates (24*sc), weather (20*sc)
  /// Footer strip always present (42*sc)
  static double _darkPanelHeight(double sc, WatermarkParams p) {
    double h = 126 * sc; // jam besar + tanggal/hari block
    if (p.showAddress && p.address.isNotEmpty) h += 30 * sc;
    if (p.showCoordinates && p.lat != null && p.lon != null) h += 24 * sc;
    if (p.showWeather && p.weather.isNotEmpty) h += 20 * sc;
    h += 42 * sc; // footer strip
    return h.clamp(160 * sc, 260 * sc);
  }

  /// Layout 3 — Timemark Clean
  /// Base structure: jam+tanggal block (92*sc) + divider (12*sc)
  /// Optional: address (26*sc), coordinates (22*sc), weather (20*sc)
  /// Footer strip always present (38*sc)
  static double _cleanPanelHeight(double sc, WatermarkParams p) {
    double h = 92 * sc; // jam besar + tanggal/hari
    h += 12 * sc;       // garis pemisah + padding atas info
    if (p.showAddress && p.address.isNotEmpty) h += 26 * sc;
    if (p.showCoordinates && p.lat != null && p.lon != null) h += 22 * sc;
    if (p.showWeather && p.weather.isNotEmpty) h += 20 * sc;
    h += 38 * sc; // footer strip
    return h.clamp(120 * sc, 200 * sc);
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════

  static void _drawVerticalText(
      Canvas c, String text, double size, double x, double topY, Color color, double sc) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(color: color, fontSize: size, letterSpacing: 1.2)),
      textDirection: ui.TextDirection.ltr,
    );
    tp.layout();
    c.save();
    c.translate(x, topY + tp.width);
    c.rotate(-3.14159 / 2);
    tp.paint(c, Offset.zero);
    c.restore();
  }

  static _TPH _tp(
    String text,
    double size,
    double y,
    Color color, {
    bool bold = false,
    double letterSpacing = 0,
    double x = 16,
    double? maxW,
    bool centerX = false,
  }) =>
      _TPH(text, size, y, color,
          bold: bold, letterSpacing: letterSpacing, x: x, maxW: maxW, centerX: centerX);

  static String _verCode(WatermarkParams p) {
    int h = 0x811C9DC5;
    for (final ch in '${p.timestamp.millisecondsSinceEpoch}${p.lat}${p.lon}'.codeUnits) {
      h ^= ch;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(36).toUpperCase().padLeft(12, '0').substring(0, 12);
  }
}

class _TPH {
  final String text;
  final double size, y, x;
  final Color color;
  final bool bold;
  final double letterSpacing;
  final double? maxW;
  final bool centerX;

  _TPH(this.text, this.size, this.y, this.color,
      {this.bold = false, this.letterSpacing = 0, this.x = 16,
       this.maxW, this.centerX = false});

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
      maxLines: 2,
      ellipsis: '…',
    );
    tp.layout(maxWidth: maxW ?? 9999);
    final double paintX = centerX ? x - tp.width / 2 : x;
    tp.paint(c, Offset(paintX, y));
  }
}
