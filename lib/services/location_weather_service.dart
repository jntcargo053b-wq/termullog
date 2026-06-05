// lib/services/location_weather_service.dart
// SLIM EDITION — POD GPS Rewrite
// Geocoding telah dipindah ke pod_address_resolver.dart.
// File ini hanya menyediakan:
//   - fetchMap / fetchMapWithRetry  (static map tiles OSM)
//   - fetchWeather                  (open-meteo, dipakai oleh preview_screen & layout)
//   - LocationWeatherResult         (dipakai oleh watermark_params)
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

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

  static final Map<String, _WeatherEntry> _weatherCache = {};
  static const Duration _weatherCacheDuration = Duration(minutes: 30);

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

  // ── Static Map Tiles ────────────────────────────────────
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

  // ── Weather ─────────────────────────────────────────────
  static Future<LocationWeatherResult> fetchFromPosition(Position pos) async {
    final weather = await _fetchWeather(
      pos.latitude.toStringAsFixed(5),
      pos.longitude.toStringAsFixed(5),
    );
    return LocationWeatherResult(address: '', weather: weather);
  }

  static Future<String> _fetchWeather(String lat, String lon) async {
    if (_isClosed) return '';
    final key = '$lat,$lon';
    final now = DateTime.now();
    final cached = _weatherCache[key];
    if (cached != null && now.isBefore(cached.expiry)) {
      return cached.weather;
    }
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lon'
        '&current=temperature_2m,weather_code&timezone=auto',
      );
      final res = await _client.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final current = data['current'] as Map<String, dynamic>?;
        if (current != null) {
          final temp =
              (current['temperature_2m'] as num?)?.toStringAsFixed(0) ?? '--';
          final code = (current['weather_code'] as num?)?.toInt() ?? 0;
          final w = '${_wmo(code)} $temp°C';
          _weatherCache[key] = _WeatherEntry(w, now.add(_weatherCacheDuration));
          return w;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Weather error: $e');
    }
    return '';
  }

  static String _wmo(int c) {
    if (c == 0)  return '☀️ Cerah';
    if (c <= 3)  return '⛅ Berawan';
    if (c <= 49) return '🌫️ Berkabut';
    if (c <= 57) return '🌦️ Gerimis';
    if (c <= 67) return '🌧️ Hujan';
    if (c <= 77) return '❄️ Salju';
    if (c <= 82) return '🌧️ Hujan Lebat';
    if (c <= 99) return '⚡ Badai Petir';
    return '🌡️';
  }
}

class _WeatherEntry {
  final String weather;
  final DateTime expiry;
  _WeatherEntry(this.weather, this.expiry);
}

// Backward-compat extension (dipakai beberapa layout lama)
extension LocationWeatherServiceExt on LocationWeatherService {
  static Future<String> fetchWeather(double lat, double lon) async {
    try {
      return await LocationWeatherService._fetchWeather(
        lat.toStringAsFixed(5),
        lon.toStringAsFixed(5),
      );
    } catch (_) {
      return '';
    }
  }
}
