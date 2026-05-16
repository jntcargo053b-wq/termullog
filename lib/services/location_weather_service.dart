// lib/services/location_weather_service.dart
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

class _CacheEntry {
  final String address;
  final double lat;
  final double lon;
  final DateTime timestamp;
  double distanceMeters = 0;

  _CacheEntry({
    required this.address,
    required this.lat,
    required this.lon,
    required this.timestamp,
  });
}

// ============================================================
// Main Service
// ============================================================

class LocationWeatherService {
  LocationWeatherService._();

  static final http.Client _client = http.Client();

  static final Map<String, _CacheEntry> _addressCache = {};
  static const int _cacheMaxSize = 100;
  static const double _cacheRadiusMeters = 50.0;

  static final Map<String, Uint8List> _mapCache = {};
  static const int _mapCacheMaxSize = 50;

  static DateTime _lastNominatimRequest =
      DateTime.now().subtract(const Duration(seconds: 2));

  static final _progressController =
      StreamController<String>.broadcast();
  static Stream<String> get onProgress => _progressController.stream;

  static void _emitProgress(String message) =>
      _progressController.add(message);

  static void close() {
    _client.close();
    _progressController.close();
  }

  // ============================================================
  // ★ PLUS CODE DETECTION
  //
  // Plus Code (Open Location Code) dikenali dengan pola:
  //   - 4–8 karakter alfanumerik UPPERCASE tanpa I,O,U,L,S,Z
  //   - diikuti tanda "+"
  //   - diikuti 2–3 karakter
  // Contoh: "2MC+QV", "8P3R+F8", "WXRG+39 Malang"
  // ============================================================

  static final RegExp _plusCodePattern = RegExp(
    r'(?:^|[\s,])([23456789CFGHJMPQRVWX]{4,8}\+[23456789CFGHJMPQRVWX]{2,3})(?:[\s,]|$)',
    caseSensitive: false,
  );

  /// Kembalikan true jika [s] adalah Plus Code atau diawali Plus Code.
  static bool _isPlusCode(String? s) {
    if (s == null || s.isEmpty) return false;
    return _plusCodePattern.hasMatch(s.trim());
  }

  /// Buang segmen Plus Code dari dalam string alamat.
  /// Contoh: "2MC+QV, Jl. Raya, Malang" → "Jl. Raya, Malang"
  static String _stripPlusCode(String address) {
    // Pisah per koma, buang segmen yang merupakan Plus Code murni
    final parts = address
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && !_isPlusCode(p))
        .toList();
    return parts.isEmpty ? address : parts.join(', ');
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

    // Cek cache radius 50 meter
    final cached = _findNearbyCache(lat, lon);
    if (cached != null) {
      _emitProgress(
          '📦 Cache lokasi terdekat (${cached.distanceMeters.toStringAsFixed(0)}m)');
      debugPrint(
          'Address from cache: ${cached.address} (${cached.distanceMeters.toStringAsFixed(0)}m)');
      final weather = await _fetchWeather(latStr, lonStr);
      return LocationWeatherResult(
        address: cached.address,
        weather: weather,
        rawAddress: cached.address,
      );
    }

    // Parallel: alamat + cuaca
    final results = await Future.wait([
      _fetchAddressFast(lat, lon, latStr, lonStr),
      _fetchWeather(latStr, lonStr),
    ]);

    String finalAddress = results[0];
    final String weather = results[1];
    final String rawAddress = finalAddress;

    if (finalAddress.isEmpty) {
      final dmsLat = _formatDMS(lat, true);
      final dmsLon = _formatDMS(lon, false);
      finalAddress = 'GPS: $dmsLat, $dmsLon';
      _emitProgress('🌐 Menggunakan koordinat GPS');
    } else {
      if (_addressCache.length >= _cacheMaxSize) {
        _addressCache.remove(_addressCache.keys.first);
      }
      _addressCache[GeoHash.encode(lat, lon)] = _CacheEntry(
        address: finalAddress,
        lat: lat,
        lon: lon,
        timestamp: DateTime.now(),
      );
      _emitProgress('✅ Alamat ditemukan');
    }

