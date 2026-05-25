// lib/widgets/watermark_preview_overlay.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/settings_cache.dart';
import '../core/constants.dart';

class WatermarkPreviewOverlay extends StatefulWidget {
  final Size previewSize;
  final DateTime timestamp;
  final bool hasPosition;
  final double? lat;
  final double? lon;
  final double? acc;
  final String address;
  final String weather;

  const WatermarkPreviewOverlay({
    super.key,
    required this.previewSize,
    required this.timestamp,
    required this.hasPosition,
    this.lat,
    this.lon,
    this.acc,
    this.address = '',
    this.weather = '',
  });

  @override
  State<WatermarkPreviewOverlay> createState() => _WatermarkPreviewOverlayState();
}

class _WatermarkPreviewOverlayState extends State<WatermarkPreviewOverlay> {
  WatermarkLayout? _currentLayout;
  bool _showWeather = true;
  bool _showAccuracy = true;
  bool _showAddress = true;
  bool _showCoordinates = true;
  double _opacity = 0.82;
  bool _showBorder = true;
  String _fontSize = 'normal';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final layout = await SettingsCache.layout;
    final showWeather = await SettingsCache.showWeather;
    final showAccuracy = await SettingsCache.showAccuracy;
    final showAddress = await SettingsCache.showAddress;
    final showCoordinates = await SettingsCache.showCoordinates;
    final opacity = await SettingsCache.opacity;
    final showBorder = await SettingsCache.showBorder;
    final fontSizeDouble = await SettingsCache.fontSize;
    final fontSizeStr = fontSizeDouble <= 13 ? 'small' : fontSizeDouble >= 20 ? 'large' : 'normal';

    if (!mounted) return;
    setState(() {
      _currentLayout = layout;
      _showWeather = showWeather;
      _showAccuracy = showAccuracy;
      _showAddress = showAddress;
      _showCoordinates = showCoordinates;
      _opacity = opacity;
      _showBorder = showBorder;
      _fontSize = fontSizeStr;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentLayout == null) return const SizedBox.shrink();

    // Pilih painter berdasarkan layout yang disimpan
    return IgnorePointer(
      child: CustomPaint(
        size: widget.previewSize,
        painter: _getPainter(),
      ),
    );
  }

  CustomPainter _getPainter() {
    // Gunakan layout yang dipilih user
    switch (_currentLayout) {
      case WatermarkLayout.minimal:
        return MinimalWatermarkPainter(
          timestamp: widget.timestamp,
          hasPosition: widget.hasPosition,
          lat: widget.lat,
          lon: widget.lon,
          acc: widget.acc,
          address: widget.address,
          weather: widget.weather,
          showWeather: _showWeather,
          showAccuracy: _showAccuracy,
          showAddress: _showAddress,
          showCoordinates: _showCoordinates,
          opacity: _opacity,
          showBorder: _showBorder,
          fontSize: _fontSize,
        );
      case WatermarkLayout.classic:
        return ClassicWatermarkPainter(
          timestamp: widget.timestamp,
          hasPosition: widget.hasPosition,
          lat: widget.lat,
          lon: widget.lon,
          acc: widget.acc,
          address: widget.address,
          weather: widget.weather,
          showWeather: _showWeather,
          showAccuracy: _showAccuracy,
          showAddress: _showAddress,
          showCoordinates: _showCoordinates,
          opacity: _opacity,
          showBorder: _showBorder,
          fontSize: _fontSize,
        );
      case WatermarkLayout.cinematic:
      default:
        return ProfessionalWatermarkPainter(
          timestamp: widget.timestamp,
          hasPosition: widget.hasPosition,
          lat: widget.lat,
          lon: widget.lon,
          acc: widget.acc,
          address: widget.address,
          weather: widget.weather,
          showWeather: _showWeather,
          showAccuracy: _showAccuracy,
          showAddress: _showAddress,
          showCoordinates: _showCoordinates,
          opacity: _opacity,
          showBorder: _showBorder,
          fontSize: _fontSize,
        );
    }
  }
}

