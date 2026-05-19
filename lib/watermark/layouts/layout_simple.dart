// lib/watermark/layouts/layout_simple.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import '../../core/constants.dart';

class LayoutSimple {
  String get name => 'Simple';

  img.Image apply({
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
    required Uint8List? mapBytes,
    required bool showAddress,
    required bool showCoordinates,
    required double opacity,
    required bool showBorder,
    required String fontSize,
  }) {
    final timeStr = DateFormat('HH:mm:ss').format(timestamp);
    final dateStr = DateFormat('dd/MM/yyyy').format(timestamp);

    final bool isBottom = watermarkPosition == 'bottom';

    // Font bawaan package image v4
    final font = img.arial24;
    final smallFont = img.arial14;

    // Posisi awal watermark
    int yPos = isBottom ? src.height - 90 : 20;

    // Background semi transparan
    img.fillRect(
      src,
      x1: 0,
      y1: isBottom ? src.height - 110 : 0,
      x2: 340,
      y2: isBottom ? src.height : 110,
      color: img.ColorRgba8(0, 0, 0, (180 * opacity).toInt()),
    );

    // Timestamp
    img.drawString(
      src,
      '$dateStr  $timeStr',
      font: font,
      x: 12,
      y: yPos,
      color: img.ColorRgb8(255, 255, 255),
    );

    yPos += 30;

    // Coordinates
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      img.drawString(
        src,
        '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}',
        font: smallFont,
        x: 12,
        y: yPos,
        color: img.ColorRgb8(0, 255, 255),
      );

      yPos += 20;
    }

    // Accuracy
    if (showAccuracy && acc != null) {
      img.drawString(
        src,
        'Accuracy ±${acc.toStringAsFixed(1)}m',
        font: smallFont,
        x: 12,
        y: yPos,
        color: img.ColorRgb8(200, 200, 200),
      );

      yPos += 20;
    }

    // Weather
    if (showWeather && weather.isNotEmpty) {
      img.drawString(
        src,
        weather,
        font: smallFont,
        x: 12,
        y: yPos,
        color: img.ColorRgb8(255, 215, 0),
      );
    }

    return src;
  }

  static Uint8List encodeJpg(
    img.Image image, {
    int quality = kJpegQuality,
  }) {
    return Uint8List.fromList(
      img.encodeJpg(image, quality: quality),
    );
  }
}
