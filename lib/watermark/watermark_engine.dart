// lib/watermark/watermark_engine.dart
import 'dart:async';
import 'dart:math';

import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_params.dart';


// ── Isolate support ──────────────────────────────────────────────────────────
class _EncodeParams {
  final int width;
  final int height;
  final Uint8List rgbaBytes;
  final int quality;
  const _EncodeParams(this.width, this.height, this.rgbaBytes, this.quality);
}

Uint8List _encodeJpgIsolate(_EncodeParams p) {
  final image = img.Image.fromBytes(
    width: p.width,
    height: p.height,
    bytes: p.rgbaBytes.buffer,
    numChannels: 4,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: p.quality));
}

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

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, W.toDouble(), H.toDouble()));
      canvas.drawImage(uiImage, Offset.zero, Paint());

      _drawReferenceLayout(canvas, W.toDouble(), H.toDouble(), sc, fontScale, params, customLogo);

      final picture = recorder.endRecording();
      final uiOut = await picture.toImage(W, H);
      final byteData = await uiOut.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) throw Exception('Failed to get raw RGBA');
      return await compute(
        _encodeJpgIsolate,
        _EncodeParams(W, H, byteData.buffer.asUint8List(), params.imageQuality),
      );
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
      
      final scale = min(canvasW / originalW, canvasH / originalH);
      final offsetX = (canvasW - originalW * scale) / 2;
      final offsetY = (canvasH - originalH * scale) / 2;
      
      final double sc = (originalW / 1080.0).clamp(0.8, 2.5);
      final double fontScale = params.fontScale.clamp(0.5, 2.0);
      
      ui.Image? customLogo;
      if (params.customLogoBytes != null) {
        customLogo = await _decodeUiImage(params.customLogoBytes!);
      }
      
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, canvasW, canvasH));
      
      canvas.save();
      canvas.translate(offsetX, offsetY);
      canvas.scale(scale, scale);
      canvas.drawImage(uiImage, Offset.zero, Paint());
      canvas.restore();
      
      canvas.save();
      canvas.translate(offsetX, offsetY);
      canvas.scale(scale, scale);
      _drawReferenceLayout(canvas, originalW, originalH, sc, fontScale, params, customLogo);
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

  /// Main layout with Deep Blue & Amber Branding and sync with WatermarkParams
  static void _drawReferenceLayout(
    Canvas c, double W, double H, double sc, double fontScale,
    WatermarkParams p, ui.Image? customLogo
  ) {
    // --- Branding Colors ---
    const Color brandPrimary = Color(0xFF0D47A1); // Deep Blue
    const Color brandAccent = Color(0xFFFFB300);  // Amber
    const Color textPrimary = Color(0xFF212121);
    const Color textSecondary = Color(0xFF757575);

    // --- Spacing Constants ---
    final double panelPaddingHorizontal = 32 * sc;
    final double panelPaddingVertical = 28 * sc;
    final double headerSpacing = 32 * sc;
    final double contentVerticalGap = 24 * sc;
    final double dividerPadding = 32 * sc;

    // 1. Measure Time
    final String timeStr = DateFormat(p.timeFormat.isNotEmpty ? p.timeFormat : 'HH:mm:ss').format(p.timestamp);
    final double timeFontSize = 92 * sc * fontScale;
    final timePainter = TextPainter(
      text: TextSpan(text: timeStr, style: TextStyle(fontSize: timeFontSize, fontWeight: FontWeight.w700)),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    // 2. Measure Badge
    final String appName = p.appName.isNotEmpty ? p.appName : 'termullog';
    final double badgeFontSize = 34 * sc * fontScale;
    final namePainter = TextPainter(
      text: TextSpan(text: appName, style: TextStyle(fontSize: badgeFontSize, fontWeight: FontWeight.w700)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final double badgePaddingH = 36 * sc;
    final double badgePaddingV = 16 * sc;
    final double badgeW = (namePainter.width + badgePaddingH).clamp(160 * sc, 400 * sc);
    final double badgeH = (namePainter.height + badgePaddingV).clamp(90 * sc, 110 * sc);

    final double logoW = 150 * sc;
    final double logoH = 65 * sc;

    // 3. Dynamic Panel Width
    double headerRowW = badgeW + headerSpacing + timePainter.width;
    if (p.showLogo) headerRowW += headerSpacing + logoW;
    final double panelW = (headerRowW + panelPaddingHorizontal * 2).clamp(700 * sc, W - 64 * sc);

    final double panelH = _calculatePanelHeight(sc, fontScale, p, panelW, panelPaddingVertical, contentVerticalGap, dividerPadding);
    final double panelX = 32 * sc;
    final double targetY = H - panelH - 120 * sc;
    final double panelY = targetY.clamp(32 * sc, H - panelH - 32 * sc);

    // Draw Panel Background
    final RRect panelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(panelX, panelY, panelW, panelH),
      Radius.circular(20 * sc),
    );
    c.drawRRect(panelRect, Paint()..color = Colors.white.withOpacity(p.opacity.clamp(0.4, 0.9)));

    if (p.showBorder) {
      c.drawRRect(panelRect, Paint()
        ..color = brandAccent.withOpacity(p.opacity.clamp(0.4, 1.0))
        ..strokeWidth = 3 * sc
        ..style = PaintingStyle.stroke);
    }

    double currentX = panelX + panelPaddingHorizontal;
    double currentY = panelY + panelPaddingVertical;

    // --- Header Section ---
    // A. Badge
    {
      final RRect badgeRRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(currentX, currentY, badgeW, badgeH), Radius.circular(12 * sc));
      c.drawRRect(badgeRRect, Paint()..color = brandAccent.withOpacity(p.opacity.clamp(0.6, 1.0)));
      _tp(appName, badgeFontSize, currentY + (badgeH - namePainter.height) / 2, textPrimary,
          bold: true, x: currentX + badgeW / 2, centerX: true, maxW: badgeW - 16 * sc).paint(c);
    }

    // B. Time
    currentX += badgeW + headerSpacing;
    _tp(timeStr, timeFontSize, currentY - 4 * sc, brandPrimary, bold: true, x: currentX).paint(c);

    // C. Logo
    if (p.showLogo) {
      currentX += timePainter.width + headerSpacing;
      final double safeLogoX = currentX.clamp(panelX + panelPaddingHorizontal, panelX + panelW - logoW - panelPaddingHorizontal);
      _drawSelectedLogo(c, safeLogoX, currentY + 14 * sc, sc, p.logoType, customLogo, logoW, logoH, p.opacity, brandAccent);
    }

    currentY += badgeH + contentVerticalGap;
    currentX = panelX + panelPaddingHorizontal;

    // Divider
    currentY += dividerPadding / 2;
    c.drawLine(Offset(currentX, currentY), Offset(panelX + panelW - panelPaddingHorizontal, currentY),
        Paint()..color = textSecondary.withOpacity(0.2)..strokeWidth = 2 * sc);
    currentY += dividerPadding / 2;

    // --- Content Section ---
    // Date
    final String dateStr = DateFormat(p.dateFormat.isNotEmpty ? p.dateFormat : 'EEEE, d MMMM yyyy', 'id_ID').format(p.timestamp);
    _tp(dateStr, 32 * sc * fontScale, currentY, textPrimary, bold: true, x: currentX).paint(c);
    currentY += 60 * sc;

    // Coordinates
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final String latDir = p.lat! >= 0 ? 'N' : 'S';
      final String lonDir = p.lon! >= 0 ? 'E' : 'W';
      final String coord = '${p.lat!.abs().toStringAsFixed(6)}°$latDir, ${p.lon!.abs().toStringAsFixed(6)}°$lonDir';
      _tp(coord, 28 * sc * fontScale, currentY, textSecondary, x: currentX).paint(c);
      currentY += 55 * sc;
    }

    // Accuracy
    if (p.showAccuracy && p.acc != null) {
      _tp('Accuracy: ±${p.acc!.toStringAsFixed(1)} m', 24 * sc * fontScale, currentY, textSecondary, x: currentX).paint(c);
      currentY += 50 * sc;
    }

    // Address
    if (p.showAddress && p.address.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(text: p.address, style: TextStyle(fontSize: 24 * sc * fontScale)),
        textDirection: ui.TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: panelW - (panelPaddingHorizontal * 2));
      _tp(p.address, 24 * sc * fontScale, currentY, textSecondary, x: currentX,
          maxW: panelW - (panelPaddingHorizontal * 2), maxLines: 3).paint(c);
      currentY += tp.height + 20 * sc;
    }

    // Weather
    if (p.showWeather && p.weather.isNotEmpty) {
      _tp(p.weather, 24 * sc * fontScale, currentY, const Color(0xFF00796B), x: currentX).paint(c);
      currentY += 45 * sc;
    }

    // Footer
    _tp('🛡 Timemark menjamin keaslian waktu', 24 * sc * fontScale, currentY, textSecondary, x: currentX).paint(c);

    // Vertical Verification Code
    final String verCode = _verCode(p);
    final double verCenterY = panelY + panelH / 2;
    _drawVerticalText(c, '© $verCode Timemark Verified', 22 * sc * fontScale,
        W - 55 * sc, verCenterY, Colors.white.withOpacity(0.8), sc);

    // Bottom Branding
    _tp('Timemark', 36 * sc * fontScale, H - 120 * sc, Colors.white, x: W - 280 * sc, bold: true).paint(c);
    _tp('Camera', 26 * sc * fontScale, H - 75 * sc, Colors.white70, x: W - 280 * sc).paint(c);
  }

  static double _calculatePanelHeight(double sc, double fontScale, WatermarkParams p, double panelW, double verticalPadding, double contentGap, double dividerPadding) {
    double h = verticalPadding * 2;
    h += 90 * sc; // Estimated badge height
    h += contentGap;
    h += dividerPadding;
    
    h += 60 * sc; // Date
    if (p.showCoordinates && p.lat != null) h += 55 * sc;
    if (p.showAccuracy && p.acc != null) h += 50 * sc;
    if (p.showAddress && p.address.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(text: p.address, style: TextStyle(fontSize: 24 * sc * fontScale)),
        textDirection: ui.TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: panelW - (32 * sc * 2));
      h += tp.height + 20 * sc;
    }
    if (p.showWeather && p.weather.isNotEmpty) h += 45 * sc;
    h += 60 * sc; // Footer height contribution
    return h;
  }

  static void _drawSelectedLogo(Canvas c, double x, double y, double sc, String? type, ui.Image? customLogo, double w, double h, double opacity, Color accentColor) {
    if (type == 'custom' && customLogo != null) {
      c.drawImageRect(
        customLogo,
        Rect.fromLTWH(0, 0, customLogo.width.toDouble(), customLogo.height.toDouble()),
        Rect.fromLTWH(x, y, w, h),
        Paint(),
      );
    } else if (type == 'timemark_icon') {
      _drawTimemarkIcon(c, x + 40 * sc, y + 30 * sc, 30 * sc, accentColor);
    } else {
      _drawMiniLogo(c, x, y, sc, w, h, opacity, accentColor);
    }
  }

  static void _drawMiniLogo(Canvas c, double x, double y, double sc, double w, double h, double opacity, Color accentColor) {
    final Paint p = Paint()..color = Colors.white.withOpacity(opacity.clamp(0.6, 1.0));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(8 * sc)), p);
    final Paint vanPaint = Paint()..color = accentColor.withOpacity(opacity.clamp(0.6, 1.0));
    c.drawRect(Rect.fromLTWH(x + 10 * sc, y + 18 * sc, 35 * sc, 24 * sc), vanPaint);
    _tp('NEXT', 16 * sc, y + 22 * sc, Colors.black.withOpacity(opacity.clamp(0.6, 1.0)), bold: true, x: x + 55 * sc).paint(c);
  }

  static void _drawTimemarkIcon(Canvas c, double cx, double cy, double radius, Color color) {
    final Paint p = Paint()..color = color..style = PaintingStyle.fill;
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
