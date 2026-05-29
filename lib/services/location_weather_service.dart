// lib/services/location_weather_service.dart (final with all fixes)
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:geocoding/geocoding.dart';

// ============================================================
// LocationWeatherResult
// ============================================================

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

// ============================================================
// GeoHash untuk caching pintar
// ============================================================

class GeoHash {
  static const int _precision = 4;

  static String encode(double lat, double lon) {
    final latRounded =
        (lat * pow(10, _precision)).round() / pow(10, _precision);
    final lonRounded =
        (lon * pow(10, _precision)).round() / pow(10, _precision);
    return '${latRounded.toStringAsFixed(_precision)},'
        '${lonRounded.toStringAsFixed(_precision)}';
  }

  static double distance(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}

// ============================================================
// Cache Entry
// ============================================================

class _AddressCacheEntry {
  final String address;
  final double lat;
  final double lon;
  final DateTime timestamp;
  double distanceMeters = 0;

  _AddressCacheEntry({
    required this.address,
    required this.lat,
    required this.lon,
    required this.timestamp,
  });
}

class _WeatherCacheEntry {
  final String weather;
  final DateTime timestamp;

  _WeatherCacheEntry({
    required this.weather,
    required this.timestamp,
  });
}

// ============================================================
// Main Service
// ============================================================

class LocationWeatherService {
  LocationWeatherService._();

  static final http.Client _client = http.Client();

  // Cache alamat dengan radius 5m (fix #1)
  static final Map<String, _AddressCacheEntry> _addressCache = {};
  static const int _addressCacheMaxSize = 100;
  static const double _addressCacheRadiusMeters = 5.0;

  // Cache weather TTL 10 menit
  static final Map<String, _WeatherCacheEntry> _weatherCache = {};
  static const int _weatherCacheMaxSize = 50;

  // Cache mini map (LRU sejati dengan LinkedHashMap)
  static final LinkedHashMap<String, Uint8List> _mapCache = LinkedHashMap();
  static const int _mapCacheMaxSize = 50;

  static DateTime _lastNominatimRequest =
      DateTime.now().subtract(const Duration(seconds: 2));

  static final _progressController =
      StreamController<String>.broadcast();
  static Stream<String> get onProgress => _progressController.stream;

  static bool _isClosed = false;

  static const String _locationIqApiKey = 'pk.05a5be327fe64484e26fca823101a387';

  static void _emitProgress(String message) {
    if (_isClosed) return;
    _progressController.add(message);
  }

  static void close() {
    if (_isClosed) return;
    _isClosed = true;
    _client.close();
    _progressController.close();
  }

  static final RegExp _plusCodePattern = RegExp(
    r'(?:^|[\s,])([23456789CFGHJMPQRVWX]{4,8}\+[23456789CFGHJMPQRVWX]{2,3})(?:[\s,]|$)',
    caseSensitive: false,
  );

  static bool _isPlusCode(String? s) {
    if (s == null || s.isEmpty) return false;
    return _plusCodePattern.hasMatch(s.trim());
  }

  static String _stripPlusCode(String address) {
    final parts = address
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && !_isPlusCode(p))
        .toList();
    return parts.isEmpty ? address : parts.join(', ');
  }

  static List<String> _uniqueParts(List<String> parts) {
    return LinkedHashSet<String>.from(parts).toList();
  }

  // ============================================================
  // Main Method - FETCH ADDRESS & WEATHER
  // ============================================================

