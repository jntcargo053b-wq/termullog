// lib/watermark/layouts/layout_cinematic.dart
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';
import '../../core/constants.dart';
import '../watermark_utils.dart';

class LayoutCinematic extends WatermarkLayoutBase {
  @override
  String get name => 'Cinematic';

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
    const int watermarkHeight = 110;
    const int margin = 20;
    final double fontSizeValue = getFontSizeValue(fontSize);
    
    // Tentukan posisi Y (TOP atau BOTTOM)
    final int yPos = getYPosition(src.height, watermarkHeight, watermarkPosition, margin);
    
    // Background dengan gradasi
    final bgStart = img.ColorRgba8(0, 0, 0, (255 * 0.9).toInt());
    final bgEnd = img.ColorRgba8(0, 0, 0, (255 * 0.6).toInt());
    WatermarkUtils.drawGradientBackground(src, 0, yPos, src.width, watermarkHeight, bgStart, bgEnd);
    
    // Garis aksen atas (gaya sinematik)
    img.drawRect(src, x: 0, y: yPos, width: src.width, height: 4, color: kColorGold);
    
    // Format waktu
    final timeStr = DateFormat('HH:mm:ss').format(timestamp);
    final dateStr = DateFormat('dd MMM yyyy', 'id').format(timestamp);
    
    // Teks waktu (besar)
    WatermarkUtils.drawTextWithShadow(
      src, timeStr, 20, yPos + 25,
      kColorWhite, WatermarkFontManager.getBold(28),
    );
    
    // Teks tanggal
    WatermarkUtils.drawTextWithShadow(
      src, dateStr, 20, yPos + 60,
      kColorGold, WatermarkFontManager.getRegular(14),
    );
    
    int lineY = yPos + 85;
    
    // Koordinat
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final coordStr = '${lat.toStringAsFixed(4)}°N, ${lon.toStringAsFixed(4)}°E';
      WatermarkUtils.drawTextWithShadow(
        src, coordStr, 20, lineY,
        kColorGrey, WatermarkFontManager.getRegular(11),
      );
      lineY += 18;
    }
    
    // Akurasi
    if (showAccuracy && acc != null) {
      final accuracyColor = getAccuracyColor(acc);
      final accStr = 'Accuracy: ±${acc!.toStringAsFixed(1)}m';
      WatermarkUtils.drawTextWithShadow(
        src, accStr, 20, lineY,
        accuracyColor, WatermarkFontManager.getRegular(11),
      );
      lineY += 18;
    }
    
    // Cuaca
    if (showWeather && weather.isNotEmpty) {
      final weatherStr = 'Weather: $weather';
      WatermarkUtils.drawTextWithShadow(
        src, weatherStr, 20, lineY,
        kColorCyan, WatermarkFontManager.getRegular(11),
      );
    }
    
    return src;
  }
}
