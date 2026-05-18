// lib/watermark/layouts/layout_timemark_style.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutTimeMarkStyle extends WatermarkLayoutBase {
  @override
  String get name => 'TimeMark Style (TES HIJAU)';

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
    // ── TES: Background HIJAU mencolok ──
    img.fillRect(src,
        x1: 0, y1: src.height - 160,
        x2: src.width - 1, y2: src.height - 1,
        color: img.ColorRgba8(0, 200, 0, 220));

    // ── TES: Teks PUTIH besar ──
    img.drawString(src, 'TIMEMARK AKTIF',
        font: img.arial24,
        x: 40, y: src.height - 80,
        color: WatermarkLayoutBase.white);

    // ── TES: Jam besar ──
    img.drawString(src, DateFormat('HH:mm').format(timestamp),
        font: img.arial24,
        x: 40, y: src.height - 40,
        color: WatermarkLayoutBase.white);

    return WatermarkLayoutBase.encodeJpg(src);
  }
}
