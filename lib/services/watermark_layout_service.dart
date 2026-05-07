import 'package:shared_preferences/shared_preferences.dart';

class WatermarkLayoutService {
  static String position = 'bottom';

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
