// lib/watermark/watermark_engine.dart
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
      final double sc = (W / 1080.0).clamp(0.8, 2.5);
      final double fontScale = params.fontScale.clamp(0.5, 2.0);

      final uiImage = await _decodeUiImage(params.imageBytes);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, W.toDouble(), H.toDouble()));
      canvas.drawImage(uiImage, Offset.zero, Paint());

      final layout = WatermarkLayout.values[params.layoutIndex];
      switch (layout) {
        case WatermarkLayout.podCorporate:
          _drawTimemarkLight(canvas, W.toDouble(), H.toDouble(), sc, fontScale, params);
          break;
        case WatermarkLayout.podDarkField:
          _drawTimemarkDark(canvas, W.toDouble(), H.toDouble(), sc, fontScale, params);
          break;
        case WatermarkLayout.podGovern:
          _drawTimemarkClean(canvas, W.toDouble(), H.toDouble(), sc, fontScale, params);
          break;
      }

      final picture = recorder.endRecording();
      final uiOut = await picture.toImage(W, H);
      final byteData = await uiOut.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) throw Exception('Failed to get raw RGBA');
      final imgOut = img.Image.fromBytes(
        width: W,
        height: H,
        bytes: byteData.buffer,
        numChannels: 4,
      );
      return Uint8List.fromList(img.encodeJpg(imgOut, quality: params.imageQuality));
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

  // ========== LAYOUT 1 – LIGHT ==========
  static void _drawTimemarkLight(Canvas c, double W, double H, double sc, double fontScale, WatermarkParams p) {
    final double panelH = _lightPanelHeight(sc, p);
    final double panelY = H - panelH;
    final double padL = 16 * sc;

    c.drawRect(Rect.fromLTWH(0, panelY, W, panelH),
        Paint()..color = Colors.white.withOpacity(p.opacity.clamp(0.88, 1.0)));
    c.drawRect(Rect.fromLTWH(0, panelY, 8 * sc, 90 * sc), Paint()..color = const Color(0xFFF5C518));

    final double row1Y = panelY + 12 * sc;
    final double badgeW = 160 * sc;
    final double badgeH = 60 * sc;
    final rrectBadge = RRect.fromRectAndRadius(
        Rect.fromLTWH(16 * sc, row1Y, badgeW, badgeH), Radius.circular(12 * sc));
    c.drawRRect(rrectBadge, Paint()..color = const Color(0xFFF5C518));
    _tp(p.appName.isNotEmpty ? p.appName : 'termullog',
        22 * sc * fontScale, row1Y + 14 * sc, const Color(0xFF1A1A1A),
        bold: true, x: 16 * sc + badgeW / 2, centerX: true, maxW: badgeW - 16 * sc).paint(c);
    final String timeStr = DateFormat(p.timeFormat).format(p.timestamp);
    _tp(timeStr, 58 * sc * fontScale, row1Y + 2 * sc, const Color(0xFF1565C0),
        bold: true, x: 16 * sc + badgeW + 20 * sc).paint(c);
    final double brandX = W - 200 * sc;
    _tp('Termullog', 26 * sc * fontScale, row1Y + 8 * sc, const Color(0xFFF5C518),
        bold: true, x: brandX).paint(c);
    _tp('Camera', 16 * sc * fontScale, row1Y + 38 * sc, const Color(0xFF222222), x: brandX).paint(c);

    final double row2Y = panelY + 90 * sc;
    c.drawRect(Rect.fromLTWH(0, row2Y, W, 1.5 * sc), Paint()..color = const Color(0xFFE0E0E0));
    final String dateStr = DateFormat(p.dateFormat, 'id_ID').format(p.timestamp);
    _tp(dateStr, 20 * sc * fontScale, row2Y + 10 * sc, const Color(0xFF222222), bold: true, x: padL).paint(c);

    double row3Y = row2Y + 44 * sc;
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final String coord = '${p.lat!.abs().toStringAsFixed(6)}°${p.lat! < 0 ? 'S' : 'N'}, '
          '${p.lon!.abs().toStringAsFixed(6)}°${p.lon! < 0 ? 'W' : 'E'}';
      _tp(coord, 18 * sc * fontScale, row3Y, const Color(0xFF444444), x: padL).paint(c);
      row3Y += 30 * sc;
      if (p.showAccuracy && p.acc != null) {
        _tp('±${p.acc!.toStringAsFixed(1)} m', 14 * sc * fontScale, row3Y, const Color(0xFF888888), x: padL).paint(c);
        row3Y += 24 * sc;
      }
    }
    if (p.showAddress && p.address.isNotEmpty) {
      _tp(p.address, 15 * sc * fontScale, row3Y, const Color(0xFF666666),
          x: padL, maxW: W - padL * 2 - 80 * sc, maxLines: 3).paint(c);
      row3Y += 24 * sc;
    }
    if (p.showWeather && p.weather.isNotEmpty) {
      _tp(p.weather, 14 * sc * fontScale, row3Y, const Color(0xFF006064), x: padL).paint(c);
    }

    final double footerY = H - 40 * sc;
    c.drawRect(Rect.fromLTWH(0, footerY, W, 1 * sc), Paint()..color = const Color(0xFFE0E0E0));
    _tp('🛡 Termullog menjamin keaslian waktu', 13 * sc * fontScale, footerY + 6 * sc,
        const Color(0xFF888888), x: padL).paint(c);

    final String verCode = _verCode(p);
    final double verTopLight = (H - panelH / 2).clamp(40 * sc, H - 40 * sc);
    _drawVerticalText(c, '© $verCode  Termullog Verified', 13 * sc * fontScale,
        W - 22 * sc, verTopLight, const Color(0xFF888888), sc);
    if (p.showBorder) {
      c.drawRect(Rect.fromLTWH(0, panelY, W, 4 * sc), Paint()..color = const Color(0xFFF5C518));
    }
  }

  // ========== LAYOUT 2 – DARK ==========
  static void _drawTimemarkDark(Canvas c, double W, double H, double sc, double fontScale, WatermarkParams p) {
    final double panelH = _darkPanelHeight(sc, p);
    final double panelY = H - panelH;
    final double padL = 30 * sc;
    c.drawRect(Rect.fromLTWH(0, panelY, W, panelH),
        Paint()..color = Color.fromRGBO(18, 18, 18, p.opacity.clamp(0.82, 0.96)));
    c.drawRect(Rect.fromLTWH(0, panelY, W, 3 * sc), Paint()..color = const Color(0xFFF5C518));

    final double brandY1 = (panelY - 100 * sc).clamp(16 * sc, panelY - 36 * sc);
    final double brandY2 = (panelY - 64 * sc).clamp(brandY1 + 30 * sc, panelY - 8 * sc);
    _tp('Termullog', 26 * sc * fontScale, brandY1, const Color(0xFFF5C518), bold: true, x: W - 220 * sc).paint(c);
    _tp('Foto 100% akurat', 16 * sc * fontScale, brandY2, Colors.white, x: W - 220 * sc).paint(c);

    final String verCode = _verCode(p);
    final double verTopDark = (panelY - panelH * 0.3).clamp(40 * sc, H - 40 * sc);
    _drawVerticalText(c, '© $verCode  Termullog Verified', 13 * sc * fontScale,
        W - 22 * sc, verTopDark, const Color(0xFFAAAAAA), sc);

    final String timeStr = DateFormat(p.timeFormat).format(p.timestamp);
    _tp(timeStr, 72 * sc * fontScale, panelY + 18 * sc, Colors.white, bold: true, x: padL).paint(c);
    final double sepX = padL + 180 * sc;
    c.drawLine(Offset(sepX, panelY + 20 * sc), Offset(sepX, panelY + 110 * sc),
        Paint()..color = Colors.white54..strokeWidth = 2 * sc);
    final double dateX = sepX + 20 * sc;
    final String dateNum = DateFormat(p.dateFormat).format(p.timestamp);
    final String dayName = DateFormat('EEEE', 'id_ID').format(p.timestamp);
    _tp(dateNum, 22 * sc * fontScale, panelY + 28 * sc, Colors.white, x: dateX).paint(c);
    _tp(dayName, 20 * sc * fontScale, panelY + 56 * sc, Colors.white70, x: dateX).paint(c);

    double addrY = panelY + 126 * sc;
    if (p.showAddress && p.address.isNotEmpty) {
      _tp(p.address, 18 * sc * fontScale, addrY, Colors.white,
          x: padL, maxW: W - padL * 2, maxLines: 3).paint(c);
      addrY += 30 * sc;
    }
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final String coord = '${p.lat!.abs().toStringAsFixed(6)}°${p.lat! < 0 ? 'S' : 'N'}, '
          '${p.lon!.abs().toStringAsFixed(6)}°${p.lon! < 0 ? 'W' : 'E'}';
      _tp(coord, 15 * sc * fontScale, addrY, Colors.white54, x: padL).paint(c);
      addrY += 24 * sc;
      if (p.showAccuracy && p.acc != null) {
        _tp('±${p.acc!.toStringAsFixed(1)} m', 13 * sc * fontScale, addrY, Colors.white38, x: padL).paint(c);
        addrY += 20 * sc;
      }
    }
    if (p.showWeather && p.weather.isNotEmpty) {
      _tp(p.weather, 15 * sc * fontScale, addrY, const Color(0xFF80CBC4), x: padL).paint(c);
    }

    final double footerY = H - 42 * sc;
    c.drawRect(Rect.fromLTWH(0, footerY, W, 1 * sc), Paint()..color = Colors.white24);
    _tp('🛡 Kode Foto: ', 13 * sc * fontScale, footerY + 8 * sc, Colors.white54, x: padL).paint(c);
    _tp(verCode, 13 * sc * fontScale, footerY + 8 * sc, Colors.white, bold: true, x: padL + 130 * sc).paint(c);
  }

  // ========== LAYOUT 3 – CLEAN ==========
  static void _drawTimemarkClean(Canvas c, double W, double H, double sc, double fontScale, WatermarkParams p) {
    final double panelH = _cleanPanelHeight(sc, p);
    final double panelY = H - panelH;
    final double padL = 24 * sc;
    c.drawRect(Rect.fromLTWH(0, panelY, W, panelH),
        Paint()..color = Color.fromRGBO(10, 10, 20, p.opacity.clamp(0.78, 0.94)));
    _tp('Termullog', 24 * sc * fontScale, 28 * sc, const Color(0xFFF5C518), bold: true, x: W - 210 * sc).paint(c);
    _tp('Camera', 15 * sc * fontScale, 58 * sc, Colors.white70, x: W - 210 * sc).paint(c);
    final String timeStr = DateFormat(p.timeFormat).format(p.timestamp);
    _tp(timeStr, 64 * sc * fontScale, panelY + 14 * sc, Colors.white, bold: true, x: padL).paint(c);
    c.drawRect(Rect.fromLTWH(padL + 160 * sc, panelY + 14 * sc, 3 * sc, 70 * sc),
        Paint()..color = const Color(0xFFF5C518));
    final double dateX = padL + 175 * sc;
    _tp(DateFormat(p.dateFormat).format(p.timestamp), 18 * sc * fontScale, panelY + 22 * sc, Colors.white70, x: dateX).paint(c);
    _tp(DateFormat('EEEE', 'id_ID').format(p.timestamp), 16 * sc * fontScale, panelY + 48 * sc, Colors.white54, x: dateX).paint(c);
    c.drawRect(Rect.fromLTWH(padL, panelY + 92 * sc, W - padL * 2, 1 * sc), Paint()..color = Colors.white24);
    double infoY = panelY + 104 * sc;
    if (p.showAddress && p.address.isNotEmpty) {
      _tp(p.address, 16 * sc * fontScale, infoY, Colors.white70,
          x: padL, maxW: W - padL * 2, maxLines: 3).paint(c);
      infoY += 26 * sc;
    }
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final String coord = '${p.lat!.abs().toStringAsFixed(6)}°${p.lat! < 0 ? 'S' : 'N'}, '
          '${p.lon!.abs().toStringAsFixed(6)}°${p.lon! < 0 ? 'W' : 'E'}';
      _tp(coord, 14 * sc * fontScale, infoY, Colors.white54, x: padL).paint(c);
      infoY += 22 * sc;
      if (p.showAccuracy && p.acc != null) {
        _tp('±${p.acc!.toStringAsFixed(1)} m', 12 * sc * fontScale, infoY, Colors.white38, x: padL).paint(c);
        infoY += 18 * sc;
      }
    }
    if (p.showWeather && p.weather.isNotEmpty) {
      _tp(p.weather, 14 * sc * fontScale, infoY, const Color(0xFF80CBC4), x: padL).paint(c);
    }
    final String verCode = _verCode(p);
    final double footerY = H - 38 * sc;
    c.drawRect(Rect.fromLTWH(0, footerY, W, 1 * sc), Paint()..color = Colors.white12);
    _tp('🛡 Kode Foto: $verCode', 12 * sc * fontScale, footerY + 8 * sc, Colors.white38, x: padL).paint(c);
    if (p.showBorder) {
      c.drawRect(Rect.fromLTWH(0, panelY, W, 3 * sc), Paint()..color = const Color(0xFFF5C518));
    }
  }

  // ========== PANEL HEIGHT CALCULATORS ==========
  static double _lightPanelHeight(double sc, WatermarkParams p) {
    double h = 90 * sc + 44 * sc;
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      h += 30 * sc;
      if (p.showAccuracy && p.acc != null) h += 24 * sc;
    }
    if (p.showAddress && p.address.isNotEmpty) h += 24 * sc;
    if (p.showWeather && p.weather.isNotEmpty) h += 20 * sc;
    h += 40 * sc;
    return h.clamp(140 * sc, 220 * sc);
  }
  static double _darkPanelHeight(double sc, WatermarkParams p) {
    double h = 126 * sc;
    if (p.showAddress && p.address.isNotEmpty) h += 30 * sc;
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      h += 24 * sc;
      if (p.showAccuracy && p.acc != null) h += 20 * sc;
    }
    if (p.showWeather && p.weather.isNotEmpty) h += 20 * sc;
    h += 42 * sc;
    return h.clamp(160 * sc, 260 * sc);
  }
  static double _cleanPanelHeight(double sc, WatermarkParams p) {
    double h = 92 * sc + 12 * sc;
    if (p.showAddress && p.address.isNotEmpty) h += 26 * sc;
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      h += 22 * sc;
      if (p.showAccuracy && p.acc != null) h += 18 * sc;
    }
    if (p.showWeather && p.weather.isNotEmpty) h += 20 * sc;
    h += 38 * sc;
    return h.clamp(120 * sc, 200 * sc);
  }

  // ========== HELPERS ==========
  static void _drawVerticalText(Canvas c, String text, double size, double x, double topY, Color color, double sc) {
    final tp = TextPainter(text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, letterSpacing: 1.2)), textDirection: ui.TextDirection.ltr);
    tp.layout();
    c.save();
    c.translate(x, topY + tp.width);
    c.rotate(-3.14159 / 2);
    tp.paint(c, Offset.zero);
    c.restore();
  }
  static _TPH _tp(String text, double size, double y, Color color,
      {bool bold = false, double letterSpacing = 0, double x = 16, double? maxW, bool centerX = false, int maxLines = 2}) =>
      _TPH(text, size, y, color, bold: bold, letterSpacing: letterSpacing, x: x, maxW: maxW, centerX: centerX, maxLines: maxLines);
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
  final String text; final double size, y, x; final Color color; final bool bold; final double letterSpacing; final double? maxW; final bool centerX; final int maxLines;
  _TPH(this.text, this.size, this.y, this.color, {this.bold = false, this.letterSpacing = 0, this.x = 16, this.maxW, this.centerX = false, this.maxLines = 2});
  void paint(Canvas c) {
    final tp = TextPainter(text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, letterSpacing: letterSpacing)), textDirection: ui.TextDirection.ltr, maxLines: maxLines, ellipsis: '…');
    tp.layout(maxWidth: maxW ?? 9999);
    final double paintX = centerX ? x - tp.width / 2 : x;
    tp.paint(c, Offset(paintX, y));
  }
}
