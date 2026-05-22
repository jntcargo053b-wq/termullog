import 'package:shared_preferences/shared_preferences.dart';

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
  static double? _fontSize;

  // ==========================================================================
  // WATERMARK LAYOUT
  // ==========================================================================

  static String? _layout;

  static Future<String> get layout async {
    await preload();

    _layout ??=
        _prefs!.getString('layout') ?? 'cinematic';

    return _layout!;
  }

  static Future<void> setLayout(String value) async {
    await preload();

    _layout = value;

    await _prefs!.setString('layout', value);
  }

  // ==========================================================================
  // SHOW WEATHER
  // ==========================================================================

  static bool? _showWeather;

  static Future<bool> get showWeather async {
    await preload();

    _showWeather ??=
        _prefs!.getBool('showWeather') ?? true;

    return _showWeather!;
  }

  static Future<void> setShowWeather(bool value) async {
    await preload();

    _showWeather = value;

    await _prefs!.setBool('showWeather', value);
  }

  // ==========================================================================
  // SHOW ACCURACY
  // ==========================================================================

  static bool? _showAccuracy;

  static Future<bool> get showAccuracy async {
    await preload();

    _showAccuracy ??=
        _prefs!.getBool('showAccuracy') ?? true;

    return _showAccuracy!;
  }

  static Future<void> setShowAccuracy(bool value) async {
    await preload();

    _showAccuracy = value;

    await _prefs!.setBool('showAccuracy', value);
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

  // ==========================================================================
  // INIT
  // ==========================================================================

  static Future<void> preload() async {
    _prefs ??= await SharedPreferences.getInstance();

    _showMiniMap ??= _prefs!.getBool('showMiniMap') ?? true;

    _mapSize ??= _prefs!.getString('mapSize') ?? 'medium';

    _mapZoomLevel ??= _prefs!.getInt('mapZoomLevel') ?? 17;

    _showAddress ??= _prefs!.getBool('showAddress') ?? true;

    _showCoordinates ??=
        _prefs!.getBool('showCoordinates') ?? true;

    _opacity ??= _prefs!.getDouble('opacity') ?? 0.85;

    _showBorder ??= _prefs!.getBool('showBorder') ?? true;

    _fontSize ??= _prefs!.getDouble('fontSize') ?? 14.0;
  }

  // ==========================================================================
  // SHOW MINI MAP
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

  // ==========================================================================
  // MAP SIZE
  // ==========================================================================

  static Future<String> get mapSize async {
    await preload();
    return _mapSize!;
  }

  static Future<void> setMapSize(String value) async {
    await preload();

    _mapSize = value;

    await _prefs!.setString('mapSize', value);
  }

  // ==========================================================================
  // MAP ZOOM
  // ==========================================================================

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
  // SHOW ADDRESS
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

  // ==========================================================================
  // SHOW COORDINATES
  // ==========================================================================

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
  // OPACITY
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

  // ==========================================================================
  // SHOW BORDER
  // ==========================================================================

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
  // FONT SIZE
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
}
