// lib/watermark/layouts/layout_survey.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'package:image/src/font/arial_12.dart';
import 'package:image/src/font/arial_14.dart';
import 'watermark_layout_base.dart';
import '../../core/constants.dart';

class LayoutSurvey extends WatermarkLayoutBase {
  @override
  String get name => 'Survey';
  
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
    // Semi-transparent panel bottom left
    final int panelW = 320;
    final int panelH = 220;
    final int panelX = 16;
    final int panelY = src.height - panelH - 16;
    
    // Draw panel background
    for (int i = 0; i < panelH; i++) {
      for (int j = 0; j < panelW; j++) {
        final int alpha = (0.9 * 255).toInt();
        img.drawPixel(src, panelX + j, panelY + i, img.getColor(15, 23, 42, alpha));
      }
    }
    
    // Border
    img.drawRect(src,
        x1: panelX, y1: panelY,
        x2: panelX + panelW, y2: panelY + panelH,
        color: kColorTeal, thickness: 2);
    
    int x = panelX + 16;
    int y = panelY + 16;
    
    // Header
    img.drawString(src, img.arial14, x, y, 'FIELD SURVEY DATA', color: kColorTeal);
    y += 28;
    
    // Data rows
    _drawRow(src, 'DATE', DateFormat('dd MMM yyyy').format(timestamp), x, y);
    y += 24;
    _drawRow(src, 'TIME', DateFormat('HH:mm:ss').format(timestamp), x, y);
    y += 24;
    
    if (hasPosition && lat != null && lon != null) {
      _drawRow(src, 'LAT', lat.toStringAsFixed(6), x, y);
      y += 24;
      _drawRow(src, 'LON', lon.toStringAsFixed(6), x, y);
      y += 24;
      
      if (showAccuracy && acc != null) {
        _drawRow(src, 'ACC', '±${acc.toStringAsFixed(1)}m', x, y);
        y += 24;
      }
    }
    
    if (showWeather && weather.isNotEmpty) {
      _drawRow(src, 'WEATHER', weather, x, y);
      y += 24;
    }
    
    return WatermarkLayoutBase.encodeJpg(src);
  }
  
  void _drawRow(img.Image src, String label, String value, int x, int y) {
    img.drawString(src, img.arial12, x, y, label, color: kColorLightGrey);
    img.drawString(src, img.arial12, x + 100, y, value, color: kColorWhite);
  }
  
  @override
  Future<Uint8List> applyAsync({...}) async {
    return apply(...);
  }
}
