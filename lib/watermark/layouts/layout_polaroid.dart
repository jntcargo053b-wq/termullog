// lib/watermark/layouts/layout_polaroid.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutPolaroid extends WatermarkLayoutBase {
  @override
  String get name => 'Polaroid';

  static const int borderTop = 24;
  static const int borderSide = 24;
  static const int borderBottom = 70;
  static const int maxAddrLen = 40;

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

    // Canvas ivory
    final canvas = img.Image(width: newW, height: newH);
    img.fillRect(canvas, x1: 0, y1: 0, x2: newW - 1, y2: newH - 1,
        color: img.ColorRgba8(248, 245, 235, 255));

    // Shadow
    img.fillRect(canvas,
        x1: borderSide + 3, y1: borderTop + 3,
        x2: borderSide + src.width + 3, y2: borderTop + src.height + 3,
        color: img.ColorRgba8(0, 0, 0, 25));

    // Foto
    img.compositeImage(canvas, src, dstX: borderSide, dstY: borderTop, blend: img.BlendMode.alpha);

    // Border subtle
    img.drawRect(canvas,
        x1: borderSide, y1: borderTop,
        x2: borderSide + src.width - 1, y2: borderTop + src.height - 1,
        color: img.ColorRgba8(200, 195, 185, 80), thickness: 1);

    // Teks di area bawah
    final font = img.arial24;
    final textColor = img.ColorRgba8(40, 40, 40, 255);
    int cy = src.height + borderTop + 12;

    // Tanggal
    img.drawString(canvas, DateFormat('dd MMM yyyy').format(timestamp),
        font: font, x: borderSide + 2, y: cy, color: textColor);
    cy += 24;

    // Koordinat
    if (hasPosition) {
      String coord = '${lat!.toStringAsFixed(4)}, ${lon!.toStringAsFixed(4)}';
      if (showAccuracy) coord += '  ±${acc?.toStringAsFixed(0) ?? '?'}m';
      img.drawString(canvas, coord, font: font, x: borderSide + 2, y: cy,
          color: img.ColorRgba8(80, 80, 80, 255));
      cy += 22;
    }

    // Alamat
    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      String addr = address.length > maxAddrLen
          ? '${address.substring(0, maxAddrLen - 1)}…' : address;
      img.drawString(canvas, addr, font: font, x: borderSide + 2, y: cy,
          color: img.ColorRgba8(100, 100, 100, 255));
    }

    return encodeJpg(canvas);
  }
}
