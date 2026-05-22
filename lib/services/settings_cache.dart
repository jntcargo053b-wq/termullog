// lib/services/settings_cache.dart
import 'package:termullog/core/constants.dart';
import 'settings_service.dart';

class SettingsCache {
  static WatermarkLayout? _layout;
  static bool? _showWeather;
  static bool? _showAccuracy;
  static bool? _showMiniMap;
  static String? _mapSize;
  static int? _mapZoomLevel;
  // --- 5 setting yang sebelumnya tidak di-cache ---
  static bool? _showAddress;
  static bool? _showCoordinates;
  static double? _opacity;
  static bool? _showBorder;
  static String? _fontSize;
  // ------------------------------------------------
  static DateTime? _lastLoad;
  static Future<void>? _loadingFuture;

  static bool get _isStale =>
      _lastLoad == null ||
      DateTime.now().difference(_lastLoad!) > const Duration(minutes: 5);

  static Future<void> preload() async {
    if (!_isStale && _lastLoad != null) return;
    if (_loadingFuture != null) return _loadingFuture!;

    _loadingFuture = _performPreload();
    await _loadingFuture;
    _loadingFuture = null;
  }

  static Future<void> _performPreload() async {
    try {
      final results = await Future.wait([
        SettingsService.getWatermarkLayout(),   // 0
        SettingsService.getShowWeather(),        // 1
        SettingsService.getShowAccuracy(),       // 2
        SettingsService.getShowMiniMap(),        // 4
        SettingsService.getMapSize(),            // 5
        SettingsService.getMapZoomLevel(),       // 6
        SettingsService.getShowAddress(),        // 7
        SettingsService.getShowCoordinates(),    // 8
        SettingsService.getOpacity(),            // 9
        SettingsService.getShowBorder(),         // 10
        SettingsService.getFontSize(),           // 11
      ]);

      _layout = results[0] as WatermarkLayout;
      _showWeather = results[1] as bool;
      _showAccuracy = results[2] as bool;
      _showMiniMap = results[3] as bool;
      _mapSize = results[4] as String;
      _mapZoomLevel = results[5] as int;
      _showAddress = results[6] as bool;
      _showCoordinates = results[7] as bool;
      _opacity = results[8] as double;
      _showBorder = results[9] as bool;
      _fontSize = results[10] as String;
      _lastLoad = DateTime.now();
    } catch (e) {
      _lastLoad = null;
      rethrow;
    }
  }

  static Future<WatermarkLayout> get layout async {
    await preload();
    if (_layout == null) throw StateError('WatermarkLayout gagal dimuat');
    return _layout!;
  }

  static Future<bool> get showWeather async {
    await preload();
    if (_showWeather == null) throw StateError('showWeather gagal dimuat');
    return _showWeather!;
  }

  static Future<bool> get showAccuracy async {
    await preload();
    if (_showAccuracy == null) throw StateError('showAccuracy gagal dimuat');
    return _showAccuracy!;
  }

    await preload();
  }

  static Future<bool> get showMiniMap async {
    await preload();
    if (_showMiniMap == null) throw StateError('showMiniMap gagal dimuat');
    return _showMiniMap!;
  }

  static Future<String> get mapSize async {
    await preload();
    if (_mapSize == null) throw StateError('mapSize gagal dimuat');
    return _mapSize!;
  }

  static Future<int> get mapZoomLevel async {
    await preload();
    if (_mapZoomLevel == null) throw StateError('mapZoomLevel gagal dimuat');
    return _mapZoomLevel!;
  }

  static Future<bool> get showAddress async {
    await preload();
    if (_showAddress == null) throw StateError('showAddress gagal dimuat');
    return _showAddress!;
  }

  static Future<bool> get showCoordinates async {
    await preload();
    if (_showCoordinates == null) throw StateError('showCoordinates gagal dimuat');
    return _showCoordinates!;
  }

  static Future<double> get opacity async {
    await preload();
    if (_opacity == null) throw StateError('opacity gagal dimuat');
    return _opacity!;
  }

  static Future<bool> get showBorder async {
    await preload();
    if (_showBorder == null) throw StateError('showBorder gagal dimuat');
    return _showBorder!;
  }

  static Future<String> get fontSize async {
    await preload();
    if (_fontSize == null) throw StateError('fontSize gagal dimuat');
    return _fontSize!;
  }

  static void invalidate() {
    _lastLoad = null;
    _loadingFuture = null;
  }

  static Future<void> refreshLayout() async {
    _layout = await SettingsService.getWatermarkLayout();
    _lastLoad = DateTime.now();
  }

  static Future<void> refreshShowWeather() async {
    _showWeather = await SettingsService.getShowWeather();
    _lastLoad = DateTime.now();
  }

  static Future<void> refreshShowAccuracy() async {
    _showAccuracy = await SettingsService.getShowAccuracy();
    _lastLoad = DateTime.now();
  }

  static Future<void> refreshWatermarkPosition() async {
    _lastLoad = DateTime.now();
  }

  static Future<void> refreshShowMiniMap() async {
    _showMiniMap = await SettingsService.getShowMiniMap();
    _lastLoad = DateTime.now();
  }

  static Future<void> refreshMapSize() async {
    _mapSize = await SettingsService.getMapSize();
    _lastLoad = DateTime.now();
  }

  static Future<void> refreshMapZoomLevel() async {
    _mapZoomLevel = await SettingsService.getMapZoomLevel();
    _lastLoad = DateTime.now();
  }

  static Future<void> refreshAll() async {
    await _performPreload();
  }
}
