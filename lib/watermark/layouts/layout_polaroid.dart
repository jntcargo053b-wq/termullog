import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'watermark_layout_base.dart';
import '../../core/constants.dart';

class LayoutPolaroid extends WatermarkLayoutBase {
  @override
  String get name => 'Polaroid';

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
    final int border = 20;
    final int bottomBorder = 80;
    final img.Image result = img.Image(
      width: src.width + border * 2,
      height: src.height + border + bottomBorder,
    );

    img.fill(result, kColorIvory);
    img.compositeImage(result, src, dstX: border, dstY: border);

    final String dateStr = DateFormat('dd MMM yyyy').format(timestamp);
    final String timeStr = DateFormat('HH:mm').format(timestamp);

    final int dateWidth = dateStr.length * 12;
    final int dateX = border + ((src.width - dateWidth) ~/ 2);
    final int dateY = border + src.height + 20;
    img.drawString(result, img.arial24, dateX, dateY, dateStr, color: kColorDarkText);

    final int timeWidth = timeStr.length * 8;
    final int timeX = border + ((src.width - timeWidth) ~/ 2);
    final int timeY = dateY + 28;
    img.drawString(result, img.arial14, timeX, timeY, timeStr, color: kColorDarkText);

    if (hasPosition && showCoordinates && lat != null && lon != null) {
      final String coordStr = '${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°';
      final int coordWidth = coordStr.length * 6;
      final int coordX = border + ((src.width - coordWidth) ~/ 2);
      final int coordY = timeY + 24;
      img.drawString(result, img.arial14, coordX, coordY, coordStr, color: kColorLightGrey);
    }

    if (showBorder) {
      final int lineY = border + src.height + 5;
      img.drawLine(result, border, lineY, border + src.width, lineY, kColorLightGrey);
    }

    return WatermarkLayoutBase.encodeJpg(result);
  }
}
