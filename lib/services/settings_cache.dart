// lib/services/settings_cache.dart
import 'package:termullog/core/constants.dart';
import 'settings_service.dart';

class SettingsCache {
  static WatermarkLayout? _layout;
  static bool? _showWeather;
  static bool? _showAccuracy;
  static String? _watermarkPosition;
  static bool? _showMiniMap;
  static String? _mapSize;
  static int? _mapZoomLevel;
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
        SettingsService.getWatermarkLayout(),
        SettingsService.getShowWeather(),
        SettingsService.getShowAccuracy(),
        SettingsService.getWatermarkPosition(),
        SettingsService.getShowMiniMap(),
        SettingsService.getMapSize(),
        SettingsService.getMapZoomLevel(),
      ]);

      _layout = results[0] as WatermarkLayout;
      _showWeather = results[1] as bool;
      _showAccuracy = results[2] as bool;
      _watermarkPosition = results[3] as String;
      _showMiniMap = results[4] as bool;
      _mapSize = results[5] as String;
      _mapZoomLevel = results[6] as int;
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

  static Future<String> get watermarkPosition async {
    await preload();
    if (_watermarkPosition == null) throw StateError('watermarkPosition gagal dimuat');
    return _watermarkPosition!;
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
    _watermarkPosition = await SettingsService.getWatermarkPosition();
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
