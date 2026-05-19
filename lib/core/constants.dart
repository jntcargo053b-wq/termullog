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

// ============================================================
// LAYOUT CATEGORY
// ============================================================
enum LayoutCategory {
  classic,
  modern,
  cinematic,
  data,
  corner,
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

  /// Get layout category
  LayoutCategory get category {
    switch (this) {
      case WatermarkLayout.minimal:
      case WatermarkLayout.polaroid:
        return LayoutCategory.classic;
      case WatermarkLayout.hud:
      case WatermarkLayout.modern:
        return LayoutCategory.modern;
      case WatermarkLayout.cinematic:
        return LayoutCategory.cinematic;
      case WatermarkLayout.dslrCorner:
        return LayoutCategory.corner;
    }
  }

  /// Display name for UI
  String get displayName {
    switch (this) {
      case WatermarkLayout.minimal:     return 'Minimal';
      case WatermarkLayout.dslrCorner:  return 'DSLR Corner';
      case WatermarkLayout.cinematic:   return 'Cinematic';
      case WatermarkLayout.hud:         return 'HUD Modern';
      case WatermarkLayout.polaroid:    return 'Polaroid';
      case WatermarkLayout.modern:      return 'Modern Clean Card';
    }
  }

  /// Description for each layout
  String get description {
    switch (this) {
      case WatermarkLayout.minimal:
        return 'Gaya minimalis sederhana tanpa background';
      case WatermarkLayout.dslrCorner:
        return 'Gaya pojok kamera DSLR dengan informasi lengkap';
      case WatermarkLayout.cinematic:
        return 'Gaya sinematik dengan gradasi halus dan elegan';
      case WatermarkLayout.hud:
        return 'Heads-Up Display modern dengan efek transparan';
      case WatermarkLayout.polaroid:
        return 'Gaya polaroid klasik dengan bingkai ivory';
      case WatermarkLayout.modern:
        return 'Desain bersih, navy gelap, aksen teal modern';
    }
  }

  /// Preview emoji/icon for UI
  String get previewIcon {
    switch (this) {
      case WatermarkLayout.minimal:     return '✨';
      case WatermarkLayout.dslrCorner:  return '📷';
      case WatermarkLayout.cinematic:   return '🎬';
      case WatermarkLayout.hud:         return '🎮';
      case WatermarkLayout.polaroid:    return '🖼️';
      case WatermarkLayout.modern:      return '💳';
    }
  }

  /// Get string identifier for safe storage
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

  /// Get layout by index value (for serialization) - LEGACY
  static WatermarkLayout fromIndex(int index) {
    if (index >= 0 && index < all.length) {
      return all[index];
    }
    return WatermarkLayout.modern;
  }

  /// Get integer index (for serialization) - LEGACY
  int get index {
    return all.indexOf(this);
  }

  /// Get layout from string identifier (safe)
  static WatermarkLayout fromTypeString(String type) {
    switch (type) {
      case 'minimal':
        return WatermarkLayout.minimal;
      case 'dslr_corner':
        return WatermarkLayout.dslrCorner;
      case 'cinematic':
        return WatermarkLayout.cinematic;
      case 'hud':
        return WatermarkLayout.hud;
      case 'polaroid':
        return WatermarkLayout.polaroid;
      case 'modern':
        return WatermarkLayout.modern;
      default:
        return WatermarkLayout.modern;
    }
  }

  /// Check if layout supports dark theme well
  bool get supportsDarkTheme {
    switch (this) {
      case WatermarkLayout.hud:
      case WatermarkLayout.modern:
        return true;
      default:
        return false;
    }
  }

  /// Check if layout supports light theme well
  bool get supportsLightTheme {
    switch (this) {
      case WatermarkLayout.polaroid:
      case WatermarkLayout.minimal:
        return true;
      default:
        return false;
    }
  }
}

// ============================================================
// WATERMARK THEME (GLOBAL STYLE)
// ============================================================
enum WatermarkTheme {
  dark,       // Tema gelap modern
  light,      // Tema terang bersih
  kodak,      // Tema retro Kodak
  cinematic,  // Tema sinematik
  survey,     // Tema survey profesional
}

extension WatermarkThemeExtension on WatermarkTheme {
  String get displayName {
    switch (this) {
      case WatermarkTheme.dark:      return 'Dark Modern';
      case WatermarkTheme.light:     return 'Light Clean';
      case WatermarkTheme.kodak:     return 'Kodak Retro';
      case WatermarkTheme.cinematic: return 'Cinematic';
      case WatermarkTheme.survey:    return 'Survey Pro';
    }
  }
}

