// lib/watermark/layouts/layout_timemark_style.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutTimeMarkStyle extends WatermarkLayoutBase {
  @override
  String get name => 'TimeMark Style';

  @override
  Uint8List apply({
    required img.Image src,
    required DateTime timestamp,
    required bool hasPosition,
    required double? lat, required double? lon, required double? acc,
    required String address, required String weather,
    required bool showWeather, required bool showAccuracy,
    required bool showMiniMap,
    Uint8List? mapBytes,
    bool showAddress = true, bool showCoordinates = true,
    double opacity = 0.85, bool showBorder = true, String fontSize = 'normal',
  }) {
    final double scale = (src.width / 1080).clamp(0.7, 2.0);
    final int panelH = (200 * scale).round();
    final int padX = (24 * scale).round();
    final int y0 = src.height - panelH;
    if (y0 < 0) return WatermarkLayoutBase.encodeJpg(src);

    const m = 12;
    // Card HITAM
    img.fillRect(src, x1: m, y1: y0 + m, x2: src.width - m, y2: y0 + panelH - m,
        color: img.ColorRgba8(0, 0, 0, (200 * opacity).toInt()));

    // Border PUTIH tipis
    img.drawRect(src, x1: m, y1: y0 + m, x2: src.width - m, y2: y0 + panelH - m,
        color: img.ColorRgba8(255, 255, 255, 40), thickness: 1);

    final font = fontSize == 'small' ? img.arial14 : img.arial24;
    int cy = y0 + 24;

    // Jam BESAR — PUTIH
    img.drawString(src, DateFormat('HH:mm').format(timestamp),
        font: font, x: padX, y: cy, color: WatermarkLayoutBase.white);
    cy += (40 * scale).round();

    // Tanggal — PUTIH
    img.drawString(src, DateFormat('EEEE, dd MMMM yyyy', 'id').format(timestamp),
        font: font, x: padX, y: cy, color: WatermarkLayoutBase.white);
    cy += (28 * scale).round();

    // Koordinat — BIRU
    if (showCoordinates && hasPosition) {
      img.drawString(src, '${lat!.toStringAsFixed(5)}°  ${lon!.toStringAsFixed(5)}°',
          font: font, x: padX, y: cy, color: WatermarkLayoutBase.blue);
      cy += (26 * scale).round();
    }

    // Akurasi — ABU-ABU
    if (showAccuracy && hasPosition) {
      img.drawString(src, '± ${acc?.toStringAsFixed(0) ?? '?'} m',
          font: font, x: padX, y: cy, color: WatermarkLayoutBase.grey);
      cy += (24 * scale).round();
    }

    // Alamat — PUTIH
    if (showAddress && address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      final lines = _split(address);
      for (final line in lines.take(2)) {
        img.drawString(src, line, font: font, x: padX, y: cy, color: WatermarkLayoutBase.white);
        cy += (22 * scale).round();
      }
    }

    // Cuaca — BIRU
    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, weather, font: font, x: padX, y: cy, color: WatermarkLayoutBase.blue);
    }

    // Mini map
    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) {
      try {
        final map = img.decodeImage(mapBytes);
        if (map != null) {
          final sz = (120 * scale).round();
          final resized = img.copyResize(map, width: sz, height: sz);
          final mx = src.width - sz - padX;
          final my = y0 + panelH - sz - 20;
          img.drawRect(src, x1: mx - 1, y1: my - 1, x2: mx + sz, y2: my + sz,
              color: WatermarkLayoutBase.blue, thickness: 2);
          img.compositeImage(src, resized, dstX: mx, dstY: my, blend: img.BlendMode.alpha);
        }
      } catch (_) {}
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  List<String> _split(String a) {
    final parts = a.split(',');
    if (parts.length <= 2) return [a];
    return [parts.take(2).join(',').trim(), parts.skip(2).join(',').trim()];
  }
}