// ==================== BASE PAINTER (untuk menghindari duplikasi helper) ====================

abstract class BaseWatermarkPainter extends CustomPainter {
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

  const BaseWatermarkPainter({
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

  List<String> wrapText(String text, int maxChars) {
    final words = text.split(' ');
    final lines = <String>[];
    String current = '';
    for (final word in words) {
      if ((current + word).length > maxChars) {
        lines.add(current.trim());
        current = '$word ';
      } else {
        current += '$word ';
      }
    }
    if (current.trim().isNotEmpty) lines.add(current.trim());
    return lines;
  }

  double get fontSizeMultiplier {
    if (fontSize == 'small') return 0.82;
    if (fontSize == 'large') return 1.25;
    return 1.0;
  }

  @override
  bool shouldRepaint(covariant BaseWatermarkPainter old) {
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
        old.opacity != opacity ||
        old.showBorder != showBorder ||
        old.fontSize != fontSize;
  }
}

// ==================== PROFESSIONAL / CINEMATIC PAINTER ====================

class ProfessionalWatermarkPainter extends BaseWatermarkPainter {
  const ProfessionalWatermarkPainter({
    required super.timestamp,
    required super.hasPosition,
    super.lat,
    super.lon,
    super.acc,
    required super.address,
    required super.weather,
    required super.showWeather,
    required super.showAccuracy,
    required super.showAddress,
    required super.showCoordinates,
    required super.opacity,
    required super.showBorder,
    required super.fontSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double maxAddressChars = 38;
    final scale = size.width / 1080;
    final margin = 18 * scale;
    final panelW = size.width * 0.92;
    final panelX = (size.width - panelW) / 2;
    final radius = 26 * scale;
    final padX = 26 * scale;
    final padY = 24 * scale;

    final fsMult = fontSizeMultiplier;

    List<String> addressLines = [];
    if (showAddress && address.isNotEmpty && !address.startsWith('GPS:')) {
      addressLines = wrapText(address, maxAddressChars);
      if (addressLines.length > 2) addressLines = addressLines.sublist(0, 2);
    }

    // Hitung tinggi konten
    double contentHeight = 0;
    contentHeight += 30 * scale; // date
    contentHeight += 50 * scale; // time
    contentHeight += 18 * scale; // separator line
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      contentHeight += 28 * scale;
    }
    if (showAccuracy && hasPosition && acc != null) {
      contentHeight += 24 * scale;
    }
    if (addressLines.isNotEmpty) {
      contentHeight += addressLines.length * 24 * scale;
    }
    if (showWeather && weather.isNotEmpty) {
      contentHeight += 24 * scale;
    }

    final panelH = contentHeight + padY * 2;
    final panelY = size.height - panelH - margin;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(panelX, panelY, panelW, panelH),
      Radius.circular(radius),
    );

    // Shadow
    canvas.drawShadow(Path()..addRRect(rect), Colors.black, 12, true);

    // Background gradient
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(panelX, panelY),
        Offset(panelX, panelY + panelH),
        [Colors.black.withOpacity(opacity), Colors.black.withOpacity(opacity - 0.08)],
      );
    canvas.drawRRect(rect, bgPaint);

    // Border
    if (showBorder) {
      final border = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withOpacity(0.15);
      canvas.drawRRect(rect, border);
    }

    double cy = panelY + padY;

    void drawText(String text, double fontSize, Color color, {bool bold = false, double spacing = 0}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            height: 1.22,
            letterSpacing: spacing,
            fontFamily: 'Roboto',
            shadows: const [Shadow(blurRadius: 3, color: Colors.black54, offset: Offset(1, 1))],
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 2,
        ellipsis: '...',
      );
      tp.layout(maxWidth: panelW - padX * 2);
      tp.paint(canvas, Offset(panelX + padX, cy));
    }

    // Date
    drawText(DateFormat('EEE, dd MMM yyyy').format(timestamp), 15 * fsMult, Colors.white70, spacing: 0.3);
    cy += 32 * scale;

