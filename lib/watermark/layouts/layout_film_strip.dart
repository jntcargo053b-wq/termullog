// lib/watermark/layouts/layout_film_strip.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutFilmStrip extends WatermarkLayoutBase {
  @override
  String get name => 'Film Strip (TEST)';

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
    // ── TEST: Background merah mencolok ──
    img.fillRect(src,
        x1: 0, y1: src.height - 120,
        x2: src.width - 1, y2: src.height - 1,
        color: img.ColorRgba8(255, 0, 0, (200 * opacity).toInt()));

    // ── TEST: Teks putih besar ──
    img.drawString(src, 'FILM STRIP AKTIF',
        font: img.arial24,
        x: 20, y: src.height - 60,
        color: WatermarkLayoutBase.white);

    return WatermarkLayoutBase.encodeJpg(src);
  }
}
