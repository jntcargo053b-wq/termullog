import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';

class ProfessionalWatermarkPainter extends CustomPainter {
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

  const ProfessionalWatermarkPainter({
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
  });

  double computeHeightSync(Size canvasSize) {
    final baseWidth = 320.0;
    final scale = (canvasSize.width / baseWidth).clamp(0.75, 1.4);
    final padX = 20.0 * scale;
    double cy = 18 * scale;
    final fsMultiplier = fontSize == 'small' ? 0.82 : fontSize == 'large' ? 1.22 : 1.0;

    double simulateTextHeight(String text, double fontSizePt, int maxLines) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: TextStyle(fontSize: fontSizePt, height: 1.25)),
        textDirection: ui.TextDirection.ltr,
        maxLines: maxLines,
      );
      tp.layout(maxWidth: canvasSize.width - padX * 2);
      return tp.height;
    }

    // Date
    cy += simulateTextHeight(DateFormat('EEE, dd MMM yyyy').format(timestamp), 14 * fsMultiplier, 1) + (8 * scale);
    // Time
    cy += simulateTextHeight(DateFormat('HH:mm:ss').format(timestamp), 29 * fsMultiplier, 1) + (8 * scale);
    cy += 18 * scale; // line space

    if (showCoordinates && hasPosition && lat != null && lon != null)
      cy += simulateTextHeight('📍 ${lat!.toStringAsFixed(5)}, ${lon!.toStringAsFixed(5)}', 12.5 * fsMultiplier, 1) + (8 * scale);
    if (showAccuracy && hasPosition && acc != null)
      cy += simulateTextHeight('🎯 Accuracy ±${acc!.toStringAsFixed(1)}m', 11.5 * fsMultiplier, 1) + (8 * scale);
    if (showAddress && address.isNotEmpty)
      cy += simulateTextHeight('🏠 $address', 12.5 * fsMultiplier, 3) + (8 * scale);
    if (showWeather && weather.isNotEmpty)
      cy += simulateTextHeight('☁ $weather', 12.5 * fsMultiplier, 2) + (8 * scale);

    return cy + 16;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Tentukan radius berdasarkan layout (hanya untuk referensi, tidak digunakan karena card sudah fixed)
    double effectiveOpacity = opacity;
    switch (layout) {
      case WatermarkLayout.modern:
      case WatermarkLayout.gpsCard:
        effectiveOpacity = 0.82;
        break;
      case WatermarkLayout.minimal:
        effectiveOpacity = 0.72;
        break;
      case WatermarkLayout.hud:
        effectiveOpacity = 0.55;
        break;
      case WatermarkLayout.cinematic:
      case WatermarkLayout.cinematicV2:
        effectiveOpacity = 0.90;
        break;
      default:
        effectiveOpacity = opacity;
    }

    final baseWidth = 320.0;
    final scale = (size.width / baseWidth).clamp(0.75, 1.4);
    final padX = 20.0 * scale;
    final fsMultiplier = fontSize == 'small' ? 0.82 : fontSize == 'large' ? 1.22 : 1.0;
    double cy = 18 * scale;

    void drawText({
      required String text,
      required double fontSizePt,
      required Color color,
      bool bold = false,
      int maxLines = 2,
      double spacing = 0.0,
    }) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSizePt,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            height: 1.25,
            letterSpacing: spacing,
            fontFamily: 'Roboto',
            shadows: const [Shadow(blurRadius: 3, color: Colors.black54, offset: Offset(1, 1))],
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: maxLines,
        ellipsis: '...',
      );
      tp.layout(maxWidth: size.width - (padX * 2));
      tp.paint(canvas, Offset(padX, cy));
      cy += tp.height + (8 * scale);
    }

    // Date
    drawText(text: DateFormat('EEE, dd MMM yyyy').format(timestamp), fontSizePt: 14 * fsMultiplier, color: Colors.white70, spacing: 0.3);
    // Time
    drawText(text: DateFormat('HH:mm:ss').format(timestamp), fontSizePt: 29 * fsMultiplier, color: Colors.white, bold: true, spacing: 0.9);
    // Line
    final linePaint = Paint()..color = Colors.white.withOpacity(0.10)..strokeWidth = 1;
    canvas.drawLine(Offset(padX, cy), Offset(size.width - padX, cy), linePaint);
    cy += 18 * scale;

    if (showCoordinates && hasPosition && lat != null && lon != null) {
      drawText(text: '📍 ${lat!.toStringAsFixed(5)}, ${lon!.toStringAsFixed(5)}', fontSizePt: 12.5 * fsMultiplier, color: const Color(0xFF64B5F6), maxLines: 1);
    }
    if (showAccuracy && hasPosition && acc != null) {
      drawText(text: '🎯 Accuracy ±${acc!.toStringAsFixed(1)}m', fontSizePt: 11.5 * fsMultiplier, color: Colors.white60, maxLines: 1);
    }
    if (showAddress && address.isNotEmpty) {
      drawText(text: '🏠 $address', fontSizePt: 12.5 * fsMultiplier, color: Colors.white70, maxLines: 3);
    }
    if (showWeather && weather.isNotEmpty) {
      drawText(text: '☁ $weather', fontSizePt: 12.5 * fsMultiplier, color: const Color(0xFF4FC3F7), maxLines: 2);
    }
  }

  @override
  bool shouldRepaint(covariant ProfessionalWatermarkPainter old) {
    return old.timestamp != timestamp ||
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
        old.layout != layout;
  }
}
