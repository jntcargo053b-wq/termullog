// lib/services/settings_cache.dart
import '../core/constants.dart';
import 'settings_service.dart';

class SettingsCache {
  static WatermarkLayout? _layout;
  static bool? _showWeather;
  static bool? _showAccuracy;
  static String? _watermarkPosition;
  static bool? _showMiniMap;
  static DateTime? _lastLoad;

  static bool get _isStale =>
      _lastLoad == null ||
      DateTime.now().difference(_lastLoad!) > const Duration(minutes: 5);

  static Future<void> preload() async {
    if (!_isStale) return;
    _layout = await SettingsService.getWatermarkLayout();
    _showWeather = await SettingsService.getShowWeather();
    _showAccuracy = await SettingsService.getShowAccuracy();
    _watermarkPosition = await SettingsService.getWatermarkPosition();
    _showMiniMap = await SettingsService.getShowMiniMap();
    _lastLoad = DateTime.now();
  }

  static Future<WatermarkLayout> get layout async {
    await preload();
    return _layout!;
  }

  static Future<bool> get showWeather async {
    await preload();
    return _showWeather!;
  }

  static Future<bool> get showAccuracy async {
    await preload();
    return _showAccuracy!;
  }

  static Future<String> get watermarkPosition async {
    await preload();
    return _watermarkPosition!;
  }

  static Future<bool> get showMiniMap async {
    await preload();
    return _showMiniMap!;
  }

  static void invalidate() {
    _lastLoad = null;
  }
}
