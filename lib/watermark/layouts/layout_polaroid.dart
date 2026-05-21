// lib/watermark/layouts/layout_polaroid.dart
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'package:image/src/font/arial_24.dart';
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
    // Add polaroid border
    final int border = 20;
    final int bottomBorder = 60; // Sedikit lebih besar untuk kenyamanan
    final img.Image result = img.Image(
      width: src.width + border * 2,
      height: src.height + border + bottomBorder,
    );
    
    // Ivory background - perbaikan fill
    img.fill(result, kColorIvory);
    
    // Add photo
    img.compositeImage(result, src, dstX: border, dstY: border);
    
    // Caption dengan perhitungan posisi yang lebih akurat
    final String caption = DateFormat('dd MMM yyyy').format(timestamp);
    
    // Perbaikan: Hitung lebar teks dengan lebih akurat
    // Untuk font arial24, perkiraan lebar per karakter sekitar 12-14 pixel
    final int approxCharWidth = 12;
    final int captionWidth = caption.length * approxCharWidth;
    final int captionX = border + ((src.width - captionWidth) ~/ 2);
    final int captionY = border + src.height + (bottomBorder ~/ 2) + 8; // +8 untuk centering vertikal
    
    // Pastikan posisi tidak negatif
    final int safeCaptionX = captionX < border ? border : captionX;
    
    img.drawString(result, img.arial24, safeCaptionX, captionY, caption, color: kColorDarkText);
    
    // Optional: Tambahkan garis pemisah seperti polaroid asli
    if (showBorder) {
      final int lineY = border + src.height + 5;
      img.drawLine(result, border, lineY, border + src.width, lineY, kColorLightGrey);
    }
    
    return WatermarkLayoutBase.encodeJpg(result);
  }
}
