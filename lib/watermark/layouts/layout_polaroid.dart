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
  }) {
    final int canvasW = src.width + borderSide * 2;
    final int canvasH = src.height + borderTop + borderBottom;

    // =========================================================
    // CANVAS
    // =========================================================

    final canvas = img.Image(
      width: canvasW,
      height: canvasH,
    );

    // Background putih ivory
    img.fill(
      canvas,
      color: img.ColorRgba8(248, 245, 238, 255),
    );

    // =========================================================
    // SHADOW FOTO
    // =========================================================

    img.fillRect(
      canvas,
      x1: borderSide + 6,
      y1: borderTop + 6,
      x2: borderSide + src.width + 6,
      y2: borderTop + src.height + 6,
      color: img.ColorRgba8(0, 0, 0, 25),
    );

    // =========================================================
    // FOTO
    // =========================================================

    img.compositeImage(
      canvas,
      src,
      dstX: borderSide,
      dstY: borderTop,
      blend: img.BlendMode.alpha,
    );

    // =========================================================
    // FONT
    // =========================================================

    final titleFont = img.arial24;
    final smallFont = img.arial14;

    final textColor = img.ColorRgba8(35, 35, 35, 255);
    final subColor = img.ColorRgba8(90, 90, 90, 255);

    int textY = borderTop + src.height + 16;

    // =========================================================
    // TANGGAL
    // =========================================================

    final dateText =
        DateFormat('dd MMM yyyy • HH:mm').format(timestamp);

    img.drawString(
      canvas,
      dateText,
      font: titleFont,
      x: borderSide,
      y: textY,
      color: textColor,
    );

    textY += 32;

    // =========================================================
    // ALAMAT
    // =========================================================

    final cleanAddress = address.trim().isNotEmpty
        ? address
        : 'Lokasi tidak tersedia';

    final addressLines =
        _wrapText(cleanAddress, 42);

    for (final line in addressLines.take(3)) {
      img.drawString(
        canvas,
        line,
        font: smallFont,
        x: borderSide,
        y: textY,
        color: subColor,
      );

      textY += 18;
    }

    // =========================================================
    // WEATHER + GPS
    // =========================================================

    final info = <String>[];

    if (showWeather && weather.isNotEmpty) {
      info.add(weather);
    }

    if (showAccuracy && acc != null) {
      info.add('GPS ±${acc.toStringAsFixed(0)}m');
    }

    if (info.isNotEmpty) {
      img.drawString(
        canvas,
        info.join('   •   '),
        font: smallFont,
        x: borderSide,
        y: canvasH - 28,
        color: subColor,
      );
    }

    // =========================================================
    // MINI MAP
    // =========================================================

    if (showMiniMap && mapBytes != null) {
      try {
        final map = img.decodeImage(mapBytes);

        if (map != null) {
          final resized = img.copyResize(
            map,
            width: 110,
            height: 70,
          );

          final mapX = canvasW - 110 - borderSide;
          final mapY = canvasH - 70 - 18;

          // Shadow map
          img.fillRect(
            canvas,
            x1: mapX + 3,
            y1: mapY + 3,
            x2: mapX + 113,
            y2: mapY + 73,
            color: img.ColorRgba8(0, 0, 0, 30),
          );

          // White border
          img.fillRect(
            canvas,
            x1: mapX - 2,
            y1: mapY - 2,
            x2: mapX + 112,
            y2: mapY + 72,
            color: img.ColorRgba8(255, 255, 255, 255),
          );

          img.compositeImage(
            canvas,
            resized,
            dstX: mapX,
            dstY: mapY,
          );
        }
      } catch (_) {}
    }

    return WatermarkLayoutBase.encodeJpg(canvas);
  }

  // =========================================================
  // TEXT WRAP
  // =========================================================

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

    if (current.trim().isNotEmpty) {
      lines.add(current.trim());
    }

    return lines;
  }
}
