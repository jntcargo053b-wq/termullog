// lib/watermark/unified_watermark_painter.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';

class UnifiedWatermarkPainter extends CustomPainter {
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
  final String fontSize;
  final WatermarkLayout layout;
  final double fontScale;
  final double cardWidth;
  final bool isHighQuality;
  final double pixelRatio;
  final String? dateFormat;      // opsional, dari SettingsCache
  final String? timeFormat;      // opsional, dari SettingsCache

  static final Map<String, double> _heightCache = {};
  static const int _maxHeightCache = 30;

  // Format default
  static const String _defaultDateFormat = 'EEE, dd MMM yyyy';
  static const String _defaultTimeFormat = 'HH:mm:ss';

  const UnifiedWatermarkPainter({
    required this.timestamp,
    required this.hasPosition,
    this.lat,
    this.lon,
    this.acc,
    required this.address,
    required this.weather,
    required this.showWeather,
    required this.showAccuracy,
    required this.showAddress,
    required this.showCoordinates,
    required this.opacity,
    required this.showBorder,
    required this.fontSize,
    required this.layout,
    this.fontScale = 1.0,
    required this.cardWidth,
    this.isHighQuality = true,
    this.pixelRatio = 1.0,
    this.dateFormat,
    this.timeFormat,
  });

  DateFormat get _dateFormatter {
    final pattern = dateFormat ?? _defaultDateFormat;
    try {
      return DateFormat(pattern, 'id');
    } catch (_) {
      return DateFormat(_defaultDateFormat, 'id');
    }
  }

  DateFormat get _timeFormatter {
    final pattern = timeFormat ?? _defaultTimeFormat;
    try {
      return DateFormat(pattern);
    } catch (_) {
      return DateFormat(_defaultTimeFormat);
    }
  }

