// lib/watermark/layouts/layout_polaroid.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutPolaroid extends WatermarkLayoutBase {
  @override
  String get name => 'Polaroid';

  static const int borderTop = 28;
  static const int borderSide = 24;
  static const int borderBottom = 140;

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
    final int canvasW = src.width + borderSide * 2;
    final int canvasH = src.height + borderTop + borderBottom;

    final canvas = img.Image(width: canvasW, height: canvasH);
    img.fillRect(canvas, x1: 0, y1: 0, x2: canvasW - 1, y2: canvasH - 1,
        color: img.ColorRgba8(248, 245, 238, 255));

    img.fillRect(canvas,
        x1: borderSide + 6, y1: borderTop + 6,
        x2: borderSide + src.width + 6, y2: borderTop + src.height + 6,
        color: img.ColorRgba8(0, 0, 0, 25));

    img.compositeImage(canvas, src,
        dstX: borderSide, dstY: borderTop, blend: img.BlendMode.alpha);

    final font = fontSize == 'small' ? img.arial14 : fontSize == 'large' ? img.arial24 : img.arial24;
    final smallFont = fontSize == 'small' ? img.arial14 : fontSize == 'large' ? img.arial24 : img.arial14;

    final textColor = img.ColorRgba8(35, 35, 35, 255);
    final subColor = img.ColorRgba8(90, 90, 90, 255);

    int textY = borderTop + src.height + 16;

    img.drawString(canvas,
        DateFormat('dd MMM yyyy • HH:mm').format(timestamp),
        font: font, x: borderSide, y: textY, color: textColor);
    textY += 32;

    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final coordStr = '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
      img.drawString(canvas, coordStr,
          font: smallFont, x: borderSide, y: textY, color: subColor);
      textY += 18;
    }

    if (showAddress && address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      final lines = _wrapText(address, 42);
      for (final line in lines.take(2)) {
        img.drawString(canvas, line,
            font: smallFont, x: borderSide, y: textY, color: subColor);
        textY += 18;
      }
    }

    final info = <String>[];
    if (showWeather && weather.isNotEmpty) info.add(weather);
    if (showAccuracy && hasPosition && acc != null) info.add('GPS ±${acc.toStringAsFixed(0)}m');
    if (info.isNotEmpty) {
      img.drawString(canvas, info.join('   •   '),
          font: smallFont, x: borderSide, y: canvasH - 28, color: subColor);
    }

    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) {
      try {
        final map = img.decodeImage(mapBytes);
        if (map != null) {
          final resized = img.copyResize(map, width: 110, height: 70);
          final mapX = canvasW - 110 - borderSide;
          final mapY = canvasH - 70 - 18;
          img.fillRect(canvas,
              x1: mapX + 3, y1: mapY + 3,
              x2: mapX + 113, y2: mapY + 73,
              color: img.ColorRgba8(0, 0, 0, 30));
          img.fillRect(canvas,
              x1: mapX - 2, y1: mapY - 2,
              x2: mapX + 112, y2: mapY + 72,
              color: img.ColorRgba8(255, 255, 255, 255));
          img.compositeImage(canvas, resized,
              dstX: mapX, dstY: mapY);
        }
      } catch (_) {}
    }

    return WatermarkLayoutBase.encodeJpg(canvas);
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
}
