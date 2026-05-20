// lib/watermark/layouts/layout_cinematic.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'watermark_layout_base.dart';
import '../../core/constants.dart';

class LayoutCinematic extends WatermarkLayoutBase {
  @override
  String get name => 'Cinematic';

  @override
  Uint8List apply({
    required img.Image src,
    required DateTime timestamp,
    required bool hasPosition,
    required double? lat,
    required double? lon,
    required double? acc,
    required String address,
    required String weather,
    required bool showWeather,
    required bool showAccuracy,
    required String watermarkPosition,
    required bool showMiniMap,
    Uint8List? mapBytes,
    bool showAddress = true,
    bool showCoordinates = true,
    double opacity = 0.85,
    bool showBorder = true,
    String fontSize = 'normal',
  }) {
    // Create 2.39:1 letterbox
    final int targetHeight = (src.width / 2.39).round();
    final int barHeight = (src.height - targetHeight) ~/ 2;
    
    final img.Image finalImage = img.Image(width: src.width, height: targetHeight);
    img.fill(finalImage, color: img.ColorRgb8(0, 0, 0));
    
    // Composite image in center
    if (barHeight > 0) {
      img.compositeImage(finalImage, src, dstX: 0, dstY: 0);
    } else {
      img.copyInto(finalImage, src, dstX: 0, dstY: 0);
    }
    
    // Gold overlay gradient at bottom
    final int gradientHeight = (targetHeight * 0.15).round();
    for (int i = 0; i < gradientHeight; i++) {
      final int alpha = (i / gradientHeight * 180).clamp(0, 180).toInt();
      img.drawLine(finalImage,
          x1: 0, y1: targetHeight - gradientHeight + i,
          x2: src.width, y2: targetHeight - gradientHeight + i,
          color: img.ColorRgba8(0, 0, 0, alpha));
    }
    
    // Centered typography with gold accent
    final int centerX = src.width ~/ 2;
    int y = targetHeight - 100;
    
    // Date
    final String dateStr = DateFormat('MMMM dd, yyyy').format(timestamp).toUpperCase();
    _drawCenteredText(finalImage, dateStr, centerX, y, 14, kColorGold);
    y += 28;
    
    // Main time
    final String timeStr = DateFormat('HH : mm : ss').format(timestamp);
    _drawCenteredText(finalImage, timeStr, centerX, y, 48, kColorWhite);
    y += 60;
    
    // Gold accent line
    for (int i = -30; i <= 30; i++) {
      img.drawPixel(finalImage, centerX + i, y, kColorGold);
    }
    y += 30;
    
    // Location
    if (hasPosition && showCoordinates && lat != null && lon != null) {
      final String coordStr = '${lat.toStringAsFixed(4)}° ${lat >= 0 ? 'N' : 'S'}, ${lon.toStringAsFixed(4)}° ${lon >= 0 ? 'E' : 'W'}';
      _drawCenteredText(finalImage, coordStr, centerX, y, 12, kColorGold);
      y += 24;
    }
    
    // Address
    if (showAddress && address.isNotEmpty) {
      String shortAddr = address.length > 45 ? '${address.substring(0, 42)}...' : address;
      _drawCenteredText(finalImage, shortAddr, centerX, y, 11, kColorWhite);
    }
    
    return WatermarkLayoutBase.encodeJpg(finalImage);
  }
  
  void _drawCenteredText(img.Image img, String text, int centerX, int y, int fontSize, img.Color color) {
    final int approxWidth = text.length * (fontSize ~/ 2);
    final int x = centerX - (approxWidth ~/ 2);
    img.drawString(img, text, font: _getFont(fontSize), x: x, y: y, color: color);
  }
  
  img.Font _getFont(int size) {
    if (size <= 14) return img.arial14;
    if (size <= 24) return img.arial24;
    return img.arial36;
  }
  
  @override
  Future<Uint8List> applyAsync({...}) async {
    // Similar but with Flutter Canvas
    return apply(...); // Fallback
  }
}
