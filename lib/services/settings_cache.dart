// lib/services/settings_cache.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../models/watermark_position.dart';

class SettingsCache {
  static SharedPreferences? _prefs;

  // Cache variables (semua properti)
  static bool? _showMiniMap;
  static String? _mapSize;
  static int? _mapZoomLevel;
  static bool? _showAddress;
  static bool? _showCoordinates;
  static double? _opacity;
  static bool? _showBorder;
  static double? _fontSize;
  static WatermarkLayout? _layout;
  static bool? _showWeather;
  static bool? _showAccuracy;
  static String? _dateFormat;
  static String? _timeFormat;
  static String? _themeMode;
  static int? _imageQuality;
  static bool? _keepScreenOn;
  static bool? _useHighAccuracy;
  static bool? _autoSave;

  // ==========================================================================
  // INIT / PRELOAD
  // ==========================================================================
  static Future<void> preload() async {
    _prefs ??= await SharedPreferences.getInstance();

    _showMiniMap ??= _prefs!.getBool('showMiniMap') ?? true;
    _mapSize ??= _prefs!.getString('mapSize') ?? 'medium';
    _mapZoomLevel ??= _prefs!.getInt('mapZoomLevel') ?? 17;
    _showAddress ??= _prefs!.getBool('showAddress') ?? true;
    _showCoordinates ??= _prefs!.getBool('showCoordinates') ?? true;
    _opacity ??= _prefs!.getDouble('opacity') ?? 0.85;
    _showBorder ??= _prefs!.getBool('showBorder') ?? true;
    _fontSize ??= _prefs!.getDouble('fontSize') ?? 16.0;
    _showWeather ??= _prefs!.getBool('showWeather') ?? true;
    _showAccuracy ??= _prefs!.getBool('showAccuracy') ?? true;
    _dateFormat ??= _prefs!.getString('dateFormat') ?? 'dd/MM/yyyy';
    _timeFormat ??= _prefs!.getString('timeFormat') ?? 'HH:mm:ss';
    _themeMode ??= _prefs!.getString('themeMode') ?? 'dark';
    _imageQuality ??= _prefs!.getInt('imageQuality') ?? 90;
    _keepScreenOn ??= _prefs!.getBool('keepScreenOn') ?? true;
    _useHighAccuracy ??= _prefs!.getBool('useHighAccuracy') ?? true;
    _autoSave ??= _prefs!.getBool('autoSave') ?? false;
  }

  // ==========================================================================
  // WATERMARK LAYOUT
  // ==========================================================================
  static Future<WatermarkLayout> get layout async {
    await preload();
    if (_layout == null) {
      final saved = _prefs!.getString('layout');
      _layout = WatermarkLayout.values.firstWhere(
        (e) => e.name == (saved ?? 'modern'),
        orElse: () => WatermarkLayout.modern,
      );
    }
    return _layout!;
  }

  static Future<void> setLayout(WatermarkLayout value) async {
    await preload();
    _layout = value;
    await _prefs!.setString('layout', value.name);
  }

  // ==========================================================================
  // SHOW WEATHER & ACCURACY
  // ==========================================================================
  static Future<bool> get showWeather async {
    await preload();
    return _showWeather!;
  }
  static Future<void> setShowWeather(bool value) async {
    await preload();
    _showWeather = value;
    await _prefs!.setBool('showWeather', value);
  }

  static Future<bool> get showAccuracy async {
    await preload();
    return _showAccuracy!;
  }
  static Future<void> setShowAccuracy(bool value) async {
    await preload();
    _showAccuracy = value;
    await _prefs!.setBool('showAccuracy', value);
  }

  // ==========================================================================
  // MINI MAP & MAP SETTINGS
  // ==========================================================================
  static Future<bool> get showMiniMap async {
    await preload();
    return _showMiniMap!;
  }
  static Future<void> setShowMiniMap(bool value) async {
    await preload();
    _showMiniMap = value;
    await _prefs!.setBool('showMiniMap', value);
  }

  static Future<String> get mapSize async {
    await preload();
    return _mapSize!;
  }
  static Future<void> setMapSize(String value) async {
    await preload();
    _mapSize = value;
    await _prefs!.setString('mapSize', value);
  }

  static Future<int> get mapZoomLevel async {
    await preload();
    return _mapZoomLevel!;
  }
  static Future<void> setMapZoomLevel(int value) async {
    await preload();
    _mapZoomLevel = value;
    await _prefs!.setInt('mapZoomLevel', value);
  }

  // ==========================================================================
  // ADDRESS & COORDINATES
  // ==========================================================================
  static Future<bool> get showAddress async {
    await preload();
    return _showAddress!;
  }
  static Future<void> setShowAddress(bool value) async {
    await preload();
    _showAddress = value;
    await _prefs!.setBool('showAddress', value);
  }

