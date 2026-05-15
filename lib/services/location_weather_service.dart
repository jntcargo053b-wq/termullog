import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:geocoding/geocoding.dart';
import 'package:image/image.dart' as img;

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

  // ────────────────────────────────────────────────────────
  static Future<LocationWeatherResult> fetchFromPosition(Position position) async {
    final lat = position.latitude;
    final lon = position.longitude;
    final latStr = lat.toStringAsFixed(6);
    final lonStr = lon.toStringAsFixed(6);
    
    _emitProgress('📍 Mencari lokasi...');
    
    final cached = _findNearbyCache(lat, lon);
    if (cached != null) {
      _emitProgress('📦 Menggunakan cache lokasi terdekat (${cached.distanceMeters.toStringAsFixed(0)}m)');
      final weather = await _fetchWeather(latStr, lonStr);
      return LocationWeatherResult(
        address: cached.address,
        weather: weather,
        rawAddress: cached.address,
      );
    }

    final results = await Future.wait([
      _fetchAddressWithProviders(lat, lon, latStr, lonStr),
      _fetchWeather(latStr, lonStr),
    ]);

    String finalAddress = results[0];
    String weather = results[1];

    if (finalAddress.isEmpty) {
      final dmsLat = _formatDMS(lat, true);
      final dmsLon = _formatDMS(lon, false);
      finalAddress = '📍 $dmsLat, $dmsLon';
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
    }

    return LocationWeatherResult(address: finalAddress, weather: weather, rawAddress: finalAddress);
  }

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

  static String _formatDMS(double coord, bool isLat) {
    final degrees = coord.abs().floor();
    final minutes = ((coord.abs() - degrees) * 60).floor();
    final seconds = ((coord.abs() - degrees - minutes / 60) * 3600).toStringAsFixed(1);
    final direction = isLat ? (coord >= 0 ? 'N' : 'S') : (coord >= 0 ? 'E' : 'W');
    return '${degrees}°${minutes}\'${seconds}" $direction';
  }

  // ────────────────────────────────────────────────────────
  static Future<String> _fetchAddressWithProviders(
    double lat, double lon, String latStr, String lonStr) async {
    
    // Prioritas 1: Geocoding package (biasanya lebih lengkap di Android/iOS)
    _emitProgress('🗺️ Mengambil data dari Geocoding...');
    String address = await _fetchFromGeocoding(lat, lon);
    if (address.isNotEmpty) {
      debugPrint('✅ Address from Geocoding: $address');
      return address;
    }

    // Prioritas 2: Nominatim dengan parsing detail
    _emitProgress('🌍 Mencoba Nominatim...');
    address = await _fetchFromNominatim(latStr, lonStr);
    if (address.isNotEmpty) {
      debugPrint('✅ Address from Nominatim: $address');
      return address;
    }

    // Prioritas 3: Photon (sebagai fallback)
    _emitProgress('📡 Mencoba Photon API...');
    address = await _fetchFromPhoton(latStr, lonStr);
    if (address.isNotEmpty) {
      debugPrint('✅ Address from Photon: $address');
      return address;
    }

    return '';
  }

  // ────────────────────────────────────────────────────────
  static Future<String> _fetchFromGeocoding(double lat, double lon) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lon)
          .timeout(const Duration(seconds: 5));
      
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        
        // Log lengkap untuk debugging
        debugPrint('Geocoding result: street=${p.street}, subLocality=${p.subLocality}, '
            'locality=${p.locality}, adminArea=${p.administrativeArea}, '
            'subAdminArea=${p.subAdministrativeArea}, postalCode=${p.postalCode}');
        
        final parts = <String>[];
        if (p.street?.isNotEmpty == true) parts.add(p.street!);
        if (p.subLocality?.isNotEmpty == true) parts.add(p.subLocality!);
        if (p.subAdministrativeArea?.isNotEmpty == true) parts.add(p.subAdministrativeArea!);
        if (p.locality?.isNotEmpty == true) parts.add(p.locality!);
        if (p.administrativeArea?.isNotEmpty == true && p.locality != p.administrativeArea)
          parts.add(p.administrativeArea!);
        if (p.postalCode?.isNotEmpty == true) parts.add(p.postalCode!);
        
        if (parts.isNotEmpty) {
          return parts.join(', ');
        }
      }
    } on TimeoutException {
      debugPrint('Geocoding timeout');
    } catch (e) {
      debugPrint('Geocoding error: $e');
    }
    return '';
  }

  // ────────────────────────────────────────────────────────
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
        '?format=json&lat=$latStr&lon=$lonStr&zoom=18&addressdetails=1&accept-language=id');
      
      final res = await _client.get(uri, headers: {'User-Agent': 'TermulLog/1.0'})
          .timeout(const Duration(seconds: 5));
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
          
          if (parts.isNotEmpty) return parts.join(', ');
        }
        
        // Fallback ke display_name
        final displayName = data['display_name'] as String?;
        if (displayName != null && displayName.isNotEmpty) {
          final parts = displayName.split(',').take(4).toList();
          return parts.join(', ');
        }
      }
    } on TimeoutException {
      debugPrint('Nominatim timeout');
    } catch (e) {
      debugPrint('Nominatim error: $e');
    }
    return '';
  }

  // ────────────────────────────────────────────────────────
  static Future<String> _fetchFromPhoton(String latStr, String lonStr) async {
    try {
      final uri = Uri.parse('https://photon.komoot.io/reverse?lat=$latStr&lon=$lonStr');
      final res = await _client.get(uri).timeout(const Duration(seconds: 5));
      
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final features = data['features'] as List?;
        if (features != null && features.isNotEmpty) {
          final props = features[0]['properties'] as Map<String, dynamic>?;
          if (props != null) {
            final parts = <String>[];
            final street = props['street'] as String?;
            final city = props['city'] as String?;
            final state = props['state'] as String?;
            if (street?.isNotEmpty == true) parts.add(street!);
            if (city?.isNotEmpty == true) parts.add(city!);
            if (state?.isNotEmpty == true) parts.add(state!);
            if (parts.isNotEmpty) return parts.join(', ');
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

  // ────────────────────────────────────────────────────────
  static Future<String> _fetchWeather(String latStr, String lonStr) async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$latStr&longitude=$lonStr'
        '&current=temperature_2m,weather_code&timezone=auto');
      final res = await _client.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final current = data['current'] as Map<String, dynamic>?;
        if (current != null) {
          final temp = (current['temperature_2m'] as num?)?.toStringAsFixed(0) ?? '--';
          final code = (current['weather_code'] as num?)?.toInt() ?? 0;
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
    if (c == 0) return '☀️ Cerah';
    if (c <= 3) return '⛅ Berawan';
    if (c <= 49) return '🌫️ Kabut';
    if (c <= 59) return '🌦️ Gerimis';
    if (c <= 67) return '🌧️ Hujan';
    if (c <= 77) return '❄️ Salju';
    if (c <= 82) return '☔ Hujan lebat';
    if (c <= 86) return '🌨️ Badai salju';
    if (c == 95) return '⚡ Badai petir';
    return '🌡️';
  }

  // ────────────────────────────────────────────────────────
  static Future<Uint8List?> fetchOSMStaticMap(double lat, double lon) async {
    final cacheKey = '${lat.toStringAsFixed(3)},${lon.toStringAsFixed(3)}';
    if (_mapCache.containsKey(cacheKey)) {
      debugPrint('Static map from cache');
      return _mapCache[cacheKey];
    }
    
    try {
      final url = Uri.parse(
        'https://staticmap.openstreetmap.de/staticmap.php'
        '?center=$lat,$lon'
        '&zoom=16'
        '&size=400x250'
        '&maptype=mapnik'
        '&markers=$lat,$lon,ol-marker');
      
      final response = await _client.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final bytes = Uint8List.fromList(response.bodyBytes);
        if (bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50) {
          if (_mapCache.length >= _mapCacheMaxSize) {
            _mapCache.remove(_mapCache.keys.first);
          }
          _mapCache[cacheKey] = bytes;
          debugPrint('OSM Static Map fetched: ${bytes.length} bytes');
          return bytes;
        } else {
          debugPrint('OSM Static Map: response bukan PNG');
        }
      }
    } catch (e) {
      debugPrint('OSM Static Map error: $e');
    }
    return null;
  }

  static Future<Uint8List?> fetchMapWithRetry(double lat, double lon, {int maxRetries = 2}) async {
    // Coba static map
    for (int i = 0; i < maxRetries; i++) {
      final result = await fetchOSMStaticMap(lat, lon);
      if (result != null) return result;
      if (i < maxRetries - 1) await Future.delayed(Duration(seconds: i + 1));
    }
    // Fallback OSM tile
    debugPrint('Static map gagal, mencoba OSM tile...');
    return await _fetchOsmTileBytes(lat, lon, zoom: 15);
  }

  static Future<Uint8List?> _fetchOsmTileBytes(double lat, double lng, {int zoom = 15}) async {
    try {
      final n = pow(2, zoom).toInt();
      final tileX = ((lng + 180) / 360 * n).toInt().clamp(0, n - 1);
      final latRad = lat * pi / 180;
      final tileY = ((1 - log(tan(latRad) + 1 / cos(latRad)) / pi) / 2 * n)
          .toInt().clamp(0, n - 1);

      const subdomains = ['a', 'b', 'c'];
      final sub = subdomains[tileX % 3];
      final url = 'https://$sub.tile.openstreetmap.org/$zoom/$tileX/$tileY.png';

      final response = await _client.get(Uri.parse(url), headers: {
        'User-Agent': 'TermulLog/1.0',
      }).timeout(const Duration(seconds: 8));

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
