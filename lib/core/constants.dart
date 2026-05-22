// lib/core/constants.dart
import 'package:image/image.dart' as img;

// ============================================================
// WATERMARK LAYOUT STYLE (ENUM)
// ============================================================
enum WatermarkLayout {
  minimal,
  dslrCorner,
  cinematic,
  fieldSurvey,
  hud,
  gpsCard,
  polaroid,
  sidePanel,
  cinematicV2,
  timeMarkStyle,
  modern,
}

extension WatermarkLayoutExtension on WatermarkLayout {
  String get displayName {
    switch (this) {
      case WatermarkLayout.minimal:        return 'Film Strip';
      case WatermarkLayout.dslrCorner:     return 'DSLR Corner';
      case WatermarkLayout.cinematic:      return 'Cinematic';
      case WatermarkLayout.fieldSurvey:    return 'Field Survey';
      case WatermarkLayout.hud:            return 'HUD Modern';
      case WatermarkLayout.gpsCard:        return 'GPS Card';
      case WatermarkLayout.polaroid:       return 'Polaroid';
      case WatermarkLayout.sidePanel:      return 'Side Panel';
      case WatermarkLayout.cinematicV2:    return 'Cinematic V2';
      case WatermarkLayout.timeMarkStyle:  return 'TimeMark Style';
      case WatermarkLayout.modern:         return 'Modern Clean Card';
    }
  }

  String get description {
    switch (this) {
      case WatermarkLayout.minimal:        return 'Gaya strip film dengan border biru profesional';
      case WatermarkLayout.dslrCorner:     return 'Informasi seperti tampilan kamera DSLR di pojok';
      case WatermarkLayout.cinematic:      return 'Gaya sinematik dengan gradasi halus dan elegan';
      case WatermarkLayout.fieldSurvey:    return 'Gaya form survey dengan tabel data terstruktur';
      case WatermarkLayout.hud:            return 'Heads-Up Display modern dengan efek transparan';
      case WatermarkLayout.gpsCard:        return 'Panel GPS dengan map strip adaptif';
      case WatermarkLayout.polaroid:       return 'Gaya polaroid klasik dengan bingkai ivory';
      case WatermarkLayout.sidePanel:      return 'Panel samping vertikal dengan jam besar';
      case WatermarkLayout.cinematicV2:    return 'Gaya sinematik dengan font modern Roboto (Canvas)';
      case WatermarkLayout.timeMarkStyle:  return 'Gaya GPS TimeMark Camera dengan font modern';
      case WatermarkLayout.modern:         return 'Desain bersih, navy gelap, aksen teal modern';
    }
  }
}

// ============================================================
// OUTPUT & KUALITAS
// ============================================================
const int kMaxOutputWidth = 1600;
const int kJpegQuality = 90;
// ... dan seterusnya semua konstanta yang Anda miliki