  static Future<bool> get showCoordinates async {
    await preload();
    return _showCoordinates!;
  }
  static Future<void> setShowCoordinates(bool value) async {
    await preload();
    _showCoordinates = value;
    await _prefs!.setBool('showCoordinates', value);
  }

  // ==========================================================================
  // OPACITY & BORDER
  // ==========================================================================
  static Future<double> get opacity async {
    await preload();
    return _opacity!;
  }
  static Future<void> setOpacity(double value) async {
    await preload();
    _opacity = value;
    await _prefs!.setDouble('opacity', value);
  }

  static Future<bool> get showBorder async {
    await preload();
    return _showBorder!;
  }
  static Future<void> setShowBorder(bool value) async {
    await preload();
    _showBorder = value;
    await _prefs!.setBool('showBorder', value);
  }

  // ==========================================================================
  // FONT SIZE (double)
  // ==========================================================================
  static Future<double> get fontSize async {
    await preload();
    return _fontSize!;
  }
  static Future<void> setFontSize(double value) async {
    await preload();
    _fontSize = value;
    await _prefs!.setDouble('fontSize', value);
  }

  // ==========================================================================
  // DATE & TIME FORMAT
  // ==========================================================================
  static Future<String> get dateFormat async {
    await preload();
    return _dateFormat!;
  }
  static Future<void> setDateFormat(String value) async {
    await preload();
    _dateFormat = value;
    await _prefs!.setString('dateFormat', value);
  }

  static Future<String> get timeFormat async {
    await preload();
    return _timeFormat!;
  }
  static Future<void> setTimeFormat(String value) async {
    await preload();
    _timeFormat = value;
    await _prefs!.setString('timeFormat', value);
  }

  // ==========================================================================
  // THEME MODE
  // ==========================================================================
  static Future<String> get themeMode async {
    await preload();
    return _themeMode!;
  }
  static Future<void> setThemeMode(String value) async {
    await preload();
    _themeMode = value;
    await _prefs!.setString('themeMode', value);
  }

  // ==========================================================================
  // IMAGE QUALITY
  // ==========================================================================
  static Future<int> get imageQuality async {
    await preload();
    return _imageQuality!;
  }
  static Future<void> setImageQuality(int value) async {
    await preload();
    _imageQuality = value;
    await _prefs!.setInt('imageQuality', value);
  }

  // ==========================================================================
  // KEEP SCREEN ON
  // ==========================================================================
  static Future<bool> get keepScreenOn async {
    await preload();
    return _keepScreenOn!;
  }
  static Future<void> setKeepScreenOn(bool value) async {
    await preload();
    _keepScreenOn = value;
    await _prefs!.setBool('keepScreenOn', value);
  }

  // ==========================================================================
  // USE HIGH ACCURACY
  // ==========================================================================
  static Future<bool> get useHighAccuracy async {
    await preload();
    return _useHighAccuracy!;
  }
  static Future<void> setUseHighAccuracy(bool value) async {
    await preload();
    _useHighAccuracy = value;
    await _prefs!.setBool('useHighAccuracy', value);
  }

  // ==========================================================================
  // AUTO SAVE
  // ==========================================================================
  static Future<bool> get autoSave async {
    await preload();
    return _autoSave!;
  }
  static Future<void> setAutoSave(bool value) async {
    await preload();
    _autoSave = value;
    await _prefs!.setBool('autoSave', value);
  }

  // ==========================================================================
  // RESET ALL SETTINGS
  // ==========================================================================
  static Future<void> resetAllSettings() async {
    await preload();
    await _prefs!.clear();
    _invalidateAll();
    await preload();
  }

  static void _invalidateAll() {
    _showMiniMap = null;
    _mapSize = null;
    _mapZoomLevel = null;
    _showAddress = null;
    _showCoordinates = null;
    _opacity = null;
    _showBorder = null;
    _fontSize = null;
    _layout = null;
    _showWeather = null;
    _showAccuracy = null;
    _dateFormat = null;
    _timeFormat = null;
    _themeMode = null;
    _imageQuality = null;
    _keepScreenOn = null;
    _useHighAccuracy = null;
    _autoSave = null;
  }

  // ==========================================================================
  // INVALIDATE CACHE (public)
  // ==========================================================================
  static void invalidate() {
    _invalidateAll();
  }

  // ==========================================================================
  // WATERMARK POSITION (persistent)
  // ==========================================================================
  static Future<void> saveWatermarkPosition(WatermarkPosition pos) async {
    await preload();
    final jsonString = jsonEncode(pos.toJson());
    await _prefs!.setString('watermark_position', jsonString);
  }

  static Future<WatermarkPosition> loadWatermarkPosition() async {
    await preload();
    final raw = _prefs!.getString('watermark_position');
    if (raw == null) return WatermarkPosition.initial;
    try {
      final Map<String, dynamic> map = jsonDecode(raw);
      return WatermarkPosition.fromJson(map);
    } catch (_) {
      return WatermarkPosition.initial;
    }
  }
}
