// lib/watermark/watermark_utils.dart
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart' show rootBundle;
import 'dart:typed_data';

class WatermarkUtils {
  // ============================================================
  // DROP SHADOW UTILITY
  // ============================================================
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
    // Gambar shadow
    img.drawString(src, text, x: x + shadowOffset, y: y + shadowOffset,
        font: font, color: shadowColor);
    // Gambar teks asli
    img.drawString(src, text, x: x, y: y, font: font, color: color);
  }

  // ============================================================
  // GLASSMORPHISM EFFECT
  // ============================================================
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
    
    // Fill dengan warna glass
    img.fillRect(src, x: x, y: y, width: width, height: height, color: glassColor);
    
    // Border tipis
    img.drawRect(src, x: x, y: y, width: width, height: height,
        color: borderColor, thickness: 1);
  }

  // ============================================================
  // SHARPNESS & COLOR ADJUSTMENT
  // ============================================================
  static img.Image applySharpness(img.Image src, {double amount = 0.5}) {
    return img.sharpen(src, amount: amount);
  }

  static img.Image applyContrast(img.Image src, {double contrast = 1.1}) {
    return img.contrast(src, contrast: contrast);
  }

  static img.Image autoEnhance(img.Image src) {
    var result = src;
    // Tingkatkan ketajaman sedikit
    result = img.sharpen(result, amount: 0.3);
    return result;
  }

  // ============================================================
  // GRADIENT BACKGROUND
  // ============================================================
  static void drawGradientBackground(
    img.Image src,
    int x,
    int y,
    int width,
    int height,
    img.Color startColor,
    img.Color endColor,
  ) {
    for (int i = 0; i < height; i++) {
      final double ratio = i / height;
      final r = (startColor.r * (1 - ratio) + endColor.r * ratio).toInt();
      final g = (startColor.g * (1 - ratio) + endColor.g * ratio).toInt();
      final b = (startColor.b * (1 - ratio) + endColor.b * ratio).toInt();
      final a = (startColor.a * (1 - ratio) + endColor.a * ratio).toInt();
      final lineColor = img.ColorRgba8(r, g, b, a);
      img.drawLine(src, x1: x, y1: y + i, x2: x + width, y2: y + i, color: lineColor);
    }
  }

  // ============================================================
  // ROUNDED RECTANGLE
  // ============================================================
  static void fillRoundedRect(
    img.Image src,
    int x,
    int y,
    int width,
    int height,
    int radius,
    img.Color color,
  ) {
    // Fill body
    img.fillRect(src, x: x + radius, y: y, width: width - radius * 2, height: height, color: color);
    img.fillRect(src, x: x, y: y + radius, width: width, height: height - radius * 2, color: color);
    
    // Fill corners
    img.fillCircle(src, x: x + radius, y: y + radius, radius: radius, color: color);
    img.fillCircle(src, x: x + width - radius, y: y + radius, radius: radius, color: color);
    img.fillCircle(src, x: x + radius, y: y + height - radius, radius: radius, color: color);
    img.fillCircle(src, x: x + width - radius, y: y + height - radius, radius: radius, color: color);
  }
}

// ============================================================
// FONT MANAGER
// ============================================================
class WatermarkFontManager {
  static img.Font? _regularFont;
  static img.Font? _boldFont;
  static img.Font? _monoFont;
  static bool _isLoaded = false;

  static Future<void> loadFonts() async {
    if (_isLoaded) return;
    
    try {
      // Load fallback font dari system (gunakan Arial style)
      // Untuk production, sebaiknya pakem font file dari assets
      _regularFont = img.Font.getDefault();
      _boldFont = img.Font.getDefault();
      _monoFont = img.Font.getDefault();
      _isLoaded = true;
    } catch (e) {
      print('Failed to load fonts: $e');
    }
  }

  static img.Font getRegular(double size) {
    return _regularFont ?? img.Font.getDefault();
  }

  static img.Font getBold(double size) {
    return _boldFont ?? img.Font.getDefault();
  }

  static img.Font getMono(double size) {
    return _monoFont ?? img.Font.getDefault();
  }
}
