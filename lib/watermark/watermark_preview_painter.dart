// lib/watermark/watermark_preview_painter.dart
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Live preview painter yang identik dengan layout WatermarkEngine.
class WatermarkPreviewPainter extends CustomPainter {
  final DateTime timestamp;
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
  final bool showLogo;
  final String appName;
  final double fontScale;
  final String dateFormat;
  final String timeFormat;

  const WatermarkPreviewPainter({
    required this.timestamp,
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
    required this.showLogo,
    required this.appName,
    required this.fontScale,
    required this.dateFormat,
    required this.timeFormat,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width;
    final H = size.height;
    final double sc = (W / 1080.0).clamp(0.4, 1.2);
    final double fontScale = this.fontScale.clamp(0.5, 2.0);

    _drawReferenceLayout(canvas, W, H, sc, fontScale);
  }

  void _drawReferenceLayout(Canvas c, double W, double H, double sc, double fontScale) {
    final double innerPadding = 24 * sc;
    final double headerSpacing = 24 * sc;

    // Badge
    final String appName = this.appName.isNotEmpty ? this.appName : 'termullog';
    final double badgeFontSize = 32 * sc * fontScale;
    final namePainter = TextPainter(
      text: TextSpan(text: appName, style: TextStyle(fontSize: badgeFontSize, fontWeight: FontWeight.w700)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final double badgePadding = 32 * sc;
    final double badgeW = (namePainter.width + badgePadding).clamp(140 * sc, 350 * sc);
    final double badgeH = 85 * sc;

    // Time
    final String timeStr = DateFormat(timeFormat.isNotEmpty ? timeFormat : 'HH:mm').format(timestamp);
    final double timeFontSize = 85 * sc * fontScale;
    final timePainter = TextPainter(
      text: TextSpan(text: timeStr, style: TextStyle(fontSize: timeFontSize, fontWeight: FontWeight.w700)),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    final double logoW = 150 * sc;
    final double logoH = 65 * sc;

    // Dynamic panel width
    double headerW = badgeW + headerSpacing + timePainter.width;
    if (showLogo) headerW += headerSpacing + logoW;
    final double panelW = (headerW + innerPadding * 2).clamp(600 * sc, W - 48 * sc);

    final double panelH = _calculatePanelHeight(sc, fontScale, panelW, innerPadding);
    final double panelX = 24 * sc;
    final double targetY = H - panelH - 120 * sc;
    final double panelY = targetY.clamp(24 * sc, H - panelH - 24 * sc);

    // Panel background
    final RRect panelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(panelX, panelY, panelW, panelH),
      Radius.circular(16 * sc),
    );
    c.drawRRect(panelRect, Paint()..color = Colors.white.withOpacity(opacity.clamp(0.4, 0.9)));

    if (showBorder) {
      c.drawRRect(panelRect, Paint()
        ..color = Colors.orange.withOpacity(opacity.clamp(0.4, 1.0))
        ..strokeWidth = 3 * sc
        ..style = PaintingStyle.stroke);
    }

    double currentX = panelX + innerPadding;
    double currentY = panelY + innerPadding;

    // Badge (default style)
    final RRect badgeRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(currentX, currentY, badgeW, badgeH), Radius.circular(10 * sc));
    c.drawRRect(badgeRRect, Paint()..color = const Color(0xFFFFC107).withOpacity(opacity.clamp(0.6, 1.0)));
    _drawText(c, appName, badgeFontSize, currentY + (badgeH - namePainter.height) / 2, Colors.black87,
        bold: true, x: currentX + badgeW / 2, centerX: true, maxW: badgeW - 12 * sc);

    // Time
    currentX += badgeW + headerSpacing;
    _drawText(c, timeStr, timeFontSize, currentY - 4 * sc, const Color(0xFF1A237E), bold: true, x: currentX);

    // Logo (simplified)
    if (showLogo) {
      currentX += timePainter.width + headerSpacing;
      final double safeLogoX = currentX.clamp(panelX, panelX + panelW - logoW - innerPadding);
      _drawPreviewLogo(c, safeLogoX, currentY + 12 * sc, sc);
    }

    currentY += 110 * sc;
    currentX = panelX + innerPadding;

    // Divider
    c.drawLine(Offset(currentX, currentY), Offset(panelX + panelW - innerPadding, currentY),
        Paint()..color = Colors.grey.withOpacity(0.2)..strokeWidth = 2 * sc);
    currentY += 32 * sc;

    // Date
    final String dateStr = DateFormat(dateFormat.isNotEmpty ? dateFormat : 'EEEE, d MMMM yyyy', 'id_ID').format(timestamp);
    _drawText(c, dateStr, 30 * sc * fontScale, currentY, Colors.black87, bold: true, x: currentX);
    currentY += 55 * sc;

    // Coordinates
    if (showCoordinates && lat != null && lon != null) {
      final String latDir = lat! >= 0 ? 'N' : 'S';
      final String lonDir = lon! >= 0 ? 'E' : 'W';
      final String coord = '${lat!.abs().toStringAsFixed(6)}°$latDir, ${lon!.abs().toStringAsFixed(6)}°$lonDir';
      _drawText(c, coord, 26 * sc * fontScale, currentY, Colors.grey[700]!, x: currentX);
      currentY += 50 * sc;
    }

    // Accuracy
    if (showAccuracy && acc != null) {
      _drawText(c, 'Accuracy: ±${acc!.toStringAsFixed(1)} m', 22 * sc * fontScale, currentY, Colors.grey[600]!, x: currentX);
      currentY += 45 * sc;
    }

    // Address
    if (showAddress && address.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(text: address, style: TextStyle(fontSize: 22 * sc * fontScale)),
        textDirection: ui.TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: panelW - (innerPadding * 2));
      _drawText(c, address, 22 * sc * fontScale, currentY, Colors.grey[700]!,
          x: currentX, maxW: panelW - (innerPadding * 2), maxLines: 3);
      currentY += tp.height + 20 * sc;
    }

    // Weather
    if (showWeather && weather.isNotEmpty) {
      _drawText(c, weather, 22 * sc * fontScale, currentY, const Color(0xFF00796B), x: currentX);
      currentY += 40 * sc;
    }

    // Footer
    _drawText(c, '🛡 Timemark menjamin keaslian waktu', 22 * sc * fontScale, currentY, Colors.grey[600]!, x: currentX);

    // Vertical verification code
    final String verCode = _previewVerCode();
    final double verCenterY = panelY + panelH / 2;
    _drawVerticalText(c, '© $verCode Timemark Verified', 20 * sc * fontScale,
        W - 50 * sc, verCenterY, Colors.white.withOpacity(0.8), sc);

    // Bottom branding
    _drawText(c, 'Timemark', 32 * sc * fontScale, H - 110 * sc, Colors.white, bold: true, x: W - 260 * sc);
    _drawText(c, 'Camera', 24 * sc * fontScale, H - 70 * sc, Colors.white70, x: W - 260 * sc);
  }

  double _calculatePanelHeight(double sc, double fontScale, double panelW, double innerPadding) {
    double h = innerPadding + 110 * sc + 32 * sc + 55 * sc;
    if (showCoordinates && lat != null) h += 50 * sc;
    if (showAccuracy && acc != null) h += 45 * sc;
    if (showAddress && address.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(text: address, style: TextStyle(fontSize: 22 * sc * fontScale)),
        textDirection: ui.TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: panelW - (innerPadding * 2));
      h += tp.height + 20 * sc;
    }
    if (showWeather && weather.isNotEmpty) h += 40 * sc;
    h += 50 * sc + innerPadding;
    return h;
  }

  void _drawPreviewLogo(Canvas c, double x, double y, double sc) {
    final Paint p = Paint()..color = Colors.white.withOpacity(opacity.clamp(0.6, 1.0));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, 150 * sc, 65 * sc), Radius.circular(8 * sc)), p);
    _drawText(c, 'NEXT', 18 * sc, y + 24 * sc, Colors.black.withOpacity(opacity.clamp(0.6, 1.0)),
        bold: true, x: x + 55 * sc, centerX: true);
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
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
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
        oldDelegate.showLogo != showLogo ||
        oldDelegate.appName != appName ||
        oldDelegate.fontScale != fontScale ||
        oldDelegate.dateFormat != dateFormat ||
        oldDelegate.timeFormat != timeFormat;
  }
}
