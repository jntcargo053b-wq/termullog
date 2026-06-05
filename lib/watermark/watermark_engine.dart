// lib/watermark/watermark_engine.dart
// ============================================================
// WATERMARK ENGINE — POD Edition (3 Style: Corporate, Dark Field, Government)
// ============================================================

import 'dart:async';
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
    final layout = WatermarkLayout.values[params.layoutIndex];
    switch (layout) {
      case WatermarkLayout.podCorporate:
        _drawCorporateWatermark(canvas, width, height, params);
        break;
      case WatermarkLayout.podDarkField:
        _drawDarkFieldWatermark(canvas, width, height, params);
        break;
      case WatermarkLayout.podGovern:
        _drawGovernmentWatermark(canvas, width, height, params);
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
  // CORPORATE WATERMARK (Panel putih bersih di bawah foto)
  // ═══════════════════════════════════════════════════════════════
  
  static void _drawCorporateWatermark(
    Canvas canvas,
    int width,
    int height,
    WatermarkParams p,
  ) {
    final panelHeight = _calculatePanelHeight(p);
    final panelY = height - panelHeight - _panelMargin;
    
    // Draw white panel background
    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(p.opacity)
      ..style = PaintingStyle.fill;
    
    canvas.drawRect(
      Rect.fromLTWH(0, panelY, width.toDouble(), panelHeight),
      bgPaint,
    );
    
    // Draw top border accent
    final accentPaint = Paint()
      ..color = const Color(0xFF1565C0)
      ..style = PaintingStyle.fill;
    
    canvas.drawRect(
      Rect.fromLTWH(0, panelY, width.toDouble(), 4),
      accentPaint,
    );
    
    // Content
    var yOffset = panelY + _panelPadding;
    
    // App name / Logo text
    _drawText(canvas, p.appName, _panelPadding, yOffset, const Color(0xFF1565C0),
        fontSize: _getFontSize(p.fontSize) * 1.1, bold: true);
    
    // Timestamp (right-aligned)
    final timestamp = _formatTimestamp(p.timestamp, p.dateFormat, p.timeFormat);
    final timestampWidth = _measureText(timestamp, _getFontSize(p.fontSize) * 0.9);
    _drawText(canvas, timestamp, width - timestampWidth - _panelPadding, yOffset, Colors.grey.shade700,
        fontSize: _getFontSize(p.fontSize) * 0.9);
    
    yOffset += _getFontSize(p.fontSize) * _lineHeight + 4;
    
    // Divider line
    final dividerPaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(_panelPadding, yOffset),
      Offset(width - _panelPadding, yOffset),
      dividerPaint,
    );
    
    yOffset += 8;
    
    // Address
    if (p.showAddress && p.address.isNotEmpty) {
      _drawText(canvas, '📍 ${p.address}', _panelPadding, yOffset, Colors.grey.shade800,
          fontSize: _getFontSize(p.fontSize) * 0.85);
      yOffset += _getFontSize(p.fontSize) * 0.85 * _lineHeight;
    }
    
    // Coordinates and Accuracy in one line
    String locationInfo = '';
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      locationInfo += _formatCoordinates(p.lat!, p.lon!);
    }
    if (p.showAccuracy && p.acc != null) {
      if (locationInfo.isNotEmpty) locationInfo += ' • ';
      locationInfo += '±${p.acc!.toStringAsFixed(0)}m';
    }
    if (locationInfo.isNotEmpty) {
      _drawText(canvas, locationInfo, _panelPadding, yOffset, Colors.grey.shade600,
          fontSize: _getFontSize(p.fontSize) * 0.8);
      yOffset += _getFontSize(p.fontSize) * 0.8 * _lineHeight;
    }
    
    // Weather
    if (p.showWeather && p.weather.isNotEmpty) {
      _drawText(canvas, '🌡️ ${p.weather}', _panelPadding, yOffset, Colors.grey.shade600,
          fontSize: _getFontSize(p.fontSize) * 0.8);
    }
    
    // Hash/Verification line (bottom)
    final hashText = _generateHash(p);
    _drawText(canvas, hashText, _panelPadding, panelY + panelHeight - _panelPadding - 4, Colors.grey.shade400,
        fontSize: _getFontSize(p.fontSize) * 0.65);
  }
  
  // ═══════════════════════════════════════════════════════════════
  // DARK FIELD WATERMARK (Overlay gelap, accent cyan)
  // ═══════════════════════════════════════════════════════════════
  
  static void _drawDarkFieldWatermark(
    Canvas canvas,
    int width,
    int height,
    WatermarkParams p,
  ) {
    final padding = 12.0;
    final barHeight = 52.0;
    final barY = height - barHeight - _panelMargin;
    
    // Draw dark overlay bar
    final bgPaint = Paint()
      ..color = Colors.black.withOpacity(p.opacity)
      ..style = PaintingStyle.fill;
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(_panelMargin, barY, width - (_panelMargin * 2), barHeight),
        const Radius.circular(8),
      ),
      bgPaint,
    );
    
    // Cyan accent line
    final accentPaint = Paint()
      ..color = const Color(0xFF00BCD4)
      ..style = PaintingStyle.fill;
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(_panelMargin, barY, width - (_panelMargin * 2), 3),
        const Radius.circular(2),
      ),
      accentPaint,
    );
    
    // Content layout in bar
    var xOffset = _panelMargin + padding;
    final yPos = barY + barHeight / 2;
    
    // App name short
    _drawText(canvas, p.appName, xOffset, yPos, const Color(0xFF00BCD4),
        fontSize: _getFontSize(p.fontSize) * 0.85, bold: true);
    xOffset += _measureText(p.appName, _getFontSize(p.fontSize) * 0.85) + 16;
    
    // Separator
    _drawText(canvas, '|', xOffset, yPos, Colors.white38,
        fontSize: _getFontSize(p.fontSize) * 0.85);
    xOffset += 12;
    
    // Timestamp
    final timestamp = _formatTimestampShort(p.timestamp);
    _drawText(canvas, timestamp, xOffset, yPos, Colors.white70,
        fontSize: _getFontSize(p.fontSize) * 0.8);
    xOffset += _measureText(timestamp, _getFontSize(p.fontSize) * 0.8) + 16;
    
    // Coordinates (short)
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final coordText = _formatCoordinatesShort(p.lat!, p.lon!);
      _drawText(canvas, coordText, xOffset, yPos, Colors.white70,
          fontSize: _getFontSize(p.fontSize) * 0.75);
      xOffset += _measureText(coordText, _getFontSize(p.fontSize) * 0.75) + 12;
    }
    
    // Accuracy with color coding
    if (p.showAccuracy && p.acc != null) {
      final accText = '±${p.acc!.toStringAsFixed(0)}m';
      final accColor = _getAccuracyColor(p.acc!);
      _drawText(canvas, accText, xOffset, yPos, accColor,
          fontSize: _getFontSize(p.fontSize) * 0.75);
    }
  }
  
  // ═══════════════════════════════════════════════════════════════
  // GOVERNMENT WATERMARK (Strip biru tua formal)
  // ═══════════════════════════════════════════════════════════════
  
  static void _drawGovernmentWatermark(
    Canvas canvas,
    int width,
    int height,
    WatermarkParams p,
  ) {
    final barHeight = 64.0;
    final barY = height - barHeight;
    
    // Draw dark blue government bar
    final bgPaint = Paint()
      ..color = const Color(0xFF0D2B4E)
      ..style = PaintingStyle.fill;
    
    canvas.drawRect(Rect.fromLTWH(0, barY, width.toDouble(), barHeight), bgPaint);
    
    // Gold accent line
    final accentPaint = Paint()
      ..color = const Color(0xFFD4AF37)
      ..style = PaintingStyle.fill;
    
    canvas.drawRect(Rect.fromLTWH(0, barY, width.toDouble(), 3), accentPaint);
    canvas.drawRect(Rect.fromLTWH(0, barY + barHeight - 3, width.toDouble(), 3), accentPaint);
    
    // Two-column layout
    final leftCol = _panelMargin;
    final rightCol = width / 2 + _panelMargin;
    var yOffset = barY + 10;
    
    // Left column - Official title
    _drawText(canvas, p.appName.toUpperCase(), leftCol, yOffset, const Color(0xFFD4AF37),
        fontSize: _getFontSize(p.fontSize) * 0.9, bold: true);
    yOffset += _getFontSize(p.fontSize) * 0.9 + 4;
    
    // Timestamp
    final timestamp = _formatTimestamp(p.timestamp, p.dateFormat, p.timeFormat);
    _drawText(canvas, timestamp, leftCol, yOffset, Colors.white70,
        fontSize: _getFontSize(p.fontSize) * 0.75);
    yOffset += _getFontSize(p.fontSize) * 0.75 + 4;
    
    // Verification badge
    final verificationText = _generateVerificationCode(p);
    _drawText(canvas, 'VER: $verificationText', leftCol, yOffset, const Color(0xFFD4AF37),
        fontSize: _getFontSize(p.fontSize) * 0.65);
    
    // Right column - Location data
    yOffset = barY + 10;
    
    if (p.showAddress && p.address.isNotEmpty) {
      _drawText(canvas, p.address, rightCol, yOffset, Colors.white,
          fontSize: _getFontSize(p.fontSize) * 0.8);
      yOffset += _getFontSize(p.fontSize) * 0.8 * _lineHeight;
    }
    
    String locationData = '';
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      locationData += _formatCoordinates(p.lat!, p.lon!);
    }
    if (p.showAccuracy && p.acc != null) {
      if (locationData.isNotEmpty) locationData += ' ';
      locationData += '(±${p.acc!.toStringAsFixed(0)}m)';
    }
    if (locationData.isNotEmpty) {
      _drawText(canvas, locationData, rightCol, yOffset, Colors.white70,
          fontSize: _getFontSize(p.fontSize) * 0.7);
      yOffset += _getFontSize(p.fontSize) * 0.7 * _lineHeight;
    }
    
    if (p.showWeather && p.weather.isNotEmpty) {
      _drawText(canvas, p.weather, rightCol, yOffset, Colors.white70,
          fontSize: _getFontSize(p.fontSize) * 0.7);
    }
  }
  
  // ═══════════════════════════════════════════════════════════════
  // Helper Methods
  // ═══════════════════════════════════════════════════════════════
  
  static double _calculatePanelHeight(WatermarkParams p) {
    double height = 0;
    height += _getFontSize(p.fontSize) * _lineHeight; // header
    height += 12; // divider
    if (p.showAddress && p.address.isNotEmpty) height += _getFontSize(p.fontSize) * 0.85 * _lineHeight;
    if ((p.showCoordinates && p.lat != null) || (p.showAccuracy && p.acc != null)) {
      height += _getFontSize(p.fontSize) * 0.8 * _lineHeight;
    }
    if (p.showWeather && p.weather.isNotEmpty) height += _getFontSize(p.fontSize) * 0.8 * _lineHeight;
    height += 20; // bottom padding
    return height;
  }
  
  static double _getFontSize(String size) {
    switch (size) {
      case 'small': return 11.0;
      case 'large': return 15.0;
      default: return 13.0;
    }
  }
  
  static String _formatTimestamp(DateTime time, String dateFormat, String timeFormat) {
    final date = DateFormat(dateFormat).format(time);
    final timeStr = DateFormat(timeFormat).format(time);
    return '$date  $timeStr';
  }
  
  static String _formatTimestampShort(DateTime time) {
    return DateFormat('HH:mm:ss').format(time);
  }
  
  static String _formatCoordinates(double lat, double lon) {
    return '${lat.toStringAsFixed(6)}°, ${lon.toStringAsFixed(6)}°';
  }
  
  static String _formatCoordinatesShort(double lat, double lon) {
    return '${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°';
  }
  
  static Color _getAccuracyColor(double accuracy) {
    if (accuracy <= 5) return const Color(0xFF4CAF50); // Green
    if (accuracy <= 15) return const Color(0xFFFF9800); // Orange
    return const Color(0xFFF44336); // Red
  }
  
  static String _generateHash(WatermarkParams p) {
    final hashString = '${p.timestamp.millisecondsSinceEpoch}${p.lat}${p.lon}';
    return 'HASH: ${hashString.hashCode.toRadixString(16).substring(0, 8).toUpperCase()}';
  }
  
  static String _generateVerificationCode(WatermarkParams p) {
    final verString = '${p.timestamp.day}${p.timestamp.month}${p.timestamp.year}${(p.lat ?? 0).abs().floor()}';
    return verString.hashCode.toRadixString(16).substring(0, 6).toUpperCase();
  }
  
  static void _drawText(
    Canvas canvas,
    String text,
    double x,
    double y,
    Color color, {
    double fontSize = 13.0,
    bool bold = false,
  }) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        fontFamily: 'monospace',
      ),
    );
    
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: ui.TextDirection.ltr,  // ← PERBAIKAN: gunakan ui.TextDirection
    );
    
    textPainter.layout();
    textPainter.paint(canvas, Offset(x, y - textPainter.height / 2));
  }
  
  static double _measureText(String text, double fontSize) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(fontSize: fontSize, fontFamily: 'monospace'),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: ui.TextDirection.ltr,  // ← PERBAIKAN: gunakan ui.TextDirection
    );
    textPainter.layout();
    return textPainter.width;
  }
}
