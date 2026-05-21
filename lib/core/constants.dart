// lib/core/constants.dart
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';

// ============================================================
// OUTPUT & KUALITAS
// ============================================================
const int kMaxOutputWidth = 1600;
const int kJpegQuality = 90;
const int kSigMaxWidth = 260;
const int kLogoMaxWidth = 90;

// ============================================================
// WATERMARK LAYOUT STYLE (SEDERHANA)
// ============================================================
enum WatermarkLayout {
  cinematic,    // Tampilan sinematik letterbox
  hud,          // Heads-up display modern
  polaroid,     // Gaya polaroid klasik
  documentary,  // Gaya dokumenter/minimalis
  leica,        // Gaya Leica dengan font khas
  survey,       // Gaya survey dengan data lengkap
}

// ============================================================
// LAYOUT CATEGORY
// ============================================================
enum LayoutCategory {
  cinematic,  // cinematic
  modern,     // hud, documentary
  classic,    // polaroid, leica
  data,       // survey
}

// ============================================================
// LAYOUT THEME - Default style per layout
// ============================================================
class LayoutTheme {
  final Color primaryColor;         // Warna utama (Flutter Color)
  final img.Color primaryImgColor;  // Warna utama (package:image)
  final String fontFamily;          // Font yang digunakan
  final double defaultOpacity;      // Opacity default
  final String defaultPosition;     // Posisi default
  final bool supportsBorder;        // Apakah mendukung border
  final bool supportsMiniMap;       // Apakah mendukung mini map

  // HAPUS 'const' dari constructor
  LayoutTheme({
    required this.primaryColor,
    required this.primaryImgColor,
    required this.fontFamily,
    required this.defaultOpacity,
    required this.defaultPosition,
    this.supportsBorder = true,
    this.supportsMiniMap = true,
  });

  // HAPUS 'const' dari themes (static final, BUKAN const)
  static final Map<WatermarkLayout, LayoutTheme> themes = {
    // CINEMATIC - Letterbox, elegan, PlayfairDisplay
    WatermarkLayout.cinematic: LayoutTheme(
      primaryColor: const Color(0xFF1B2A4A),
      primaryImgColor: img.getColor(27, 42, 74),
      fontFamily: 'PlayfairDisplay',
      defaultOpacity: 1.0,
      defaultPosition: 'bottom',
      supportsBorder: false,
      supportsMiniMap: true,
    ),

    // HUD - Transparan, cyan, JetBrainsMono
    WatermarkLayout.hud: LayoutTheme(
      primaryColor: const Color(0xFF00B8D4),
      primaryImgColor: img.getColor(0, 184, 212),
      fontFamily: 'JetBrainsMono',
      defaultOpacity: 0.75,
      defaultPosition: 'topLeft',
      supportsBorder: false,
      supportsMiniMap: false,
    ),

    // POLAROID - Ivory, Caveat handwriting
    WatermarkLayout.polaroid: LayoutTheme(
      primaryColor: const Color(0xFFF8F5EB),
      primaryImgColor: img.getColor(248, 245, 235),
      fontFamily: 'Caveat',
      defaultOpacity: 1.0,
      defaultPosition: 'fullFrame',
      supportsBorder: true,
      supportsMiniMap: false,
    ),

    // DOCUMENTARY - Minimalis, BebasNeue
    WatermarkLayout.documentary: LayoutTheme(
      primaryColor: const Color(0xFF2C3E50),
      primaryImgColor: img.getColor(44, 62, 80),
      fontFamily: 'BebasNeue',
      defaultOpacity: 0.9,
      defaultPosition: 'bottom',
      supportsBorder: true,
      supportsMiniMap: true,
    ),

    // LEICA - Klasik, Inter (pengganti Helvetica)
    WatermarkLayout.leica: LayoutTheme(
      primaryColor: const Color(0xFFCC0000),
      primaryImgColor: img.getColor(204, 0, 0),
      fontFamily: 'Inter',
      defaultOpacity: 0.85,
      defaultPosition: 'bottomRight',
      supportsBorder: false,
      supportsMiniMap: false,
    ),

    // SURVEY - Data lengkap, RobotoMono
    WatermarkLayout.survey: LayoutTheme(
      primaryColor: const Color(0xFF00A86B),
      primaryImgColor: img.getColor(0, 168, 107),
      fontFamily: 'RobotoMono',
      defaultOpacity: 0.95,
      defaultPosition: 'bottomLeft',
      supportsBorder: true,
      supportsMiniMap: true,
    ),
  };

  /// Mendapatkan theme untuk layout tertentu
  static LayoutTheme of(WatermarkLayout layout) {
    return themes[layout] ?? themes[WatermarkLayout.cinematic]!;
  }
}

extension WatermarkLayoutExtension on WatermarkLayout {
  static const List<WatermarkLayout> all = [
    WatermarkLayout.cinematic,
    WatermarkLayout.hud,
    WatermarkLayout.polaroid,
    WatermarkLayout.documentary,
    WatermarkLayout.leica,
    WatermarkLayout.survey,
  ];

