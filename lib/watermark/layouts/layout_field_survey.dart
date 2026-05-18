// lib/watermark/layouts/layout_field_survey.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutFieldSurvey extends WatermarkLayoutBase {
  @override
  String get name => 'Field Survey';

  static const int headerH = 28;
  static const int rowH = 24;
  static const int padX = 12;
  static const int colW = 60;

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
    final font = fontSize == 'small' ? img.arial14 : fontSize == 'large' ? img.arial24 : img.arial14;
    final int rowCount = (hasPosition ? 4 : 1) + (showAccuracy && hasPosition ? 1 : 0);
    final int totalH = headerH + rowCount * rowH + 8;
    final bool isTop = watermarkPosition == 'top';
    final int y0 = isTop ? 0 : src.height - totalH;
    if (y0 < 0) return WatermarkLayoutBase.encodeJpg(src);

    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + totalH,
        color: img.ColorRgba8(0, 0, 0, (200 * opacity).toInt()));

    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + headerH,
        color: WatermarkLayoutBase.blue);
    img.drawString(src, 'FIELD SURVEY',
        font: font, x: padX, y: y0 + 6, color: img.ColorRgba8(255, 255, 255, 255));

    int cy = y0 + headerH;
    final rows = <Map<String, String>>[
      {'label': 'DATE', 'value': DateFormat('yyyy-MM-dd').format(timestamp)},
      {'label': 'TIME', 'value': DateFormat('HH:mm:ss').format(timestamp)},
    ];
    if (showCoordinates && hasPosition) {
      rows.add({'label': 'LAT', 'value': lat!.toStringAsFixed(6)});
      rows.add({'label': 'LON', 'value': lon!.toStringAsFixed(6)});
      if (showAccuracy) {
        rows.add({'label': 'ACC', 'value': '±${acc?.toStringAsFixed(0) ?? '?'} m'});
      }
    }

    for (int i = 0; i < rows.length; i++) {
      final bgColor = i.isEven
          ? img.ColorRgba8(255, 255, 255, 15)
          : img.ColorRgba8(0, 0, 0, 0);
      img.fillRect(src, x1: 0, y1: cy, x2: src.width - 1, y2: cy + rowH, color: bgColor);

      img.drawString(src, rows[i]['label']!,
          font: font, x: padX, y: cy + 4, color: WatermarkLayoutBase.grey);
      img.drawString(src, rows[i]['value']!,
          font: font, x: padX + colW, y: cy + 4, color: WatermarkLayoutBase.white);
      cy += rowH;
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }
}