    return LocationWeatherResult(
        address: finalAddress, weather: weather, rawAddress: rawAddress);
  }

  // ============================================================
  // Cache Helper
  // ============================================================

  static _CacheEntry? _findNearbyCache(double lat, double lon) {
    for (final entry in _addressCache.values) {
      final distance =
          GeoHash.distance(lat, lon, entry.lat, entry.lon);
      if (distance <= _cacheRadiusMeters) {
        entry.distanceMeters = distance;
        return entry;
      }
    }
    return null;
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
  // FAST ADDRESS FETCH
  // ============================================================

  static Future<String> _fetchAddressFast(
      double lat, double lon, String latStr, String lonStr) async {
    // Provider 1: Photon (biasanya < 1 detik)
    final photon = await _fetchFromPhoton(latStr, lonStr);
    if (photon.isNotEmpty) return photon;

    // Provider 2: Geocoding package (Google) — dengan filter Plus Code
    final geocoding = await _fetchFromGeocoding(lat, lon);
    if (geocoding.isNotEmpty) return geocoding;

    // Provider 3: Nominatim fallback
    final nominatim = await _fetchFromNominatim(latStr, lonStr);
    if (nominatim.isNotEmpty) return nominatim;

    return '';
  }

  // ============================================================
  // PROVIDER 1: Photon (tercepat)
  // ============================================================

  static Future<String> _fetchFromPhoton(
      String latStr, String lonStr) async {
    try {
      final uri = Uri.parse(
          'https://photon.komoot.io/reverse?lat=$latStr&lon=$lonStr');
      final res =
          await _client.get(uri).timeout(const Duration(seconds: 3));

      if (res.statusCode != 200) return '';

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) return '';

      final props =
          features[0]['properties'] as Map<String, dynamic>? ?? {};

      final name       = _safeStr(props['name']);
      final housenumber= _safeStr(props['housenumber']);
      final street     = _safeStr(props['street']);
      final district   = _safeStr(props['district']);
      final city       = _safeStr(props['city']);
      final state      = _safeStr(props['state']);

      final parts = <String>[];

      // Nama POI (warung, kantor, dsb) hanya jika berbeda dari jalan
      if (name != null && name != street) parts.add(name);

      // Nama jalan + nomor
      if (street != null) {
        parts.add(housenumber != null
            ? '$street No.$housenumber'
            : street);
      }

      if (district != null) parts.add(district);
      if (city != null)     parts.add(city);
      if (state != null && state != city) parts.add(state);

      if (parts.isEmpty) return '';

      // Photon tidak mengembalikan Plus Code, tapi tetap saring
      final address = _stripPlusCode(parts.join(', '));
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
  // PROVIDER 2: Geocoding Package (Google Maps)
  // ★ FIX UTAMA: filter Plus Code dari p.street
  // ============================================================

  static Future<String> _fetchFromGeocoding(
      double lat, double lon) async {
    try {
      final placemarks =
          await placemarkFromCoordinates(lat, lon)
              .timeout(const Duration(seconds: 4));

      if (placemarks.isEmpty) return '';

      // Cari placemark pertama yang p.street-nya BUKAN Plus Code
      Placemark? best;
      for (final p in placemarks) {
        if (!_isPlusCode(p.street)) {
          best = p;
          break;
        }
      }
      // Jika semua street adalah Plus Code, pakai yang pertama
      // tapi abaikan field street-nya
      final p = best ?? placemarks.first;

      final parts = <String>[];

      // ★ Cek street: jika Plus Code → skip, coba thoroughfare
      final street = (!_isPlusCode(p.street) && p.street?.isNotEmpty == true)
          ? p.street
          : (!_isPlusCode(p.thoroughfare) && p.thoroughfare?.isNotEmpty == true)
              ? p.thoroughfare
              : null;
      if (street != null) parts.add(street);

      // subLocality = kelurahan/desa
      if (p.subLocality?.isNotEmpty == true &&
          !_isPlusCode(p.subLocality)) {
        parts.add(p.subLocality!);
      }

      // subAdministrativeArea = kecamatan
      if (p.subAdministrativeArea?.isNotEmpty == true &&
          !_isPlusCode(p.subAdministrativeArea)) {
        parts.add(p.subAdministrativeArea!);
      }

      // locality = kota/kabupaten
      if (p.locality?.isNotEmpty == true &&
          !_isPlusCode(p.locality)) {
        parts.add(p.locality!);
      }

      // administrativeArea = provinsi (hanya jika berbeda dari locality)
      if (p.administrativeArea?.isNotEmpty == true &&
          p.administrativeArea != p.locality &&
          !_isPlusCode(p.administrativeArea)) {
        parts.add(p.administrativeArea!);
      }

      if (parts.isEmpty) return '';

      final address = parts.join(', ');
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
  // PROVIDER 3: Nominatim
  // ============================================================

  static Future<String> _fetchFromNominatim(
      String latStr, String lonStr) async {
    // Rate limit: min 1 detik antar request
    final wait = 1000 -
        DateTime.now()
            .difference(_lastNominatimRequest)
            .inMilliseconds;
    if (wait > 0) await Future.delayed(Duration(milliseconds: wait));

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
        final address = parts.join(', ');
        debugPrint('Nominatim: $address');
        return address;
      }

      // display_name sebagai last resort — strip Plus Code
      final display = data['display_name'] as String?;
      if (display != null && display.isNotEmpty) {
        final cleaned = _stripPlusCode(
            display.split(',').take(4).join(', '));
        debugPrint('Nominatim display_name: $cleaned');
        return cleaned;
      }
    } on TimeoutException {
      debugPrint('Nominatim timeout');
    } catch (e) {
      debugPrint('Nominatim error: $e');
    }
    return '';
  }

  // ============================================================
  // FETCH WEATHER (Open-Meteo, gratis)
  // ============================================================

  static Future<String> _fetchWeather(
      String latStr, String lonStr) async {
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
          return '${_wmoDesc(code)} $temp°C';
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
    if (c == 95) return '⚡ Badai Petir';
    return '🌡️';
  }

  // ============================================================
  // MINI MAP
  // ============================================================

  static Future<Uint8List?> fetchOSMStaticMap(
      double lat, double lon) async {
    final cacheKey =
        '${lat.toStringAsFixed(3)},${lon.toStringAsFixed(3)}';
    if (_mapCache.containsKey(cacheKey)) return _mapCache[cacheKey];

    try {
      final url = Uri.parse(
        'https://staticmap.openstreetmap.de/staticmap.php'
        '?center=$lat,$lon&zoom=16&size=400x250'
        '&maptype=mapnik&markers=$lat,$lon,ol-marker',
      );
      final response =
          await _client.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final bytes = Uint8List.fromList(response.bodyBytes);
        final isPng = bytes.length > 4 &&
            bytes[0] == 0x89 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x4E &&
            bytes[3] == 0x47;
        if (isPng) {
          if (_mapCache.length >= _mapCacheMaxSize) {
            _mapCache.remove(_mapCache.keys.first);
          }
          _mapCache[cacheKey] = bytes;
          return bytes;
        }
      }
    } catch (e) {
      debugPrint('OSM Static Map error: $e');
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
