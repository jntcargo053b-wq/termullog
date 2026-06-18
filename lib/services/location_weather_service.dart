// lib/services/location_weather_service.dart
// Menyediakan:
//   - fetchMap / fetchMapWithRetry  (static map tiles OSM)
//   - fetchFromPosition             (weather saja, delegate ke WeatherService)
//   - LocationWeatherResult         (dipakai oleh watermark_params)

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'weather_service.dart';

class LocationWeatherResult {
  final String address;
  final String weather;
  final String rawAddress;
  const LocationWeatherResult({
    required this.address,
    required this.weather,
    this.rawAddress = '',
  });
}

class LocationWeatherService {
  LocationWeatherService._();

  static http.Client _client = http.Client();
  static bool _isClosed = false;

  static void close() {
    if (_isClosed) return;
    _isClosed = true;
    _client.close();
  }

  static void reopen() {
    if (!_isClosed) return;
    _client = http.Client();
    _isClosed = false;
  }

  // ── Static Map Tiles ─────────────────────────────────────
  static Future<Uint8List?> fetchMap(
    double lat,
    double lon, {
    int width = 300,
    int height = 300,
    int zoom = 15,
  }) async {
    if (_isClosed) return null;
    try {
      final url = Uri.parse(
        'https://staticmap.openstreetmap.de/staticmap.php'
        '?center=$lat,$lon&zoom=$zoom&size=${width}x$height&maptype=mapnik',
      );
      final res = await _client.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return res.bodyBytes;
    } catch (e) {
      if (kDebugMode) debugPrint('Map fetch error: $e');
    }
    return null;
  }

  static Future<Uint8List?> fetchMapWithRetry(
    double lat,
    double lon, {
    int retries = 2,
    int width = 300,
    int height = 300,
    int zoom = 15,
  }) async {
    for (int i = 0; i < retries; i++) {
      final r = await fetchMap(lat, lon, width: width, height: height, zoom: zoom);
      if (r != null) return r;
      await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
    }
    return null;
  }

  // ── Weather — delegate ke WeatherService (satu sumber) ──
  static final _weatherService = WeatherService();

  static Future<LocationWeatherResult> fetchFromPosition(Position pos) async {
    final weather = await _weatherService.fetchWeather(
      pos.latitude,
      pos.longitude,
    );
    return LocationWeatherResult(address: '', weather: weather);
  }
}
