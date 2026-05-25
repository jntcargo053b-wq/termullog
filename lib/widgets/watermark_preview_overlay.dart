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
  }
}

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
    final double margin = 16 * scale;
    final double padX = 24 * scale;
    final double padY = 20 * scale;
    
    // Perbesar tinggi baris agar teks tidak tumpang tindih
    final double rowH = 38 * scale;      // untuk tanggal & waktu
    final double smallRowH = 30 * scale; // untuk koordinat, akurasi, alamat, cuaca
    
    final double fsMultiplier = fontSize == 'small' ? 0.75 : fontSize == 'large' ? 1.4 : 1.0;
    final double radius = 16 * scale;

    // Hitung jumlah baris secara akurat
    int rowCount = 2; // tanggal + waktu
    if (showCoordinates && hasPosition && lat != null && lon != null) rowCount++;
    if (showAccuracy && hasPosition && acc != null) rowCount++;
    
    int addressLines = 0;
    if (showAddress && address.isNotEmpty && !address.startsWith('GPS:')) {
      addressLines = _wrapText(address, 45).length;
      if (addressLines > 2) addressLines = 2;
      rowCount += addressLines;
    }
    
    if (showWeather && weather.isNotEmpty) rowCount++;
    
    // Garis pemisah + ruang ekstra
    final double separatorSpace = 12 * scale;
    final double bottomPadding = 16 * scale;
    
    final double panelH = padY * 2 + 
                          (rowCount - 2) * smallRowH + 
                          2 * rowH + 
                          separatorSpace + 
                          bottomPadding;
    
    double y0 = size.height - panelH - margin;
    if (y0 < margin) y0 = margin; // safety
    final double x0 = margin;
    final double panelW = size.width - margin * 2;

    // Background
    final RRect bgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x0, y0, panelW, panelH), Radius.circular(radius));
    final Paint bgPaint = Paint()..color = Colors.black.withOpacity(opacity);
    canvas.drawRRect(bgRect, bgPaint);

    // Border
    if (showBorder) {
      final Paint borderPaint = Paint()
        ..color = Colors.white.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRRect(bgRect, borderPaint);
    }

    double cy = y0 + padY;

    void drawText(String text, double x, double y, Color color,
        {bool bold = false, double size = 16}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: size,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontFamily: 'Roboto',
            shadows: const [Shadow(offset: Offset(1, 1), color: Colors.black54)],
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(x, y));
    }

    // Tanggal
    drawText(DateFormat('EEE, dd MMM yyyy').format(timestamp),
        x0 + padX, cy, Colors.white, size: 16 * fsMultiplier);
    cy += rowH;

    // Waktu
    drawText(DateFormat('HH:mm:ss').format(timestamp),
        x0 + padX, cy, Colors.white, bold: true, size: 22 * fsMultiplier);
    cy += rowH;

    // Garis pemisah
    final Paint linePaint = Paint()..color = Colors.white24..strokeWidth = 1;
    canvas.drawLine(Offset(x0 + padX, cy), Offset(x0 + panelW - padX, cy), linePaint);
    cy += separatorSpace;

    // Koordinat
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      drawText('${lat!.toStringAsFixed(5)}°, ${lon!.toStringAsFixed(5)}°',
          x0 + padX, cy, const Color(0xFF1E90FF), size: 13 * fsMultiplier);
      cy += smallRowH;
    }

    // Akurasi
    if (showAccuracy && hasPosition && acc != null) {
      drawText('Akurasi ±${acc!.toStringAsFixed(1)}m',
          x0 + padX, cy, Colors.grey[400]!, size: 13 * fsMultiplier);
      cy += smallRowH;
    }

    // Alamat
    if (showAddress && address.isNotEmpty && !address.startsWith('GPS:')) {
      final lines = _wrapText(address, 45);
      for (int i = 0; i < lines.length && i < 2; i++) {
        drawText(lines[i], x0 + padX, cy, Colors.white70, size: 13 * fsMultiplier);
        cy += smallRowH;
      }
    }

    // Cuaca
    if (showWeather && weather.isNotEmpty) {
      drawText(weather, x0 + padX, cy, const Color(0xFF1E90FF), size: 13 * fsMultiplier);
      // tidak perlu cy += karena terakhir
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