  static Future<LocationWeatherResult> fetchFromPosition(
      Position position) async {
    final lat = position.latitude;
    final lon = position.longitude;
    final latStr = lat.toStringAsFixed(6);
    final lonStr = lon.toStringAsFixed(6);

    _emitProgress('📍 Mencari lokasi...');

    // 🔥 Hindari geocode saat GPS masih noise (fix #2)
    if (position.accuracy > 18) {
      return LocationWeatherResult(
        address: '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}',
        weather: '',
        rawAddress: '',
      );
    }

    final cached = _findNearbyAddressCache(lat, lon);
    if (cached != null) {
      _emitProgress(
          '📦 Cache lokasi terdekat (${cached.distanceMeters.toStringAsFixed(0)}m)');
      final weather = await _fetchWeatherWithCache(lat, lon);
      return LocationWeatherResult(
        address: cached.address,
        weather: weather,
        rawAddress: cached.address,
      );
    }

    final addressFuture = _fetchAddressParallel(lat, lon, latStr, lonStr);
    final weatherFuture = _fetchWeatherWithCache(lat, lon);

    final results = await Future.wait([addressFuture, weatherFuture]);
    String finalAddress = results[0];
    String weather = results[1];

    if (finalAddress.isEmpty) {
      final dmsLat = _formatDMS(lat, true);
      final dmsLon = _formatDMS(lon, false);
      finalAddress = 'GPS: $dmsLat, $dmsLon';
      _emitProgress('🌐 Menggunakan koordinat GPS');
    } else {
      _trimAddressCache();
      _addressCache[GeoHash.encode(lat, lon)] = _AddressCacheEntry(
        address: finalAddress,
        lat: lat,
        lon: lon,
        timestamp: DateTime.now(),
      );
      _emitProgress('✅ Alamat ditemukan');
    }

    return LocationWeatherResult(
        address: finalAddress, weather: weather, rawAddress: finalAddress);
  }

  // ============================================================
  // Address Cache Helper (fix #5)
  // ============================================================

  static _AddressCacheEntry? _findNearbyAddressCache(double lat, double lon) {
    _AddressCacheEntry? best;
    double bestDistance = double.infinity;

    for (final entry in _addressCache.values) {
      final distance = GeoHash.distance(lat, lon, entry.lat, entry.lon);
      if (distance <= _addressCacheRadiusMeters && distance < bestDistance) {
        bestDistance = distance;
        entry.distanceMeters = distance;
        best = entry;
      }
    }
    return best;
  }

  static void _trimAddressCache() {
    if (_addressCache.length < _addressCacheMaxSize) return;
    final oldest = _addressCache.entries.reduce(
      (a, b) => a.value.timestamp.isBefore(b.value.timestamp) ? a : b,
    );
    _addressCache.remove(oldest.key);
  }

  static void _trimWeatherCache() {
    if (_weatherCache.length < _weatherCacheMaxSize) return;
    final oldest = _weatherCache.entries.reduce(
      (a, b) => a.value.timestamp.isBefore(b.value.timestamp) ? a : b,
    );
    _weatherCache.remove(oldest.key);
  }

  // ============================================================
  // Format DMS
  // ============================================================

  static String _formatDMS(double coord, bool isLat) {
    final degrees = coord.abs().floor();
    final minutes = ((coord.abs() - degrees) * 60).floor();
    final seconds =
        ((coord.abs() - degrees - minutes / 60) * 3600).toStringAsFixed(1);
    final direction =
        isLat ? (coord >= 0 ? 'N' : 'S') : (coord >= 0 ? 'E' : 'W');
    return "${degrees}°${minutes}'${seconds}\" $direction";
  }

  // ============================================================
  // PARALLEL ADDRESS FETCH (fix #4)
  // ============================================================

  static Future<String> _fetchAddressParallel(
      double lat, double lon, String latStr, String lonStr) async {
    try {
      // 🔥 Provider paling akurat dulu (Google Geocoding)
      final geocoding =
          await _fetchFromGeocoding(lat, lon).timeout(const Duration(seconds: 3));
      if (geocoding.isNotEmpty && !geocoding.contains('Unnamed Road')) {
        return geocoding;
      }

      final nominatim =
          await _fetchFromNominatim(latStr, lonStr);
      if (nominatim.isNotEmpty) {
        return nominatim;
      }

      final photon =
          await _fetchFromPhoton(latStr, lonStr);
      return photon;
    } catch (_) {
      return '';
    }
  }

