// lib/watermark/layouts/layout_field_survey.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutFieldSurvey extends WatermarkLayoutBase {
  @override
  String get name => 'Field Survey';

  static const bool _positionBottom = true; // full width bottom

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
    final int headerH = (28 * scale).round();
    final int rowH = (24 * scale).round();
    final int padX = (12 * scale).round();
    final int colW = (60 * scale).round();

    final img.BitmapFont font = fontSize == 'small' ? img.arial14 : img.arial24;

    final List<Map<String, String>> rows = [
      {'label': 'DATE', 'value': DateFormat('yyyy-MM-dd').format(timestamp)},
      {'label': 'TIME', 'value': DateFormat('HH:mm:ss').format(timestamp)},
    ];
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      rows.add({'label': 'LAT', 'value': lat.toStringAsFixed(6)});
      rows.add({'label': 'LON', 'value': lon.toStringAsFixed(6)});
      if (showAccuracy && acc != null) {
        rows.add({'label': 'ACC', 'value': '±${acc.toStringAsFixed(0)} m'});
      }
    }
    if (showAddress && address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      final maxChars = (src.width / 6).toInt().clamp(30, 50);
      final shortAddr = address.length > maxChars ? '${address.substring(0, maxChars - 1)}…' : address;
      rows.add({'label': 'ADDR', 'value': shortAddr});
    }
    if (showWeather && weather.isNotEmpty) {
      rows.add({'label': 'WX', 'value': weather});
    }

    final int totalH = headerH + rows.length * rowH + 8;
    final int y0 = _positionBottom ? src.height - totalH : 0;
    if (y0 < 0) return WatermarkLayoutBase.encodeJpg(src);

    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + totalH,
        color: img.ColorRgba8(0, 0, 0, (200 * opacity).toInt()));

    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + headerH,
        color: WatermarkLayoutBase.blue);
    img.drawString(src, 'FIELD SURVEY', font: font, x: padX + 1, y: y0 + 6 + 1,
        color: img.ColorRgba8(0, 0, 0, 80));
    img.drawString(src, 'FIELD SURVEY', font: font, x: padX, y: y0 + 6,
        color: WatermarkLayoutBase.white);

    int cy = y0 + headerH;
    for (int i = 0; i < rows.length; i++) {
      final bgColor = i.isEven ? img.ColorRgba8(255, 255, 255, 12) : img.ColorRgba8(0, 0, 0, 0);
      img.fillRect(src, x1: 0, y1: cy, x2: src.width - 1, y2: cy + rowH, color: bgColor);
      img.drawString(src, rows[i]['label']!, font: font, x: padX, y: cy + (rowH / 2 - 10).round(),
          color: WatermarkLayoutBase.grey);
      img.drawString(src, rows[i]['value']!, font: font, x: padX + colW, y: cy + (rowH / 2 - 10).round(),
          color: WatermarkLayoutBase.white);
      if (i < rows.length - 1) {
        img.fillRect(src, x1: padX, y1: cy + rowH - 1, x2: src.width - padX, y2: cy + rowH,
            color: img.ColorRgba8(255, 255, 255, 8));
      }
      cy += rowH;
    }

    if (showBorder) {
      img.drawRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + totalH - 1,
          color: img.ColorRgba8(30, 144, 255, 60), thickness: 1);
    }
    return WatermarkLayoutBase.encodeJpg(src);
  }
}
