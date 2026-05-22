// lib/watermark/layouts/layout_field_survey.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutFieldSurvey extends WatermarkLayoutBase {
  @override
  String get name => 'Field Survey';

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
    final int rowH = WatermarkLayoutBase.getLineHeight(fontSize, scale, small: false);
    final int padX = (14 * scale).round();
    final int colW = (60 * scale).round();

    final img.BitmapFont fontRow = fontSize == 'small' ? img.arial14 : img.arial24;
    final img.BitmapFont fontHeader = fontSize == 'small' ? img.arial14 : img.arial24;

    final List<Map<String, String>> rows = [];

    rows.add({'label': 'DATE', 'value': DateFormat('yyyy-MM-dd').format(timestamp)});
    rows.add({'label': 'TIME', 'value': DateFormat('HH:mm:ss').format(timestamp)});

    if (showCoordinates && hasPosition && lat != null && lon != null) {
      rows.add({'label': 'LAT', 'value': lat.toStringAsFixed(6)});
      rows.add({'label': 'LON', 'value': lon.toStringAsFixed(6)});
      if (showAccuracy && acc != null) {
        rows.add({'label': 'ACC', 'value': '±${acc.toStringAsFixed(0)} m'});
      }
    }

    if (showAddress && address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      final int maxChars = WatermarkLayoutBase.safeMaxChars(src.width, 12);
      final String wrapped = WatermarkLayoutBase.wrapText(address, maxChars);
      final List<String> lines = wrapped.split('\n');
      for (int i = 0; i < lines.length; i++) {
        final String displayLine = i == 0 ? lines[i] : '   ${lines[i]}';
        rows.add({'label': i == 0 ? 'ADDR' : '', 'value': displayLine});
      }
    }

    if (showWeather && weather.isNotEmpty) {
      rows.add({'label': 'WX', 'value': weather});
    }

    final int totalH = headerH + rows.length * rowH + 8;
    final int y0 = src.height - totalH;
    if (y0 < 0) return WatermarkLayoutBase.encodeJpg(src);

    // Background panel (warna proper)
    final img.Color bgColor = img.ColorRgba8(0, 0, 0, (200 * opacity).toInt());
    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + totalH, color: bgColor);

    // Header biru
    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + headerH,
        color: WatermarkLayoutBase.blue);
    WatermarkLayoutBase.drawTextWithShadow(
      src, 'FIELD SURVEY', padX, y0 + 6,
      font: fontHeader, color: WatermarkLayoutBase.white,
    );

    int cy = y0 + headerH;
    for (int i = 0; i < rows.length; i++) {
      final bool isEven = i.isEven;
      final img.Color stripeColor = isEven
          ? img.ColorRgba8(255, 255, 255, 12)
          : img.ColorRgba8(0, 0, 0, 0);
      img.fillRect(src, x1: 0, y1: cy, x2: src.width - 1, y2: cy + rowH, color: stripeColor);

      final String label = rows[i]['label']!;
      if (label.isNotEmpty) {
        img.drawString(src, label, font: fontRow, x: padX, y: cy + (rowH ~/ 2 - 8),
            color: WatermarkLayoutBase.grey);
      }
      img.drawString(src, rows[i]['value']!, font: fontRow,
          x: padX + colW, y: cy + (rowH ~/ 2 - 8),
          color: WatermarkLayoutBase.white);

      if (i < rows.length - 1) {
        img.fillRect(src,
            x1: padX, y1: cy + rowH - 1,
            x2: src.width - padX, y2: cy + rowH,
            color: img.ColorRgba8(255, 255, 255, 8));
      }
      cy += rowH;
    }

    if (showBorder) {
      img.drawRect(src,
          x1: 0, y1: y0,
          x2: src.width - 1, y2: y0 + totalH - 1,
          color: img.ColorRgba8(30, 144, 255, 60), thickness: 1);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }
}
