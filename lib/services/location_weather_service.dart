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
    final latRounded = (lat * pow(10, _precision)).round() / pow(10, _precision);
    final lonRounded = (lon * pow(10, _precision)).round() / pow(10, _precision);
    return '${latRounded.toStringAsFixed(_precision)},${lonRounded.toStringAsFixed(_precision)}';
  }
  
  static double distance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat/2) * sin(dLat/2) +
              cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
              sin(dLon/2) * sin(dLon/2);
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
  
  static DateTime _lastNominatimRequest = DateTime.now().subtract(const Duration(seconds: 2));
  
  static final _progressController = StreamController<String>.broadcast();
  static Stream<String> get onProgress => _progressController.stream;
  
  static void _emitProgress(String message) {
    _progressController.add(message);
  }
  
  static void close() {
    _client.close();
    _progressController.close();
  }

  // ============================================================
  // Main Method - FETCH ADDRESS & WEATHER
  // ============================================================

  static Future<LocationWeatherResult> fetchFromPosition(Position position) async {
    final lat = position.latitude;
    final lon = position.longitude;
    final latStr = lat.toStringAsFixed(6);
    final lonStr = lon.toStringAsFixed(6);
    
    _emitProgress('📍 Mencari lokasi...');
    
    // Cek cache dengan radius 50 meter
    final cached = _findNearbyCache(lat, lon);
    
    if (cached != null) {
      _emitProgress('📦 Menggunakan cache lokasi terdekat (${cached.distanceMeters.toStringAsFixed(0)}m)');
      debugPrint('Address from nearby cache: ${cached.address} (${cached.distanceMeters.toStringAsFixed(0)}m away)');
      
      // Fetch weather parallel
      final weather = await _fetchWeather(latStr, lonStr);
      return LocationWeatherResult(
        address: cached.address,
        weather: weather,
        rawAddress: cached.address,
      );
    }

    // ─── PARALLEL REQUEST: Address + Weather ──────────────────────────────
    final results = await Future.wait([
      _fetchAddressFast(lat, lon, latStr, lonStr),
      _fetchWeather(latStr, lonStr),
    ]);

    String finalAddress = results[0];
    String weather = results[1];
    String rawAddress = finalAddress;

    // Ultimate fallback: format DMS jika alamat kosong
    if (finalAddress.isEmpty) {
      final dmsLat = _formatDMS(lat, true);
      final dmsLon = _formatDMS(lon, false);
      finalAddress = '📍 $dmsLat, $dmsLon';
      rawAddress = finalAddress;
      _emitProgress('🌐 Menggunakan koordinat DMS');
    } else {
      // Simpan ke cache
      if (_addressCache.length >= _cacheMaxSize) {
        _addressCache.remove(_addressCache.keys.first);
      }
      final cacheKey = GeoHash.encode(lat, lon);
      _addressCache[cacheKey] = _CacheEntry(
        address: finalAddress,
        lat: lat,
        lon: lon,
        timestamp: DateTime.now(),
      );
      _emitProgress('✅ Alamat ditemukan');
    }

    return LocationWeatherResult(address: finalAddress, weather: weather, rawAddress: rawAddress);
  }

  // ============================================================
  // Cache Helper
  // ============================================================

  static _CacheEntry? _findNearbyCache(double lat, double lon) {
    for (var entry in _addressCache.values) {
      final distance = GeoHash.distance(lat, lon, entry.lat, entry.lon);
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
    final seconds = ((coord.abs() - degrees - minutes / 60) * 3600).toStringAsFixed(1);
    final direction = isLat 
        ? (coord >= 0 ? 'N' : 'S')
        : (coord >= 0 ? 'E' : 'W');
    return '${degrees}°${minutes}\'${seconds}" $direction';
  }

  // ============================================================
  // FAST ADDRESS FETCH (Provider tercepat lebih dulu)
  // ============================================================

  static Future<String> _fetchAddressFast(
    double lat, double lon, String latStr, String lonStr
  ) async {
    String address = '';

    // Provider 1: Photon (biasanya paling cepat, < 1 detik)
    address = await _fetchFromPhoton(latStr, lonStr);
    if (address.isNotEmpty) return address;

    // Provider 2: Geocoding package (lokal, cepat jika data tersedia)
    address = await _fetchFromGeocoding(lat, lon);
    if (address.isNotEmpty) return address;

    // Provider 3: Nominatim (paling lengkap, tapi lebih lambat)
    address = await _fetchFromNominatim(latStr, lonStr);
    if (address.isNotEmpty) return address;

    return address;
  }

  // ============================================================
  // PROVIDER 1: Photon (tercepat)
  // ============================================================

  static Future<String> _fetchFromPhoton(String latStr, String lonStr) async {
    try {
      final uri = Uri.parse(
        'https://photon.komoot.io/reverse?lat=$latStr&lon=$lonStr'
      );
      final res = await _client.get(uri).timeout(const Duration(seconds: 3));
      
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final features = data['features'] as List?;
        
        if (features != null && features.isNotEmpty) {
          final properties = features[0]['properties'] as Map<String, dynamic>?;
          if (properties != null) {
            final parts = <String>[];
            
            final street = properties['street'] as String?;
            final city = properties['city'] as String?;
            final state = properties['state'] as String?;
            final postcode = properties['postcode'] as String?;
            
            if (street?.isNotEmpty == true) parts.add(street!);
            if (city?.isNotEmpty == true) parts.add(city!);
            if (state?.isNotEmpty == true) parts.add(state!);
            if (postcode?.isNotEmpty == true) parts.add(postcode!);
            
            if (parts.isNotEmpty) {
              final address = parts.join(', ');
              debugPrint('Address from Photon: $address');
              return address;
            }
          }
        }
      }
    } on TimeoutException {
      debugPrint('Photon timeout');
    } catch (e) {
      debugPrint('Photon error: $e');
    }
    return '';
  }

  // ============================================================
  // PROVIDER 2: Geocoding Package
  // ============================================================

  static Future<String> _fetchFromGeocoding(double lat, double lon) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lon).timeout(
        const Duration(seconds: 3),
      );
      
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[];
        
        if (p.street?.isNotEmpty == true) parts.add(p.street!);
        if (p.subLocality?.isNotEmpty == true) parts.add(p.subLocality!);
        if (p.subAdministrativeArea?.isNotEmpty == true) parts.add(p.subAdministrativeArea!);
        if (p.locality?.isNotEmpty == true) parts.add(p.locality!);
        if (p.administrativeArea?.isNotEmpty == true && p.locality != p.administrativeArea) {
          parts.add(p.administrativeArea!);
        }
        if (p.postalCode?.isNotEmpty == true) parts.add(p.postalCode!);
        
        if (parts.isNotEmpty) {
          final address = parts.join(', ');
          debugPrint('Address from Geocoding: $address');
          return address;
        }
      }
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

  static Future<String> _fetchFromNominatim(String latStr, String lonStr) async {
    final now = DateTime.now();
    final timeSinceLastRequest = now.difference(_lastNominatimRequest);
    if (timeSinceLastRequest.inMilliseconds < 1000) {
      await Future.delayed(
        Duration(milliseconds: 1000 - timeSinceLastRequest.inMilliseconds));
    }
    
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json&lat=$latStr&lon=$lonStr&zoom=18&addressdetails=1'
        '&accept-language=id',
      );
      final res = await _client.get(
        uri,
        headers: {'User-Agent': 'TermulLog/1.0'},
      ).timeout(const Duration(seconds: 3));

      _lastNominatimRequest = DateTime.now();
      
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final addressObj = data['address'] as Map<String, dynamic>?;
        
        if (addressObj != null) {
          final parts = <String>[];
          final road = addressObj['road'] as String?;
          final suburb = (addressObj['suburb'] ?? addressObj['neighbourhood']) as String?;
          final city = (addressObj['city'] ?? addressObj['town'] ?? addressObj['village']) as String?;
          final state = addressObj['state'] as String?;
          
          if (road?.isNotEmpty == true) parts.add(road!);
          if (suburb?.isNotEmpty == true) parts.add(suburb!);
          if (city?.isNotEmpty == true) parts.add(city!);
          if (state?.isNotEmpty == true) parts.add(state!);
          
          if (parts.isNotEmpty) {
            final address = parts.join(', ');
            debugPrint('Address from Nominatim (detail): $address');
            return address;
          }
        }
        
        final displayName = data['display_name'] as String?;
        if (displayName != null && displayName.isNotEmpty) {
          final parts = displayName.split(',').take(4).toList();
          final address = parts.join(', ');
          debugPrint('Address from Nominatim (display_name): $address');
          return address;
        }
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

  static Future<String> _fetchWeather(String latStr, String lonStr) async {
    try {
      final wUri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$latStr&longitude=$lonStr'
        '&current=temperature_2m,weather_code&timezone=auto',
      );
      final wRes = await _client.get(wUri).timeout(const Duration(seconds: 3));
      
      if (wRes.statusCode == 200) {
        final wData = jsonDecode(wRes.body) as Map<String, dynamic>;
        final current = wData['current'] as Map<String, dynamic>?;
        if (current != null) {
          final temp = (current['temperature_2m'] as num?)?.toStringAsFixed(0) ?? '--';
          final code = (current['weather_code'] as num?)?.toInt() ?? 0;
          final weather = '${_wmoDesc(code)} $temp°C';
          debugPrint('Weather: $weather');
          return weather;
        }
      }
    } on TimeoutException {
      debugPrint('Weather API timeout');
    } catch (e) {
      debugPrint('Weather error: $e');
    }
    return '';
  }

  static String _wmoDesc(int c) {
    if (c == 0) return '☀️ Cerah';
    if (c <= 3) return '⛅ Berawan';
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
  // MINI MAP - OpenStreetMap Static (GRATIS)
  // ============================================================

  static Future<Uint8List?> fetchOSMStaticMap(double lat, double lon) async {
    final cacheKey = '${lat.toStringAsFixed(3)},${lon.toStringAsFixed(3)}';
    
    if (_mapCache.containsKey(cacheKey)) {
      debugPrint('Static map from cache: $cacheKey');
      return _mapCache[cacheKey];
    }
    
    try {
      final url = Uri.parse(
        'https://staticmap.openstreetmap.de/staticmap.php'
        '?center=$lat,$lon'
        '&zoom=16'
        '&size=400x250'
        '&maptype=mapnik'
        '&markers=$lat,$lon,ol-marker'
      );
      
      final response = await _client.get(url).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final bytes = Uint8List.fromList(response.bodyBytes);
        if (bytes.length > 8 &&
            bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
          debugPrint('OSM Static Map fetched: ${bytes.length} bytes');
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

  static Future<Uint8List?> fetchMapWithRetry(double lat, double lon, {int maxRetries = 2}) async {
    // Coba static map dulu
    for (int i = 0; i < maxRetries; i++) {
      final result = await fetchOSMStaticMap(lat, lon);
      if (result != null) return result;
      if (i < maxRetries - 1) await Future.delayed(Duration(seconds: i + 1));
    }
    
    // Fallback: OSM tile langsung
    debugPrint('Static map gagal, mencoba OSM tile...');
    return await _fetchOsmTileBytes(lat, lon, zoom: 15);
  }

  static Future<Uint8List?> _fetchOsmTileBytes(double lat, double lng, {int zoom = 15}) async {
    try {
      final n = pow(2, zoom).toInt();
      final tileX = ((lng + 180) / 360 * n).toInt().clamp(0, n - 1);
      final latRad = lat * pi / 180;
      final tileY = ((1 - log(tan(latRad) + 1 / cos(latRad)) / pi) / 2 * n)
          .toInt()
          .clamp(0, n - 1);

      const subdomains = ['a', 'b', 'c'];
      final sub = subdomains[tileX % 3];
      final url = 'https://$sub.tile.openstreetmap.org/$zoom/$tileX/$tileY.png';

      final response = await _client.get(
        Uri.parse(url),
        headers: {'User-Agent': 'TermulLog/1.0'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final bytes = Uint8List.fromList(response.bodyBytes);
        if (bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50) {
          debugPrint('OSM tile success: ${bytes.length} bytes');
          return bytes;
        }
      }
    } catch (e) {
      debugPrint('OSM tile error: $e');
    }
    return null;
  }
}
