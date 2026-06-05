// lib/layout_migration.dart
import 'core/constants.dart';

class LayoutMigration {
  static final Map<int, WatermarkLayout> _indexToLayout = {
    0: WatermarkLayout.podCorporate,
    1: WatermarkLayout.podDarkField,
    2: WatermarkLayout.podGovern,
  };

  static WatermarkLayout fromIndex(int index) {
    return _indexToLayout[index.clamp(0, 2)] ?? WatermarkLayout.podCorporate;
  }

  static WatermarkLayout fromName(String name) {
    return WatermarkLayout.values.firstWhere(
      (l) => l.name == name,
      orElse: () => WatermarkLayout.podCorporate,
    );
  }
}
