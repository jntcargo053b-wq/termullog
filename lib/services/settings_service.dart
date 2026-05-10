import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';

class SettingsService {
  static const String _keyWatermarkLayout = 'watermark_layout';
  static const String _keyShowWeather = 'show_weather';
  static const String _keyShowAccuracy = 'show_accuracy';
  static const String _keyShowAddress = 'show_address';
  static const String _keyShowCoordinates = 'show_coordinates';
  static const String _keyWatermarkPosition = 'watermark_position';
  static const String _keyDateFormat = 'date_format';
  static const String _keyTimeFormat = 'time_format';
  static const String _keyOpacity = 'opacity';

  static Future<WatermarkLayout> getWatermarkLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_keyWatermarkLayout) ?? WatermarkLayout.modern.index;
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

  static Future<bool> getShowAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowAddress) ?? true;
  }

  static Future<void> setShowAddress(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowAddress, show);
  }

  static Future<bool> getShowCoordinates() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowCoordinates) ?? true;
  }

  static Future<void> setShowCoordinates(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowCoordinates, show);
  }

  static Future<String> getWatermarkPosition() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyWatermarkPosition) ?? 'bottom';
  }

  static Future<void> setWatermarkPosition(String position) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWatermarkPosition, position);
  }

  static Future<String> getDateFormat() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDateFormat) ?? 'dd/MM/yyyy';
  }

  static Future<void> setDateFormat(String format) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDateFormat, format);
  }

  static Future<String> getTimeFormat() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyTimeFormat) ?? 'HH:mm:ss';
  }

  static Future<void> setTimeFormat(String format) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTimeFormat, format);
  }

  static Future<double> getOpacity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyOpacity) ?? 0.85;
  }

  static Future<void> setOpacity(double opacity) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyOpacity, opacity);
  }
}
