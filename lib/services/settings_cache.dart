// lib/services/settings_cache.dart
// FINAL VERSION – Production ready
// - Cache in-memory dengan validasi preload
// - Reset aman (hapus semua key termasuk legacy)
// - Whitelist validation untuk setiap value yang dibaca
// - Kompatibel dengan camera_screen.dart v9
import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../models/watermark_position.dart';

class SettingsCache {
  static SharedPreferences? _prefs;

  // Cache variables
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
  static WatermarkPosition? _watermarkPosition;
  static String? _appName;
  static Uint8List? _customLogoBytes;

  // Whitelist valid values
  static const Set<String> _validMapSizes = {'small', 'medium', 'large'};
  static const Set<String> _validThemeModes = {'light', 'dark', 'system'};

  // Daftar semua key yang digunakan (termasuk legacy untuk cleanup)
  static const List<String> _settingKeys = [
    // Current keys
    'showMiniMap', 'mapSize', 'mapZoomLevel', 'showAddress', 'showCoordinates',
    'opacity', 'showBorder', 'fontSize', 'layout', 'showWeather', 'showAccuracy',
    'dateFormat', 'timeFormat', 'themeMode', 'imageQuality', 'keepScreenOn',
    'useHighAccuracy', 'autoSave', 'watermark_position', 'appName', 'customLogoBytes',
    // Legacy keys (migration cleanup)
    'show_mini_map', 'map_size', 'map_zoom_level', 'show_address', 'show_coordinates',
    'show_weather', 'show_accuracy', 'date_format', 'time_format', 'theme_mode',
    'font_size', 'show_border', 'keep_screen_on', 'auto_save', 'image_quality',
    'use_high_accuracy', 'watermark_layout',
  ];

  // Validation helpers
  static String _validateMapSize(String size) =>
      _validMapSizes.contains(size) ? size : 'medium';
  static String _validateThemeMode(String mode) =>
      _validThemeModes.contains(mode) ? mode : 'dark';
  static double _validateOpacity(double value) => value.clamp(0.1, 1.0);
  static double _validateFontSize(double value) => value.clamp(10.0, 32.0);
  static int _validateImageQuality(int value) => value.clamp(50, 100);
  static int _validateMapZoomLevel(int value) => value.clamp(10, 21);

  // ==========================================================================
  // INIT & PRELOAD (dengan validasi corrupt data)
  // ==========================================================================
  static Future<void> preload() async {
    _prefs ??= await SharedPreferences.getInstance();

    _showMiniMap ??= _prefs!.getBool('showMiniMap') ?? true;
    _mapSize ??= _validateMapSize(_prefs!.getString('mapSize') ?? 'medium');
    _mapZoomLevel ??= _validateMapZoomLevel(_prefs!.getInt('mapZoomLevel') ?? 17);
    _showAddress ??= _prefs!.getBool('showAddress') ?? true;
    _showCoordinates ??= _prefs!.getBool('showCoordinates') ?? true;
    _opacity ??= _validateOpacity(_prefs!.getDouble('opacity') ?? 0.85);
    _showBorder ??= _prefs!.getBool('showBorder') ?? true;
    _fontSize ??= _validateFontSize(_prefs!.getDouble('fontSize') ?? 16.0);
    _showWeather ??= _prefs!.getBool('showWeather') ?? true;
    _showAccuracy ??= _prefs!.getBool('showAccuracy') ?? true;
    _dateFormat ??= _prefs!.getString('dateFormat') ?? 'dd/MM/yyyy';
    _timeFormat ??= _prefs!.getString('timeFormat') ?? 'HH:mm:ss';
    _themeMode ??= _validateThemeMode(_prefs!.getString('themeMode') ?? 'dark');
    _imageQuality ??= _validateImageQuality(_prefs!.getInt('imageQuality') ?? 90);
    _keepScreenOn ??= _prefs!.getBool('keepScreenOn') ?? true;
    _useHighAccuracy ??= _prefs!.getBool('useHighAccuracy') ?? true;
    _autoSave ??= _prefs!.getBool('autoSave') ?? false;
    _appName ??= _prefs!.getString('appName') ?? 'TermulLog';
  }