  LayoutCategory get category {
    switch (this) {
      case WatermarkLayout.cinematic:
        return LayoutCategory.cinematic;
      case WatermarkLayout.hud:
      case WatermarkLayout.documentary:
        return LayoutCategory.modern;
      case WatermarkLayout.polaroid:
      case WatermarkLayout.leica:
        return LayoutCategory.classic;
      case WatermarkLayout.survey:
        return LayoutCategory.data;
    }
  }

  String get displayName {
    switch (this) {
      case WatermarkLayout.cinematic:    return 'Cinematic';
      case WatermarkLayout.hud:          return 'HUD';
      case WatermarkLayout.polaroid:     return 'Polaroid';
      case WatermarkLayout.documentary:  return 'Documentary';
      case WatermarkLayout.leica:        return 'Leica Style';
      case WatermarkLayout.survey:       return 'Survey Pro';
    }
  }

  String get description {
    switch (this) {
      case WatermarkLayout.cinematic:    
        return 'Tampilan letterbox sinematik dengan gradasi elegan';
      case WatermarkLayout.hud:          
        return 'Heads-up display modern transparan di pojok layar';
      case WatermarkLayout.polaroid:     
        return 'Gaya polaroid klasik dengan bingkai ivory';
      case WatermarkLayout.documentary:  
        return 'Gaya dokumenter minimalis yang bersih';
      case WatermarkLayout.leica:        
        return 'Gaya khas Leica dengan aksen merah khas';
      case WatermarkLayout.survey:       
        return 'Gaya survey dengan data lengkap dan terstruktur';
    }
  }

  String get previewIcon {
    switch (this) {
      case WatermarkLayout.cinematic:    return '🎬';
      case WatermarkLayout.hud:          return '🎮';
      case WatermarkLayout.polaroid:     return '🖼️';
      case WatermarkLayout.documentary:  return '📹';
      case WatermarkLayout.leica:        return '📷';
      case WatermarkLayout.survey:       return '📋';
    }
  }

  // Konversi ke typeString untuk penyimpanan
  String get typeString {
    switch (this) {
      case WatermarkLayout.cinematic:    return 'cinematic';
      case WatermarkLayout.hud:          return 'hud';
      case WatermarkLayout.polaroid:     return 'polaroid';
      case WatermarkLayout.documentary:  return 'documentary';
      case WatermarkLayout.leica:        return 'leica';
      case WatermarkLayout.survey:       return 'survey';
    }
  }

  // Font family untuk setiap layout
  String get fontFamily {
    switch (this) {
      case WatermarkLayout.cinematic:    return 'PlayfairDisplay';
      case WatermarkLayout.hud:          return 'JetBrainsMono';
      case WatermarkLayout.polaroid:     return 'Caveat';
      case WatermarkLayout.documentary:  return 'BebasNeue';
      case WatermarkLayout.leica:        return 'Inter';
      case WatermarkLayout.survey:       return 'RobotoMono';
    }
  }

  // Warna utama (Flutter)
  Color get primaryColor {
    switch (this) {
      case WatermarkLayout.cinematic:    return const Color(0xFF1B2A4A);
      case WatermarkLayout.hud:          return const Color(0xFF00B8D4);
      case WatermarkLayout.polaroid:     return const Color(0xFFF8F5EB);
      case WatermarkLayout.documentary:  return const Color(0xFF2C3E50);
      case WatermarkLayout.leica:        return const Color(0xFFCC0000);
      case WatermarkLayout.survey:       return const Color(0xFF00A86B);
    }
  }

  // Warna utama (package image)
  img.Color get primaryImgColor {
    switch (this) {
      case WatermarkLayout.cinematic:    return img.getColor(27, 42, 74);
      case WatermarkLayout.hud:          return img.getColor(0, 184, 212);
      case WatermarkLayout.polaroid:     return img.getColor(248, 245, 235);
      case WatermarkLayout.documentary:  return img.getColor(44, 62, 80);
      case WatermarkLayout.leica:        return img.getColor(204, 0, 0);
      case WatermarkLayout.survey:       return img.getColor(0, 168, 107);
    }
  }

  // Opacity default
  double get defaultOpacity {
    switch (this) {
      case WatermarkLayout.cinematic:    return 1.0;
      case WatermarkLayout.hud:          return 0.75;
      case WatermarkLayout.polaroid:     return 1.0;
      case WatermarkLayout.documentary:  return 0.9;
      case WatermarkLayout.leica:        return 0.85;
      case WatermarkLayout.survey:       return 0.95;
    }
  }

  // Posisi default
  String get defaultPosition {
    switch (this) {
      case WatermarkLayout.cinematic:    return 'bottom';
      case WatermarkLayout.hud:          return 'topLeft';
      case WatermarkLayout.polaroid:     return 'fullFrame';
      case WatermarkLayout.documentary:  return 'bottom';
      case WatermarkLayout.leica:        return 'bottomRight';
      case WatermarkLayout.survey:       return 'bottomLeft';
    }
  }