  TextStyle _textStyle({
    required double fontSize,
    required Color color,
    bool bold = false,
    double letterSpacing = 0.0,
    bool withShadow = false,
  }) {
    return TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      height: 1.25,
      letterSpacing: letterSpacing,
      fontFamily: 'Roboto',
      leadingDistribution: TextLeadingDistribution.even,
      shadows: (isHighQuality && withShadow)
          ? [Shadow(blurRadius: 3, color: Colors.black54, offset: Offset(0, 1))]
          : null,
    );
  }

  TextPainter _createPainter(String text, TextStyle style, double maxWidth, int maxLines) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '...',
    );
    tp.layout(maxWidth: maxWidth);
    return tp;
  }

  double computeHeight() {
    // Key stabil: gunakan string literal, bukan hashCode yang bisa berubah
    final cacheKey = [
      layout.index,
      fontScale.toStringAsFixed(2),
      cardWidth.round(),
      showAddress ? address : '',
      showWeather ? weather : '',
      showCoordinates,
      showAccuracy,
      fontSize,
      pixelRatio.toStringAsFixed(2),
      isHighQuality,
      dateFormat,
      timeFormat,
    ].join('_');
    if (_heightCache.containsKey(cacheKey)) return _heightCache[cacheKey]!;
    if (_heightCache.length > _maxHeightCache) _heightCache.clear();

    final layoutScale = (cardWidth / 320).clamp(0.8, 1.2);
    final exportBoost = isHighQuality ? pixelRatio.clamp(1.0, 4.0) : 1.0;
    final typographyScale = (cardWidth / 320).clamp(0.85, 1.1) * fontScale * exportBoost;
    final double padX = 20.0 * layoutScale;
    final double fsMultiplier = fontSize == 'small' ? 0.82 : fontSize == 'large' ? 1.22 : 1.0;
    final double effFontMulti = fsMultiplier * typographyScale;

    double cy = 18 * layoutScale;

    double measureText(String text, double fontSizePt, int maxLines, {double? maxWidth}) {
      final style = _textStyle(fontSize: fontSizePt, color: Colors.white);
      final actualMaxWidth = maxWidth ?? (cardWidth - padX * 2);
      final tp = _createPainter(text, style, actualMaxWidth, maxLines);
      return tp.height;
    }

    final dateText = _dateFormatter.format(timestamp);
    final timeText = _timeFormatter.format(timestamp);

    cy += measureText(dateText, 14 * effFontMulti, 1) + 8 * layoutScale;
    cy += measureText(timeText, 29 * effFontMulti, 1) + 8 * layoutScale;
    cy += 18 * layoutScale;

    if (showCoordinates && hasPosition && lat != null && lon != null) {
      cy += measureText('${lat!.toStringAsFixed(5)}, ${lon!.toStringAsFixed(5)}', 12.5 * effFontMulti, 1) + 8 * layoutScale;
    }
    if (showAccuracy && hasPosition && acc != null) {
      cy += measureText('Accuracy ±${acc!.toStringAsFixed(1)}m', 11.5 * effFontMulti, 1) + 8 * layoutScale;
    }
    if (showAddress && address.isNotEmpty) {
      final double iconSize = 12 * effFontMulti;
      final double textOffset = iconSize + 10;
      cy += measureText(address, 12.5 * effFontMulti, 3, maxWidth: cardWidth - padX * 2 - textOffset) + 8 * layoutScale;
    }
    if (showWeather && weather.isNotEmpty) {
      cy += measureText(weather, 12.5 * effFontMulti, 2) + 8 * layoutScale;
    }

    final height = cy + 24 * layoutScale;
    _heightCache[cacheKey] = height;
    return height;
  }

  void _drawIcon(Canvas canvas, IconData icon, double x, double y, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(fontFamily: icon.fontFamily, fontSize: size, color: color),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x, y));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final layoutScale = (cardWidth / 320).clamp(0.8, 1.2);
    final exportBoost = isHighQuality ? pixelRatio.clamp(1.0, 4.0) : 1.0;
    final typographyScale = (cardWidth / 320).clamp(0.85, 1.1) * fontScale * exportBoost;
    final double padX = 20.0 * layoutScale;
    final double fsMultiplier = fontSize == 'small' ? 0.82 : fontSize == 'large' ? 1.22 : 1.0;
    final double effFontMulti = fsMultiplier * typographyScale;
    double cy = 18 * layoutScale;

    final double radius = size.width * 0.045;
    final RRect rect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));

    if (isHighQuality) {
      canvas.drawShadow(Path()..addRRect(rect), Colors.black, 8, true);
    }

    if (isHighQuality) {
      final bgPaint = Paint()..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.black.withOpacity(opacity * 0.80), Colors.black.withOpacity(opacity * 0.70)],
      ).createShader(Offset.zero & size);
      canvas.drawRRect(rect, bgPaint);
    } else {
      canvas.drawRRect(rect, Paint()..color = Colors.black.withOpacity(opacity * 0.78));
    }

    if (showBorder) {
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withOpacity(0.22);
      canvas.drawRRect(rect, borderPaint);
    }

    void drawText(
      String text,
      double fontSizePt,
      Color color,
      int maxLines, {
      bool bold = false,
      double spacing = 0.0,
      bool withShadow = false,
      double? maxWidth,
      double offsetX = 0,
    }) {
      final style = _textStyle(fontSize: fontSizePt, color: color, bold: bold, letterSpacing: spacing, withShadow: withShadow);
      final actualMaxWidth = maxWidth ?? (size.width - padX * 2);
      final tp = _createPainter(text, style, actualMaxWidth, maxLines);
      tp.paint(canvas, Offset(padX + offsetX, cy));
      cy += tp.height + 8 * layoutScale;
    }

    final dateText = _dateFormatter.format(timestamp);
    final timeText = _timeFormatter.format(timestamp);

    drawText(dateText, 14 * effFontMulti, Colors.white70, 1, spacing: 0.3);
    drawText(timeText, 29 * effFontMulti, Colors.white, 1, bold: true, spacing: 0.9, withShadow: isHighQuality);

    final linePaint = Paint()
      ..strokeWidth = 1
      ..isAntiAlias = false
      ..color = Colors.white.withOpacity(0.12);
    canvas.drawLine(Offset(padX, cy), Offset(size.width - padX, cy), linePaint);
    cy += 18 * layoutScale;

    if (showCoordinates && hasPosition && lat != null && lon != null) {
      drawText('${lat!.toStringAsFixed(5)}, ${lon!.toStringAsFixed(5)}', 12.5 * effFontMulti, const Color(0xFF64B5F6), 1);
    }
    if (showAccuracy && hasPosition && acc != null) {
      drawText('Accuracy ±${acc!.toStringAsFixed(1)}m', 11.5 * effFontMulti, Colors.white60, 1);
    }
    if (showAddress && address.isNotEmpty) {
      final double iconSize = 12 * effFontMulti;
      final double textOffset = iconSize + 10;
      _drawIcon(canvas, Icons.home, padX, cy + 2, iconSize, Colors.white70);
      drawText(
        address,
        12.5 * effFontMulti,
        Colors.white70,
        3,
        maxWidth: size.width - padX * 2 - textOffset,
        offsetX: textOffset,
      );
    }
    if (showWeather && weather.isNotEmpty) {
      drawText(weather, 12.5 * effFontMulti, const Color(0xFF4FC3F7), 2);
    }
  }

  @override
  bool shouldRepaint(covariant UnifiedWatermarkPainter old) {
    final nowSeconds = timestamp.millisecondsSinceEpoch ~/ 1000;
    final oldSeconds = old.timestamp.millisecondsSinceEpoch ~/ 1000;
    return nowSeconds != oldSeconds ||
        old.lat != lat ||
        old.lon != lon ||
        old.acc != acc ||
        old.address != address ||
        old.weather != weather ||
        old.showWeather != showWeather ||
        old.showAccuracy != showAccuracy ||
        old.showAddress != showAddress ||
        old.showCoordinates != showCoordinates ||
        old.fontSize != fontSize ||
        old.layout != layout ||
        old.fontScale != fontScale ||
        old.cardWidth != cardWidth ||
        old.isHighQuality != isHighQuality ||
        old.pixelRatio != pixelRatio ||
        old.opacity != opacity ||
        old.showBorder != showBorder ||
        old.dateFormat != dateFormat ||
        old.timeFormat != timeFormat;
  }
}
