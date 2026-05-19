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
// WATERMARK LAYOUT STYLE
// ============================================================
enum WatermarkLayout {
  minimal,          // 0 - Film Strip
  dslrCorner,       // 1 - DSLR Corner
  gpsTimestamp,     // 2 - GPS Timestamp (formerly cinematic)
  fieldSurvey,      // 3 - Field Survey
  hud,              // 4 - HUD Modern
  gpsCard,          // 5 - GPS Card
  polaroid,         // 6 - Polaroid
  sidePanel,        // 7 - Side Panel
  cinematic,        // 8 - Cinematic
  timeMarkStyle,    // 9 - TimeMark Style
  modern,           // 10 - Modern Clean Card
}

// ============================================================
// LAYOUT CATEGORY
// ============================================================
enum LayoutCategory {
  classic,    // minimal, polaroid
  modern,     // hud, gpsCard, modern
  cinematic,  // cinematic, gpsTimestamp
  data,       // fieldSurvey, timeMarkStyle
  corner,     // dslrCorner, sidePanel
}

extension WatermarkLayoutExtension on WatermarkLayout {
  /// List of all watermark layouts
  static const List<WatermarkLayout> all = [
    WatermarkLayout.minimal,
    WatermarkLayout.dslrCorner,
    WatermarkLayout.gpsTimestamp,
    WatermarkLayout.fieldSurvey,
    WatermarkLayout.hud,
    WatermarkLayout.gpsCard,
    WatermarkLayout.polaroid,
    WatermarkLayout.sidePanel,
    WatermarkLayout.cinematic,
    WatermarkLayout.timeMarkStyle,
    WatermarkLayout.modern,
  ];

  /// Get layout category
  LayoutCategory get category {
    switch (this) {
      case WatermarkLayout.minimal:
      case WatermarkLayout.polaroid:
        return LayoutCategory.classic;
      case WatermarkLayout.hud:
      case WatermarkLayout.gpsCard:
      case WatermarkLayout.modern:
        return LayoutCategory.modern;
      case WatermarkLayout.cinematic:
      case WatermarkLayout.gpsTimestamp:
        return LayoutCategory.cinematic;
      case WatermarkLayout.fieldSurvey:
      case WatermarkLayout.timeMarkStyle:
        return LayoutCategory.data;
      case WatermarkLayout.dslrCorner:
      case WatermarkLayout.sidePanel:
        return LayoutCategory.corner;
    }
  }

  /// Display name for UI
  String get displayName {
    switch (this) {
      case WatermarkLayout.minimal:        return 'Film Strip';
      case WatermarkLayout.dslrCorner:     return 'DSLR Corner';
      case WatermarkLayout.gpsTimestamp:   return 'GPS Timestamp';
      case WatermarkLayout.fieldSurvey:    return 'Field Survey';
      case WatermarkLayout.hud:            return 'HUD Modern';
      case WatermarkLayout.gpsCard:        return 'GPS Card';
      case WatermarkLayout.polaroid:       return 'Polaroid';
      case WatermarkLayout.sidePanel:      return 'Side Panel';
      case WatermarkLayout.cinematic:      return 'Cinematic';
      case WatermarkLayout.timeMarkStyle:  return 'TimeMark Style';
      case WatermarkLayout.modern:         return 'Modern Clean Card';
    }
  }

  /// Description for each layout
  String get description {
    switch (this) {
      case WatermarkLayout.minimal:        
        return 'Gaya strip film dengan border biru profesional';
      case WatermarkLayout.dslrCorner:     
        return 'Informasi seperti tampilan kamera DSLR di pojok';
      case WatermarkLayout.gpsTimestamp:   
        return 'Tampilan timestamp GPS yang bersih dan profesional';
      case WatermarkLayout.fieldSurvey:    
        return 'Gaya form survey dengan tabel data terstruktur';
      case WatermarkLayout.hud:            
        return 'Heads-Up Display modern dengan efek transparan';
      case WatermarkLayout.gpsCard:        
        return 'Panel GPS dengan map strip adaptif';
      case WatermarkLayout.polaroid:       
        return 'Gaya polaroid klasik dengan bingkai ivory';
      case WatermarkLayout.sidePanel:      
        return 'Panel samping vertikal dengan jam besar';
      case WatermarkLayout.cinematic:      
        return 'Gaya sinematik dengan gradasi halus dan elegan';
      case WatermarkLayout.timeMarkStyle:  
        return 'Gaya GPS TimeMark Camera dengan font modern';
      case WatermarkLayout.modern:         
        return 'Desain bersih, navy gelap, aksen teal modern';
    }
  }

