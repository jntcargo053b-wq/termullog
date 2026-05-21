// lib/watermark/layouts/layout_polaroid.dart
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
    final int bottomBorder = 50;
    final img.Image result = img.Image(
      width: src.width + border * 2,
      height: src.height + border + bottomBorder,
    );
    
    // Ivory background
    img.fill(result, color: kColorIvory);
    
    // Add photo
    img.compositeImage(result, src, dstX: border, dstY: border);
    
    // Caption
    final String caption = DateFormat('dd MMM yyyy').format(timestamp);
    final int captionX = border + (src.width ~/ 2) - (caption.length * 6);
    final int captionY = border + src.height + (bottomBorder ~/ 2);
    img.drawString(result, caption, font: img.arial24, x: captionX, y: captionY, color: kColorDarkText);
    
    return WatermarkLayoutBase.encodeJpg(result);
  }
}