  // ============================================================
  // PROVIDER 1: Geocoding Package (Google Maps)
  // ============================================================

  static Future<String> _fetchFromGeocoding(double lat, double lon) async {
    try {
      final placemarks =
          await placemarkFromCoordinates(lat, lon).timeout(const Duration(seconds: 4));
      if (placemarks.isEmpty) return '';

      Placemark? best;
      for (final p in placemarks) {
        if (!_isPlusCode(p.street)) {
          best = p;
          break;
        }
      }
      final p = best ?? placemarks.first;

      final parts = <String>[];

      final street = (!_isPlusCode(p.street) && p.street?.isNotEmpty == true)
          ? p.street
          : (!_isPlusCode(p.thoroughfare) && p.thoroughfare?.isNotEmpty == true)
              ? p.thoroughfare
              : null;
      if (street != null) parts.add(street);

      if (p.subLocality?.isNotEmpty == true &&
          !_isPlusCode(p.subLocality)) {
        parts.add(p.subLocality!);
      }

      if (p.subAdministrativeArea?.isNotEmpty == true &&
          !_isPlusCode(p.subAdministrativeArea)) {
        parts.add(p.subAdministrativeArea!);
      }

      if (p.locality?.isNotEmpty == true &&
          !_isPlusCode(p.locality)) {
        parts.add(p.locality!);
      }

      if (p.administrativeArea?.isNotEmpty == true &&
          p.administrativeArea != p.locality &&
          !_isPlusCode(p.administrativeArea)) {
        parts.add(p.administrativeArea!);
      }

      if (parts.isEmpty) return '';

      final address = _uniqueParts(parts).join(', ');
      debugPrint('Geocoding: $address');
      return address;
    } on TimeoutException {
      debugPrint('Geocoding timeout');
    } catch (e) {
      debugPrint('Geocoding error: $e');
    }
    return '';
  }

  // ============================================================
  // PROVIDER 2: Photon
  // ============================================================

