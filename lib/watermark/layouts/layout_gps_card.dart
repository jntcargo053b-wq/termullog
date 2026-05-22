// lib/watermark/layouts/layout_gps_card.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutGpsCard extends WatermarkLayoutBase {
  @override
  String get name => 'GPS Card';

  static const bool _positionBottom = true;

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
  }) {
    final double scale = (src.width / 1080).clamp(0.7, 2.0);
    final int panelW = (src.width * 0.85).toInt();
    final int padX = (15 * scale).round();
    final int rowH = (24 * scale).round();
    final int iconW = (30 * scale).round();
    final img.BitmapFont fontS = fontSize == 'small' ? img.arial14 : img.arial24;

    int rows = 2;
    if (showCoordinates && hasPosition) rows += 1;
    if (showAccuracy && hasPosition) rows += 1;
    if (showAddress && address.isNotEmpty) rows += 1;
    if (showWeather && weather.isNotEmpty) rows += 1;

    final int panelH = rows * rowH + 16;
    final int y0 = _positionBottom ? src.height - panelH - 16 : 16;
    final int x0 = (src.width - panelW) ~/ 2;
    final img.Color bgColor = img.ColorRgba8(0, 0, 0, (200 * opacity).toInt());

    // Perbaikan: named parameters untuk fillRect
    img.fillRect(src,
        x1: x0, y1: y0,
        x2: x0 + panelW, y2: y0 + panelH,
        color: bgColor);
    if (showBorder) {
      img.drawRect(src,
          x1: x0, y1: y0,
          x2: x0 + panelW, y2: y0 + panelH,
          color: WatermarkLayoutBase.white, thickness: 1);
    }

    int cy = y0 + 8;
    final dateStr = DateFormat('dd MMM yyyy').format(timestamp);
    final timeStr = DateFormat('HH:mm:ss').format(timestamp);
    img.drawString(src, dateStr, font: fontS, x: x0 + padX + iconW, y: cy, color: WatermarkLayoutBase.white);
    cy += rowH;
    img.drawString(src, timeStr, font: fontS, x: x0 + padX + iconW, y: cy, color: WatermarkLayoutBase.white);
    cy += rowH;

    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final coord = '${lat.toStringAsFixed(5)}°, ${lon.toStringAsFixed(5)}°';
      img.drawString(src, coord, font: fontS, x: x0 + padX + iconW, y: cy, color: WatermarkLayoutBase.blue);
      cy += rowH;
    }
    if (showAccuracy && hasPosition && acc != null) {
      final accStr = 'Accuracy: ±${acc.toStringAsFixed(1)} m';
      img.drawString(src, accStr, font: fontS, x: x0 + padX + iconW, y: cy, color: WatermarkLayoutBase.grey);
      cy += rowH;
    }
    if (showAddress && address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      final short = address.length > 35 ? '${address.substring(0, 32)}...' : address;
      img.drawString(src, short, font: fontS, x: x0 + padX + iconW, y: cy, color: WatermarkLayoutBase.grey);
      cy += rowH;
    }
    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, weather, font: fontS, x: x0 + padX + iconW, y: cy, color: WatermarkLayoutBase.blue);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }
}
