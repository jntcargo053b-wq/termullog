// lib/watermark/layouts/layout_polaroid.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutPolaroid extends WatermarkLayoutBase {
  @override
  String get name => 'Polaroid';

  static const int borderTop = 26;
  static const int borderSide = 26;
  static const int borderBottom = 110;

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
    final int newW = src.width + borderSide * 2;
    final int newH = src.height + borderTop + borderBottom;

    final canvas = img.Image(width: newW, height: newH);

    // Background polaroid
    img.fill(
      canvas,
      color: img.ColorRgba8(247, 244, 236, 255),
    );

    // Soft shadow
    img.fillRect(
      canvas,
      x1: borderSide + 5,
      y1: borderTop + 5,
      x2: borderSide + src.width + 5,
      y2: borderTop + src.height + 5,
      color: img.ColorRgba8(0, 0, 0, 20),
    );

    // Main image
    img.compositeImage(
      canvas,
      src,
      dstX: borderSide,
      dstY: borderTop,
      blend: img.BlendMode.alpha,
    );

    // Thin border
    img.drawRect(
      canvas,
      x1: borderSide,
      y1: borderTop,
      x2: borderSide + src.width - 1,
      y2: borderTop + src.height - 1,
      color: img.ColorRgba8(210, 205, 195, 120),
      thickness: 1,
    );

    // Separator line
    final int separatorY = borderTop + src.height + 8;

    img.drawLine(
      canvas,
      x1: borderSide + 8,
      y1: separatorY,
      x2: newW - borderSide - 8,
      y2: separatorY,
      color: img.ColorRgba8(190, 185, 175, 120),
    );

    final titleFont = img.arial24;
    final smallFont = img.arial14;

    final primary = img.ColorRgba8(35, 35, 35, 255);
    final secondary = img.ColorRgba8(90, 90, 90, 255);

    int cy = separatorY + 12;

    // Date
    final String date =
        DateFormat('dd MMM yyyy • HH:mm').format(timestamp);

    img.drawString(
      canvas,
      date,
      font: titleFont,
      x: borderSide + 8,
      y: cy,
      color: primary,
    );

    cy += 28;

    // Coordinates
    if (hasPosition && lat != null && lon != null) {
      String coord =
          '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';

      if (showAccuracy && acc != null) {
        coord += '   ±${acc.toStringAsFixed(0)}m';
      }

      img.drawString(
        canvas,
        coord,
        font: smallFont,
        x: borderSide + 8,
        y: cy,
        color: secondary,
      );

      cy += 18;
    }

    // Address
    if (address.isNotEmpty &&
        address != 'Tidak ada lokasi' &&
        !address.startsWith('GPS:')) {
      final lines = _wrapText(address, 42);

      for (final line in lines.take(2)) {
        img.drawString(
          canvas,
          line,
          font: smallFont,
          x: borderSide + 8,
          y: cy,
          color: secondary,
        );

        cy += 16;
      }
    }

    // Weather
    if (showWeather && weather.isNotEmpty) {
      img.drawString(
        canvas,
        weather,
        font: smallFont,
        x: borderSide + 8,
        y: cy,
        color: img.ColorRgba8(70, 70, 70, 255),
      );
    }

    // Mini map
    if (showMiniMap && mapBytes != null) {
      final map = img.decodeImage(mapBytes);

      if (map != null) {
        final resized = img.copyResize(
          map,
          width: 80,
          height: 80,
        );

        final mapX = newW - borderSide - 88;
        final mapY = newH - 88;

        // White frame
        img.fillRect(
          canvas,
          x1: mapX - 3,
          y1: mapY - 3,
          x2: mapX + 83,
          y2: mapY + 83,
          color: img.ColorRgba8(255, 255, 255, 255),
        );

        img.compositeImage(
          canvas,
          resized,
          dstX: mapX,
          dstY: mapY,
        );

        img.drawRect(
          canvas,
          x1: mapX - 3,
          y1: mapY - 3,
          x2: mapX + 83,
          y2: mapY + 83,
          color: img.ColorRgba8(180, 180, 180, 255),
        );
      }
    }

    return WatermarkLayoutBase.encodeJpg(canvas);
  }

  List<String> _wrapText(String text, int maxChars) {
    final words = text.split(' ');
    final List<String> lines = [];

    String current = '';

    for (final word in words) {
      if ((current + word).length > maxChars) {
        lines.add(current.trim());
        current = '$word ';
      } else {
        current += '$word ';
      }
    }

    if (current.isNotEmpty) {
      lines.add(current.trim());
    }

    return lines;
  }
}
