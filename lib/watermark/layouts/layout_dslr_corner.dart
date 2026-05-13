
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutDSLRCorner extends WatermarkLayoutBase {
  @override
  String get name => 'DSLR Corner';
  
  static const int padX = 18;
  static const int padY = 16;
  static const int lineH = 26;
  static const int brkLen = 22;
  static const int brkW = 4;

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
  }) {
    int rows = 2;
    if (hasPosition) rows += 2;
    if (showAccuracy && hasPosition) rows += 1;
    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) rows += 1;
    if (showWeather && weather.isNotEmpty) rows += 1;

    final int boxH = padY * 2 + rows * lineH;
    final int boxW = (src.width * 0.55).toInt().clamp(300, src.width - 30);
    final bool isTop = watermarkPosition == 'top';
    final int x0 = 20;
    final int y0 = isTop ? 20 : src.height - boxH - 20;
    final int x1 = x0 + boxW;
    final int y1 = y0 + boxH;

    // Darken background area
    final region = img.copyCrop(src, x: x0, y: y0, width: boxW, height: boxH);
    img.adjustColor(region, brightness: -0.85);
    img.compositeImage(src, region, dstX: x0, dstY: y0);

    // Draw corner brackets
    _drawCornerBrackets(src, x0, y0, x1, y1);

    // Draw text content
    final font = img.arial24;
    int cy = y0 + padY;
    final int xT = x0 + padX;

    img.drawString(src, DateFormat('dd  MMM  yyyy').format(timestamp), 
      font: font, x: xT, y: cy, color: WatermarkLayoutBase.blue);
    cy += lineH;
    img.drawString(src, DateFormat('HH : mm : ss').format(timestamp), 
      font: font, x: xT, y: cy, color: WatermarkLayoutBase.white);
    cy += lineH;

    if (hasPosition) {
      img.drawString(src, 'N ${lat!.toStringAsFixed(6)}', 
        font: font, x: xT, y: cy, color: WatermarkLayoutBase.offWhite);
      cy += lineH;
      img.drawString(src, 'E ${lon!.toStringAsFixed(6)}', 
        font: font, x: xT, y: cy, color: WatermarkLayoutBase.offWhite);
      cy += lineH;
      if (showAccuracy) {
        img.drawString(src, 'ACC  ±${acc?.toStringAsFixed(0) ?? '?'} m', 
          font: font, x: xT, y: cy, color: WatermarkLayoutBase.grey);
        cy += lineH;
      }
    }

    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      String sh = address.length > 50 ? '${address.substring(0, 47)}…' : address;
      img.drawString(src, sh, font: font, x: xT, y: cy, color: WatermarkLayoutBase.grey);
      cy += lineH;
    }

    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, weather, font: font, x: xT, y: cy, color: WatermarkLayoutBase.blue);
    }

    // Mini map
    if (showMiniMap && mapBytes != null && hasPosition) {
      WatermarkLayoutBase.drawMiniMap(src, mapBytes,
          watermarkHeight: boxH + 20, isTop: isTop);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  void _drawCornerBrackets(img.Image src, int x0, int y0, int x1, int y1) {
    // Top-left
    img.fillRect(src, x1: x0, y1: y0, x2: x0 + brkLen, y2: y0 + brkW, color: WatermarkLayoutBase.blue);
    img.fillRect(src, x1: x0, y1: y0, x2: x0 + brkW, y2: y0 + brkLen, color: WatermarkLayoutBase.blue);
    // Top-right
    img.fillRect(src, x1: x1 - brkLen, y1: y0, x2: x1, y2: y0 + brkW, color: WatermarkLayoutBase.blue);
    img.fillRect(src, x1: x1 - brkW, y1: y0, x2: x1, y2: y0 + brkLen, color: WatermarkLayoutBase.blue);
    // Bottom-left
    img.fillRect(src, x1: x0, y1: y1 - brkW, x2: x0 + brkLen, y2: y1, color: WatermarkLayoutBase.blue);
    img.fillRect(src, x1: x0, y1: y1 - brkLen, x2: x0 + brkW, y2: y1, color: WatermarkLayoutBase.blue);
    // Bottom-right
    img.fillRect(src, x1: x1 - brkLen, y1: y1 - brkW, x2: x1, y2: y1, color: WatermarkLayoutBase.blue);
    img.fillRect(src, x1: x1 - brkW, y1: y1 - brkLen, x2: x1, y2: y1, color: WatermarkLayoutBase.blue);
  }
}
