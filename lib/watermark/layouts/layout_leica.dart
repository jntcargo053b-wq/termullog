import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'watermark_layout_base.dart';
import '../../core/constants.dart';

class LayoutLeica extends WatermarkLayoutBase {
  @override
  String get name => 'Leica';

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
    final double scale = (src.width / 1080).clamp(0.7, 1.5);
    final int margin = 20;
    final int panelW = (220 * scale).toInt();
    final int x = src.width - margin - panelW;

    // Kumpulkan semua baris teks
    final List<String> lines = [];
    lines.add(DateFormat('yyyy-MM-dd').format(timestamp));
    lines.add(DateFormat('HH:mm:ss').format(timestamp));
    
    if (hasPosition && showCoordinates && lat != null && lon != null) {
      lines.add('${lat.toStringAsFixed(4)}° ${lon.toStringAsFixed(4)}°');
    }
    if (showAccuracy && acc != null) {
      lines.add('±${acc.toStringAsFixed(1)}m');
    }
    if (showAddress && address.isNotEmpty && !address.startsWith('GPS:') && address != 'Tidak ada lokasi') {
      final maxChars = WatermarkLayoutBase.safeMaxChars(panelW, 11);
      final wrapped = WatermarkLayoutBase.wrapText(address, maxChars);
      lines.addAll(wrapped.split('\n'));
    }
    if (showWeather && weather.isNotEmpty) {
      lines.add(weather);
    }

    final int lineH = WatermarkLayoutBase.getLineHeight(fontSize, scale, small: false);
    final int smallLineH = WatermarkLayoutBase.getLineHeight(fontSize, scale, small: true);
    final int topMargin = (12 * scale).toInt();
    final int panelH = topMargin + 
        (lines.length * (lines.length < 3 ? lineH : smallLineH)) + 8;

    int y = src.height - margin - panelH + topMargin;

    // Lingkaran merah Leica
    img.fillCircle(src, src.width - margin - 12, y + 12, 6, kColorRed);

    for (int i = 0; i < lines.length; i++) {
      final bool isMain = i < 2;
      final int lineHeight = isMain ? lineH : smallLineH;
      final img.BitmapFont font = isMain ? img.arial14 : img.arial12;
      final int textColor = isMain ? kColorWhite : kColorLightGrey;
      
      WatermarkLayoutBase.drawTextWithShadow(
        src, lines[i], x, y,
        font: font, color: textColor,
      );
      y += lineHeight + 4;
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }
}