  static Future<String> _fetchFromPhoton(String latStr, String lonStr) async {
    try {
      final uri = Uri.parse(
          'https://photon.komoot.io/reverse?lat=$latStr&lon=$lonStr');
      final res =
          await _client.get(uri).timeout(const Duration(milliseconds: 1800));
      if (res.statusCode != 200) return '';

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) return '';

      final props =
          features[0]['properties'] as Map<String, dynamic>? ?? {};

      final name        = _safeStr(props['name']);
      final housenumber = _safeStr(props['housenumber']);
      final street      = _safeStr(props['street']);
      final district    = _safeStr(props['district']);
      final city        = _safeStr(props['city']);
      final state       = _safeStr(props['state']);

      final parts = <String>[];
      if (name != null && name != street) parts.add(name);
      if (street != null) {
        parts.add(housenumber != null
            ? '$street No.$housenumber'
            : street);
      }
      if (district != null) parts.add(district);
      if (city != null)     parts.add(city);
      if (state != null && state != city) parts.add(state);

      if (parts.isEmpty) return '';
      final address = _uniqueParts(parts).join(', ');
      debugPrint('Photon: $address');
      return address;
    } on TimeoutException {
      debugPrint('Photon timeout');
    } catch (e) {
      debugPrint('Photon error: $e');
    }
    return '';
  }

  // ============================================================
  // PROVIDER 3: Nominatim
  // ============================================================

  static Future<String> _fetchFromNominatim(String latStr, String lonStr) async {
    final wait = 1000 -
        DateTime.now()
            .difference(_lastNominatimRequest)
            .inMilliseconds;
    if (wait > 0) await Future.delayed(Duration(milliseconds: wait));

    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse'
          '?format=jsonv2&lat=$latStr&lon=$lonStr'
          '&zoom=18&addressdetails=1&accept-language=id',
        );
        final res = await _client.get(
          uri,
          headers: {
            'User-Agent': 'TermulLog/1.0',
            'Accept-Language': 'id,en;q=0.8',
          },
        ).timeout(const Duration(seconds: 5));

        _lastNominatimRequest = DateTime.now();

        if (res.statusCode == 429) {
          debugPrint('Nominatim rate limited, retrying...');
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }

        if (res.statusCode != 200) return '';

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>?;
        if (addr == null) return '';

        final road     = _safeStr(addr['road'])
                      ?? _safeStr(addr['pedestrian'])
                      ?? _safeStr(addr['footway'])
                      ?? _safeStr(addr['path']);
        final housenum = _safeStr(addr['house_number']);
        final suburb   = _safeStr(addr['suburb'])
                      ?? _safeStr(addr['neighbourhood'])
                      ?? _safeStr(addr['village'])
                      ?? _safeStr(addr['hamlet']);
        final district = _safeStr(addr['city_district'])
                      ?? _safeStr(addr['district'])
                      ?? _safeStr(addr['subdistrict']);
        final city     = _safeStr(addr['city'])
                      ?? _safeStr(addr['town'])
                      ?? _safeStr(addr['municipality'])
                      ?? _safeStr(addr['county']);

        final parts = <String>[];
        if (road != null) {
          parts.add(housenum != null ? '$road No.$housenum' : road);
        }
        if (suburb != null)   parts.add(suburb);
        if (district != null && district != suburb) parts.add(district);
        if (city != null)     parts.add(city);

        if (parts.isNotEmpty) {
          final address = _uniqueParts(parts).join(', ');
          debugPrint('Nominatim: $address');
          return address;
        }

        final display = data['display_name'] as String?;
        if (display != null && display.isNotEmpty) {
          final cleaned = _stripPlusCode(
              display.split(',').take(4).join(', '));
          debugPrint('Nominatim display_name: $cleaned');
          return cleaned;
        }

        return '';
      } on TimeoutException {
        debugPrint('Nominatim timeout');
        return '';
      } catch (e) {
        debugPrint('Nominatim error: $e');
        return '';
      }
    }
    return '';
  }

  // ============================================================
  // FETCH WEATHER (dengan cache 10 menit)
  // ============================================================

  static Future<String> _fetchWeatherWithCache(double lat, double lon) async {
    final key = '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';

    final cached = _weatherCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.timestamp).inMinutes < 10) {
      return cached.weather;
    }

    final result = await _fetchWeatherFromApi(lat.toStringAsFixed(6), lon.toStringAsFixed(6));
    if (result.isNotEmpty) {
      _trimWeatherCache();
      _weatherCache[key] = _WeatherCacheEntry(
        weather: result,
        timestamp: DateTime.now(),
      );
    }
    return result;
  }

  static Future<String> _fetchWeatherFromApi(String latStr, String lonStr) async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$latStr&longitude=$lonStr'
        '&current=temperature_2m,weather_code&timezone=auto',
      );
      final res =
          await _client.get(uri).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final current =
            data['current'] as Map<String, dynamic>?;
        if (current != null) {
          final temp =
              (current['temperature_2m'] as num?)?.toStringAsFixed(0) ??
                  '--';
          final code =
              (current['weather_code'] as num?)?.toInt() ?? 0;
          final weather = '${_wmoDesc(code)} $temp°C';
          debugPrint('Weather: $weather');
          return weather;
        }
      }
    } on TimeoutException {
      debugPrint('Weather timeout');
    } catch (e) {
      debugPrint('Weather error: $e');
    }
    return '';
  }

  static String _wmoDesc(int c) {
    if (c == 0)  return '☀️ Cerah';
    if (c <= 3)  return '⛅ Berawan';
    if (c <= 49) return '🌫️ Berkabut';
    if (c <= 59) return '🌦️ Gerimis';
    if (c <= 67) return '🌧️ Hujan';
    if (c <= 77) return '❄️ Salju';
    if (c <= 82) return '🌧️ Hujan Lebat';
    if (c <= 86) return '🌨️ Badai Salju';
    if (c <= 94) return '🌨️ Hujan Es';
    if (c <= 95) return '⚡ Badai Petir';
    if (c <= 99) return '⛈️ Badai Petir Hujan Es';
    return '🌡️';
  }

  // ============================================================
  // MINI MAP — dengan fallback ganda & LRU sejati
  // ============================================================

  static Future<Uint8List?> fetchOSMStaticMap(double lat, double lon) async {
    final cacheKey =
        '${lat.toStringAsFixed(3)},${lon.toStringAsFixed(3)}';
    if (_mapCache.containsKey(cacheKey)) {
      final bytes = _mapCache.remove(cacheKey)!;
      _mapCache[cacheKey] = bytes;
      return bytes;
    }

    final urls = <String>[
      'https://staticmap.openstreetmap.de/staticmap.php'
          '?center=$lat,$lon&zoom=16&size=400x250'
          '&maptype=mapnik&markers=$lat,$lon,ol-marker',
    ];

    if (_locationIqApiKey.isNotEmpty &&
        _locationIqApiKey != 'pk.YOUR_API_KEY_HERE') {
      urls.add(
        'https://maps.locationiq.com/v3/staticmap'
        '?key=$_locationIqApiKey'
        '&center=$lat,$lon'
        '&zoom=16'
        '&size=400x250'
        '&markers=icon:large-red-cutout|$lat,$lon',
      );
    }

    for (final urlString in urls) {
      try {
        final response = await _client
            .get(Uri.parse(urlString))
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          final bytes = Uint8List.fromList(response.bodyBytes);
          final isPng = bytes.length > 4 &&
              bytes[0] == 0x89 &&
              bytes[1] == 0x50 &&
              bytes[2] == 0x4E &&
              bytes[3] == 0x47;
          if (isPng) {
            while (_mapCache.length >= _mapCacheMaxSize) {
              _mapCache.remove(_mapCache.keys.first);
            }
            _mapCache[cacheKey] = bytes;
            return bytes;
          }
        }
      } catch (e) {
        debugPrint('Mini map provider error: $e');
      }
    }
    return null;
  }

  static Future<Uint8List?> fetchMapWithRetry(double lat, double lon,
      {int maxRetries = 2}) async {
    for (int i = 0; i < maxRetries; i++) {
      final result = await fetchOSMStaticMap(lat, lon);
      if (result != null) return result;
      if (i < maxRetries - 1) {
        await Future.delayed(Duration(seconds: i + 1));
      }
    }
    return await _fetchOsmTileBytes(lat, lon, zoom: 15);
  }

  static Future<Uint8List?> _fetchOsmTileBytes(double lat, double lng,
      {int zoom = 15}) async {
    try {
      final n = pow(2, zoom).toInt();
      final tileX =
          ((lng + 180) / 360 * n).toInt().clamp(0, n - 1);
      final latRad = lat * pi / 180;
      final tileY =
          ((1 - log(tan(latRad) + 1 / cos(latRad)) / pi) / 2 * n)
              .toInt()
              .clamp(0, n - 1);
      const subdomains = ['a', 'b', 'c'];
      final sub = subdomains[tileX % 3];
      final url =
          'https://$sub.tile.openstreetmap.org/$zoom/$tileX/$tileY.png';
      final response = await _client.get(
        Uri.parse(url),
        headers: {'User-Agent': 'TermulLog/1.0'},
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final bytes = Uint8List.fromList(response.bodyBytes);
        if (bytes.length > 4 &&
            bytes[0] == 0x89 &&
            bytes[1] == 0x50) {
          return bytes;
        }
      }
    } catch (e) {
      debugPrint('OSM tile error: $e');
    }
    return null;
  }

  // ============================================================
  // Helpers
  // ============================================================

  static String? _safeStr(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}
