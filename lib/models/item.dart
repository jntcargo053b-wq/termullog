// ════════════════════════════════════════════════════════════════════════════
//  models/item.dart
//  Model data satu laporan foto
// ════════════════════════════════════════════════════════════════════════════

class Item {
  final String id;
  final String path;
  final String time;

  const Item({
    required this.id,
    required this.path,
    required this.time,
  });
}