    // Time
    drawText(DateFormat('HH:mm:ss').format(timestamp), 31 * fsMult, Colors.white, bold: true, spacing: 1.1);
    cy += 48 * scale;

    // Separator line
    final linePaint = Paint()..color = Colors.white10..strokeWidth = 1;
    canvas.drawLine(Offset(panelX + padX, cy), Offset(panelX + panelW - padX, cy), linePaint);
    cy += 18 * scale;

    // Coordinates
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      drawText('${lat!.toStringAsFixed(5)}, ${lon!.toStringAsFixed(5)}', 13 * fsMult, const Color(0xFF64B5F6));
      cy += 28 * scale;
    }

    // Accuracy
    if (showAccuracy && hasPosition && acc != null) {
      drawText('Accuracy ±${acc!.toStringAsFixed(1)}m', 12 * fsMult, Colors.white60);
      cy += 24 * scale;
    }

    // Address
    for (final line in addressLines) {
      drawText(line, 13 * fsMult, Colors.white70);
      cy += 24 * scale;
    }

    // Weather
    if (showWeather && weather.isNotEmpty) {
      drawText(weather, 13 * fsMult, const Color(0xFF4FC3F7));
      // no need to increment cy after last element
    }

    // Jika GPS belum fix, tampilkan pesan
    if (!hasPosition && showAddress) {
      drawText('Mencari lokasi GPS...', 13 * fsMult, Colors.white54);
    }
  }
}

// ==================== MINIMAL PAINTER ====================

class MinimalWatermarkPainter extends BaseWatermarkPainter {
  const MinimalWatermarkPainter({
    required super.timestamp,
    required super.hasPosition,
    super.lat,
    super.lon,
    super.acc,
    required super.address,
    required super.weather,
    required super.showWeather,
    required super.showAccuracy,
    required super.showAddress,
    required super.showCoordinates,
    required super.opacity,
    required super.showBorder,
    required super.fontSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 1080;
    final margin = 12 * scale;
    final padX = 16 * scale;
    final padY = 12 * scale;
    final radius = 12 * scale;
    final fsMult = fontSizeMultiplier;

    final panelW = size.width * 0.88;
    final panelX = (size.width - panelW) / 2;

    // Hitung tinggi
    double contentHeight = 0;
    contentHeight += 24 * scale; // time
    if (showCoordinates && hasPosition && lat != null && lon != null) contentHeight += 20 * scale;
    if (showAddress && address.isNotEmpty && !address.startsWith('GPS:')) contentHeight += 20 * scale;
    if (showWeather && weather.isNotEmpty) contentHeight += 20 * scale;

    final panelH = contentHeight + padY * 2;
    final panelY = size.height - panelH - margin;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(panelX, panelY, panelW, panelH),
      Radius.circular(radius),
    );

    final bgPaint = Paint()..color = Colors.black.withOpacity(opacity);
    canvas.drawRRect(rect, bgPaint);

    if (showBorder) {
      final border = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withOpacity(0.2);
      canvas.drawRRect(rect, border);
    }

    double cy = panelY + padY;

    void drawText(String text, double fontSize, Color color, {bool bold = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
            fontFamily: 'Roboto',
            shadows: const [Shadow(offset: Offset(1, 1), color: Colors.black54)],
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(panelX + padX, cy));
    }

    // Time
    drawText(DateFormat('HH:mm:ss').format(timestamp), 20 * fsMult, Colors.white, bold: true);
    cy += 26 * scale;

    // Coordinates
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      drawText('${lat!.toStringAsFixed(4)}, ${lon!.toStringAsFixed(4)}', 11 * fsMult, const Color(0xFF64B5F6));
      cy += 22 * scale;
    }

    // Address (single line)
    if (showAddress && address.isNotEmpty && !address.startsWith('GPS:')) {
      String shortAddr = address.length > 35 ? '${address.substring(0, 35)}...' : address;
      drawText(shortAddr, 11 * fsMult, Colors.white70);
      cy += 22 * scale;
    }

