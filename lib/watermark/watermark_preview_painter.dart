// lib/watermark/watermark_preview_painter.dart
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'watermark_layout.dart';

/// Live preview painter that matches the exact layout of WatermarkEngine.
/// Now supports both custom logos and custom badges for full brand consistency during preview.
class WatermarkPreviewPainter extends CustomPainter {
  final DateTime timestamp;
  final bool hasPosition;
  final double? lat;
  final double? lon;
  final double? acc;
  final String address;
  final String weather;
  final bool showWeather;
  final bool showAccuracy;
  final bool showAddress;
  final bool showCoordinates;
  final double opacity;
  final bool showBorder;
  final WatermarkLayout layout;
  
  // Custom Branding Support
  final String appName;
  final bool showLogo;
  final String? logoType; // 'next_van', 'timemark_icon', or 'custom'
  final ui.Image? customLogo; // Pre-decoded logo for immediate preview
  final String? badgeType; // 'default' or 'custom'
  final ui.Image? customBadge; // Pre-decoded badge for immediate preview
  final String dateFormat;
  final String timeFormat;

  const WatermarkPreviewPainter({
    required this.timestamp,
    required this.hasPosition,
    required this.lat,
    required this.lon,
    required this.acc,
    required this.address,
    required this.weather,
    required this.showWeather,
    required this.showAccuracy,
    required this.showAddress,
    required this.showCoordinates,
    required this.opacity,
    required this.showBorder,
    required this.layout,
    this.appName = 'termullog',
    this.showLogo = true,
    this.logoType,
    this.customLogo,
    this.badgeType,
    this.customBadge,
    this.dateFormat = '',
    this.timeFormat = '',
  });

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width;
    final H = size.height;
    
    // Scale preview based on screen width, identical to engine logic
    final double sc = (W / 1080.0).clamp(0.4, 1.2);
    final double fontScale = 1.0;

