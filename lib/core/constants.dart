// ════════════════════════════════════════════════════════════════════════════
//  core/constants.dart
//  Konstanta global aplikasi
// ════════════════════════════════════════════════════════════════════════════

import 'package:image/image.dart' as img;

// ─── Output / kualitas ───────────────────────────────────────────────────────
const int kMaxOutputWidth = 1600;
const int kJpegQuality    = 90;
const int kSigMaxWidth    = 260;
const int kLogoMaxWidth   = 90;

// ─── Watermark layout geometry ───────────────────────────────────────────────
const int kPanelPaddingX  = 25;
const int kSidebarPadX    = 18;
const int kAccentBarWidth = 10;
const int kCornerMargin   = 20;
const int kTextLineSmall  = 18;
const int kTextLineLarge  = 28;
const int kSectionGap     = 12;

// ─── Watermark colours ───────────────────────────────────────────────────────
final img.Color kColorWhite     = img.ColorRgb8(255, 255, 255);
final img.Color kColorCyan      = img.ColorRgb8(0, 184, 148);
final img.Color kColorGrey      = img.ColorRgb8(210, 210, 210);
final img.Color kColorDarkBg    = img.ColorRgba8(15, 23, 42, 230);
final img.Color kColorDarkBgMed = img.ColorRgba8(15, 23, 42, 210);
final img.Color kColorBlackCard = img.ColorRgba8(0, 0, 0, 170);
final img.Color kColorGlassBg   = img.ColorRgba8(0, 0, 0, 120);
final img.Color kColorShadow    = img.ColorRgb8(0, 0, 0);

// ─── UI colours ──────────────────────────────────────────────────────────────
const kColorNavy     = 0xFF1B4F72;
const kColorNavyDark = 0xFF0D2137;
const kColorBlue     = 0xFF2980B9;
