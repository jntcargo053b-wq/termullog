// ════════════════════════════════════════════════════════════════════════════
//  core/constants.dart
//  Konstanta global aplikasi TermulLog
// ════════════════════════════════════════════════════════════════════════════

import 'package:image/image.dart' as img;

// ============================================================
// OUTPUT & KUALITAS
// ============================================================

/// Maksimum lebar/tinggi output gambar (resize)
const int kMaxOutputWidth = 1600;

/// Kualitas JPEG (1-100, 90 adalah kualitas tinggi)
const int kJpegQuality = 90;

/// Maksimum lebar untuk signature
const int kSigMaxWidth = 260;

/// Maksimum lebar untuk logo
const int kLogoMaxWidth = 90;

// ============================================================
// WATERMARK LAYOUT STYLE
// ============================================================

/// Enum untuk memilih gaya tampilan watermark
enum WatermarkLayout {
  minimal,          // Film Strip style
  modern,           // DSLR Corner style
  elegant,          // Cinematic style
  professional,     // Field Survey style
  semiTransparent,  // HUD Modern style
}

/// Extension untuk mendapatkan nama tampilan dan deskripsi
extension WatermarkLayoutExtension on WatermarkLayout {
  String get displayName {
    switch (this) {
      case WatermarkLayout.minimal:
        return 'Film Strip';
      case WatermarkLayout.modern:
        return 'DSLR Corner';
      case WatermarkLayout.elegant:
        return 'Cinematic';
      case WatermarkLayout.professional:
        return 'Field Survey';
      case WatermarkLayout.semiTransparent:
        return 'HUD Modern';
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
    }
  }
}

// ============================================================
// WATERMARK LAYOUT GEOMETRY
// ============================================================

/// Padding horizontal panel watermark
const int kPanelPaddingX = 25;

/// Padding horizontal untuk sidebar
const int kSidebarPadX = 18;

/// Lebar accent bar (garis aksen di samping)
const int kAccentBarWidth = 10;

/// Margin sudut watermark
const int kCornerMargin = 20;

/// Jarak antar baris teks (kecil)
const int kTextLineSmall = 18;

/// Jarak antar baris teks (besar)
const int kTextLineLarge = 28;

/// Jarak antar section
const int kSectionGap = 12;

// ============================================================
// WATERMARK COLOURS (untuk package image)
// ============================================================

/// Putih murni
final img.Color kColorWhite = img.ColorRgb8(255, 255, 255);

/// Biru cyan / toska (warna aksen utama)
final img.Color kColorCyan = img.ColorRgb8(0, 184, 148);

/// Abu-abu terang untuk teks sekunder
final img.Color kColorGrey = img.ColorRgb8(210, 210, 210);

/// Background gelap transparan (opacity ~90%)
final img.Color kColorDarkBg = img.ColorRgba8(15, 23, 42, 230);

/// Background gelap medium (opacity ~82%)
final img.Color kColorDarkBgMed = img.ColorRgba8(15, 23, 42, 210);

/// Background hitam card (opacity ~67%)
final img.Color kColorBlackCard = img.ColorRgba8(0, 0, 0, 170);

/// Background glass morphism (opacity ~47%)
final img.Color kColorGlassBg = img.ColorRgba8(0, 0, 0, 120);

/// Warna shadow
final img.Color kColorShadow = img.ColorRgb8(0, 0, 0);

// ============================================================
// LAYOUT WATERMARK TAMBAHAN (untuk layout HUD & Cinematic)
// ============================================================

/// Biru terang untuk aksen (RGB)
final img.Color kColorLightBlue = img.ColorRgb8(30, 144, 255);

/// Biru redup untuk background
final img.Color kColorDimBlue = img.ColorRgb8(20, 80, 160);

/// Putih kebiruan untuk teks
final img.Color kColorOffWhite = img.ColorRgb8(220, 225, 235);

/// Abu-abu gelap untuk teks sekunder
final img.Color kColorDarkGrey = img.ColorRgb8(140, 150, 165);

/// Background sangat gelap (opacity ~82%)
final img.Color kColorVeryDarkBg = img.ColorRgba8(0, 0, 10, 210);

/// Background paling gelap (opacity ~92%)
final img.Color kColorBlackerBg = img.ColorRgba8(0, 0, 8, 235);

/// Warna biru redup untuk UI
final img.Color kColorDimBlue200 = img.ColorRgb8(20, 80, 160);

/// Abu-abu terang
final img.Color kColorLightGrey = img.ColorRgb8(200, 200, 205);

/// Emas / kuning untuk aksen
final img.Color kColorGold = img.ColorRgb8(255, 180, 50);

// ============================================================
// UI COLOURS (untuk Flutter Widget) - HINDARI DUPLIKASI
// ============================================================

/// Warna navy untuk app bar
const int kColorNavyUi = 0xFF1B4F72;

/// Warna navy gelap
const int kColorNavyDarkUi = 0xFF0D2137;

/// Warna biru untuk tombol (UI)
const int kColorBlueUi = 0xFF2980B9;

/// Warna cyan terang untuk aksen
const int kColorCyanLightUi = 0xFF00B8D4;

/// Warna cyan gelap
const int kColorCyanDarkUi = 0xFF0077B6;

// ============================================================
// LAYOUT WATERMARK GEOMETRY TAMBAHAN
// ============================================================

/// Padding horizontal untuk teks watermark
const int kWatermarkPadX = 14;

/// Padding vertikal untuk teks watermark
const int kWatermarkPadY = 12;

/// Tinggi garis header watermark
const int kHeaderHeight = 22;

/// Tinggi baris watermark
const int kRowHeight = 20;

/// Lebar kolom value pada layout tabel
const int kColumnValueWidth = 100;

/// Panjang maksimal alamat yang ditampilkan
const int kMaxAddressLength = 45;

/// Panjang maksimal alamat untuk layout tertentu
const int kMaxAddressLengthShort = 38;

/// Panjang maksimal alamat untuk layout film strip
const int kMaxAddressLengthFilmStrip = 42;

// ============================================================
// GPS & LOCATION
// ============================================================

/// Akurasi GPS target (meter)
const double kTargetAccuracy = 10.0;

/// Akurasi GPS bagus (meter)
const double kGoodAccuracy = 15.0;

/// Akurasi GPS sedang (meter)
const double kMediumAccuracy = 25.0;

/// Akurasi GPS buruk (meter)
const double kPoorAccuracy = 50.0;

/// Maksimum akurasi yang diterima
const double kMaxAccuracy = 80.0;

/// Waktu maksimum menunggu GPS (detik)
const int kGpsTimeoutSeconds = 25;

/// Interval update GPS (milidetik)
const int kGpsIntervalMs = 700;

// ============================================================
// HELPER FUNCTIONS
// ============================================================

/// Memotong string address jika terlalu panjang
String truncateAddress(String address, int maxLength) {
  if (address.length <= maxLength) return address;
  return '${address.substring(0, maxLength - 1)}…';
}

/// Mendapatkan warna berdasarkan akurasi GPS
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