    // Weather
    if (showWeather && weather.isNotEmpty) {
      drawText(weather, 11 * fsMult, const Color(0xFF4FC3F7));
    }

    if (!hasPosition && showAddress) {
      drawText('Mencari GPS...', 11 * fsMult, Colors.white54);
    }
  }
}

// ==================== CLASSIC PAINTER ====================

class ClassicWatermarkPainter extends BaseWatermarkPainter {
  const ClassicWatermarkPainter({
    required super.timestamp,
    required super.hasPosition,
    super.lat,
    super.lon,
    super.acc,
    required super.address,
    required super.weather,
    required super.showWeather,
    required super.showAccuracy,
    required super.showAddress,
    required super.showCoordinates,
    required super.opacity,
    required super.showBorder,
    required super.fontSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const int maxAddressChars = 45;
    final scale = size.width / 1080;
    final margin = 16 * scale;
    final padX = 20 * scale;
    final padY = 16 * scale;
    final radius = 20 * scale;
    final fsMult = fontSizeMultiplier;

    final panelW = size.width * 0.9;
    final panelX = (size.width - panelW) / 2;

    List<String> addressLines = [];
    if (showAddress && address.isNotEmpty && !address.startsWith('GPS:')) {
      addressLines = wrapText(address, maxAddressChars);
      if (addressLines.length > 2) addressLines = addressLines.sublist(0, 2);
    }

    // Hitung tinggi
    double contentHeight = 0;
    contentHeight += 28 * scale; // date
    contentHeight += 36 * scale; // time
    if (showCoordinates && hasPosition && lat != null && lon != null) contentHeight += 24 * scale;
    if (showAccuracy && hasPosition && acc != null) contentHeight += 24 * scale;
    if (addressLines.isNotEmpty) contentHeight += addressLines.length * 22 * scale;
    if (showWeather && weather.isNotEmpty) contentHeight += 24 * scale;

    final panelH = contentHeight + padY * 2;
    final panelY = size.height - panelH - margin;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(panelX, panelY, panelW, panelH),
      Radius.circular(radius),
    );

    final bgPaint = Paint()..color = Colors.black.withOpacity(opacity);
    canvas.drawRRect(rect, bgPaint);

    if (showBorder) {
      final border = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withOpacity(0.2);
      canvas.drawRRect(rect, border);
    }

    double cy = panelY + padY;

    void drawText(String text, double fontSize, Color color, {bool bold = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
            fontFamily: 'Roboto',
            shadows: const [Shadow(offset: Offset(1, 1), color: Colors.black54)],
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 2,
        ellipsis: '...',
      );
      tp.layout(maxWidth: panelW - padX * 2);
      tp.paint(canvas, Offset(panelX + padX, cy));
    }

    // Date
    drawText(DateFormat('dd/MM/yyyy').format(timestamp), 13 * fsMult, Colors.white70);
    cy += 28 * scale;

    // Time
    drawText(DateFormat('HH:mm:ss').format(timestamp), 24 * fsMult, Colors.white, bold: true);
    cy += 36 * scale;

    // Coordinates
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      drawText('📍 ${lat!.toStringAsFixed(5)}°, ${lon!.toStringAsFixed(5)}°', 12 * fsMult, const Color(0xFF64B5F6));
      cy += 24 * scale;
    }

    // Accuracy
    if (showAccuracy && hasPosition && acc != null) {
      drawText('🎯 ±${acc!.toStringAsFixed(1)}m', 11 * fsMult, Colors.white60);
      cy += 24 * scale;
    }

    // Address
    for (final line in addressLines) {
      drawText(line, 12 * fsMult, Colors.white70);
      cy += 22 * scale;
    }

    // Weather
    if (showWeather && weather.isNotEmpty) {
      drawText('☁️ $weather', 12 * fsMult, const Color(0xFF4FC3F7));
    }

    if (!hasPosition && showAddress) {
      drawText('Mencari lokasi...', 12 * fsMult, Colors.white54);
    }
  }
}
