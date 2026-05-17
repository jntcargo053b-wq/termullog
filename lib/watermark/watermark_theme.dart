// lib/watermark/watermark_theme.dart
import 'package:image/image.dart' as img;

/// Konfigurasi tema untuk watermark
class WatermarkThemeConfig {
  final img.Color background;
  final img.Color primaryText;
  final img.Color secondaryText;
  final img.Color accent;
  final img.Color border;
  final double backgroundOpacity;

  const WatermarkThemeConfig({
    required this.background,
    required this.primaryText,
    required this.secondaryText,
    required this.accent,
    required this.border,
    this.backgroundOpacity = 0.85,
  });

  /// Tema gelap (default)
  static const dark = WatermarkThemeConfig(
    background: img.ColorRgba8(0, 0, 0, 200),
    primaryText: img.ColorRgba8(255, 255, 255, 255),
    secondaryText: img.ColorRgba8(200, 200, 200, 255),
    accent: img.ColorRgba8(30, 144, 255, 255),
    border: img.ColorRgba8(255, 255, 255, 40),
  );

  /// Tema terang
  static const light = WatermarkThemeConfig(
    background: img.ColorRgba8(255, 255, 255, 200),
    primaryText: img.ColorRgba8(30, 30, 30, 255),
    secondaryText: img.ColorRgba8(100, 100, 100, 255),
    accent: img.ColorRgba8(0, 120, 210, 255),
    border: img.ColorRgba8(0, 0, 0, 30),
  );

  /// Tema Kodak retro
  static const kodak = WatermarkThemeConfig(
    background: img.ColorRgba8(20, 15, 10, 230),
    primaryText: img.ColorRgba8(255, 140, 50, 255),
    secondaryText: img.ColorRgba8(200, 160, 100, 255),
    accent: img.ColorRgba8(255, 200, 50, 255),
    border: img.ColorRgba8(255, 140, 50, 80),
  );

  /// Tema sinematik
  static const cinematic = WatermarkThemeConfig(
    background: img.ColorRgba8(0, 0, 15, 220),
    primaryText: img.ColorRgba8(220, 225, 235, 255),
    secondaryText: img.ColorRgba8(140, 150, 165, 255),
    accent: img.ColorRgba8(30, 144, 255, 255),
    border: img.ColorRgba8(30, 144, 255, 60),
  );

  /// Tema survey profesional
  static const survey = WatermarkThemeConfig(
    background: img.ColorRgba8(0, 0, 10, 235),
    primaryText: img.ColorRgba8(255, 255, 255, 255),
    secondaryText: img.ColorRgba8(150, 150, 150, 255),
    accent: img.ColorRgba8(0, 180, 255, 255),
    border: img.ColorRgba8(0, 180, 255, 100),
  );

  /// Mendapatkan tema berdasarkan enum
  static WatermarkThemeConfig fromTheme(WatermarkTheme theme) {
    switch (theme) {
      case WatermarkTheme.light: return light;
      case WatermarkTheme.kodak: return kodak;
      case WatermarkTheme.cinematic: return cinematic;
      case WatermarkTheme.survey: return survey;
      case WatermarkTheme.dark:
      default:
        return dark;
    }
  }
}
