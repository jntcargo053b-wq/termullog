// lib/watermark/watermark_preview_painter.dart
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'watermark_params.dart';

/// Live preview painter matching WatermarkEngine layout including Mini Map support.
class WatermarkPreviewPainter extends CustomPainter {
  final WatermarkParams params;
  final double previewWidth;
  final double previewHeight;
  
  // Pre-decoded assets for preview performance
  final ui.Image? customLogo;
  final ui.Image? customBadge;
  final ui.Image? mapImage; // Pre-decoded static map image for preview

  const WatermarkPreviewPainter({
    required this.params,
    required this.previewWidth,
    required this.previewHeight,
    this.customLogo,
    this.customBadge,
    this.mapImage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final W = previewWidth;
    final H = previewHeight;

    final double sc = (W / 1080.0).clamp(0.4, 1.2);
    final double fontScale = params.fontScale.clamp(0.5, 2.0);

    _drawReferenceLayout(canvas, W, H, sc, fontScale);
  }

  void _drawReferenceLayout(Canvas c, double W, double H, double sc, double fontScale) {
    // --- Branding Colors ---
    const Color brandPrimary = Color(0xFF0D47A1); 
    const Color brandAccent = Color(0xFFFFB300);  
    const Color textPrimary = Color(0xFF212121);
    const Color textSecondary = Color(0xFF757575);

    // --- Spacing Constants ---
    final double panelPaddingHorizontal = 32 * sc;
    final double panelPaddingVertical = 28 * sc;
    final double headerSpacing = 32 * sc;
    final double contentVerticalGap = 24 * sc;
    final double dividerPadding = 32 * sc;

    // 1. Measure Time
    final String timeStr = DateFormat(params.timeFormat.isNotEmpty ? params.timeFormat : 'HH:mm:ss').format(params.timestamp);
    final double timeFontSize = 92 * sc * fontScale;
    final timePainter = TextPainter(
      text: TextSpan(text: timeStr, style: TextStyle(fontSize: timeFontSize, fontWeight: FontWeight.w700)),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    // 2. Measure Badge
    final String appName = params.appName.isNotEmpty ? params.appName : 'termullog';
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

    // 3. Dynamic Panel Width (Considers Map if present)
    double headerRowW = badgeW + headerSpacing + timePainter.width;
    if (params.showLogo) headerRowW += headerSpacing + logoW;
    
    // Mini Map Dimension
    double mapW = 0;
    if (params.showMiniMap) {
      mapW = params.mapSize.toDouble() * sc;
    }

    final double basePanelW = (headerRowW + panelPaddingHorizontal * 2).clamp(700 * sc, W - 64 * sc);
    // If map is active, we ensure the panel is wide enough or let map sit within bounds
    final double panelW = params.showMiniMap ? max(basePanelW, mapW + panelPaddingHorizontal * 2) : basePanelW;

    // 4. Calculate dynamic panel height
    final double panelH = _calculatePanelHeight(sc, fontScale, panelW, panelPaddingVertical, contentVerticalGap, dividerPadding);
    final double panelX = 32 * sc;
    final double targetY = H - panelH - 120 * sc;
    final double panelY = targetY.clamp(32 * sc, H - panelH - 32 * sc);

    // Draw Panel Background
    final RRect panelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(panelX, panelY, panelW, panelH),
      Radius.circular(20 * sc),
    );
    c.drawRRect(panelRect, Paint()..color = Colors.white.withOpacity(params.opacity.clamp(0.4, 0.95)));

    if (params.showBorder) {
      c.drawRRect(panelRect, Paint()
        ..color = brandAccent.withOpacity(params.opacity.clamp(0.4, 1.0))
        ..strokeWidth = 3 * sc
        ..style = PaintingStyle.stroke);
    }

    double currentX = panelX + panelPaddingHorizontal;
    double currentY = panelY + panelPaddingVertical;

    // --- Header Section ---
    if (params.badgeType == 'custom' && customBadge != null) {
      c.drawImageRect(customBadge!, Rect.fromLTWH(0, 0, customBadge!.width.toDouble(), customBadge!.height.toDouble()), Rect.fromLTWH(currentX, currentY, badgeW, badgeH), Paint());
    } else {
      final RRect badgeRRect = RRect.fromRectAndRadius(Rect.fromLTWH(currentX, currentY, badgeW, badgeH), Radius.circular(12 * sc));
      c.drawRRect(badgeRRect, Paint()..color = brandAccent.withOpacity(params.opacity.clamp(0.6, 1.0)));
      _drawText(c, appName, badgeFontSize, currentY + (badgeH - namePainter.height) / 2, textPrimary, bold: true, x: currentX + badgeW / 2, centerX: true, maxW: badgeW - 16 * sc);
    }

    currentX += badgeW + headerSpacing;
    _drawText(c, timeStr, timeFontSize, currentY - 4 * sc, brandPrimary, bold: true, x: currentX);

    if (params.showLogo) {
      currentX += timePainter.width + headerSpacing;
      final double safeLogoX = currentX.clamp(panelX + panelPaddingHorizontal, panelX + panelW - logoW - panelPaddingHorizontal);
      _drawPreviewLogo(c, safeLogoX, currentY + 14 * sc, sc, logoW, logoH, params.opacity, brandAccent);
    }

    currentY += badgeH + contentVerticalGap;
    currentX = panelX + panelPaddingHorizontal;

    // --- Map Section ---
    if (params.showMiniMap && mapImage != null) {
      final double mapH = mapW; // Square map for preview
      c.drawImageRect(
        mapImage!,
        Rect.fromLTWH(0, 0, mapImage!.width.toDouble(), mapImage!.height.toDouble()),
        Rect.fromLTWH(currentX, currentY, mapW, mapH),
        Paint(),
      );
      // Map Border
      c.drawRect(Rect.fromLTWH(currentX, currentY, mapW, mapH), Paint()..color = Colors.grey.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 1 * sc);
      currentY += mapH + contentVerticalGap;
    }

    // Divider
    currentY += dividerPadding / 2;
    c.drawLine(Offset(currentX, currentY), Offset(panelX + panelW - panelPaddingHorizontal, currentY),
        Paint()..color = textSecondary.withOpacity(0.2)..strokeWidth = 2 * sc);
    currentY += dividerPadding / 2;

    // --- Content Section ---
    final String dateStr = DateFormat(params.dateFormat.isNotEmpty ? params.dateFormat : 'EEEE, d MMMM yyyy', 'id_ID').format(params.timestamp);
    _drawText(c, dateStr, 32 * sc * fontScale, currentY, textPrimary, bold: true, x: currentX);
    currentY += 60 * sc;

    if (params.showCoordinates && params.lat != null && params.lon != null) {
      final String latDir = params.lat! >= 0 ? 'N' : 'S';
      final String lonDir = params.lon! >= 0 ? 'E' : 'W';
      final String coord = '${params.lat!.abs().toStringAsFixed(6)}°$latDir, ${params.lon!.abs().toStringAsFixed(6)}°$lonDir';
      _drawText(c, coord, 28 * sc * fontScale, currentY, textSecondary, x: currentX);
      currentY += 55 * sc;
    }

    if (params.showAccuracy && params.acc != null) {
      _drawText(c, 'Accuracy: ±${params.acc!.toStringAsFixed(1)} m', 24 * sc * fontScale, currentY, textSecondary, x: currentX);
      currentY += 50 * sc;
    }

    if (params.showAddress && params.address.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(text: params.address, style: TextStyle(fontSize: 24 * sc * fontScale)),
        textDirection: ui.TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: panelW - (panelPaddingHorizontal * 2));
      _drawText(c, params.address, 24 * sc * fontScale, currentY, textSecondary, x: currentX, maxW: panelW - (panelPaddingHorizontal * 2), maxLines: 3);
      currentY += tp.height + 20 * sc;
    }

    if (params.showWeather && params.weather.isNotEmpty) {
      _drawText(c, params.weather, 24 * sc * fontScale, currentY, const Color(0xFF00796B), x: currentX);
      currentY += 45 * sc;
    }

    _drawText(c, '🛡 Timemark menjamin keaslian waktu', 24 * sc * fontScale, currentY, textSecondary, x: currentX);

    // Vertical Verification Code
    final String verCode = _previewVerCode();
    final double verCenterY = panelY + panelH / 2;
    _drawVerticalText(c, '© $verCode Timemark Verified', 22 * sc * fontScale, W - 55 * sc, verCenterY, Colors.white.withOpacity(0.8), sc);

    // Bottom Branding
    _drawText(c, 'Timemark', 36 * sc * fontScale, H - 120 * sc, Colors.white, bold: true, x: W - 280 * sc);
    _drawText(c, 'Camera', 26 * sc * fontScale, H - 75 * sc, Colors.white70, x: W - 280 * sc);
  }

