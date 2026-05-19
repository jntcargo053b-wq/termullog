// lib/watermark/layouts/layout_modern_card.dart
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';
import '../../core/constants.dart';
import '../watermark_utils.dart';

class LayoutModernCard extends WatermarkLayoutBase {
  @override
  String get name => 'Modern Card';

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
    const int cardWidth = 280;
    const int cardHeight = 130;
    const int margin = 20;
    final double fontSizeValue = getFontSizeValue(fontSize);
    
    // Posisi card
    final int xPos = src.width - cardWidth - margin;
    final int yPos = watermarkPosition == 'bottom'
        ? src.height - cardHeight - margin
        : margin;
    
    // Background glassmorphism
    WatermarkUtils.drawGlassmorphism(src, xPos, yPos, cardWidth, cardHeight, opacity: 0.85);
    
    // Border aksen kiri
    img.drawRect(src, x: xPos, y: yPos, width: 5, height: cardHeight, color: kColorCyan);
    
    // Icon GPS
    // (menggunakan teks sebagai pengganti icon)
    final timeStr = DateFormat('HH:mm').format(timestamp);
    final dateStr = DateFormat('dd/MM/yyyy').format(timestamp);
    
    // Header
    WatermarkUtils.drawTextWithShadow(
      src, timeStr, xPos + 20, yPos + 20,
      kColorWhite, WatermarkFontManager.getBold(20),
    );
    
    WatermarkUtils.drawTextWithShadow(
      src, dateStr, xPos + 20, yPos + 45,
      kColorGrey, WatermarkFontManager.getRegular(12),
    );
    
    int lineY = yPos + 70;
    
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final coordStr = '📍 ${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°';
      WatermarkUtils.drawTextWithShadow(
        src, coordStr, xPos + 20, lineY,
        kColorCyan, WatermarkFontManager.getRegular(11),
      );
      lineY += 18;
    }
    
    if (showAccuracy && acc != null) {
      final accStr = '🎯 ±${acc!.toStringAsFixed(1)}m';
      WatermarkUtils.drawTextWithShadow(
        src, accStr, xPos + 20, lineY,
        kColorWhite70, WatermarkFontManager.getRegular(11),
      );
    }
    
    return src;
  }
}
