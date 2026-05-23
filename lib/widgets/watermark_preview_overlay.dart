import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';
import '../services/settings_cache.dart';

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
  double _opacity = 0.85;
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

    switch (_currentLayout!) {
      case WatermarkLayout.cinematic:
        return CustomPaint(
          size: widget.previewSize,
          painter: CinematicPreviewPainter(
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
          ),
        );
      default:
        return CustomPaint(
          size: widget.previewSize,
          painter: MinimalPreviewPainter(
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
          ),
        );
    }
  }
}

// ─── PAINTER UNTUK LAYOUT CINEMATIC ────────────────────────────────────
class CinematicPreviewPainter extends CustomPainter {
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

  const CinematicPreviewPainter({
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

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.width / 1080;
    final double padX = 24 * scale;
    final double padY = 20 * scale;
    final double rowH = 32 * scale;
    final double smallRowH = 24 * scale;
    final double margin = 12 * scale;
    final double fsMultiplier = fontSize == 'small' ? 0.75 : fontSize == 'large' ? 1.4 : 1.0;

    int rowCount = 2;
    if (showCoordinates && hasPosition) rowCount++;
    if (showAccuracy && hasPosition) rowCount++;
    if (showAddress && address.isNotEmpty && !address.startsWith('GPS:')) rowCount += 2;
    if (showWeather && weather.isNotEmpty) rowCount++;

    final double panelH = padY * 2 + rowCount * rowH + 20;
    final double y0 = size.height - panelH - margin;
    final double x0 = margin;
    final double panelW = size.width - margin * 2;

    // Background
    final Paint bgPaint = Paint()..color = Colors.black.withOpacity(opacity);
    canvas.drawRect(Rect.fromLTWH(x0, y0, panelW, panelH), bgPaint);

    // Border
    if (showBorder) {
      final Paint borderPaint = Paint()
        ..color = Colors.white.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRect(Rect.fromLTWH(x0, y0, panelW, panelH), borderPaint);
    }

    double cy = y0 + padY;

    void drawText(String text, double x, double y, Color color, {bool bold = false, double size = 16}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: size,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontFamily: 'Roboto',
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      tp.layout();
      // Shadow
      final shadowPainter = TextPainter(
        text: TextSpan(text: text, style: TextStyle(color: Colors.black54, fontSize: size, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        textDirection: ui.TextDirection.ltr,
      );
      shadowPainter.layout();
      shadowPainter.paint(canvas, Offset(x + 1, y + 1));
      tp.paint(canvas, Offset(x, y));
    }

    final dateStr = DateFormat('EEE, dd MMM yyyy').format(timestamp);
    drawText(dateStr, x0 + padX, cy, Colors.white, size: 16 * fsMultiplier);
    cy += rowH;

    final timeStr = DateFormat('HH:mm:ss').format(timestamp);
    drawText(timeStr, x0 + padX, cy, Colors.white, bold: true, size: 22 * fsMultiplier);
    cy += rowH;

    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final coord = '${lat!.toStringAsFixed(5)}°, ${lon!.toStringAsFixed(5)}°';
      drawText(coord, x0 + padX, cy, const Color(0xFF1E90FF), size: 13 * fsMultiplier);
      cy += smallRowH;
    }

    if (showAccuracy && hasPosition && acc != null) {
      final accStr = 'Akurasi ±${acc!.toStringAsFixed(1)}m';
      drawText(accStr, x0 + padX, cy, Colors.grey.shade400, size: 13 * fsMultiplier);
      cy += smallRowH;
    }

    if (showAddress && address.isNotEmpty && !address.startsWith('GPS:')) {
      final maxChars = 45;
      final lines = _wrapText(address, maxChars);
      for (int i = 0; i < lines.length && i < 2; i++) {
        drawText(lines[i], x0 + padX, cy, Colors.white70, size: 13 * fsMultiplier);
        cy += smallRowH;
      }
    }

    if (showWeather && weather.isNotEmpty) {
      drawText(weather, x0 + padX, cy, const Color(0xFF1E90FF), size: 13 * fsMultiplier);
    }
  }

  List<String> _wrapText(String text, int maxChars) {
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

  @override
  bool shouldRepaint(CinematicPreviewPainter oldDelegate) {
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
        oldDelegate.fontSize != fontSize;
  }
}

// ─── PAINTER MINIMAL (FALLBACK) ──────────────────────────────────────
class MinimalPreviewPainter extends CustomPainter {
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

  const MinimalPreviewPainter({
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

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.width / 1080;
    final double pad = 16 * scale;
    final double rowH = 28 * scale;
    final double panelH = 80 * scale;
    final double y0 = size.height - panelH - 20;

    final Paint bgPaint = Paint()..color = Colors.black.withOpacity(opacity);
    canvas.drawRect(Rect.fromLTWH(0, y0, size.width, panelH), bgPaint);

    if (showBorder) {
      final Paint borderPaint = Paint()..color = Colors.white30..style = PaintingStyle.stroke..strokeWidth = 1;
      canvas.drawRect(Rect.fromLTWH(0, y0, size.width, panelH), borderPaint);
    }

    void drawText(String text, double x, double y, Color color, {double size = 16}) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontFamily: 'Roboto')),
        textDirection: ui.TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(x, y));
    }

    double y = y0 + pad;
    final dateStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(timestamp);
    drawText(dateStr, pad, y, Colors.white, size: 14 * scale);
    y += rowH;
    if (showCoordinates && hasPosition && lat != null) {
      drawText('${lat!.toStringAsFixed(4)}°, ${lon!.toStringAsFixed(4)}°', pad, y, Colors.white70, size: 12 * scale);
    }
  }

  @override
  bool shouldRepaint(MinimalPreviewPainter oldDelegate) => true;
}
