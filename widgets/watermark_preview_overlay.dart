import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';
import '../services/settings_cache.dart';
import '../watermark/layouts/watermark_layout_base.dart';

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
  bool _showMiniMap = false; // skip mini map untuk preview

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
    final fontSize = await SettingsCache.fontSize;
    // Konversi double ke string
    final fontSizeStr = fontSize <= 13 ? 'small' : fontSize >= 20 ? 'large' : 'normal';

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

    return CustomPaint(
      size: widget.previewSize,
      painter: _getPainter(),
    );
  }

  CustomPainter _getPainter() {
    switch (_currentLayout!) {
      case WatermarkLayout.cinematic:
        return CinematicPreviewPainter(
          size: widget.previewSize,
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
      // Tambahkan case untuk layout lain jika diperlukan
      default:
        return const _EmptyPainter();
    }
  }
}

class _EmptyPainter extends CustomPainter {
  const _EmptyPainter();
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Painter untuk LayoutCinematic ─────────────────────────────────────
class CinematicPreviewPainter extends CustomPainter {
  final Size size;
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
    required this.size,
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

    // Hitung baris
    int rowCount = 2;
    if (showCoordinates && hasPosition) rowCount++;
    if (showAccuracy && hasPosition) rowCount++;
    if (showAddress && address.isNotEmpty && !address.startsWith('GPS:')) rowCount += 2;
    if (showWeather && weather.isNotEmpty) rowCount++;

    final double panelH = padY * 2 + rowCount * rowH + 20;
    final double y0 = size.height - panelH - margin;
    final double x0 = margin;
    final double panelW = size.width - margin * 2;

    // Background panel
    final Paint bgPaint = Paint()..color = Colors.black.withOpacity(opacity.clamp(0.0, 1.0));
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

    // Helper draw text
    void drawText(String text, double x, double y, Color color, {bool bold = false, double size = 16}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontFamily: 'Roboto'),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(x, y));
    }

    // Tanggal
    final dateStr = DateFormat('EEE, dd MMM yyyy').format(timestamp);
    drawText(dateStr, x0 + padX, cy, Colors.white, size: 16);
    cy += rowH;

    // Waktu
    final timeStr = DateFormat('HH:mm:ss').format(timestamp);
    drawText(timeStr, x0 + padX, cy, Colors.white, bold: true, size: 22);
    cy += rowH;

    // Koordinat
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final coord = '${lat.toStringAsFixed(5)}°, ${lon.toStringAsFixed(5)}°';
      drawText(coord, x0 + padX, cy, const Color(0xFF1E90FF), size: 13);
      cy += smallRowH;
    }

    // Akurasi
    if (showAccuracy && hasPosition && acc != null) {
      final accStr = 'Akurasi ±${acc.toStringAsFixed(1)}m';
      drawText(accStr, x0 + padX, cy, Colors.grey.shade400, size: 13);
      cy += smallRowH;
    }

    // Alamat
    if (showAddress && address.isNotEmpty && !address.startsWith('GPS:')) {
      final maxChars = 45;
      final List<String> lines = _wrapText(address, maxChars);
      for (int i = 0; i < lines.length && i < 2; i++) {
        drawText(lines[i], x0 + padX, cy, Colors.white70, size: 13);
        cy += smallRowH;
      }
    }

    // Cuaca
    if (showWeather && weather.isNotEmpty) {
      drawText(weather, x0 + padX, cy, const Color(0xFF1E90FF), size: 13);
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