// ============================================================
// WATERMARK LAYOUT GEOMETRY
// ============================================================
const int kPanelPaddingX = 25;
const int kSidebarPadX = 18;
const int kAccentBarWidth = 10;
const int kCornerMargin = 20;
const int kTextLineSmall = 18;
const int kTextLineLarge = 28;
const int kSectionGap = 12;
const int kWatermarkPadX = 14;
const int kWatermarkPadY = 12;
const int kHeaderHeight = 22;
const int kRowHeight = 20;
const int kColumnValueWidth = 100;
const int kMaxAddressLength = 45;
const int kMaxAddressLengthShort = 38;
const int kMaxAddressLengthFilmStrip = 42;

// ============================================================
// WATERMARK COLOURS (untuk package image)
// ============================================================
final img.Color kColorWhite = img.ColorRgb8(255, 255, 255);
final img.Color kColorWhite70 = img.ColorRgba8(255, 255, 255, 180);
final img.Color kColorCyan = img.ColorRgb8(0, 184, 148);
final img.Color kColorGrey = img.ColorRgb8(210, 210, 210);
final img.Color kColorDarkBg = img.ColorRgba8(15, 23, 42, 230);
final img.Color kColorDarkBgMed = img.ColorRgba8(15, 23, 42, 210);
final img.Color kColorBlackCard = img.ColorRgba8(0, 0, 0, 170);
final img.Color kColorGlassBg = img.ColorRgba8(0, 0, 0, 120);
final img.Color kColorShadow = img.ColorRgb8(0, 0, 0);
final img.Color kColorLightBlue = img.ColorRgb8(30, 144, 255);
final img.Color kColorDimBlue = img.ColorRgb8(20, 80, 160);
final img.Color kColorOffWhite = img.ColorRgb8(220, 225, 235);
final img.Color kColorDarkGrey = img.ColorRgb8(140, 150, 165);
final img.Color kColorVeryDarkBg = img.ColorRgba8(0, 0, 10, 210);
final img.Color kColorBlackerBg = img.ColorRgba8(0, 0, 8, 235);
final img.Color kColorDimBlue200 = img.ColorRgb8(20, 80, 160);
final img.Color kColorLightGrey = img.ColorRgb8(200, 200, 205);
final img.Color kColorGold = img.ColorRgb8(255, 180, 50);
final img.Color kColorIvory = img.ColorRgb8(248, 245, 235);
final img.Color kColorDarkText = img.ColorRgb8(40, 40, 40);
final img.Color kColorNavy = img.ColorRgba8(10, 15, 40, 240);
final img.Color kColorGpsPanel = img.ColorRgba8(0, 0, 8, 235);
final img.Color kColorGpsAccent = img.ColorRgb8(0, 180, 255);
final img.Color kColorBlue = img.ColorRgb8(0, 120, 255);
final img.Color kColorGreen = img.ColorRgb8(0, 200, 100);
final img.Color kColorRed = img.ColorRgb8(255, 60, 60);
final img.Color kColorOrange = img.ColorRgb8(255, 140, 0);

// ============================================================
// UI COLOURS (Flutter Widget)
// ============================================================
const int kColorNavyUi = 0xFF1B4F72;
const int kColorNavyDarkUi = 0xFF0D2137;
const int kColorBlueUi = 0xFF2980B9;
const int kColorCyanLightUi = 0xFF00B8D4;
const int kColorCyanDarkUi = 0xFF0077B6;

// ============================================================
// GPS & LOCATION
// ============================================================
const double kTargetAccuracy = 10.0;
const double kGoodAccuracy = 15.0;
const double kMediumAccuracy = 25.0;
const double kPoorAccuracy = 50.0;
const double kMaxAccuracy = 80.0;
const int kGpsTimeoutSeconds = 25;
const int kGpsIntervalMs = 700;

// ============================================================
// HELPER FUNCTIONS
// ============================================================
String truncateAddress(String address, int maxLength) {
  if (address.length <= maxLength) return address;
  return '${address.substring(0, maxLength - 1)}…';
}

img.Color getAccuracyColor(double accuracy) {
  if (accuracy <= kTargetAccuracy) {
    return kColorCyan;
  } else if (accuracy <= kGoodAccuracy) {
    return kColorLightBlue;
  } else if (accuracy <= kMediumAccuracy) {
    return kColorGold;
  } else {
    return kColorGrey;
  }
}

// ============================================================
// VALIDATION (SEDERHANA)
// ============================================================
bool validateSettings() {
  assert(kJpegQuality >= 0 && kJpegQuality <= 100, 
    'JPEG quality must be between 0 and 100');
  assert(kMaxOutputWidth > 0, 
    'Max output width must be positive');
  assert(kGpsTimeoutSeconds > 0, 
    'GPS timeout must be positive');
  return true;
}