  // Apakah mendukung border
  bool get supportsBorder {
    switch (this) {
      case WatermarkLayout.cinematic:    return false;
      case WatermarkLayout.hud:          return false;
      case WatermarkLayout.polaroid:     return true;
      case WatermarkLayout.documentary:  return true;
      case WatermarkLayout.leica:        return false;
      case WatermarkLayout.survey:       return true;
    }
  }

  // Apakah mendukung mini map
  bool get supportsMiniMap {
    switch (this) {
      case WatermarkLayout.cinematic:    return true;
      case WatermarkLayout.hud:          return false;
      case WatermarkLayout.polaroid:     return false;
      case WatermarkLayout.documentary:  return true;
      case WatermarkLayout.leica:        return false;
      case WatermarkLayout.survey:       return true;
    }
  }

  // Theme accessor
  LayoutTheme get theme => LayoutTheme.of(this);

  // Membaca dari String (aman) dengan migrasi layout lama
  static WatermarkLayout fromTypeString(String type) {
    // Migrasi layout lama ke baru
    switch (type) {
      // Layout baru
      case 'cinematic':    return WatermarkLayout.cinematic;
      case 'hud':          return WatermarkLayout.hud;
      case 'polaroid':     return WatermarkLayout.polaroid;
      case 'documentary':  return WatermarkLayout.documentary;
      case 'leica':        return WatermarkLayout.leica;
      case 'survey':       return WatermarkLayout.survey;
      
      // Migrasi layout lama
      case 'minimal':
      case 'timeMarkStyle':
        return WatermarkLayout.documentary;
      case 'dslr_corner':
        return WatermarkLayout.leica;
      case 'gps_timestamp':
      case 'side_panel':
      case 'modern':
      case 'gps_card':
        return WatermarkLayout.cinematic;
      case 'field_survey':
        return WatermarkLayout.survey;
        
      default: return WatermarkLayout.cinematic;
    }
  }
}

// ============================================================
// WATERMARK THEME (untuk dark/light mode tambahan)
// ============================================================
enum WatermarkColorTheme {
  dark, 
  light, 
  auto,
}

extension WatermarkColorThemeExtension on WatermarkColorTheme {
  String get displayName {
    switch (this) {
      case WatermarkColorTheme.dark:   return 'Dark';
      case WatermarkColorTheme.light:  return 'Light';
      case WatermarkColorTheme.auto:   return 'Auto (Based on image)';
    }
  }
}

// ============================================================
// GEOMETRY
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
final img.Color kColorWhite = img.getColor(255, 255, 255);
final img.Color kColorCyan = img.getColor(0, 184, 148);
final img.Color kColorGrey = img.getColor(210, 210, 210);
final img.Color kColorDarkBg = img.getColor(15, 23, 42, 230);
final img.Color kColorDarkBgMed = img.getColor(15, 23, 42, 210);
final img.Color kColorBlackCard = img.getColor(0, 0, 0, 170);
final img.Color kColorGlassBg = img.getColor(0, 0, 0, 120);
final img.Color kColorShadow = img.getColor(0, 0, 0);
final img.Color kColorLightBlue = img.getColor(30, 144, 255);
final img.Color kColorDimBlue = img.getColor(20, 80, 160);
final img.Color kColorOffWhite = img.getColor(220, 225, 235);
final img.Color kColorDarkGrey = img.getColor(140, 150, 165);
final img.Color kColorVeryDarkBg = img.getColor(0, 0, 10, 210);
final img.Color kColorBlackerBg = img.getColor(0, 0, 8, 235);
final img.Color kColorDimBlue200 = img.getColor(20, 80, 160);
final img.Color kColorLightGrey = img.getColor(200, 200, 205);
final img.Color kColorGold = img.getColor(255, 180, 50);
final img.Color kColorIvory = img.getColor(248, 245, 235);
final img.Color kColorDarkText = img.getColor(40, 40, 40);
final img.Color kColorNavy = img.getColor(10, 15, 40, 240);
final img.Color kColorGpsPanel = img.getColor(0, 0, 8, 235);
final img.Color kColorGpsAccent = img.getColor(0, 180, 255);
final img.Color kColorTeal = img.getColor(0, 168, 107);
final img.Color kColorRed = img.getColor(204, 0, 0);
final img.Color kColorBrightCyan = img.getColor(0, 184, 212);
final img.Color kColorDarkBlue = img.getColor(27, 42, 74);
final img.Color kColorDarkSlate = img.getColor(44, 62, 80);

// ============================================================
// UI COLORS (Flutter)
// ============================================================
const int kColorNavyUi = 0xFF1B4F72;
const int kColorNavyDarkUi = 0xFF0D2137;
const int kColorBlueUi = 0xFF2980B9;
const int kColorCyanLightUi = 0xFF00B8D4;
const int kColorCyanDarkUi = 0xFF0077B6;
const int kColorTealUi = 0xFF00A86B;
const int kColorRedUi = 0xFFCC0000;
const int kColorDarkBlueUi = 0xFF1B2A4A;
const int kColorDarkSlateUi = 0xFF2C3E50;

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
