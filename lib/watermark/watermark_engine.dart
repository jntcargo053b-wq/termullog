// lib/watermark/watermark_engine.dart
// ============================================================
// WATERMARK ENGINE — POD Edition
// ============================================================

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import 'watermark_params.dart';
import 'watermark_layout.dart';

class WatermarkEngine {
  // Constants
  static const double _panelPadding = 12.0;
  static const double _panelMargin = 16.0;
  static const double _lineHeight = 1.2;
  static const int _mapSize = 120;
  
  /// Main entry point: add watermark to image
  static Future<Uint8List> process(WatermarkParams params) async {
    // Decode original image
    final originalImg = img.decodeImage(params.imageBytes);
    if (originalImg == null) {
      throw Exception('Failed to decode image');
    }
    
    // Get dimensions
    final width = originalImg.width;
    final height = originalImg.height;
    
    // Create UI image from bytes
    final uiImage = await _decodeUiImage(params.imageBytes);
    
    // Create recorder for drawing
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    
    // Draw original image
    canvas.drawImage(uiImage, Offset.zero, Paint());
    
    // Draw watermark based on layout
    switch (WatermarkLayout.values[params.layoutIndex]) {
      case WatermarkLayout.timemarkClassic:
        _drawClassicWatermark(canvas, width, height, params);
        break;
      case WatermarkLayout.timemarkMinimal:
        _drawMinimalWatermark(canvas, width, height, params);
        break;
      case WatermarkLayout.timemarkCard:
        _drawCardWatermark(canvas, width, height, params);
        break;
      case WatermarkLayout.timemarkHUD:
        _drawHudWatermark(canvas, width, height, params);
        break;
      case WatermarkLayout.timemarkFilm:
        _drawFilmWatermark(canvas, width, height, params);
        break;
    }
    
    // Finalize picture
    final picture = recorder.endRecording();
    final uiImageOutput = await picture.toImage(width, height);
    final byteData = await uiImageOutput.toByteData(format: ui.ImageByteFormat.png);
    
    if (byteData == null) {
      throw Exception('Failed to encode image');
    }
    
    // Convert to JPEG
    final jpegImg = img.decodeImage(byteData.buffer.asUint8List());
    if (jpegImg == null) {
      throw Exception('Failed to decode processed image');
    }
    
    return Uint8List.fromList(img.encodeJpg(jpegImg, quality: params.imageQuality));
  }
  
