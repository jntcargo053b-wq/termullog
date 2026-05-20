// lib/watermark/layouts/layout_hud.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'watermark_layout_base.dart';
import '../../core/constants.dart';

class LayoutHUD extends WatermarkLayoutBase {
  @override
  String get name => 'HUD';
  
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
    // Top-left corner HUD
    final int margin = 16;
    int x = margin;
    int y = margin;
    
    // Draw transparent panel
    final int panelW = 220;
    final int panelH = 180;
    for (int i = 0; i < panelH; i++) {
      for (int j = 0; j < panelW; j++) {
        final int alpha = (0.6 * 255).toInt();
        if (i == 0 || i == panelH - 1 || j == 0 || j == panelW - 1) {
          img.drawPixel(src, x + j, y + i, img.ColorRgba8(0, 184, 212, alpha));
        } else if (i > 2 && i < panelH - 2 && j > 2 && j < panelW - 2) {
          img.drawPixel(src, x + j, y + i, img.ColorRgba8(0, 0, 0, (0.7 * 255).toInt()));
        }
      }
    }
    
    y += 16;
    x += 16;
    
    // Time (large, cyan)
    final String timeStr = DateFormat('HH:mm:ss').format(timestamp);
    img.drawString(src, timeStr, font: img.arial24, x: x, y: y, color: kColorBrightCyan);
    y += 32;
    
    // Date
    final String dateStr = DateFormat('dd MMM yyyy').format(timestamp);
    img.drawString(src, dateStr, font: img.arial14, x: x, y: y, color: kColorBrightCyan);
    y += 24;
    
    // Coordinates (monospace)
    if (hasPosition && showCoordinates && lat != null && lon != null) {
      final String coordStr = '${lat.toStringAsFixed(5)}° ${lon.toStringAsFixed(5)}°';
      img.drawString(src, coordStr, font: img.arial12, x: x, y: y, color: kColorWhite);
      y += 20;
      
      if (showAccuracy && acc != null) {
        final String accStr = '±${acc.toStringAsFixed(1)}m';
        img.drawString(src, accStr, font: img.arial12, x: x, y: y, color: getAccuracyColor(acc));
        y += 20;
      }
    }
    
    // Weather
    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, weather, font: img.arial12, x: x, y: y, color: kColorWhite);
    }
    
    return WatermarkLayoutBase.encodeJpg(src);
  }
  
  @override
  Future<Uint8List> applyAsync({...}) async {
    return apply(...);
  }
}
