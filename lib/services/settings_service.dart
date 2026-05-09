import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';

class SettingsService {
  static const String _keyWatermarkLayout = 'watermark_layout';
  static const String _keyShowWeather = 'show_weather';
  static const String _keyShowAccuracy = 'show_accuracy';
  static const String _keyWatermarkPosition = 'watermark_position'; // top/bottom
  
  static Future<WatermarkLayout> getWatermarkLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_keyWatermarkLayout) ?? 0;
    return WatermarkLayout.values[index];
  }
  
  static Future<void> setWatermarkLayout(WatermarkLayout layout) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyWatermarkLayout, layout.index);
  }
  
  static Future<bool> getShowWeather() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowWeather) ?? true;
  }
  
  static Future<void> setShowWeather(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowWeather, show);
  }
  
  static Future<bool> getShowAccuracy() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowAccuracy) ?? true;
  }
  
  static Future<void> setShowAccuracy(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowAccuracy, show);
  }
  
  static Future<String> getWatermarkPosition() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyWatermarkPosition) ?? 'bottom';
  }
  
  static Future<void> setWatermarkPosition(String position) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWatermarkPosition, position);
  }
}
