// lib/watermark/watermark_engine.dart
import 'dart:async';
import 'dart:math';
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
      
      // Preload custom badge and logo images (if any)
      ui.Image? customBadgeImage;
      if (params.badgeType == 'custom' && params.customBadgeBytes != null) {
        customBadgeImage = await _bytesToUiImage(params.customBadgeBytes!);
      }
      ui.Image? customLogoImage;
      if (params.logoType == 'custom' && params.customLogoBytes != null) {
        customLogoImage = await _bytesToUiImage(params.customLogoBytes!);
      }

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, W.toDouble(), H.toDouble()));
      canvas.drawImage(uiImage, Offset.zero, Paint());

      _drawReferenceLayout(
        canvas, W, H, sc, fontScale, params,
        customBadgeImage: customBadgeImage,
        customLogoImage: customLogoImage,
      );

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

  /// Convert bytes to ui.Image, returns null on timeout or error
  static Future<ui.Image?> _bytesToUiImage(Uint8List bytes) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    try {
      return await completer.future.timeout(const Duration(seconds: 2));
    } catch (e) {
      return null;
    }
  }

  static void _drawReferenceLayout(
    Canvas c,
    double W, double H, double sc, double fontScale, WatermarkParams p, {
    ui.Image? customBadgeImage,
    ui.Image? customLogoImage,
  }) {
    final double panelH = _calculatePanelHeight(sc, fontScale, p);
    final double panelX = 20 * sc;
    final double targetY = H - panelH - 120 * sc;
    final double panelY = targetY.clamp(20 * sc, H - panelH - 20 * sc);
    final double panelW = 560 * sc;

    final RRect panelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(panelX, panelY, panelW, panelH),
      Radius.circular(12 * sc),
    );
    c.drawRRect(panelRect, Paint()..color = Colors.white.withOpacity(p.opacity.clamp(0.7, 1.0)));

    if (p.showBorder) {
      c.drawRRect(panelRect, Paint()
        ..color = Colors.orange
        ..strokeWidth = 2 * sc
        ..style = PaintingStyle.stroke);
    }

    double currentX = panelX + 16 * sc;
    double currentY = panelY + 16 * sc;

    // --- BADGE ---
    final String appName = p.appName.isNotEmpty ? p.appName : 'termullog';
    final double badgeFontSize = 32 * sc * fontScale;
    double badgeW;
    final double badgeH = 80 * sc;

    if (p.badgeType == 'custom' && customBadgeImage != null) {
      badgeW = 150 * sc;
      final Rect badgeRect = Rect.fromLTWH(currentX, currentY, badgeW, badgeH);
      c.drawImageRect(
        customBadgeImage,
        Rect.fromLTWH(0, 0, customBadgeImage.width.toDouble(), customBadgeImage.height.toDouble()),
        badgeRect,
        Paint(),
      );
    } else {
      final namePainter = TextPainter(
        text: TextSpan(text: appName, style: TextStyle(fontSize: badgeFontSize, fontWeight: FontWeight.w700)),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final double badgePadding = 24 * sc;
      badgeW = (namePainter.width + badgePadding).clamp(120 * sc, 300 * sc);
      final RRect badgeRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(currentX, currentY, badgeW, badgeH),
        Radius.circular(8 * sc),
      );
      c.drawRRect(badgeRRect, Paint()..color = const Color(0xFFFFC107));
      _tp(appName, badgeFontSize, currentY + 18 * sc, Colors.black87,
          bold: true, x: currentX + badgeW / 2, centerX: true, maxW: badgeW - 8 * sc).paint(c);
    }

    // --- JAM ---
    final String timeStr = DateFormat(p.timeFormat.isNotEmpty ? p.timeFormat : 'HH:mm').format(p.timestamp);
    final double timeX = currentX + badgeW + 16 * sc;
    _tp(timeStr, 80 * sc * fontScale, currentY - 4 * sc, const Color(0xFF1A237E),
        bold: true, x: timeX).paint(c);

    // --- LOGO ---
    if (p.showLogo) {
      final timePainter = TextPainter(
        text: TextSpan(text: timeStr, style: TextStyle(fontSize: 80 * sc * fontScale, fontWeight: FontWeight.w700)),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      double logoX = timeX + timePainter.width + 20 * sc;
      final double safeLogoX = logoX.clamp(timeX, panelX + panelW - 156 * sc);
      _drawSelectedLogo(c, safeLogoX, currentY + 15 * sc, sc, p, customLogoImage);
    }

    currentY += 100 * sc;

    // Divider
    c.drawLine(Offset(currentX, currentY), Offset(panelX + panelW - 16 * sc, currentY),
        Paint()..color = Colors.grey.withOpacity(0.3)..strokeWidth = 2 * sc);
    currentY += 25 * sc;

    // Tanggal
    final String dateStr = DateFormat(p.dateFormat.isNotEmpty ? p.dateFormat : 'EEEE, d MMMM yyyy', 'id_ID').format(p.timestamp);
    _tp(dateStr, 28 * sc * fontScale, currentY, Colors.black87, bold: true, x: currentX).paint(c);
    currentY += 50 * sc;

    // Koordinat
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final String latDir = p.lat! >= 0 ? 'N' : 'S';
      final String lonDir = p.lon! >= 0 ? 'E' : 'W';
      final String coord = '${p.lat!.abs().toStringAsFixed(6)}°$latDir, ${p.lon!.abs().toStringAsFixed(6)}°$lonDir';
      _tp(coord, 24 * sc * fontScale, currentY, Colors.grey[700]!, x: currentX).paint(c);
      currentY += 45 * sc;
    }

    // Akurasi
    if (p.showAccuracy && p.acc != null) {
      _tp('Accuracy: ±${p.acc!.toStringAsFixed(1)} m', 20 * sc * fontScale, currentY, Colors.grey[600]!, x: currentX).paint(c);
      currentY += 40 * sc;
    }

    // Alamat
    if (p.showAddress && p.address.isNotEmpty) {
      _tp(p.address, 20 * sc * fontScale, currentY, Colors.grey[700]!, x: currentX, maxW: panelW - 32 * sc, maxLines: 3).paint(c);
      final tp = TextPainter(
        text: TextSpan(text: p.address, style: TextStyle(fontSize: 20 * sc * fontScale)),
        textDirection: ui.TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: panelW - 32 * sc);
      currentY += tp.height + 15 * sc;
    }

    // Cuaca
    if (p.showWeather && p.weather.isNotEmpty) {
      _tp(p.weather, 20 * sc * fontScale, currentY, const Color(0xFF00796B), x: currentX).paint(c);
      currentY += 35 * sc;
    }

    // Footer
    _tp('🛡 Timemark menjamin keaslian waktu', 20 * sc * fontScale, currentY,
        Colors.grey[600]!, x: currentX).paint(c);

    // Kode verifikasi vertikal
    final String verCode = _verCode(p);
    final double verCenterY = panelY + panelH / 2;
    _drawVerticalText(c, '© $verCode Timemark Verified', 18 * sc * fontScale,
        W - 45 * sc, verCenterY, Colors.white.withOpacity(0.8), sc);

    // Branding bawah kanan
    _tp('Timemark', 28 * sc * fontScale, H - 100 * sc, Colors.white, x: W - 240 * sc, bold: true).paint(c);
    _tp('Camera', 22 * sc * fontScale, H - 65 * sc, Colors.white70, x: W - 240 * sc).paint(c);
  }

  static void _drawSelectedLogo(Canvas c, double x, double y, double sc, WatermarkParams p, ui.Image? customLogoImage) {
    if (p.logoType == 'custom' && customLogoImage != null) {
      final double logoW = 140 * sc;
      final double logoH = 60 * sc;
      final Rect dstRect = Rect.fromLTWH(x, y, logoW, logoH);
      c.drawImageRect(
        customLogoImage,
        Rect.fromLTWH(0, 0, customLogoImage.width.toDouble(), customLogoImage.height.toDouble()),
        dstRect,
        Paint(),
      );
    } else if (p.logoType == 'timemark_icon') {
      _drawTimemarkIcon(c, x + 40 * sc, y + 30 * sc, 30 * sc);
    } else {
      // default: next_van
      _drawMiniLogo(c, x, y, sc);
    }
  }

  static void _drawMiniLogo(Canvas c, double x, double y, double sc) {
    final Paint p = Paint()..color = Colors.white;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, 140 * sc, 60 * sc), Radius.circular(8 * sc)), p);
    final Paint vanPaint = Paint()..color = Colors.orange;
    c.drawRect(Rect.fromLTWH(x + 10 * sc, y + 20 * sc, 30 * sc, 20 * sc), vanPaint);
    _tp('NEXT', 14 * sc, y + 25 * sc, Colors.black, bold: true, x: x + 50 * sc).paint(c);
  }

  static void _drawTimemarkIcon(Canvas c, double cx, double cy, double radius) {
    final Paint p = Paint()..color = const Color(0xFFFFC107)..style = PaintingStyle.fill;
    c.drawCircle(Offset(cx, cy), radius, p);
    final Paint checkPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = radius * 0.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(cx - radius * 0.4, cy)
      ..lineTo(cx - radius * 0.1, cy + radius * 0.3)
      ..lineTo(cx + radius * 0.5, cy - radius * 0.3);
    c.drawPath(path, checkPaint);
  }

  static double _calculatePanelHeight(double sc, double fontScale, WatermarkParams p) {
    double h = 16 * sc + 100 * sc + 25 * sc + 50 * sc;
    if (p.showCoordinates && p.lat != null) h += 45 * sc;
    if (p.showAccuracy && p.acc != null) h += 40 * sc;
    if (p.showAddress && p.address.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(text: p.address, style: TextStyle(fontSize: 20 * sc * fontScale)),
        textDirection: ui.TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: (560 - 32) * sc);
      h += tp.height + 15 * sc;
    }
    if (p.showWeather && p.weather.isNotEmpty) h += 35 * sc;
    h += 45 * sc + 16 * sc;
    return h;
  }

  static void _drawVerticalText(Canvas c, String text, double size, double x, double centerY, Color color, double sc) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, letterSpacing: 1.2, fontWeight: FontWeight.w500)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    c.save();
    c.translate(x, centerY + tp.width / 2);
    c.rotate(-pi / 2);
    tp.paint(c, Offset.zero);
    c.restore();
  }

  static _TPH _tp(String text, double size, double y, Color color,
      {bool bold = false, double letterSpacing = 0, double x = 16, double? maxW, bool centerX = false, int maxLines = 2}) {
    return _TPH(text, size, y, color, bold: bold, letterSpacing: letterSpacing, x: x, maxW: maxW, centerX: centerX, maxLines: maxLines);
  }

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
  final int maxLines;

  _TPH(this.text, this.size, this.y, this.color,
      {this.bold = false, this.letterSpacing = 0, this.x = 16, this.maxW, this.centerX = false, this.maxLines = 2});

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
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: maxW ?? 9999);
    final double paintX = centerX ? x - tp.width / 2 : x;
    tp.paint(c, Offset(paintX, y));
  }
}
