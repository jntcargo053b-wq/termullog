// lib/watermark/watermark_engine.dart
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_params.dart';

class WatermarkEngine {
  /// Final high-quality process for photos (JPEG output)
  static Future<Uint8List> process(WatermarkParams params) async {
    try {
      final originalImg = img.decodeImage(params.imageBytes);
      if (originalImg == null) throw Exception('Failed to decode image');
      final W = originalImg.width;
      final H = originalImg.height;
      final double sc = (W / 1080.0).clamp(0.8, 2.5);
      final double fontScale = params.fontScale.clamp(0.5, 2.0);
      final uiImage = await _decodeUiImage(params.imageBytes);
      
      ui.Image? customLogo;
      if (params.customLogoBytes != null) {
        customLogo = await _decodeUiImage(params.customLogoBytes!);
      }
      ui.Image? customBadge;
      if (params.customBadgeBytes != null) {
        customBadge = await _decodeUiImage(params.customBadgeBytes!);
      }

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, W.toDouble(), H.toDouble()));
      canvas.drawImage(uiImage, Offset.zero, Paint());

      _drawReferenceLayout(canvas, W.toDouble(), H.toDouble(), sc, fontScale, params, customLogo, customBadge);

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

  /// Proportional preview (for live camera view or editor)
  static Future<ui.Image> preview(WatermarkParams params, {double? width, double? height}) async {
    try {
      final uiImage = await _decodeUiImage(params.imageBytes);
      final originalW = uiImage.width.toDouble();
      final originalH = uiImage.height.toDouble();
      
      final canvasW = width ?? originalW;
      final canvasH = height ?? originalH;
      
      // Calculate 'contain' scale and offsets
      final scale = min(canvasW / originalW, canvasH / originalH);
      final offsetX = (canvasW - originalW * scale) / 2;
      final offsetY = (canvasH - originalH * scale) / 2;
      
      final double sc = (originalW / 1080.0).clamp(0.8, 2.5);
      final double fontScale = params.fontScale.clamp(0.5, 2.0);
      
      ui.Image? customLogo;
      if (params.customLogoBytes != null) {
        customLogo = await _decodeUiImage(params.customLogoBytes!);
      }
      ui.Image? customBadge;
      if (params.customBadgeBytes != null) {
        customBadge = await _decodeUiImage(params.customBadgeBytes!);
      }
      
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, canvasW, canvasH));
      
      // Draw background with transformation
      canvas.save();
      canvas.translate(offsetX, offsetY);
      canvas.scale(scale, scale);
      canvas.drawImage(uiImage, Offset.zero, Paint());
      canvas.restore();
      
      // Draw watermark with same transformation to maintain proportions
      canvas.save();
      canvas.translate(offsetX, offsetY);
      canvas.scale(scale, scale);
      _drawReferenceLayout(canvas, originalW, originalH, sc, fontScale, params, customLogo, customBadge);
      canvas.restore();
      
