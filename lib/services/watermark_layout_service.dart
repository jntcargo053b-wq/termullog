// ════════════════════════════════════════════════════════════════════════════
//  services/watermark_layout_service.dart
//  Menyimpan & membaca preferensi layout watermark via SharedPreferences
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WatermarkLayoutService {
  static String position = 'bottom'; // ← ini yang hilang

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    position = prefs.getString('watermark_position') ?? 'bottom';
  }

  static Future<void> save(String pos) async {
    position = pos;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('watermark_position', pos);
  }
}
class WatermarkLayoutService {
  WatermarkLayoutService._();

  static const _key = 'layout';
  static String _current = 'layout1';

  static String get current => _current;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _current = prefs.getString(_key) ?? 'layout1';
    } catch (e) {
      debugPrint('WatermarkLayoutService.load error: $e');
    }
  }

  static Future<void> save(String layoutId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, layoutId);
      _current = layoutId;
    } catch (e) {
      debugPrint('WatermarkLayoutService.save error: $e');
    }
  }
}
