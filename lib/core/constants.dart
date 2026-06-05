// lib/core/constants.dart
// TermulLog – Proof of Delivery Edition

import 'package:image/image.dart' as img;

// ============================================================
// WATERMARK LAYOUT (Enum) — 3 style profesional POD
// ============================================================
enum WatermarkLayout {
  podCorporate,   // Corporate: panel putih bawah, logo, data terstruktur
  podDarkField,   // Dark Field: overlay gelap, accent cyan, gaya lapangan
  podGovern,      // Government: strip biru tua formal, cap verifikasi
}

extension WatermarkLayoutExtension on WatermarkLayout {
  String get displayName {
    switch (this) {
      case WatermarkLayout.podCorporate: return 'Corporate Report';
      case WatermarkLayout.podDarkField: return 'Dark Field';
      case WatermarkLayout.podGovern:    return 'Government';
    }
  }

  String get description {
    switch (this) {
      case WatermarkLayout.podCorporate:
        return 'Panel putih bersih di bawah foto. Header logo, data terstruktur, hash verifikasi.';
      case WatermarkLayout.podDarkField:
        return 'Overlay gelap transparan. Accent cyan modern. Ideal untuk foto outdoor/lapangan.';
      case WatermarkLayout.podGovern:
        return 'Strip biru tua formal. Teks structured. Cocok untuk dokumen resmi/pemerintahan.';
    }
  }

  String get iconLabel {
    switch (this) {
      case WatermarkLayout.podCorporate: return 'CORP';
      case WatermarkLayout.podDarkField: return 'FIELD';
      case WatermarkLayout.podGovern:    return 'GOV';
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
// WARNA WATERMARK (img package RGBA) — untuk wm_helpers.dart
// ============================================================
final img.Color kColorShadow = img.ColorRgba8(0, 0, 0, 140);
