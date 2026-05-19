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
  minimal,
  dslrCorner,
  gpsTimestamp,
  fieldSurvey,
  hud,
  gpsCard,
  polaroid,
  sidePanel,
  cinematic,
  timeMarkStyle,
  modern,
  modernCard,
  minimalist,
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
    WatermarkLayout.gpsTimestamp,
    WatermarkLayout.fieldSurvey,
    WatermarkLayout.hud,
    WatermarkLayout.gpsCard,
    WatermarkLayout.polaroid,
    WatermarkLayout.sidePanel,
    WatermarkLayout.cinematic,
    WatermarkLayout.timeMarkStyle,
    WatermarkLayout.modern,
    WatermarkLayout.modernCard,
    WatermarkLayout.minimalist,
  ];

  LayoutCategory get category {
    switch (this) {
      case WatermarkLayout.minimal:
      case WatermarkLayout.polaroid:
        return LayoutCategory.classic;
      case WatermarkLayout.hud:
      case WatermarkLayout.gpsCard:
      case WatermarkLayout.modern:
      case WatermarkLayout.modernCard:
      case WatermarkLayout.minimalist:
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
      case WatermarkLayout.modernCard:     return 'Modern Card';
      case WatermarkLayout.minimalist:     return 'Minimalist Clean';
    }
  }

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
      case WatermarkLayout.modernCard:     
        return 'Card modern dengan efek glassmorphism';
      case WatermarkLayout.minimalist:     
        return 'Gaya minimalis bersih tanpa background';
    }
  }

  String get typeString {
    switch (this) {
      case WatermarkLayout.minimal:        return 'minimal';
      case WatermarkLayout.dslrCorner:     return 'dslr_corner';
      case WatermarkLayout.gpsTimestamp:   return 'gps_timestamp';
      case WatermarkLayout.fieldSurvey:    return 'field_survey';
      case WatermarkLayout.hud:            return 'hud';
      case WatermarkLayout.gpsCard:        return 'gps_card';
      case WatermarkLayout.polaroid:       return 'polaroid';
      case WatermarkLayout.sidePanel:      return 'side_panel';
      case WatermarkLayout.cinematic:      return 'cinematic';
      case WatermarkLayout.timeMarkStyle:  return 'timemark_style';
      case WatermarkLayout.modern:         return 'modern';
      case WatermarkLayout.modernCard:     return 'modern_card';
      case WatermarkLayout.minimalist:     return 'minimalist';
    }
  }

  static WatermarkLayout fromIndex(int index) {
    if (index >= 0 && index < all.length) {
      return all[index];
    }
    return WatermarkLayout.modern;
  }

  int get index => all.indexOf(this);

  static WatermarkLayout fromTypeString(String type) {
    switch (type) {
      case 'minimal':        return WatermarkLayout.minimal;
      case 'dslr_corner':    return WatermarkLayout.dslrCorner;
      case 'gps_timestamp':  return WatermarkLayout.gpsTimestamp;
      case 'field_survey':   return WatermarkLayout.fieldSurvey;
      case 'hud':            return WatermarkLayout.hud;
      case 'gps_card':       return WatermarkLayout.gpsCard;
      case 'polaroid':       return WatermarkLayout.polaroid;
      case 'side_panel':     return WatermarkLayout.sidePanel;
      case 'cinematic':      return WatermarkLayout.cinematic;
      case 'timemark_style': return WatermarkLayout.timeMarkStyle;
      case 'modern':         return WatermarkLayout.modern;
      case 'modern_card':    return WatermarkLayout.modernCard;
      case 'minimalist':     return WatermarkLayout.minimalist;
      default:               return WatermarkLayout.modern;
    }
  }
}

// ============================================================
// WATERMARK THEME
// ============================================================
enum WatermarkTheme { dark, light, kodak, cinematic, survey }

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
// GEOMETRY CONSTANTS
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
// COLORS (package image)
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

// ============================================================
// UI COLORS (Flutter)
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
  if (accuracy <= kTargetAccuracy) return kColorCyan;
  if (accuracy <= kGoodAccuracy) return kColorLightBlue;
  if (accuracy <= kMediumAccuracy) return kColorGold;
  return kColorGrey;
}