  double _calculatePanelHeight(double sc, double fontScale, double panelW, double verticalPadding, double contentGap, double dividerPadding) {
    double h = verticalPadding * 2;
    h += 90 * sc; // Badge/Header
    h += contentGap;
    
    if (params.showMiniMap) {
      h += (params.mapSize.toDouble() * sc) + contentGap;
    }
    
    h += dividerPadding;
    h += 60 * sc; // Date
    if (params.showCoordinates && params.lat != null) h += 55 * sc;
    if (params.showAccuracy && params.acc != null) h += 50 * sc;
    if (params.showAddress && params.address.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(text: params.address, style: TextStyle(fontSize: 24 * sc * fontScale)),
        textDirection: ui.TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: panelW - (32 * sc * 2));
      h += tp.height + 20 * sc;
    }
    if (params.showWeather && params.weather.isNotEmpty) h += 45 * sc;
    h += 60 * sc; 
    return h;
  }

  void _drawPreviewLogo(Canvas c, double x, double y, double sc, double w, double h, double opacity, Color accentColor) {
    if (params.logoType == 'custom' && customLogo != null) {
      c.drawImageRect(customLogo!, Rect.fromLTWH(0, 0, customLogo!.width.toDouble(), customLogo!.height.toDouble()), Rect.fromLTWH(x, y, w, h), Paint());
    } else {
      final Paint p = Paint()..color = Colors.white.withOpacity(opacity.clamp(0.6, 1.0));
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(8 * sc)), p);
      final Paint iconPaint = Paint()..color = accentColor.withOpacity(opacity.clamp(0.6, 1.0));
      c.drawRect(Rect.fromLTWH(x + 10 * sc, y + 18 * sc, 35 * sc, 24 * sc), iconPaint);
      _drawText(c, 'NEXT', 16 * sc, y + 22 * sc, Colors.black.withOpacity(opacity.clamp(0.6, 1.0)), bold: true, x: x + 55 * sc);
    }
  }

  void _drawVerticalText(Canvas c, String text, double size, double x, double centerY, Color color, double sc) {
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

  void _drawText(Canvas canvas, String text, double size, double y, Color color, {bool bold = false, double x = 16, double? maxW, bool centerX = false, int maxLines = 2}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
      textDirection: ui.TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: maxW ?? 9999);
    final double paintX = centerX ? x - tp.width / 2 : x;
    tp.paint(canvas, Offset(paintX, y));
  }

  String _previewVerCode() {
    int h = 0x811C9DC5;
    for (final ch in params.timestamp.millisecondsSinceEpoch.toString().codeUnits) {
      h ^= ch;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(36).toUpperCase().padLeft(12, '0').substring(0, 12);
  }

  @override
  bool shouldRepaint(WatermarkPreviewPainter oldDelegate) {
    return oldDelegate.params != params ||
        oldDelegate.previewWidth != previewWidth ||
        oldDelegate.previewHeight != previewHeight ||
        oldDelegate.customLogo != customLogo ||
        oldDelegate.customBadge != customBadge ||
        oldDelegate.mapImage != mapImage;
  }
}
