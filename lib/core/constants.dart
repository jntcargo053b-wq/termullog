// lib/core/constants.dart
// TermulLog – Timemark Style Edition

import 'package:image/image.dart' as img;

// ============================================================
// WATERMARK LAYOUT (Enum) — 3 style Timemark
// ============================================================
enum WatermarkLayout {
  podCorporate,   // Timemark Light: panel putih, badge nama, jam biru besar
  podDarkField,   // Timemark Dark: panel gelap, jam putih besar, alamat lengkap
  podGovern,      // Timemark Clean: branding pojok atas, panel gelap minimalis
}

extension WatermarkLayoutExtension on WatermarkLayout {
  String get displayName {
    switch (this) {
      case WatermarkLayout.podCorporate: return 'Timemark Light';
      case WatermarkLayout.podDarkField: return 'Timemark Dark';
      case WatermarkLayout.podGovern:    return 'Timemark Clean';
    }
  }

  String get description {
    switch (this) {
      case WatermarkLayout.podCorporate:
        return 'Panel putih bawah. Badge nama, jam biru besar, branding kuning kanan.';
      case WatermarkLayout.podDarkField:
        return 'Panel gelap full-width. Jam putih besar, alamat lengkap, kode verifikasi.';
      case WatermarkLayout.podGovern:
        return 'Branding pojok kanan atas. Panel gelap minimalis dengan bar kuning.';
    }
  }

  String get iconLabel {
    switch (this) {
      case WatermarkLayout.podCorporate: return 'LIGHT';
      case WatermarkLayout.podDarkField: return 'DARK';
      case WatermarkLayout.podGovern:    return 'CLEAN';
    }
  }
}

// ============================================================
// OUTPUT & KUALITAS
// ============================================================
const int kMaxOutputWidth  = 2048;
const int kJpegQuality     = 92;
const int kLogoMaxWidth    = 160;
const int kLogoMaxHeight   = 60;

// ============================================================
// WARNA WATERMARK (img package RGBA)
// ============================================================
final img.Color kColorShadow = img.ColorRgba8(0, 0, 0, 140);