      final picture = recorder.endRecording();
      return await picture.toImage(canvasW.toInt(), canvasH.toInt());
    } catch (e) {
      debugPrint('WatermarkEngine.preview error: $e');
      rethrow;
    }
  }

  static Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    return completer.future.timeout(const Duration(seconds: 10),
        onTimeout: () => throw Exception('Image decode timeout'));
  }

  /// Main layout (synchronous rendering logic)
  static void _drawReferenceLayout(
    Canvas c, double W, double H, double sc, double fontScale,
    WatermarkParams p, ui.Image? customLogo, ui.Image? customBadge
  ) {
    final double innerPadding = 24 * sc;
    final double headerSpacing = 24 * sc;

    // Calculate Badge Width
    final String appName = p.appName.isNotEmpty ? p.appName : 'termullog';
    final double badgeFontSize = 32 * sc * fontScale;
    final namePainter = TextPainter(
      text: TextSpan(text: appName, style: TextStyle(fontSize: badgeFontSize, fontWeight: FontWeight.w700)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final double badgePadding = 32 * sc;
    final double badgeW = (namePainter.width + badgePadding).clamp(140 * sc, 350 * sc);
    final double badgeH = 85 * sc;

    // Calculate Time Width
    final String timeStr = DateFormat(p.timeFormat.isNotEmpty ? p.timeFormat : 'HH:mm').format(p.timestamp);
    final double timeFontSize = 85 * sc * fontScale;
    final timePainter = TextPainter(
      text: TextSpan(text: timeStr, style: TextStyle(fontSize: timeFontSize, fontWeight: FontWeight.w700)),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    final double logoW = 150 * sc;
    final double logoH = 65 * sc;

    // Dynamic Panel Width
    double headerW = badgeW + headerSpacing + timePainter.width;
    if (p.showLogo) headerW += headerSpacing + logoW;
    final double panelW = (headerW + innerPadding * 2).clamp(600 * sc, W - 48 * sc);

    final double panelH = _calculatePanelHeight(sc, fontScale, p, panelW, innerPadding);
    final double panelX = 24 * sc;
    final double targetY = H - panelH - 120 * sc;
    final double panelY = targetY.clamp(24 * sc, H - panelH - 24 * sc);

    // Draw Panel Background
    final RRect panelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(panelX, panelY, panelW, panelH),
      Radius.circular(16 * sc),
    );
    c.drawRRect(panelRect, Paint()..color = Colors.white.withOpacity(p.opacity.clamp(0.4, 0.9)));

    if (p.showBorder) {
      c.drawRRect(panelRect, Paint()
        ..color = Colors.orange.withOpacity(p.opacity.clamp(0.4, 1.0))
        ..strokeWidth = 3 * sc
        ..style = PaintingStyle.stroke);
    }

    double currentX = panelX + innerPadding;
    double currentY = panelY + innerPadding;

    // --- Header Section ---
    // Badge
    if (p.badgeType == 'custom' && customBadge != null) {
      c.drawImageRect(
        customBadge,
        Rect.fromLTWH(0, 0, customBadge.width.toDouble(), customBadge.height.toDouble()),
        Rect.fromLTWH(currentX, currentY, badgeW, badgeH),
        Paint(),
      );
    } else {
      final RRect badgeRRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(currentX, currentY, badgeW, badgeH), Radius.circular(10 * sc));
      c.drawRRect(badgeRRect, Paint()..color = const Color(0xFFFFC107).withOpacity(p.opacity.clamp(0.6, 1.0)));
      _tp(appName, badgeFontSize, currentY + (badgeH - namePainter.height) / 2, Colors.black87,
          bold: true, x: currentX + badgeW / 2, centerX: true, maxW: badgeW - 12 * sc).paint(c);
    }

    // Time
    currentX += badgeW + headerSpacing;
    _tp(timeStr, timeFontSize, currentY - 4 * sc, const Color(0xFF1A237E), bold: true, x: currentX).paint(c);

    // Logo
    if (p.showLogo) {
      currentX += timePainter.width + headerSpacing;
      final double safeLogoX = currentX.clamp(panelX, panelX + panelW - logoW - innerPadding);
      _drawSelectedLogo(c, safeLogoX, currentY + 12 * sc, sc, p.logoType, customLogo, logoW, logoH, p.opacity);
    }

    currentY += 110 * sc;
    currentX = panelX + innerPadding;

    // Divider
    c.drawLine(Offset(currentX, currentY), Offset(panelX + panelW - innerPadding, currentY),
        Paint()..color = Colors.grey.withOpacity(0.2)..strokeWidth = 2 * sc);
    
    currentY += 32 * sc;

    // --- Content Section ---
    // Date
    final String dateStr = DateFormat(p.dateFormat.isNotEmpty ? p.dateFormat : 'EEEE, d MMMM yyyy', 'id_ID').format(p.timestamp);
    _tp(dateStr, 30 * sc * fontScale, currentY, Colors.black87, bold: true, x: currentX).paint(c);
    currentY += 55 * sc;

    // Coordinates
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final String latDir = p.lat! >= 0 ? 'N' : 'S';
      final String lonDir = p.lon! >= 0 ? 'E' : 'W';
      final String coord = '${p.lat!.abs().toStringAsFixed(6)}°$latDir, ${p.lon!.abs().toStringAsFixed(6)}°$lonDir';
      _tp(coord, 26 * sc * fontScale, currentY, Colors.grey[700]!, x: currentX).paint(c);
      currentY += 50 * sc;
    }

    // Accuracy
    if (p.showAccuracy && p.acc != null) {
      _tp('Accuracy: ±${p.acc!.toStringAsFixed(1)} m', 22 * sc * fontScale, currentY, Colors.grey[600]!, x: currentX).paint(c);
      currentY += 45 * sc;
    }

    // Address
    if (p.showAddress && p.address.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(text: p.address, style: TextStyle(fontSize: 22 * sc * fontScale)),
        textDirection: ui.TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: panelW - (innerPadding * 2));
      _tp(p.address, 22 * sc * fontScale, currentY, Colors.grey[700]!, x: currentX,
          maxW: panelW - (innerPadding * 2), maxLines: 3).paint(c);
      currentY += tp.height + 20 * sc;
    }

    // Weather
    if (p.showWeather && p.weather.isNotEmpty) {
      _tp(p.weather, 22 * sc * fontScale, currentY, const Color(0xFF00796B), x: currentX).paint(c);
      currentY += 40 * sc;
    }

    // Footer
    _tp('🛡 Timemark menjamin keaslian waktu', 22 * sc * fontScale, currentY, Colors.grey[600]!, x: currentX).paint(c);

    // Vertical Verification Code
    final String verCode = _verCode(p);
    final double verCenterY = panelY + panelH / 2;
    _drawVerticalText(c, '© $verCode Timemark Verified', 20 * sc * fontScale,
        W - 50 * sc, verCenterY, Colors.white.withOpacity(0.8), sc);

    // Bottom Branding
    _tp('Timemark', 32 * sc * fontScale, H - 110 * sc, Colors.white, x: W - 260 * sc, bold: true).paint(c);
    _tp('Camera', 24 * sc * fontScale, H - 70 * sc, Colors.white70, x: W - 260 * sc).paint(c);
  }

  static double _calculatePanelHeight(double sc, double fontScale, WatermarkParams p, double panelW, double innerPadding) {
    double h = innerPadding + 110 * sc + 32 * sc + 55 * sc;
    if (p.showCoordinates && p.lat != null) h += 50 * sc;
    if (p.showAccuracy && p.acc != null) h += 45 * sc;
    if (p.showAddress && p.address.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(text: p.address, style: TextStyle(fontSize: 22 * sc * fontScale)),
        textDirection: ui.TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: panelW - (innerPadding * 2));
      h += tp.height + 20 * sc;
    }
    if (p.showWeather && p.weather.isNotEmpty) h += 40 * sc;
    h += 50 * sc + innerPadding;
    return h;
  }

  static void _drawSelectedLogo(Canvas c, double x, double y, double sc, String? type, ui.Image? customLogo, double w, double h, double opacity) {
    if (type == 'custom' && customLogo != null) {
      c.drawImageRect(
        customLogo,
        Rect.fromLTWH(0, 0, customLogo.width.toDouble(), customLogo.height.toDouble()),
        Rect.fromLTWH(x, y, w, h),
        Paint(),
      );
    } else if (type == 'timemark_icon') {
      _drawTimemarkIcon(c, x + 40 * sc, y + 30 * sc, 30 * sc);
    } else {
      _drawMiniLogo(c, x, y, sc, w, h, opacity);
    }
  }

  static void _drawMiniLogo(Canvas c, double x, double y, double sc, double w, double h, double opacity) {
    final Paint p = Paint()..color = Colors.white.withOpacity(opacity.clamp(0.6, 1.0));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(8 * sc)), p);
    final Paint vanPaint = Paint()..color = Colors.orange.withOpacity(opacity.clamp(0.6, 1.0));
    c.drawRect(Rect.fromLTWH(x + 10 * sc, y + 18 * sc, 35 * sc, 24 * sc), vanPaint);
    _tp('NEXT', 16 * sc, y + 22 * sc, Colors.black.withOpacity(opacity.clamp(0.6, 1.0)), bold: true, x: x + 55 * sc).paint(c);
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
    for (final ch in '${p.timestamp.millisecondsSinceEpoch}${p.lat ?? 0.0}${p.lon ?? 0.0}'.codeUnits) {
      h ^= ch;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(36).toUpperCase().padLeft(12, '0').substring(0, 12);
  }
}

class _TPH {
  final String text; final double size, y, x; final Color color; final bool bold;
  final double letterSpacing; final double? maxW; final bool centerX; final int maxLines;
  _TPH(this.text, this.size, this.y, this.color,
      {this.bold = false, this.letterSpacing = 0, this.x = 16, this.maxW, this.centerX = false, this.maxLines = 2});
  void paint(Canvas c) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, letterSpacing: letterSpacing)),
      textDirection: ui.TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: maxW ?? 9999);
    final double paintX = centerX ? x - tp.width / 2 : x;
    tp.paint(c, Offset(paintX, y));
  }
}
