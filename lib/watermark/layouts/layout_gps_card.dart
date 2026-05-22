// lib/watermark/layouts/layout_gps_card.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutGpsCard extends WatermarkLayoutBase {
  @override
  String get name => 'GPS Card';

  static const int padX = 16;
  static const int padY = 14;
  static const int panelH = 150;
  static const int mapW = 160;
  static const int mapH = 100;
  static const int lineH = 28;

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
    final bool isTop = false;
    final int y0 = isTop ? 0 : src.height - panelH;
    if (y0 < 0 || y0 >= src.height) return WatermarkLayoutBase.encodeJpg(src);

    final font = fontSize == 'small' ? img.arial14 : fontSize == 'large' ? img.arial24 : img.arial24;
    final smallFont = fontSize == 'small' ? img.arial14 : fontSize == 'large' ? img.arial24 : img.arial14;

    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + panelH,
        color: img.ColorRgba8(0, 0, 10, (230 * opacity).toInt()));
    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + 4,
        color: img.ColorRgba8(0, 180, 255, 255));

    int cy = y0 + padY;

    img.fillCircle(src, x: padX + 6, y: cy + 10, radius: 5,
        color: img.ColorRgba8(255, 50, 50, 255));
    img.fillCircle(src, x: padX + 6, y: cy + 10, radius: 2,
        color: WatermarkLayoutBase.white);

    img.drawString(src, DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp),
        font: font, x: padX + 16, y: cy, color: WatermarkLayoutBase.white);
    cy += lineH;

    if (showCoordinates && hasPosition) {
      img.drawString(src, '${lat!.toStringAsFixed(6)}  ${lon!.toStringAsFixed(6)}',
          font: font, x: padX + 16, y: cy, color: img.ColorRgba8(0, 180, 255, 255));
      cy += lineH;
    }

    if (showAccuracy && hasPosition) {
      img.drawString(src, '±${acc?.toStringAsFixed(0) ?? '?'} m',
          font: smallFont, x: padX + 16, y: cy, color: WatermarkLayoutBase.grey);
      cy += lineH;
    }

    if (showAddress && address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      final shortAddr = address.length > 45 ? '${address.substring(0, 44)}…' : address;
      img.drawString(src, shortAddr,
          font: smallFont, x: padX + 16, y: cy, color: WatermarkLayoutBase.grey);
      cy += lineH;
    }

    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, weather,
          font: smallFont, x: padX + 16, y: cy, color: img.ColorRgba8(0, 180, 255, 255));
    }

    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) {
      try {
        final map = img.decodeImage(mapBytes);
        if (map != null) {
          final resized = img.copyResize(map, width: mapW, height: mapH);
          final mx = src.width - mapW - padX;
          final my = y0 + 25;
          if (mx >= 0 && my >= 0) {
            img.drawRect(src, x1: mx - 2, y1: my - 2, x2: mx + mapW + 1, y2: my + mapH + 1,
                color: img.ColorRgba8(0, 180, 255, 100));
            img.compositeImage(src, resized, dstX: mx, dstY: my, blend: img.BlendMode.alpha);
          }
        }
      } catch (_) {}
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }
}
