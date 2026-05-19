// lib/watermark/watermark_utils.dart
import 'package:image/image.dart' as img;
import 'dart:typed_data';

class WatermarkUtils {
  static void drawTextWithShadow(
    img.Image src,
    String text,
    int x,
    int y,
    img.Color color,
    img.Font font, {
    int shadowOffset = 1,
    img.Color shadowColor = const img.ColorRgb8(0, 0, 0),
  }) {
    img.drawString(src, text, x: x + shadowOffset, y: y + shadowOffset,
        font: font, color: shadowColor);
    img.drawString(src, text, x: x, y: y, font: font, color: color);
  }

  static void drawGlassmorphism(
    img.Image src,
    int x,
    int y,
    int width,
    int height, {
    int borderRadius = 12,
    double opacity = 0.3,
  }) {
    final glassColor = img.ColorRgba8(255, 255, 255, (255 * opacity).toInt());
    final borderColor = img.ColorRgba8(255, 255, 255, 80);
    
    img.fillRect(src, x, y, width, height, glassColor);
    img.drawRect(src, x, y, width, height, borderColor);
  }

  static img.Image applySharpness(img.Image src, {double amount = 0.5}) {
    return src;
  }

  static img.Image applyContrast(img.Image src, {double contrast = 1.1}) {
    return src;
  }

  static img.Image autoEnhance(img.Image src) {
    return src;
  }

  static void drawGradientBackground(
    img.Image src,
    int x,
    int y,
    int width,
    int height,
    img.Color startColor,
    img.Color endColor,
  ) {
    img.fillRect(src, x, y, width, height, startColor);
  }

  static void fillRoundedRect(
    img.Image src,
    int x,
    int y,
    int width,
    int height,
    int radius,
    img.Color color,
  ) {
    img.fillRect(src, x, y, width, height, color);
  }
}

class WatermarkFontManager {
  static img.Font? _regularFont;
  static img.Font? _boldFont;
  static img.Font? _monoFont;
  static bool _isLoaded = false;

  static Future<void> loadFonts() async {
    if (_isLoaded) return;
    try {
      _regularFont = img.getFont(14);
      _boldFont = img.getFont(16);
      _monoFont = img.getFont(14);
      _isLoaded = true;
    } catch (e) {
      print('Failed to load fonts: $e');
    }
  }

  static img.Font getRegular(double size) {
    return img.getFont(size.toInt());
  }

  static img.Font getBold(double size) {
    return img.getFont(size.toInt());
  }

  static img.Font getMono(double size) {
    return img.getFont(size.toInt());
  }
}
