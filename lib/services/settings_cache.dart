import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart'; // enum WatermarkLayout, dll.
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';   // <── WAJIB! untuk enum WatermarkLayout

class SettingsCache {
  static SharedPreferences? _prefs;

  // CACHE
  static bool? _showMiniMap;
  static String? _mapSize;
  static int? _mapZoomLevel;
  static bool? _showAddress;
  static bool? _showCoordinates;
  static double? _opacity;
  static bool? _showBorder;
  static double? _fontSize; // double
  static WatermarkLayout? _layout;
  static bool? _showWeather;
  static bool? _showAccuracy;

  // ==========================================================================
  // INIT
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
  }

  // ==========================================================================
  // WATERMARK LAYOUT (enum dari constants.dart)
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
  // GETTER/SETTER LAINNYA (disesuaikan dengan SettingsScreen)
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
  // INVALIDATE CACHE
  // ==========================================================================
  static void invalidate() {
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
  }
}
