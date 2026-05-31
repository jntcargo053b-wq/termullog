// lib/services/location_weather_service.dart
// FINAL: cache dengan cleanup expired entries, fallback Nominatim -> Photon -> Android Geocoder
import 'dart:collection';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class CachedAddress {
  final double lat;
  final double lon;
  final String address;
  final DateTime timestamp;
  CachedAddress({
    required this.lat,
    required this.lon,
    required this.address,
    required this.timestamp,
  });
}

class LocationWeatherService {
  LocationWeatherService._();

  static http.Client _client = http.Client();
  static bool _isClosed = false;

  // Exact coordinate cache (5 desimal ~1.1 meter)
  static final Map<String, String> _addressCache = {};
  static const int _maxAddressCacheSize = 100;
  static final List<String> _addressCacheOrder = [];

  // Nearby cache (radius based, cari jarak terdekat, expiry 2 menit)
  static const double _addressCacheRadiusMeters = 8.0;
  static const Duration _addressCacheDuration = Duration(minutes: 2);
  static final Map<String, CachedAddress> _nearbyCache = {};
  static const int _maxNearbyCacheSize = 50;

  // Weather cache per location (10 menit)
  static final Map<String, _WeatherCacheEntry> _weatherCache = {};
  static const Duration _weatherCacheDuration = Duration(minutes: 10);

  static bool _disableCache = false; // false untuk production

  static String _cacheKey(double lat, double lon) {
    return '${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';
  }

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

  // 🔥 Nearby cache dengan cleanup entry expired
  static String? _findNearbyAddressCache(double lat, double lon) {
    final now = DateTime.now();
    final expiredKeys = <String>[];
    CachedAddress? best;
    double bestDistance = double.infinity;

    for (final entry in _nearbyCache.entries) {
      if (now.difference(entry.value.timestamp) > _addressCacheDuration) {
        expiredKeys.add(entry.key);
        continue;
      }
      final distance = Geolocator.distanceBetween(lat, lon, entry.value.lat, entry.value.lon);
      if (distance <= _addressCacheRadiusMeters && distance < bestDistance) {
        bestDistance = distance;
        best = entry.value;
      }
    }

    // Hapus entry expired setelah iterasi (hindari ConcurrentModificationError)
    for (final key in expiredKeys) {
      _nearbyCache.remove(key);
    }

    if (best != null) {
      if (kDebugMode) {
        debugPrint('Geocode: nearby cache best hit (${bestDistance.toStringAsFixed(1)}m) → ${best.address}');
      }
      return best.address;
    }
    return null;
  }

  static void _addToNearbyCache(double lat, double lon, String address) {
    // Batasi ukuran cache
    if (_nearbyCache.length >= _maxNearbyCacheSize) {
      // Hapus yang paling lama
      final oldestKey = _nearbyCache.keys.first;
      _nearbyCache.remove(oldestKey);
    }
    final key = '${lat.toStringAsFixed(6)},${lon.toStringAsFixed(6)}';
    _nearbyCache[key] = CachedAddress(
      lat: lat,
      lon: lon,
      address: address,
      timestamp: DateTime.now(),
    );
  }

  static Future<LocationWeatherResult> fetchFromPosition(Position position) async {
    final lat = position.latitude;
    final lon = position.longitude;
    final latStr = lat.toStringAsFixed(7);
    final lonStr = lon.toStringAsFixed(7);

    // Weather cache (berdasarkan lokasi, key 5 desimal)
    final weatherKey = _cacheKey(lat, lon);
    String weather;
    final now = DateTime.now();
    final cachedWeather = _weatherCache[weatherKey];
    if (cachedWeather != null && now.isBefore(cachedWeather.expiry)) {
      weather = cachedWeather.weather;
      if (kDebugMode) debugPrint('Weather: cache hit for $weatherKey → $weather');
    } else {
      weather = await _fetchWeatherFromApi(latStr, lonStr);
      _weatherCache[weatherKey] = _WeatherCacheEntry(weather, now.add(_weatherCacheDuration));
    }

    String address;
    if (_disableCache) {
      address = await _fetchAddressWithFallback(lat, lon, latStr, lonStr);
      if (kDebugMode) debugPrint('Geocode: cache BYPASSED');
    } else {
      // Cek nearby cache dulu
      final nearby = _findNearbyAddressCache(lat, lon);
      if (nearby != null) {
        address = nearby;
        return LocationWeatherResult(address: address, weather: weather, rawAddress: address);
      }

      // Cek exact cache (5 desimal)
      final cacheKey = _cacheKey(lat, lon);
      final cachedAddress = _addressCache[cacheKey];
      if (cachedAddress != null) {
        address = cachedAddress;
        _addressCacheOrder.remove(cacheKey);
        _addressCacheOrder.add(cacheKey);
        if (kDebugMode) debugPrint('Geocode: exact cache hit (5 desimal) → $address');
      } else {
        address = await _fetchAddressWithFallback(lat, lon, latStr, lonStr);
        if (address.isNotEmpty) {
          // Batasi ukuran exact cache (LRU)
          while (_addressCacheOrder.length >= _maxAddressCacheSize) {
            final oldest = _addressCacheOrder.removeAt(0);
            _addressCache.remove(oldest);
          }
          _addressCache[cacheKey] = address;
          _addressCacheOrder.add(cacheKey);
          await _saveAddressToPrefs(cacheKey, address);
          _addToNearbyCache(lat, lon, address);
        }
      }
    }

    if (address.isEmpty) {
      final dmsLat = _formatDMS(lat, true);
      final dmsLon = _formatDMS(lon, false);
      address = 'GPS: $dmsLat, $dmsLon';
    }

    return LocationWeatherResult(
      address: address,
      weather: weather,
      rawAddress: address,
    );
  }

