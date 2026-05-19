// lib/core/constants.dart
import 'package:image/image.dart' as img;

// ============================================================
// OUTPUT & KUALITAS
// ============================================================
const int kMaxOutputWidth = 1600;
const int kJpegQuality = 90;
const int kSigMaxWidth = 260;
const int kLogoMaxWidth = 90;

// ============================================================
// WATERMARK LAYOUT STYLE (VERSI SEDERHANA)
// ============================================================
enum WatermarkLayout {
  minimal,
  dslrCorner,
  cinematic,
  hud,
  polaroid,
  modern,
}

extension WatermarkLayoutExtension on WatermarkLayout {
  static const List<WatermarkLayout> all = [
    WatermarkLayout.minimal,
    WatermarkLayout.dslrCorner,
    WatermarkLayout.cinematic,
    WatermarkLayout.hud,
    WatermarkLayout.polaroid,
    WatermarkLayout.modern,
  ];

  String get displayName {
    switch (this) {
      case WatermarkLayout.minimal:     return 'Minimal';
      case WatermarkLayout.dslrCorner:  return 'DSLR Corner';
      case WatermarkLayout.cinematic:   return 'Cinematic';
      case WatermarkLayout.hud:         return 'HUD';
      case WatermarkLayout.polaroid:    return 'Polaroid';
      case WatermarkLayout.modern:      return 'Modern';
    }
  }

  String get typeString {
    switch (this) {
      case WatermarkLayout.minimal:     return 'minimal';
      case WatermarkLayout.dslrCorner:  return 'dslr_corner';
      case WatermarkLayout.cinematic:   return 'cinematic';
      case WatermarkLayout.hud:         return 'hud';
      case WatermarkLayout.polaroid:    return 'polaroid';
      case WatermarkLayout.modern:      return 'modern';
    }
  }

  static WatermarkLayout fromIndex(int index) {
    if (index >= 0 && index < all.length) return all[index];
    return WatermarkLayout.modern;
  }

  int get index => all.indexOf(this);

  static WatermarkLayout fromTypeString(String type) {
    switch (type) {
      case 'minimal':     return WatermarkLayout.minimal;
      case 'dslr_corner': return WatermarkLayout.dslrCorner;
      case 'cinematic':   return WatermarkLayout.cinematic;
      case 'hud':         return WatermarkLayout.hud;
      case 'polaroid':    return WatermarkLayout.polaroid;
      case 'modern':      return WatermarkLayout.modern;
      default:            return WatermarkLayout.modern;
    }
  }
}

// ============================================================
// WATERMARK COLORS
// ============================================================
final img.Color kColorWhite = img.ColorRgb8(255, 255, 255);
final img.Color kColorCyan = img.ColorRgb8(0, 184, 148);
final img.Color kColorGrey = img.ColorRgb8(210, 210, 210);
final img.Color kColorDarkBg = img.ColorRgba8(15, 23, 42, 230);
final img.Color kColorGold = img.ColorRgb8(255, 180, 50);
final img.Color kColorBlack = img.ColorRgb8(0, 0, 0);
final img.Color kColorLightBlue = img.ColorRgb8(30, 144, 255);

// ============================================================
// GPS CONSTANTS
// ============================================================
const double kTargetAccuracy = 10.0;
const double kGoodAccuracy = 15.0;
const double kMediumAccuracy = 25.0;
const int kGpsTimeoutSeconds = 25;

img.Color getAccuracyColor(double accuracy) {
  if (accuracy <= kTargetAccuracy) return kColorCyan;
  if (accuracy <= kGoodAccuracy) return kColorLightBlue;
  return kColorGold;
}
