// lib/widgets/professional_watermark_painter.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  final double opacity; // tidak dipakai di painter, tapi tetap parameter
  final bool showBorder; // juga untuk card
  final String fontSize; // 'small', 'normal', 'large'

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
  });

  /// Menghitung tinggi total yang dibutuhkan (sama persis dengan logika paint)
  static Future<double> computeHeightAsync({
    required Size canvasSize,
    required DateTime timestamp,
    required bool hasPosition,
    required bool showCoordinates,
    required bool showAccuracy,
    required bool showAddress,
    required String address,
    required bool showWeather,
    required String weather,
    required String fontSize,
  }) {
    // Karena perhitungan synchronously, kita buat painter dummy untuk hitung
    final dummyPainter = ProfessionalWatermarkPainter(
      timestamp: timestamp,
      hasPosition: hasPosition,
      lat: 0.0,
      lon: 0.0,
      acc: 0.0,
      address: address,
      weather: weather,
      showWeather: showWeather,
      showAccuracy: showAccuracy,
      showAddress: showAddress,
      showCoordinates: showCoordinates,
      opacity: 1.0,
      showBorder: true,
      fontSize: fontSize,
    );
    return dummyPainter._computeHeight(canvasSize);
  }

  /// Versi sinkron untuk keperluan layout (dipanggil di build)
  double computeHeightSync(Size canvasSize) {
    return _computeHeight(canvasSize);
  }

  double _computeHeight(Size canvasSize) {
    final baseWidth = 320.0;
    final scale = (canvasSize.width / baseWidth).clamp(0.75, 1.4);
    final padX = 20.0 * scale;
    double totalHeight = 18 * scale; // initial cy

    final fsMultiplier = fontSize == 'small'
        ? 0.82
        : fontSize == 'large'
            ? 1.22
            : 1.0;

    double simulateTextHeight(String text, double fontSizePt, int maxLines) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: fontSizePt, height: 1.25),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: maxLines,
      );
      tp.layout(maxWidth: canvasSize.width - padX * 2);
      return tp.height;
    }

    // Date
    double dateHeight = simulateTextHeight(
        DateFormat('EEE, dd MMM yyyy').format(timestamp), 14 * fsMultiplier, 1);
    totalHeight += dateHeight + (8 * scale);

    // Time
    double timeHeight = simulateTextHeight(
        DateFormat('HH:mm:ss').format(timestamp), 29 * fsMultiplier, 1);
    totalHeight += timeHeight + (8 * scale);

    // Line
    totalHeight += 18 * scale;

    // Coordinate
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      double coordHeight = simulateTextHeight(
          '📍 ${lat!.toStringAsFixed(5)}, ${lon!.toStringAsFixed(5)}',
          12.5 * fsMultiplier, 1);
      totalHeight += coordHeight + (8 * scale);
    }

    // Accuracy
    if (showAccuracy && hasPosition && acc != null) {
      double accHeight = simulateTextHeight(
          '🎯 Accuracy ±${acc!.toStringAsFixed(1)}m', 11.5 * fsMultiplier, 1);
      totalHeight += accHeight + (8 * scale);
    }

    // Address
    if (showAddress && address.isNotEmpty) {
      double addrHeight = simulateTextHeight('🏠 $address', 12.5 * fsMultiplier, 3);
      totalHeight += addrHeight + (8 * scale);
    }

    // Weather
    if (showWeather && weather.isNotEmpty) {
      double weatherHeight = simulateTextHeight('☁ $weather', 12.5 * fsMultiplier, 2);
      totalHeight += weatherHeight + (8 * scale);
    }

    return totalHeight + 16.0; // extra bottom padding
  }

  @override
  void paint(Canvas canvas, Size size) {
    final baseWidth = 320.0;
    final scale = (size.width / baseWidth).clamp(0.75, 1.4);
    final padX = 20.0 * scale;

    final fsMultiplier = fontSize == 'small'
        ? 0.82
        : fontSize == 'large'
            ? 1.22
            : 1.0;

    double cy = 18 * scale;

    void drawText({
      required String text,
      required double size,
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
            fontSize: size,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            height: 1.25,
            letterSpacing: spacing,
            fontFamily: 'Roboto',
            shadows: const [
              Shadow(blurRadius: 3, color: Colors.black54, offset: Offset(1, 1))
            ],
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
    drawText(
      text: DateFormat('EEE, dd MMM yyyy').format(timestamp),
      size: 14 * fsMultiplier,
      color: Colors.white70,
      spacing: 0.3,
    );

    // Time
    drawText(
      text: DateFormat('HH:mm:ss').format(timestamp),
      size: 29 * fsMultiplier,
      color: Colors.white,
      bold: true,
      spacing: 0.9,
    );

    // Garis pemisah
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.10)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(padX, cy),
      Offset(size.width - padX, cy),
      linePaint,
    );
    cy += 18 * scale;

    // Coordinate
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      drawText(
        text:
            '📍 ${lat!.toStringAsFixed(5)}, ${lon!.toStringAsFixed(5)}',
        size: 12.5 * fsMultiplier,
        color: const Color(0xFF64B5F6),
        maxLines: 1,
      );
    }

    // Accuracy
    if (showAccuracy && hasPosition && acc != null) {
      drawText(
        text: '🎯 Accuracy ±${acc!.toStringAsFixed(1)}m',
        size: 11.5 * fsMultiplier,
        color: Colors.white60,
        maxLines: 1,
      );
    }

    // Address
    if (showAddress && address.isNotEmpty) {
      drawText(
        text: '🏠 $address',
        size: 12.5 * fsMultiplier,
        color: Colors.white70,
        maxLines: 3,
      );
    }

    // Weather
    if (showWeather && weather.isNotEmpty) {
      drawText(
        text: '☁ $weather',
        size: 12.5 * fsMultiplier,
        color: const Color(0xFF4FC3F7),
        maxLines: 2,
      );
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
        old.fontSize != fontSize;
  }
}
