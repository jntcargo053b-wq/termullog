import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutSidePanel extends WatermarkLayoutBase {
  @override
  String get name => 'Side Panel';
  
  static const int panelW = 140;
  static const int padX = 12;
  static const int lineH = 32;

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
    // Panel navy dengan gradient
    for (int x = 0; x < panelW; x++) {
      final t = x / panelW;
      final r = 10 + (t * 5).toInt();
      final g = 15 + (t * 5).toInt();
      final b = 40 + (t * 10).toInt();
      img.fillRect(src, x1: x, y1: 0, x2: x, y2: src.height - 1,
          color: img.ColorRgba8(r, g, b, 240));
    }

    // Garis pemisah dengan glow
    img.fillRect(src, x1: panelW - 2, y1: 0, x2: panelW, y2: src.height - 1,
        color: img.ColorRgba8(0, 180, 255, 40));
    img.fillRect(src, x1: panelW, y1: 0, x2: panelW + 3, y2: src.height - 1,
        color: img.ColorRgba8(0, 180, 255, 200));

    final font = img.arial24;
    int cy = 24;

    // Jam — digit besar per baris
    final timeStr = DateFormat('HH').format(timestamp);
    final minStr = DateFormat('mm').format(timestamp);
    final secStr = DateFormat('ss').format(timestamp);
    
    _drawCentered(src, timeStr, font, panelW, cy, WatermarkLayoutBase.white);
    cy += lineH;
    _drawCentered(src, minStr, font, panelW, cy, WatermarkLayoutBase.white);
    cy += lineH;
    _drawCentered(src, secStr, font, panelW, cy, WatermarkLayoutBase.blue);
    cy += lineH + 12;

    // Tanggal
    _drawCentered(src, DateFormat('dd').format(timestamp), font, panelW, cy, WatermarkLayoutBase.white);
    cy += lineH;
    _drawCentered(src, DateFormat('MMM').format(timestamp), font, panelW, cy, WatermarkLayoutBase.blue);
    cy += lineH;
    _drawCentered(src, DateFormat('yyyy').format(timestamp), font, panelW, cy, WatermarkLayoutBase.grey);
    cy += lineH + 16;

    // Divider kecil
    img.fillRect(src, x1: padX + 10, y1: cy, x2: panelW - 10, y2: cy + 1,
        color: img.ColorRgba8(255, 255, 255, 40));
    cy += 12;

    // Koordinat
    if (hasPosition) {
      final latStr = '${lat!.toStringAsFixed(4)}°';
      final lonStr = '${lon!.toStringAsFixed(4)}°';
      img.drawString(src, latStr, font: font, x: padX, y: cy, color: WatermarkLayoutBase.grey);
      cy += 20;
      img.drawString(src, lonStr, font: font, x: padX, y: cy, color: WatermarkLayoutBase.grey);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  void _drawCentered(img.Image src, String text, img.BitmapFont font, int panelW, int y, img.Color color) {
    // Perkiraan lebar teks (arial24 ≈ 12px per karakter)
    final textW = text.length * 12;
    final x = (panelW - textW) ~/ 2;
    if (x > 0) {
      img.drawString(src, text, font: font, x: x, y: y, color: color);
    }
  }
}