  static Future<void> _saveAddressToPrefs(String key, String address) async {
    final prefs = await SharedPreferences.getInstance();
    final map = prefs.getString('address_cache') ?? '';
    Map<String, String> cacheMap = {};
    if (map.isNotEmpty) {
      try {
        cacheMap = Map<String, String>.from(jsonDecode(map));
      } catch (_) {}
    }
    cacheMap[key] = address;
    if (cacheMap.length > 20) {
      final keys = cacheMap.keys.toList();
      cacheMap.remove(keys.first);
    }
    await prefs.setString('address_cache', jsonEncode(cacheMap));
  }

  static Future<void> loadPersistedCache() async {
    final prefs = await SharedPreferences.getInstance();
    final map = prefs.getString('address_cache');
    if (map != null && map.isNotEmpty) {
      try {
        final cacheMap = Map<String, String>.from(jsonDecode(map));
        _addressCache.addAll(cacheMap);
        _addressCacheOrder.addAll(cacheMap.keys);
        if (kDebugMode) debugPrint('Loaded ${_addressCache.length} cached addresses');
      } catch (_) {}
    }
  }

  // ==================== FALLBACK CHAIN (Nominatim -> Photon -> Android Geocoder) ====================
  static Future<String> _fetchAddressWithFallback(
      double lat, double lon, String latStr, String lonStr) async {
    if (_isClosed) return '';

    // 1. Nominatim (paling presisi)
    try {
      final nominatim = await _fetchFromNominatim(latStr, lonStr);
      if (nominatim.isNotEmpty) {
        if (kDebugMode) debugPrint('Geocode: Nominatim OK → $nominatim');
        return nominatim;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Geocode: Nominatim error → $e');
    }

    // 2. Photon
    try {
      final photon = await _fetchFromPhoton(latStr, lonStr);
      if (photon.isNotEmpty) {
        if (kDebugMode) debugPrint('Geocode: Photon OK → $photon');
        return photon;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Geocode: Photon error → $e');
    }

    // 3. Android Geocoder (last resort)
    try {
      final android = await _fetchFromAndroidGeocoder(lat, lon);
      if (android.isNotEmpty && !android.contains('Unnamed Road')) {
        if (kDebugMode) debugPrint('Geocode: Android Geocoder OK → $android');
        return android;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Geocode: Android Geocoder error → $e');
    }

    return '';
  }

  // ==================== PROVIDER IMPLEMENTATIONS ====================
  static DateTime _lastNominatimRequest = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _nominatimMinInterval = Duration(seconds: 1);

  static Future<String> _fetchFromNominatim(String latStr, String lonStr) async {
    if (_isClosed) return '';
    final now = DateTime.now();
    final timeSinceLast = now.difference(_lastNominatimRequest);
    if (timeSinceLast < _nominatimMinInterval) {
      await Future.delayed(_nominatimMinInterval - timeSinceLast);
    }
    _lastNominatimRequest = DateTime.now();

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
            'User-Agent': 'TermulLog/1.0 (termullog@example.com)',
            'Accept-Language': 'id,en;q=0.8',
          },
        ).timeout(const Duration(seconds: 6));
        if (res.statusCode == 429) {
          if (attempt == 0) {
            await Future.delayed(const Duration(seconds: 2));
            continue;
          } else {
            return '';
          }
        }
        if (res.statusCode != 200) return '';

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>?;
        if (addr == null) return '';

        final road = _safeStr(addr['road'])
            ?? _safeStr(addr['residential'])
            ?? _safeStr(addr['pedestrian'])
            ?? _safeStr(addr['footway'])
            ?? _safeStr(addr['path'])
            ?? _safeStr(addr['service'])
            ?? _safeStr(addr['track']);
        final housenum = _safeStr(addr['house_number']);
        final suburb = _safeStr(addr['suburb'])
            ?? _safeStr(addr['neighbourhood'])
            ?? _safeStr(addr['quarter']);
        final village = _safeStr(addr['village'])
            ?? _safeStr(addr['hamlet'])
            ?? _safeStr(addr['isolated_dwelling']);
        final subdistrict = _safeStr(addr['subdistrict'])
            ?? _safeStr(addr['city_district'])
            ?? _safeStr(addr['district']);
        final city = _safeStr(addr['city'])
            ?? _safeStr(addr['town'])
            ?? _safeStr(addr['municipality'])
            ?? _safeStr(addr['county']);

        final parts = <String>[];
        if (road != null) parts.add(housenum != null ? '$road No.$housenum' : road);
        if (suburb != null) parts.add(suburb);
        if (village != null && village != suburb) parts.add(village);
        if (subdistrict != null && subdistrict != suburb && subdistrict != village) {
          parts.add(subdistrict);
        }
        if (city != null) parts.add(city);

        if (parts.isNotEmpty) return _uniqueParts(parts).join(', ');

        final display = data['display_name'] as String?;
        if (display != null && display.isNotEmpty) {
          return _stripPlusCode(display.split(',').take(4).join(', '));
        }
        return '';
      } catch (e) {
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }
        return '';
      }
    }
    return '';
  }

  static Future<String> _fetchFromPhoton(String latStr, String lonStr) async {
    if (_isClosed) return '';
    try {
      final uri = Uri.parse('https://photon.komoot.io/reverse?lat=$latStr&lon=$lonStr&lang=id');
      final res = await _client.get(
        uri,
        headers: {'User-Agent': 'TermulLog/1.0 (termullog@example.com)'},
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return '';
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) return '';
      final props = features[0]['properties'] as Map<String, dynamic>? ?? {};
      final name = _safeStr(props['name']);
      final housenumber = _safeStr(props['housenumber']);
      final street = _safeStr(props['street']);
      final district = _safeStr(props['district']);
      final city = _safeStr(props['city']);
      final state = _safeStr(props['state']);
      final parts = <String>[];
      if (name != null && name != street) parts.add(name);
      if (street != null) parts.add(housenumber != null ? '$street No.$housenumber' : street);
      if (district != null) parts.add(district);
      if (city != null) parts.add(city);
      if (state != null && state != city) parts.add(state);
      return parts.isEmpty ? '' : _uniqueParts(parts).join(', ');
    } catch (e) {
      return '';
    }
  }

  static Future<String> _fetchFromAndroidGeocoder(double lat, double lon) async {
    if (_isClosed) return '';
    try {
      final placemarks = await placemarkFromCoordinates(lat, lon, localeIdentifier: 'id_ID')
          .timeout(const Duration(seconds: 5));
      if (placemarks.isEmpty) return '';
      final p = placemarks.first;
      final parts = <String>[];
      if (p.thoroughfare?.isNotEmpty == true && !_isPlusCode(p.thoroughfare)) {
        parts.add(p.thoroughfare!);
      } else if (p.street?.isNotEmpty == true && !_isPlusCode(p.street)) {
        parts.add(p.street!);
      }
      if (p.subLocality?.isNotEmpty == true && !_isPlusCode(p.subLocality)) {
        parts.add(p.subLocality!);
      }
      if (p.locality?.isNotEmpty == true && !_isPlusCode(p.locality)) {
        parts.add(p.locality!);
      }
      if (p.administrativeArea?.isNotEmpty == true && !_isPlusCode(p.administrativeArea)) {
        parts.add(p.administrativeArea!);
      }
      return parts.isEmpty ? '' : _uniqueParts(parts).join(', ');
    } catch (e) {
      return '';
    }
  }

  static Future<String> _fetchWeatherFromApi(String latStr, String lonStr) async {
    if (_isClosed) return '🌡️ --°C';
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$latStr&longitude=$lonStr'
        '&current=temperature_2m,weather_code&timezone=auto',
      );
      final res = await _client.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final current = data['current'] as Map<String, dynamic>?;
        if (current != null) {
          final temp = (current['temperature_2m'] as num?)?.toStringAsFixed(0) ?? '--';
          final code = (current['weather_code'] as num?)?.toInt() ?? 0;
          return '${_wmoDesc(code)} $temp°C';
        }
      }
    } catch (e) {}
    return '🌡️ --°C';
  }

  static String _wmoDesc(int c) {
    if (c == 0) return '☀️ Cerah';
    if (c <= 3) return '⛅ Berawan';
    if (c <= 29) return '🌫️ Kabut/Debu';
    if (c <= 49) return '🌫️ Berkabut';
    if (c <= 57) return '🌦️ Gerimis';
    if (c <= 67) return '🌧️ Hujan';
    if (c <= 77) return '❄️ Salju';
    if (c <= 82) return '🌧️ Hujan Lebat';
    if (c <= 86) return '🌨️ Badai Salju';
    if (c <= 99) return '⚡ Badai Petir';
    return '🌡️';
  }

  static String _formatDMS(double coord, bool isLat) {
    final degrees = coord.abs().floor();
    final minutes = ((coord.abs() - degrees) * 60).floor();
    final seconds = ((coord.abs() - degrees - minutes / 60) * 3600).toStringAsFixed(1);
    final direction = isLat ? (coord >= 0 ? 'N' : 'S') : (coord >= 0 ? 'E' : 'W');
    return "${degrees}°${minutes}'${seconds}\" $direction";
  }

  static String? _safeStr(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}

class _WeatherCacheEntry {
  final String weather;
  final DateTime expiry;
  _WeatherCacheEntry(this.weather, this.expiry);
}
