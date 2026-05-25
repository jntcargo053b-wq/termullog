// lib/watermark/layouts/layout_cinematic.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'watermark_layout_base.dart';

class LayoutCinematic extends WatermarkLayoutBase {
  @override
  String get name => 'GPS Timestamp';

  static const int _padX = 24;
  static const int _padY = 20;
  static const bool _positionBottom = true; // true = bottom, false = top

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
    required bool showMiniMap,
    Uint8List? mapBytes,
    bool showAddress = true,
    bool showCoordinates = true,
    double opacity = 0.85,
    bool showBorder = true,
    String fontSize = 'normal',
    String mapSize = 'medium',
    String dateFormat = 'dd MMM yyyy',
    String timeFormat = 'HH:mm:ss',
  }) {
    final double scale = (src.width / 1080).clamp(0.7, 2.0);
    final int mapH = (120 * scale).round();
    final int lineH = (32 * scale).round();
    final int smallLine = (24 * scale).round();
    final int padX = (_padX * scale).round();
    final int padY = (_padY * scale).round();
    final int margin = (12 * scale).round();
    final fontMain = img.arial24;
    final fontSmall = img.arial14;

    int rowCount = 0;
    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) rowCount += 1;
    rowCount += 2; rowCount += 1;
    if (showCoordinates && hasPosition) rowCount += 1;
    if (showAddress && address.isNotEmpty) rowCount += 2;
    if (showWeather && weather.isNotEmpty) rowCount += 1;

    final int panelH = (showMiniMap && mapBytes != null && mapBytes.isNotEmpty ? mapH + padY : 0)
        + padY * 2 + rowCount * (smallLine + 4) + 20;
    
    final int y0 = _positionBottom ? src.height - panelH : margin;
    if (y0 < 0 || y0 >= src.height) return WatermarkLayoutBase.encodeJpg(src);

    final int cardW = src.width - margin * 2;
    final int cardX = margin;

    img.fillRect(src, x1: cardX, y1: y0 + margin, x2: cardX + cardW, y2: y0 + panelH - margin,
        color: img.ColorRgba8(19, 19, 19, (255 * opacity).toInt()));

    int cy = y0 + margin + padY;

    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) {
      try {
        final map = img.decodeImage(mapBytes);
        if (map != null) {
          final resized = img.copyResize(map, width: cardW, height: mapH);
          img.fillRect(src, x1: cardX, y1: cy, x2: cardX + cardW, y2: cy + mapH,
              color: img.ColorRgba8(0, 0, 0, 60));
          img.compositeImage(src, resized, dstX: cardX, dstY: cy, blend: img.BlendMode.alpha);
          final pinX = cardX + cardW ~/ 2;
          final pinY = cy + mapH ~/ 2;
          img.fillCircle(src, x: pinX, y: pinY, radius: 6, color: img.ColorRgba8(255, 50, 50, 255));
        }
      } catch (_) {}
      cy += mapH + padY;
    }

    img.drawString(src, DateFormat('EEE, dd MMM yyyy').format(timestamp),
        font: fontMain, x: cardX + padX, y: cy, color: WatermarkLayoutBase.white);
    cy += lineH;
    img.drawString(src, DateFormat('HH:mm:ss').format(timestamp),
        font: fontMain, x: cardX + padX, y: cy, color: WatermarkLayoutBase.white);
    cy += lineH;
    img.fillRect(src, x1: cardX + padX, y1: cy, x2: cardX + cardW - padX, y2: cy + 2,
        color: img.ColorRgba8(255, 255, 255, 20));
    cy += 12;
    
    if (showAddress && address.isNotEmpty && !address.startsWith('GPS:')) {
      final lines = _splitAddress(address);
      for (final line in lines.take(2)) {
        img.drawString(src, line, font: fontSmall, x: cardX + padX, y: cy, color: WatermarkLayoutBase.white);
        cy += smallLine;
      }
    }
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      img.drawString(src, '${lat.toStringAsFixed(5)}°, ${lon.toStringAsFixed(5)}°',
          font: fontSmall, x: cardX + padX, y: cy, color: WatermarkLayoutBase.blue);
    }
    return WatermarkLayoutBase.encodeJpg(src);
  }

  List<String> _splitAddress(String address) {
    const maxLen = 42;
    final parts = address.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return [address.length > maxLen ? '${address.substring(0, maxLen - 1)}…' : address];
    final l1 = parts.first;
    final rest = parts.skip(1).join(', ');
    return [
      l1.length > maxLen ? '${l1.substring(0, maxLen - 1)}…' : l1,
      if (rest.isNotEmpty) rest.length > maxLen ? '${rest.substring(0, maxLen - 1)}…' : rest,
    ];
  }
}