  /// Preview emoji/icon for UI
  String get previewIcon {
    switch (this) {
      case WatermarkLayout.minimal:        return '🎞️';
      case WatermarkLayout.dslrCorner:     return '📷';
      case WatermarkLayout.gpsTimestamp:   return '📍';
      case WatermarkLayout.fieldSurvey:    return '📋';
      case WatermarkLayout.hud:            return '🎮';
      case WatermarkLayout.gpsCard:        return '🛰️';
      case WatermarkLayout.polaroid:       return '🖼️';
      case WatermarkLayout.sidePanel:      return '📱';
      case WatermarkLayout.cinematic:      return '🎬';
      case WatermarkLayout.timeMarkStyle:  return '⏱️';
      case WatermarkLayout.modern:         return '✨';
    }
  }

  /// Get layout by index value (for serialization)
  static WatermarkLayout fromIndex(int index) {
    if (index >= 0 && index < all.length) {
      return all[index];
    }
    return modern; // default fallback
  }

  /// Get integer index (for serialization)
  int get index {
    return all.indexOf(this);
  }

  /// Check if layout supports dark theme well
  bool get supportsDarkTheme {
    switch (this) {
      case WatermarkLayout.hud:
      case WatermarkLayout.gpsCard:
      case WatermarkLayout.sidePanel:
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
      case WatermarkLayout.fieldSurvey:
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

// ============================================================
// WATERMARK COLOURS (untuk package image)
// ============================================================
final img.Color kColorWhite = img.ColorRgb8(255, 255, 255);
final img.Color kColorCyan = img.ColorRgb8(0, 184, 148);
final img.Color kColorGrey = img.ColorRgb8(210, 210, 210);
final img.Color kColorDarkBg = img.ColorRgba8(15, 23, 42, 230);
final img.Color kColorDarkBgMed = img.ColorRgba8(15, 23, 42, 210);
final img.Color kColorBlackCard = img.ColorRgba8(0, 0, 0, 170);
final img.Color kColorGlassBg = img.ColorRgba8(0, 0, 0, 120);
final img.Color kColorShadow = img.ColorRgb8(0, 0, 0);

// ============================================================
// LAYOUT WATERMARK TAMBAHAN
// ============================================================
final img.Color kColorLightBlue = img.ColorRgb8(30, 144, 255);
final img.Color kColorDimBlue = img.ColorRgb8(20, 80, 160);
final img.Color kColorOffWhite = img.ColorRgb8(220, 225, 235);
final img.Color kColorDarkGrey = img.ColorRgb8(140, 150, 165);
final img.Color kColorVeryDarkBg = img.ColorRgba8(0, 0, 10, 210);
final img.Color kColorBlackerBg = img.ColorRgba8(0, 0, 8, 235);
final img.Color kColorDimBlue200 = img.ColorRgb8(20, 80, 160);
final img.Color kColorLightGrey = img.ColorRgb8(200, 200, 205);
final img.Color kColorGold = img.ColorRgb8(255, 180, 50);

// ============================================================
// WARNA TAMBAHAN UNTUK LAYOUT BARU
// ============================================================
final img.Color kColorIvory = img.ColorRgb8(248, 245, 235);
final img.Color kColorDarkText = img.ColorRgb8(40, 40, 40);
final img.Color kColorNavy = img.ColorRgba8(10, 15, 40, 240);
final img.Color kColorGpsPanel = img.ColorRgba8(0, 0, 8, 235);
final img.Color kColorGpsAccent = img.ColorRgb8(0, 180, 255);

// ============================================================
// UI COLOURS (Flutter Widget)
// ============================================================
const int kColorNavyUi = 0xFF1B4F72;
const int kColorNavyDarkUi = 0xFF0D2137;
const int kColorBlueUi = 0xFF2980B9;
const int kColorCyanLightUi = 0xFF00B8D4;
const int kColorCyanDarkUi = 0xFF0077B6;

// ============================================================
// WATERMARK GEOMETRY TAMBAHAN
// ============================================================
const int kWatermarkPadX = 14;
const int kWatermarkPadY = 12;
const int kHeaderHeight = 22;
const int kRowHeight = 20;
const int kColumnValueWidth = 100;
const int kMaxAddressLength = 45;
const int kMaxAddressLengthShort = 38;
const int kMaxAddressLengthFilmStrip = 42;

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
// VALIDATION ASSERTIONS (debug mode only)
// ============================================================
assert(() {
  // Validate quality ranges
  assert(kJpegQuality >= 0 && kJpegQuality <= 100, 
    'JPEG quality must be between 0 and 100');
  assert(kMaxOutputWidth > 0, 
    'Max output width must be positive');
  assert(kGpsTimeoutSeconds > 0, 
    'GPS timeout must be positive');
  return true;
}());
