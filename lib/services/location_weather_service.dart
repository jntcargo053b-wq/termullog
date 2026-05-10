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
  static const int _precision = 4; // 4 desimal ≈ 10-20 meter
  
  static String encode(double lat, double lon) {
    final latRounded = (lat * pow(10, _precision)).round() / pow(10, _precision);
    final lonRounded = (lon * pow(10, _precision)).round() / pow(10, _precision);
    return '${latRounded.toStringAsFixed(_precision)},${lonRounded.toStringAsFixed(_precision)}';
  }
  
  static double distance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000; // Radius bumi dalam meter
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
  
  // Reusable HTTP client
  static final http.Client _client = http.Client();
  
  // Cache untuk alamat
  static final Map<String, _CacheEntry> _addressCache = {};
  static const int _cacheMaxSize = 100;
  static const double _cacheRadiusMeters = 50.0;
  
  // Cache untuk static map
  static final Map<String, Uint8List> _mapCache = {};
  static const int _mapCacheMaxSize = 50;
  
  // Rate limiting untuk Nominatim
  static DateTime _lastNominatimRequest = DateTime.now().subtract(const Duration(seconds: 2));
  
  // Event stream untuk progress
  static final _progressController = StreamController<String>.broadcast();
  static Stream<String> get onProgress => _progressController.stream;
  
  static void _emitProgress(String message) {
    _progressController.add(message);
  }
  
  // Close client
  static void close() {
    _client.close();
    _progressController.close();
  }

  // ============================================================
  // Main Method
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
      
      final weather = await _fetchWeather(latStr, lonStr);
      return LocationWeatherResult(
        address: cached.address,
        weather: weather,
        rawAddress: cached.address,
      );
    }

    // ─── PARALLEL REQUEST: Address + Weather ──────────────────────────────
    final results = await Future.wait([
      _fetchAddressWithProviders(lat, lon, latStr, lonStr),
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
  // Format DMS (Degree, Minute, Second)
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
  // Fetch Address dengan Multiple Providers
  // ============================================================

  static Future<String> _fetchAddressWithProviders(
    double lat, double lon, String latStr, String lonStr
  ) async {
    String address = '';

    _emitProgress('🗺️ Mengambil data dari Geocoding...');
    address = await _fetchFromGeocoding(lat, lon);
    if (address.isNotEmpty) return address;

    _emitProgress('📡 Mencoba Photon API...');
    address = await _fetchFromPhoton(latStr, lonStr);
    if (address.isNotEmpty) return address;

    _emitProgress('🌍 Mencoba Nominatim...');
    address = await _fetchFromNominatim(latStr, lonStr);
    if (address.isNotEmpty) return address;

    return address;
  }

  // ============================================================
  // PROVIDER 1: Geocoding Package
  // ============================================================

  static Future<String> _fetchFromGeocoding(double lat, double lon) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lon).timeout(
        const Duration(seconds: 5),
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
    } on SocketException {
      debugPrint('Geocoding network error');
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
        'https://photon.komoot.io/reverse'
        '?lat=$latStr&lon=$lonStr',
      );
      final res = await _client.get(uri).timeout(const Duration(seconds: 5));
      
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
    } on SocketException {
      debugPrint('Photon network error');
    } catch (e) {
      debugPrint('Photon error: $e');
    }
    return '';
  }

  // ============================================================
  // PROVIDER 3: Nominatim
  // ============================================================

  static Future<String> _fetchFromNominatim(String latStr, String lonStr) async {
    // Rate limit compliance: minimum 1 detik antar request
    final now = DateTime.now();
    final timeSinceLastRequest = now.difference(_lastNominatimRequest);
    if (timeSinceLastRequest.inMilliseconds < 1000) {
      final waitTime = Duration(milliseconds: 1000 - timeSinceLastRequest.inMilliseconds);
      debugPrint('Nominatim rate limit: waiting ${waitTime.inMilliseconds}ms');
      await Future.delayed(waitTime);
    }
    
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json&lat=$latStr&lon=$lonStr&zoom=18&addressdetails=1'
        '&accept-language=id', // Bahasa Indonesia
      );
      final res = await _client.get(
        uri,
        headers: {'User-Agent': 'TermulLog/1.0'},
      ).timeout(const Duration(seconds: 5));

      _lastNominatimRequest = DateTime.now();
      
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final displayName = data['display_name'] as String?;
        if (displayName != null && displayName.isNotEmpty) {
          final parts = displayName.split(',').take(4).toList();
          final address = parts.join(', ');
          debugPrint('Address from Nominatim: $address');
          return address;
        }
      }
    } on TimeoutException {
      debugPrint('Nominatim timeout');
    } on SocketException {
      debugPrint('Nominatim network error');
    } catch (e) {
      debugPrint('Nominatim error: $e');
    }
    return '';
  }

  // ============================================================
  // FETCH WEATHER
  // ============================================================

  static Future<String> _fetchWeather(String latStr, String lonStr) async {
    String weather = '';
    
    try {
      final wUri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$latStr&longitude=$lonStr'
        '&current=temperature_2m,weather_code&timezone=auto',
      );
      final wRes = await _client.get(wUri).timeout(const Duration(seconds: 6));
      
      if (wRes.statusCode == 200) {
        final wData = jsonDecode(wRes.body) as Map<String, dynamic>;
        final current = wData['current'] as Map<String, dynamic>?;
        if (current != null) {
          final temp = (current['temperature_2m'] as num?)?.toStringAsFixed(0) ?? '--';
          final code = (current['weather_code'] as num?)?.toInt() ?? 0;
          weather = '${_wmoDesc(code)} ${temp}°C';
          debugPrint('Weather: $weather');
        }
      }
    } on TimeoutException {
      debugPrint('Weather API timeout');
    } on SocketException {
      debugPrint('Weather API network error');
    } catch (e) {
      debugPrint('Weather error: $e');
    }
    
    return weather;
  }

  // ============================================================
  // WEATHER DESCRIPTION
  // ============================================================

  static String _wmoDesc(int c) {
    if (c == 0) return '☀️';
    if (c <= 3) return '⛅';
    if (c <= 49) return '🌫️';
    if (c <= 59) return '🌦️';
    if (c <= 67) return '🌧️';
    if (c <= 77) return '❄️';
    if (c <= 82) return '🌧️☔';
    if (c <= 86) return '❄️🌨️';
    if (c == 95) return '⚡';
    return '🌡️';
  }

  // ============================================================
  // OPENSTREETMAP STATIC MAP (GRATIS, TANPA API KEY)
  // ============================================================

  /// Format number dengan leading zeros
  static String _padNum(int n) => n.toString().padLeft(2, '0');

  /// Konversi koordinat ke tile coordinates
  static (int x, int y) _getTileCoordinates(double lat, double lon, int zoom) {
    final x = ((lon + 180) / 360 * pow(2, zoom)).floor();
    final y = ((1 - log(tan(lat * pi / 180) + 1 / cos(lat * pi / 180)) / pi) / 2 * pow(2, zoom)).floor();
    return (x, y);
  }

  /// Fetch static map dari OpenStreetMap (GRATIS, TANPA API KEY)
  static Future<Uint8List?> fetchOSMStaticMap(double lat, double lon) async {
    final cacheKey = '${lat.toStringAsFixed(3)},${lon.toStringAsFixed(3)}';
    
    // Cek cache
    if (_mapCache.containsKey(cacheKey)) {
      debugPrint('Static map from cache: $cacheKey');
      return _mapCache[cacheKey];
    }
    
    try {
      // OSM Static Map service (reliable, gratis)
      final url = Uri.parse(
        'https://staticmap.openstreetmap.de/staticmap.php'
        '?center=$lat,$lon'
        '&zoom=16'
        '&size=400x250'
        '&maptype=mapnik'
        '&markers=$lat,$lon,lightblue1'
      );
      
      final response = await _client.get(url).timeout(const Duration(seconds: 8));
      
      if (response.statusCode == 200) {
        debugPrint('OSM Static Map fetched: ${response.bodyBytes.length} bytes');
        
        // Simpan ke cache
        if (_mapCache.length >= _mapCacheMaxSize) {
          _mapCache.remove(_mapCache.keys.first);
        }
        _mapCache[cacheKey] = response.bodyBytes;
        
        return response.bodyBytes;
      } else {
        debugPrint('OSM Static Map error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('OSM Static Map exception: $e');
    }
    return null;
  }

  /// Fetch tile berdasarkan koordinat (fallback)
  static Future<Uint8List?> fetchOSMTile(double lat, double lon, int zoom) async {
    try {
      final (x, y) = _getTileCoordinates(lat, lon, zoom);
      final url = Uri.parse('https://tile.openstreetmap.org/$zoom/$x/$y.png');
      
      final response = await _client.get(url).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (e) {
      debugPrint('OSM Tile error: $e');
    }
    return null;
  }

  /// Fetch mini map dengan multiple tiles (untuk area lebih luas)
  static Future<Uint8List?> fetchOSMMapComposite(double lat, double lon) async {
    try {
      const zoom = 16;
      const size = 400;
      const tileSize = 256;
      final tilesWide = (size / tileSize).ceil();
      final tilesHigh = (size / tileSize).ceil();
      
      final (centerX, centerY) = _getTileCoordinates(lat, lon, zoom);
      final startX = centerX - (tilesWide ~/ 2);
      final startY = centerY - (tilesHigh ~/ 2);
      
      // Buat canvas untuk composite
      img.Image? composite;
      
      for (int i = 0; i < tilesWide; i++) {
        for (int j = 0; j < tilesHigh; j++) {
          final tileX = startX + i;
          final tileY = startY + j;
          final tileUrl = Uri.parse('https://tile.openstreetmap.org/$zoom/$tileX/$tileY.png');
          
          final response = await _client.get(tileUrl).timeout(const Duration(seconds: 5));
          
          if (response.statusCode == 200) {
            final tileImg = img.decodeImage(response.bodyBytes);
            if (tileImg != null) {
              if (composite == null) {
                composite = img.Image(width: size, height: size);
              }
              final xOffset = i * tileSize;
              final yOffset = j * tileSize;
              img.drawImage(composite!, tileImg, dstX: xOffset, dstY: yOffset);
            }
          }
        }
      }
      
      if (composite != null) {
        // Gambar marker di tengah
        final markerColor = img.ColorRgba8(255, 50, 50, 255);
        final centerXpos = composite!.width ~/ 2;
        final centerYpos = composite!.height ~/ 2;
        img.drawCircle(composite!, x: centerXpos, y: centerYpos, radius: 8, color: markerColor);
        img.drawCircle(composite!, x: centerXpos, y: centerYpos, radius: 4, color: img.ColorRgba8(255, 255, 255, 255));
        
        return Uint8List.fromList(img.encodePng(composite!));
      }
    } catch (e) {
      debugPrint('OSM composite error: $e');
    }
    return null;
  }

  /// Fetch mini map dengan retry mechanism
  static Future<Uint8List?> fetchMapWithRetry(double lat, double lon, {int maxRetries = 2}) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        final result = await fetchOSMStaticMap(lat, lon);
        if (result != null) return result;
        
        // Fallback ke composite
        final composite = await fetchOSMMapComposite(lat, lon);
        if (composite != null) return composite;
        
        // Tunggu sebelum retry
        if (i < maxRetries - 1) {
          await Future.delayed(Duration(seconds: i + 1));
        }
      } catch (e) {
        debugPrint('Map fetch retry $i error: $e');
      }
    }
    return null;
  }
}