  // ==========================================================================
  // GETTERS & SETTERS (dengan validasi di setter juga)
  // ==========================================================================
  static Future<bool> get showMiniMap async { await preload(); return _showMiniMap!; }
  static Future<void> setShowMiniMap(bool value) async {
    await preload(); _showMiniMap = value; await _prefs!.setBool('showMiniMap', value);
  }

  static Future<String> get mapSize async { await preload(); return _mapSize!; }
  static Future<void> setMapSize(String value) async {
    await preload(); final valid = _validateMapSize(value);
    _mapSize = valid; await _prefs!.setString('mapSize', valid);
  }

  static Future<int> get mapZoomLevel async { await preload(); return _mapZoomLevel!; }
  static Future<void> setMapZoomLevel(int value) async {
    await preload(); final valid = _validateMapZoomLevel(value);
    _mapZoomLevel = valid; await _prefs!.setInt('mapZoomLevel', valid);
  }

  static Future<bool> get showAddress async { await preload(); return _showAddress!; }
  static Future<void> setShowAddress(bool value) async {
    await preload(); _showAddress = value; await _prefs!.setBool('showAddress', value);
  }

  static Future<bool> get showCoordinates async { await preload(); return _showCoordinates!; }
  static Future<void> setShowCoordinates(bool value) async {
    await preload(); _showCoordinates = value; await _prefs!.setBool('showCoordinates', value);
  }

  static Future<double> get opacity async { await preload(); return _opacity!; }
  static Future<void> setOpacity(double value) async {
    await preload(); final valid = _validateOpacity(value);
    _opacity = valid; await _prefs!.setDouble('opacity', valid);
  }

  static Future<bool> get showBorder async { await preload(); return _showBorder!; }
  static Future<void> setShowBorder(bool value) async {
    await preload(); _showBorder = value; await _prefs!.setBool('showBorder', value);
  }

  static Future<double> get fontSize async { await preload(); return _fontSize!; }
  static Future<void> setFontSize(double value) async {
    await preload(); final valid = _validateFontSize(value);
    _fontSize = valid; await _prefs!.setDouble('fontSize', valid);
  }

  static Future<WatermarkLayout> get layout async {
    await preload();
    if (_layout == null) {
      final saved = _prefs!.getString('layout');
      _layout = WatermarkLayout.values.firstWhere(
        (e) => e.name == (saved ?? 'podCorporate'),
        orElse: () => WatermarkLayout.podCorporate,
      );
    }
    return _layout!;
  }
  static Future<void> setLayout(WatermarkLayout value) async {
    await preload(); _layout = value; await _prefs!.setString('layout', value.name);
  }

  static Future<bool> get showWeather async { await preload(); return _showWeather!; }
  static Future<void> setShowWeather(bool value) async {
    await preload(); _showWeather = value; await _prefs!.setBool('showWeather', value);
  }

  static Future<bool> get showAccuracy async { await preload(); return _showAccuracy!; }
  static Future<void> setShowAccuracy(bool value) async {
    await preload(); _showAccuracy = value; await _prefs!.setBool('showAccuracy', value);
  }

  static Future<String> get dateFormat async { await preload(); return _dateFormat!; }
  static Future<void> setDateFormat(String value) async {
    await preload(); _dateFormat = value; await _prefs!.setString('dateFormat', value);
  }

  static Future<String> get timeFormat async { await preload(); return _timeFormat!; }
  static Future<void> setTimeFormat(String value) async {
    await preload(); _timeFormat = value; await _prefs!.setString('timeFormat', value);
  }

  static Future<String> get themeMode async { await preload(); return _themeMode!; }
  static Future<void> setThemeMode(String value) async {
    await preload(); final valid = _validateThemeMode(value);
    _themeMode = valid; await _prefs!.setString('themeMode', valid);
  }

  static Future<int> get imageQuality async { await preload(); return _imageQuality!; }
  static Future<void> setImageQuality(int value) async {
    await preload(); final valid = _validateImageQuality(value);
    _imageQuality = valid; await _prefs!.setInt('imageQuality', valid);
  }

