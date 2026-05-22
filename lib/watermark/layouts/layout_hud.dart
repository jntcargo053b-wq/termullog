// lib/watermark/layouts/layout_hud.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutHUD extends WatermarkLayoutBase {
  @override
  String get name => 'HUD';

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
    final int padX = (16 * scale).round();
    final int rowH = (32 * scale).round();
    final img.BitmapFont font = fontSize == 'small' ? img.arial14 : img.arial24;

    final dateStr = DateFormat('dd/MM/yyyy').format(timestamp);
    final timeStr = DateFormat('HH:mm:ss').format(timestamp);
    final String top = '$dateStr  $timeStr';

    int lines = 1;
    if (showCoordinates && hasPosition) lines++;
    if (showAccuracy && hasPosition) lines++;

    final int panelH = lines * rowH + 16;
    final int y0 = _positionBottom ? src.height - panelH - 16 : 16;

    final img.Color bgColor = img.ColorRgba8(0, 0, 0, (200 * opacity).toInt());
    img.fillRect(src, x1: 0, y1: y0, x2: src.width, y2: y0 + panelH, color: bgColor);
    if (showBorder) {
      img.drawRect(src, x1: 0, y1: y0, x2: src.width, y2: y0 + panelH,
          color: WatermarkLayoutBase.white, thickness: 1);
    }

    int cy = y0 + 8;
    img.drawString(src, top, font: font, x: padX, y: cy, color: WatermarkLayoutBase.white);
    cy += rowH;
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final coord = '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';
      img.drawString(src, coord, font: font, x: padX, y: cy, color: WatermarkLayoutBase.blue);
      cy += rowH;
    }
    if (showAccuracy && hasPosition && acc != null) {
      final accStr = 'Accuracy: ±${acc.toStringAsFixed(1)}m';
      img.drawString(src, accStr, font: font, x: padX, y: cy, color: WatermarkLayoutBase.grey);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }
}