  static Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (image) {
      completer.complete(image);
    });
    return completer.future;
  }
  
  // ═══════════════════════════════════════════════════════════════
  // Classic Layout
  // ═══════════════════════════════════════════════════════════════
  
  static void _drawClassicWatermark(
    Canvas canvas,
    int width,
    int height,
    WatermarkParams p,
  ) {
    final panelWidth = width * 0.92;
    final panelHeight = _calculatePanelHeight(p);
    final panelX = (width - panelWidth) / 2;
    final panelY = height - panelHeight - _panelMargin;
    
    // Draw background panel
    final bgPaint = Paint()
      ..color = Color((0xCC000000 * p.opacity).round())
      ..style = PaintingStyle.fill;
    
    if (p.showBorder) {
      final borderPaint = Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(panelX, panelY, panelWidth, panelHeight),
          Radius.circular(12),
        ),
        bgPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(panelX, panelY, panelWidth, panelHeight),
          Radius.circular(12),
        ),
        borderPaint,
      );
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(panelX, panelY, panelWidth, panelHeight),
          Radius.circular(12),
        ),
        bgPaint,
      );
    }
    
    // Draw content
    var yOffset = panelY + _panelPadding;
    
    // Timestamp
    final timestamp = _formatTimestamp(p.timestamp, p.dateFormat, p.timeFormat);
    _drawText(canvas, timestamp, panelX + _panelPadding, yOffset, Colors.white,
        fontSize: _getFontSize(p.fontSize), bold: true);
    yOffset += _getFontSize(p.fontSize) * _lineHeight;
    
    // Address
    if (p.showAddress && p.address.isNotEmpty) {
      _drawText(canvas, p.address, panelX + _panelPadding, yOffset, Colors.white70,
          fontSize: _getFontSize(p.fontSize) * 0.85);
      yOffset += _getFontSize(p.fontSize) * 0.85 * _lineHeight;
    }
    
    // Coordinates
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final coordText = _formatCoordinates(p.lat!, p.lon!);
      _drawText(canvas, coordText, panelX + _panelPadding, yOffset, Colors.white70,
          fontSize: _getFontSize(p.fontSize) * 0.8);
      yOffset += _getFontSize(p.fontSize) * 0.8 * _lineHeight;
    }
    
    // Accuracy
    if (p.showAccuracy && p.acc != null) {
      final accText = 'Akurasi: ±${p.acc!.toStringAsFixed(0)}m';
      final accColor = _getAccuracyColor(p.acc!);
      _drawText(canvas, accText, panelX + _panelPadding, yOffset, accColor,
          fontSize: _getFontSize(p.fontSize) * 0.8);
      yOffset += _getFontSize(p.fontSize) * 0.8 * _lineHeight;
    }
    
    // Weather
    if (p.showWeather && p.weather.isNotEmpty) {
      _drawText(canvas, p.weather, panelX + _panelPadding, yOffset, Colors.white70,
          fontSize: _getFontSize(p.fontSize) * 0.9);
    }
    
    // Mini map
    if (p.showMiniMap && p.mapBytes != null) {
      _drawMiniMap(canvas, panelX + panelWidth - _mapSize - _panelPadding,
          panelY + _panelPadding, p.mapBytes!);
    }
  }
  
  // ═══════════════════════════════════════════════════════════════
  // Minimal Layout
  // ═══════════════════════════════════════════════════════════════
  
  static void _drawMinimalWatermark(
    Canvas canvas,
    int width,
    int height,
    WatermarkParams p,
  ) {
    final padding = 12.0;
    var yOffset = height - padding;
    
    // Timestamp (bottom-left)
    final timestamp = _formatTimestamp(p.timestamp, p.dateFormat, p.timeFormat);
    _drawText(canvas, timestamp, padding, yOffset, Colors.white,
        fontSize: _getFontSize(p.fontSize) * 0.9, bold: true,
        backgroundColor: Colors.black54);
    yOffset -= _getFontSize(p.fontSize) * 0.9 * _lineHeight;
    
    // Address (if space)
    if (p.showAddress && p.address.isNotEmpty) {
      _drawText(canvas, p.address, padding, yOffset, Colors.white70,
          fontSize: _getFontSize(p.fontSize) * 0.75,
          backgroundColor: Colors.black54);
    }
  }
  
  // ═══════════════════════════════════════════════════════════════
  // Card Layout
  // ═══════════════════════════════════════════════════════════════
  
  static void _drawCardWatermark(
    Canvas canvas,
    int width,
    int height,
    WatermarkParams p,
  ) {
    final cardWidth = width * 0.88;
    final cardHeight = _calculatePanelHeight(p);
    final cardX = (width - cardWidth) / 2;
    final cardY = height - cardHeight - _panelMargin;
    
    // Draw card with gradient
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xDD1565C0), Color(0xDD0D47A1)],
    );
    
    final bgPaint = Paint()
      ..shader = gradient.createShader(Rect.fromLTWH(cardX, cardY, cardWidth, cardHeight));
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cardX, cardY, cardWidth, cardHeight),
        Radius.circular(16),
      ),
      bgPaint,
    );
    
    // Content
    var yOffset = cardY + _panelPadding;
    
    final timestamp = _formatTimestamp(p.timestamp, p.dateFormat, p.timeFormat);
    _drawText(canvas, timestamp, cardX + _panelPadding, yOffset, Colors.white,
        fontSize: _getFontSize(p.fontSize) * 1.0, bold: true);
    yOffset += _getFontSize(p.fontSize) * _lineHeight;
    
    if (p.showAddress && p.address.isNotEmpty) {
      _drawText(canvas, p.address, cardX + _panelPadding, yOffset, Colors.white70,
          fontSize: _getFontSize(p.fontSize) * 0.85);
      yOffset += _getFontSize(p.fontSize) * 0.85 * _lineHeight;
    }
    
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final coordText = _formatCoordinates(p.lat!, p.lon!);
      _drawText(canvas, coordText, cardX + _panelPadding, yOffset, Colors.white70,
          fontSize: _getFontSize(p.fontSize) * 0.8);
    }
  }
  
  // ═══════════════════════════════════════════════════════════════
  // HUD Layout
  // ═══════════════════════════════════════════════════════════════
  
  static void _drawHudWatermark(
    Canvas canvas,
    int width,
    int height,
    WatermarkParams p,
  ) {
    final padding = 12.0;
    
    // Top-left: timestamp
    final timestamp = _formatTimestamp(p.timestamp, p.dateFormat, p.timeFormat);
    _drawText(canvas, timestamp, padding, padding, Colors.cyanAccent,
        fontSize: _getFontSize(p.fontSize) * 0.8, bold: true);
    
    // Top-right: weather
    if (p.showWeather && p.weather.isNotEmpty) {
      final weatherWidth = _measureText(p.weather, _getFontSize(p.fontSize) * 0.8);
      _drawText(canvas, p.weather, width - weatherWidth - padding, padding, Colors.cyanAccent,
          fontSize: _getFontSize(p.fontSize) * 0.8);
    }
    
    // Bottom-left: coordinates
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final coordText = _formatCoordinates(p.lat!, p.lon!);
      _drawText(canvas, coordText, padding, height - padding - 20, Colors.cyanAccent,
          fontSize: _getFontSize(p.fontSize) * 0.7, backgroundColor: Colors.black54);
    }
    
    // Bottom-right: accuracy
    if (p.showAccuracy && p.acc != null) {
      final accText = '±${p.acc!.toStringAsFixed(0)}m';
      final accWidth = _measureText(accText, _getFontSize(p.fontSize) * 0.7);
      final accColor = _getAccuracyColor(p.acc!);
      _drawText(canvas, accText, width - accWidth - padding, height - padding - 20, accColor,
          fontSize: _getFontSize(p.fontSize) * 0.7, backgroundColor: Colors.black54);
    }
    
    // Center: address (transparent)
    if (p.showAddress && p.address.isNotEmpty) {
      final addressWidth = _measureText(p.address, _getFontSize(p.fontSize) * 0.8);
      _drawText(canvas, p.address, (width - addressWidth) / 2, height - 40, Colors.white70,
          fontSize: _getFontSize(p.fontSize) * 0.8, backgroundColor: Colors.black54);
    }
  }
  
  // ═══════════════════════════════════════════════════════════════
  // Film Layout
  // ═══════════════════════════════════════════════════════════════
  
  static void _drawFilmWatermark(
    Canvas canvas,
    int width,
    int height,
    WatermarkParams p,
  ) {
    final barHeight = 48.0;
    final barY = height - barHeight;
    
    // Draw film strip bar
    final bgPaint = Paint()..color = Color(0xDD000000);
    canvas.drawRect(Rect.fromLTWH(0, barY, width.toDouble(), barHeight), bgPaint);
    
    // Draw perforations (film strip holes)
    final holePaint = Paint()..color = Colors.black;
    for (var x = 10.0; x < width; x += 30) {
      canvas.drawCircle(Offset(x, barY - 5), 3, holePaint);
      canvas.drawCircle(Offset(x, barY + barHeight + 5), 3, holePaint);
    }
    
    // Draw text
    var xOffset = 16.0;
    final yPos = barY + barHeight / 2;
    
    final timestamp = _formatTimestamp(p.timestamp, p.dateFormat, p.timeFormat);
    _drawText(canvas, timestamp, xOffset, yPos, Colors.white,
        fontSize: _getFontSize(p.fontSize) * 0.9, bold: true);
    xOffset += _measureText(timestamp, _getFontSize(p.fontSize) * 0.9) + 20;
    
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final coordText = _formatCoordinatesShort(p.lat!, p.lon!);
      _drawText(canvas, coordText, xOffset, yPos, Colors.white70,
          fontSize: _getFontSize(p.fontSize) * 0.8);
      xOffset += _measureText(coordText, _getFontSize(p.fontSize) * 0.8) + 20;
    }
    
    if (p.showAccuracy && p.acc != null) {
      final accText = '±${p.acc!.toStringAsFixed(0)}m';
      final accColor = _getAccuracyColor(p.acc!);
      _drawText(canvas, accText, xOffset, yPos, accColor,
          fontSize: _getFontSize(p.fontSize) * 0.8);
    }
  }
  
  // ═══════════════════════════════════════════════════════════════
  // Helper Methods
  // ═══════════════════════════════════════════════════════════════
  
  static double _calculatePanelHeight(WatermarkParams p) {
    double height = 0;
    height += _getFontSize(p.fontSize) * _lineHeight; // timestamp
    if (p.showAddress && p.address.isNotEmpty) height += _getFontSize(p.fontSize) * 0.85 * _lineHeight;
    if (p.showCoordinates && p.lat != null) height += _getFontSize(p.fontSize) * 0.8 * _lineHeight;
    if (p.showAccuracy && p.acc != null) height += _getFontSize(p.fontSize) * 0.8 * _lineHeight;
    if (p.showWeather && p.weather.isNotEmpty) height += _getFontSize(p.fontSize) * 0.9 * _lineHeight;
    return height + (_panelPadding * 2);
  }
  
  static double _getFontSize(String size) {
    switch (size) {
      case 'small': return 12.0;
      case 'large': return 18.0;
      default: return 14.0;
    }
  }
  
  static String _formatTimestamp(DateTime time, String dateFormat, String timeFormat) {
    final date = DateFormat(dateFormat).format(time);
    final timeStr = DateFormat(timeFormat).format(time);
    return '$date  $timeStr';
  }
  
  static String _formatCoordinates(double lat, double lon) {
    return '${lat.toStringAsFixed(6)}°, ${lon.toStringAsFixed(6)}°';
  }
  
  static String _formatCoordinatesShort(double lat, double lon) {
    return '${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°';
  }
  
  static Color _getAccuracyColor(double accuracy) {
    if (accuracy <= 5) return const Color(0xFF2E7D32); // Green
    if (accuracy <= 15) return const Color(0xFFE65100); // Orange
    return const Color(0xFFC62828); // Red
  }
  
  static void _drawText(
    Canvas canvas,
    String text,
    double x,
    double y,
    Color color, {
    double fontSize = 14.0,
    bool bold = false,
    Color? backgroundColor,
  }) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        fontFamily: 'monospace',
        shadows: backgroundColor != null
            ? [
                Shadow(
                  color: backgroundColor,
                  offset: Offset(0.5, 0.5),
                ),
              ]
            : null,
      ),
    );
    
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    textPainter.paint(canvas, Offset(x, y - textPainter.height));
  }
  
  static double _measureText(String text, double fontSize) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(fontSize: fontSize, fontFamily: 'monospace'),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    return textPainter.width;
  }
  
  static void _drawMiniMap(Canvas canvas, double x, double y, Uint8List mapBytes) async {
    // Note: This is synchronous, so we need to handle async differently
    // For now, we'll skip dynamic map drawing in this version
    // Map should be drawn before calling this method
  }
}