    _drawReferenceLayout(canvas, W, H, sc, fontScale);
  }

  /// Layout matching the Deep Blue & Amber branding of the high-quality engine.
  void _drawReferenceLayout(Canvas c, double W, double H, double sc, double fontScale) {
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
    final String timeStr = DateFormat(timeFormat.isNotEmpty ? timeFormat : 'HH:mm').format(timestamp);
    final double timeFontSize = 92 * sc * fontScale;
    final timePainter = TextPainter(
      text: TextSpan(text: timeStr, style: TextStyle(fontSize: timeFontSize, fontWeight: FontWeight.w700)),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    // 2. Measure Badge / Name
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
    if (showLogo) headerRowW += headerSpacing + logoW;
    final double panelW = (headerRowW + panelPaddingHorizontal * 2).clamp(700 * sc, W - 64 * sc);

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
    c.drawRRect(panelRect, Paint()..color = Colors.white.withOpacity(opacity.clamp(0.4, 0.9)));

    if (showBorder) {
      c.drawRRect(panelRect, Paint()
        ..color = brandAccent.withOpacity(opacity.clamp(0.4, 1.0))
        ..strokeWidth = 3 * sc
        ..style = PaintingStyle.stroke);
    }

    double currentX = panelX + panelPaddingHorizontal;
    double currentY = panelY + panelPaddingVertical;

    // --- Header Section ---
    
    // A. Badge (Supports Custom Assets)
    if (badgeType == 'custom' && customBadge != null) {
      paintImage(
        canvas: c,
        rect: Rect.fromLTWH(currentX, currentY, badgeW, badgeH),
        image: customBadge!,
        fit: BoxFit.fill,
      );
    } else {
      final RRect badgeRRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(currentX, currentY, badgeW, badgeH), Radius.circular(12 * sc));
      c.drawRRect(badgeRRect, Paint()..color = brandAccent.withOpacity(opacity.clamp(0.6, 1.0)));
      _drawText(c, appName, badgeFontSize, currentY + (badgeH - namePainter.height) / 2, textPrimary,
          bold: true, x: currentX + badgeW / 2, centerX: true, maxW: badgeW - 16 * sc);
    }

    // B. Time
    currentX += badgeW + headerSpacing;
    _drawText(c, timeStr, timeFontSize, currentY - 4 * sc, brandPrimary, bold: true, x: currentX);

    // C. Logo (Supports Custom Assets)
    if (showLogo) {
      currentX += timePainter.width + headerSpacing;
      final double safeLogoX = currentX.clamp(panelX + panelPaddingHorizontal, panelX + panelW - logoW - panelPaddingHorizontal);
      _drawPreviewLogo(c, safeLogoX, currentY + 14 * sc, sc, logoW, logoH, opacity, brandAccent);
    }

    currentY += badgeH + contentVerticalGap;
    currentX = panelX + panelPaddingHorizontal;

    // Divider
    currentY += dividerPadding / 2;
    c.drawLine(Offset(currentX, currentY), Offset(panelX + panelW - panelPaddingHorizontal, currentY),
        Paint()..color = textSecondary.withOpacity(0.2)..strokeWidth = 2 * sc);
    currentY += dividerPadding / 2;

    // --- Content Section ---
    final String dateStr = DateFormat(dateFormat.isNotEmpty ? dateFormat : 'EEEE, d MMMM yyyy', 'id_ID').format(timestamp);
    _drawText(c, dateStr, 32 * sc * fontScale, currentY, textPrimary, bold: true, x: currentX);
    currentY += 60 * sc;

    if (showCoordinates && lat != null && lon != null) {
      final String latDir = lat! >= 0 ? 'N' : 'S';
      final String lonDir = lon! >= 0 ? 'E' : 'W';
      final String coord = '${lat!.abs().toStringAsFixed(6)}°$latDir, ${lon!.abs().toStringAsFixed(6)}°$lonDir';
      _drawText(c, coord, 28 * sc * fontScale, currentY, textSecondary, x: currentX);
      currentY += 55 * sc;
    }

    if (showAccuracy && acc != null) {
      _drawText(c, 'Accuracy: ±${acc!.toStringAsFixed(1)} m', 24 * sc * fontScale, currentY, textSecondary, x: currentX);
      currentY += 50 * sc;
    }

    if (showAddress && address.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(text: address, style: TextStyle(fontSize: 24 * sc * fontScale)),
        textDirection: ui.TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: panelW - (panelPaddingHorizontal * 2));
      _drawText(c, address, 24 * sc * fontScale, currentY, textSecondary,
          x: currentX, maxW: panelW - (panelPaddingHorizontal * 2), maxLines: 3);
      currentY += tp.height + 20 * sc;
    }

    if (showWeather && weather.isNotEmpty) {
      _drawText(c, weather, 24 * sc * fontScale, currentY, const Color(0xFF00796B), x: currentX);
      currentY += 45 * sc;
    }

    _drawText(c, '🛡 Timemark menjamin keaslian waktu', 24 * sc * fontScale, currentY, textSecondary, x: currentX);

    // Vertical Verification Code
    final String verCode = _previewVerCode();
    final double verCenterY = panelY + panelH / 2;
    _drawVerticalText(c, '© $verCode Timemark Verified', 22 * sc * fontScale,
        W - 55 * sc, verCenterY, Colors.white.withOpacity(0.8), sc);

    // Bottom Branding
    _drawText(c, 'Timemark', 36 * sc * fontScale, H - 120 * sc, Colors.white, bold: true, x: W - 280 * sc);
    _drawText(c, 'Camera', 26 * sc * fontScale, H - 75 * sc, Colors.white70, x: W - 280 * sc);
  }

  double _calculatePanelHeight(double sc, double fontScale, double panelW, double verticalPadding, double contentGap, double dividerPadding) {
    double h = verticalPadding * 2;
    h += 90 * sc; 
    h += contentGap;
    h += dividerPadding;
    h += 60 * sc; 
    if (showCoordinates && lat != null) h += 55 * sc;
    if (showAccuracy && acc != null) h += 50 * sc;
    if (showAddress && address.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(text: address, style: TextStyle(fontSize: 24 * sc * fontScale)),
        textDirection: ui.TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: panelW - (32 * sc * 2));
      h += tp.height + 20 * sc;
    }
    if (showWeather && weather.isNotEmpty) h += 45 * sc;
    h += 60 * sc; 
    return h;
  }

  void _drawPreviewLogo(Canvas c, double x, double y, double sc, double w, double h, double opacity, Color accentColor) {
    if (logoType == 'custom' && customLogo != null) {
      paintImage(
        canvas: c,
        rect: Rect.fromLTWH(x, y, w, h),
        image: customLogo!,
        fit: BoxFit.contain,
      );
    } else {
      final Paint p = Paint()..color = Colors.white.withOpacity(opacity.clamp(0.6, 1.0));
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(8 * sc)), p);
      
      final Paint iconPaint = Paint()..color = accentColor.withOpacity(opacity.clamp(0.6, 1.0));
      c.drawRect(Rect.fromLTWH(x + 10 * sc, y + 18 * sc, 35 * sc, 24 * sc), iconPaint);
      
      _drawText(c, 'NEXT', 16 * sc, y + 22 * sc, Colors.black.withOpacity(opacity.clamp(0.6, 1.0)),
          bold: true, x: x + 55 * sc);
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

  void _drawText(Canvas canvas, String text, double size, double y, Color color,
      {bool bold = false, double x = 16, double? maxW, bool centerX = false, int maxLines = 2}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: maxW ?? 9999);
    final double paintX = centerX ? x - tp.width / 2 : x;
    tp.paint(canvas, Offset(paintX, y));
  }

  String _previewVerCode() {
    int h = 0x811C9DC5;
    for (final ch in timestamp.millisecondsSinceEpoch.toString().codeUnits) {
      h ^= ch;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(36).toUpperCase().padLeft(12, '0').substring(0, 12);
  }

  @override
  bool shouldRepaint(WatermarkPreviewPainter oldDelegate) {
    return oldDelegate.timestamp != timestamp ||
        oldDelegate.hasPosition != hasPosition ||
        oldDelegate.lat != lat ||
        oldDelegate.lon != lon ||
        oldDelegate.acc != acc ||
        oldDelegate.address != address ||
        oldDelegate.weather != weather ||
        oldDelegate.showWeather != showWeather ||
        oldDelegate.showAccuracy != showAccuracy ||
        oldDelegate.showAddress != showAddress ||
        oldDelegate.showCoordinates != showCoordinates ||
        oldDelegate.opacity != opacity ||
        oldDelegate.showBorder != showBorder ||
        oldDelegate.layout != layout ||
        oldDelegate.appName != appName ||
        oldDelegate.showLogo != showLogo ||
        oldDelegate.logoType != logoType ||
        oldDelegate.customLogo != customLogo ||
        oldDelegate.badgeType != badgeType ||
        oldDelegate.customBadge != customBadge ||
        oldDelegate.dateFormat != dateFormat ||
        oldDelegate.timeFormat != timeFormat;
  }
}
