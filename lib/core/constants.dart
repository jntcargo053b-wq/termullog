// lib/core/constants.dart
// TOTAL REBUILD — TimeMark-inspired timestamp camera app

// ============================================================
// WATERMARK LAYOUT (Enum)
// ============================================================
enum WatermarkLayout {
  timemarkClassic,    // TimeMark clone — jam besar + GPS strip bawah
  timemarkMinimal,    // Versi minimal — jam + tanggal saja di pojok
  timemarkCard,       // Card modern — dark glass panel
  timemarkHUD,        // HUD heads-up — ring + data overlay
  timemarkFilm,       // Film strip — klasik foto analog
}

extension WatermarkLayoutExtension on WatermarkLayout {
  String get displayName {
    switch (this) {
      case WatermarkLayout.timemarkClassic: return 'TimeMark Classic';
      case WatermarkLayout.timemarkMinimal: return 'Minimal Corner';
      case WatermarkLayout.timemarkCard:    return 'Glass Card';
      case WatermarkLayout.timemarkHUD:     return 'HUD Overlay';
      case WatermarkLayout.timemarkFilm:    return 'Film Strip';
    }
  }

  String get description {
    switch (this) {
      case WatermarkLayout.timemarkClassic: return 'Jam besar merah + strip GPS bawah, persis gaya TimeMark';
      case WatermarkLayout.timemarkMinimal: return 'Timestamp kecil di pojok, bersih dan tidak mengganggu';
      case WatermarkLayout.timemarkCard:    return 'Panel kaca gelap transparan dengan info lengkap';
      case WatermarkLayout.timemarkHUD:     return 'HUD modern seperti kamera militer / survei lapangan';
      case WatermarkLayout.timemarkFilm:    return 'Border film strip merah-oranye gaya kamera analog';
    }
  }
}

// ============================================================
// OUTPUT & KUALITAS
// ============================================================
const int kMaxOutputWidth = 2048;
const int kJpegQuality = 92;