  static Future<bool> get keepScreenOn async { await preload(); return _keepScreenOn!; }
  static Future<void> setKeepScreenOn(bool value) async {
    await preload(); _keepScreenOn = value; await _prefs!.setBool('keepScreenOn', value);
  }

  static Future<bool> get useHighAccuracy async { await preload(); return _useHighAccuracy!; }
  static Future<void> setUseHighAccuracy(bool value) async {
    await preload(); _useHighAccuracy = value; await _prefs!.setBool('useHighAccuracy', value);
  }

  static Future<bool> get autoSave async { await preload(); return _autoSave!; }
  static Future<void> setAutoSave(bool value) async {
    await preload(); _autoSave = value; await _prefs!.setBool('autoSave', value);
  }

  static Future<String> get appName async { await preload(); return _appName!; }
  static Future<void> setAppName(String value) async {
    await preload();
    final trimmed = value.trim().isEmpty ? 'TermulLog' : value.trim();
    _appName = trimmed;
    await _prefs!.setString('appName', trimmed);
  }

  static Future<Uint8List?> getCustomLogoBytes() async {
    await preload();
    if (_customLogoBytes != null) return _customLogoBytes;
    final b64 = _prefs!.getString('customLogoBytes');
    if (b64 == null || b64.isEmpty) return null;
    try {
      _customLogoBytes = base64Decode(b64);
      return _customLogoBytes;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setCustomLogoBytes(Uint8List? bytes) async {
    await preload();
    _customLogoBytes = bytes;
    if (bytes == null) {
      await _prefs!.remove('customLogoBytes');
    } else {
      await _prefs!.setString('customLogoBytes', base64Encode(bytes));
    }
  }

    // ==========================================================================
  // WATERMARK POSITION (full persistence dengan cache)
  // ==========================================================================
  static Future<WatermarkPosition> loadWatermarkPosition() async {
    await preload();
    if (_watermarkPosition != null) return _watermarkPosition!;
    final raw = _prefs!.getString('watermark_position');
    if (raw == null) {
      _watermarkPosition = WatermarkPosition.initial;
      return _watermarkPosition!;
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _watermarkPosition = WatermarkPosition.fromJson(map);
      return _watermarkPosition!;
    } catch (_) {
      _watermarkPosition = WatermarkPosition.initial;
      return _watermarkPosition!;
    }
  }

  static Future<void> saveWatermarkPosition(WatermarkPosition pos) async {
    try {
      await preload();
      _watermarkPosition = pos;
      final jsonString = jsonEncode(pos.toJson());
      await _prefs!.setString('watermark_position', jsonString);
    } catch (_) {}
  }

  // ==========================================================================
  // HELPER METHODS
  // ==========================================================================
  static Future<Map<String, int>> getMapDimensions() async {
    final size = await mapSize;
    switch (size) {
      case 'small': return {'width': 250, 'height': 150};
      case 'large': return {'width': 450, 'height': 200};
      default: return {'width': 350, 'height': 180};
    }
  }

  static Future<double> getFontScale() async {
    final double size = await fontSize;
    if (size <= 13.0) return 0.85;
    if (size >= 20.0) return 1.15;
    return 1.0;
  }

  // ==========================================================================
  // RESET & INVALIDATE
  // ==========================================================================
  static Future<void> resetAllSettings() async {
    await preload();
    await Future.wait(_settingKeys.map((key) => _prefs!.remove(key)));
    _invalidateAll();
    await preload();
  }

  static void _invalidateAll() {
    _showMiniMap = null; _mapSize = null; _mapZoomLevel = null;
    _showAddress = null; _showCoordinates = null; _opacity = null;
    _showBorder = null; _fontSize = null; _layout = null;
    _showWeather = null; _showAccuracy = null; _dateFormat = null;
    _timeFormat = null; _themeMode = null; _imageQuality = null;
    _keepScreenOn = null; _useHighAccuracy = null; _autoSave = null;
    _watermarkPosition = null; _appName = null; _customLogoBytes = null;
  }

  static void invalidate() {
    _invalidateAll();
    _prefs = null;
  }
}
