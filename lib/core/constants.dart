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
  modern,           // 1 - DSLR Corner
  elegant,          // 2 - Cinematic
  professional,     // 3 - Field Survey
  semiTransparent,  // 4 - HUD Modern
  gpsCard,          // 5 - GPS Card
  polaroid,         // 6 - Polaroid
  sidePanel,        // 7 - Side Panel
  cinematicV2,      // 8 - Cinematic V2
  timeMarkStyle,    // 9 - TimeMark Style
  modernCleanCard,  // 10 - Modern Clean Card
}

extension WatermarkLayoutExtension on WatermarkLayout {
  String get displayName {
    switch (this) {
      case WatermarkLayout.minimal: return 'Film Strip';
      case WatermarkLayout.modern: return 'DSLR Corner';
      case WatermarkLayout.elegant: return 'Cinematic';
      case WatermarkLayout.professional: return 'Field Survey';
      case WatermarkLayout.semiTransparent: return 'HUD Modern';
      case WatermarkLayout.gpsCard: return 'GPS Card';
      case WatermarkLayout.polaroid: return 'Polaroid';
      case WatermarkLayout.sidePanel: return 'Side Panel';
      case WatermarkLayout.cinematicV2: return 'Cinematic V2';
      case WatermarkLayout.timeMarkStyle: return 'TimeMark Style';
      case WatermarkLayout.modernCleanCard: return 'Modern Clean Card';
    }
  }

  String get description {
    switch (this) {
      case WatermarkLayout.minimal:
        return 'Gaya strip film dengan border biru profesional';
      case WatermarkLayout.modern:
        return 'Informasi seperti tampilan kamera DSLR di pojok';
      case WatermarkLayout.elegant:
        return 'Gaya sinematik dengan gradasi halus dan elegan';
      case WatermarkLayout.professional:
        return 'Gaya form survey dengan tabel data terstruktur';
      case WatermarkLayout.semiTransparent:
        return 'Heads-Up Display modern dengan efek transparan';
      case WatermarkLayout.gpsCard:
        return 'Panel GPS dengan map strip adaptif';
      case WatermarkLayout.polaroid:
        return 'Gaya polaroid klasik dengan bingkai ivory';
      case WatermarkLayout.sidePanel:
        return 'Panel samping vertikal dengan jam besar';
      case WatermarkLayout.cinematicV2:
        return 'Gaya sinematik dengan font modern Roboto (Canvas)';
      case WatermarkLayout.timeMarkStyle:
        return 'Gaya GPS TimeMark Camera dengan font modern';
      case WatermarkLayout.modernCleanCard:
        return 'Desain bersih, navy gelap, aksen teal modern';
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
