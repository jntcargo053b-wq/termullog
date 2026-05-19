// lib/watermark/layouts/layout_minimalist_clean.dart
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';
import '../../core/constants.dart';
import '../watermark_utils.dart';

class LayoutMinimalistClean extends WatermarkLayoutBase {
  @override
  String get name => 'Minimalist Clean';

  @override
  img.Image apply({
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
    required Uint8List? mapBytes,
    required bool showAddress,
    required bool showCoordinates,
    required double opacity,
    required bool showBorder,
    required String fontSize,
  }) {
    final double fontSizeValue = getFontSizeValue(fontSize) - 2;
    const int margin = 12;
    
    // Posisi pojok
    final int xPos = margin;
    final int yPos = watermarkPosition == 'bottom'
        ? src.height - 60 - margin
        : margin + 40;
    
    // Teks timestamp (tanpa background)
    final timeStr = DateFormat('HH:mm:ss').format(timestamp);
    final dateStr = DateFormat('dd/MM/yyyy').format(timestamp);
    
    WatermarkUtils.drawTextWithShadow(
      src, '$dateStr  $timeStr', xPos, yPos,
      kColorWhite, WatermarkFontManager.getRegular(fontSizeValue + 2),
      shadowOffset: 1,
    );
    
    int lineY = yPos + 22;
    
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final coordStr = '${lat.toStringAsFixed(5)}°, ${lon.toStringAsFixed(5)}°';
      WatermarkUtils.drawTextWithShadow(
        src, coordStr, xPos, lineY,
        kColorWhite70, WatermarkFontManager.getRegular(fontSizeValue - 2),
        shadowOffset: 1,
      );
      lineY += 18;
    }
    
    if (showAccuracy && acc != null) {
      final accStr = '±${acc!.toStringAsFixed(1)}m';
      WatermarkUtils.drawTextWithShadow(
        src, accStr, xPos, lineY,
        kColorWhite70, WatermarkFontManager.getRegular(fontSizeValue - 3),
        shadowOffset: 1,
      );
    }
    
    return src;
  }
}
