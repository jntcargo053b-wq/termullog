// lib/utils/layout_migration.dart
import '../core/constants.dart';

class LayoutMigration {
  // Mapping dari index lama ke layout baru
  static final Map<int, WatermarkLayout> _oldIndexToNewLayout = {
    0: WatermarkLayout.documentary,  // minimal
    1: WatermarkLayout.leica,        // dslrCorner  
    2: WatermarkLayout.cinematic,    // gpsTimestamp
    3: WatermarkLayout.survey,       // fieldSurvey
    4: WatermarkLayout.hud,          // hud
    5: WatermarkLayout.hud,          // gpsCard
    6: WatermarkLayout.polaroid,     // polaroid
    7: WatermarkLayout.cinematic,    // sidePanel
    8: WatermarkLayout.cinematic,    // cinematic
    9: WatermarkLayout.documentary,  // timeMarkStyle
    10: WatermarkLayout.cinematic,   // modern
  };
  
  static WatermarkLayout fromOldIndex(int oldIndex) {
    return _oldIndexToNewLayout[oldIndex] ?? WatermarkLayout.cinematic;
  }
  
  static WatermarkLayout fromOldTypeString(String oldType) {
    switch (oldType) {
      case 'minimal': return WatermarkLayout.documentary;
      case 'dslr_corner': return WatermarkLayout.leica;
      case 'gps_timestamp': return WatermarkLayout.cinematic;
      case 'field_survey': return WatermarkLayout.survey;
      case 'hud': return WatermarkLayout.hud;
      case 'gps_card': return WatermarkLayout.hud;
      case 'polaroid': return WatermarkLayout.polaroid;
      case 'side_panel': return WatermarkLayout.cinematic;
      case 'cinematic': return WatermarkLayout.cinematic;
      case 'timemark_style': return WatermarkLayout.documentary;
      case 'modern': return WatermarkLayout.cinematic;
      default: return WatermarkLayout.cinematic;
    }
  }
}
