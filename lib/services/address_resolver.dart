// lib/services/pod_address_resolver.dart
// ============================================================
// POD ADDRESS RESOLVER — Fixed Version
// ============================================================

import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _CacheEntry {
  final String address;
  final DateTime timestamp;
  _CacheEntry(this.address, this.timestamp);
  
  bool isExpired({Duration ttl = const Duration(hours: 24)}) {
    return DateTime.now().difference(timestamp) > ttl;
  }
}

class _NearbyEntry {
  final double lat, lon;
  final String address;
  final DateTime savedAt;
  _NearbyEntry(this.lat, this.lon, this.address, this.savedAt);
}

class PodAddressResolver {
  static http.Client _client = http.Client();
  static bool _closed = false;
  static const String _userAgent = 'TermulLog-POD/3.0 (Android)';
  
  static final LinkedHashMap<String, _CacheEntry> _exactCache = LinkedHashMap();
  static const int _exactCacheMax = 100;
  static const Duration _exactCacheTtl = Duration(hours: 24);
  
  static final Map<String, String> _gridCache = {};
  static const int _gridResolution = 10000;
  static const int _gridCacheMax = 200;
  
  static final List<_NearbyEntry> _nearbyCache = [];
  static const double _nearbyCacheRadius = 8.0;
  static const Duration _nearbyTtl = Duration(minutes: 10);
  static const int _nearbyCacheMax = 50;
  
  static DateTime _lastNominatim = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _nominatimInterval = Duration(seconds: 1);
  
  static DateTime _lastPhoton = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _photonInterval = Duration(milliseconds: 500);
  
  static const String _prefKey = 'pod_address_cache_v3';
  static bool _persistLoaded = false;
  
  static final RegExp _plusCodeRe = RegExp(
    r'(?:^|[\s,])([23456789CFGHJMPQRVWX]{4,8}\+[23456789CFGHJMPQRVWX]{2,3})(?:[\s,]|$)',
    caseSensitive: false,
  );
  
  static bool _isPlusCode(String? s) {
    if (s == null) return false;
    final trimmed = s.trim();
    if (trimmed.length < 8 || trimmed.length > 15) return false;
    return _plusCodeRe.hasMatch(trimmed);
  }
  
  // ENTRY POINT UTAMA
  static Future<String> resolve(double lat, double lon) async {
    debugPrint('🔍 RESOLVE: lat=$lat, lon=$lon');
    
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      debugPrint('❌ Invalid coordinates');
      return _toDMS(lat, lon);
    }
    
    await _loadPersistentCache();
    
    // Coba semua cache
    final gridKey = _gridKey(lat, lon);
    final gridCached = _gridCache[gridKey];
    if (gridCached != null) {
      debugPrint('✅ GRID CACHE HIT: $gridCached');
      return gridCached;
    }
    
    final exactKey = _cacheKey(lat, lon);
    final exactEntry = _exactCache[exactKey];
    if (exactEntry != null && !exactEntry.isExpired()) {
      debugPrint('✅ EXACT CACHE HIT: ${exactEntry.address}');
      return exactEntry.address;
    }
    
    final nearby = _nearbyLookup(lat, lon);
    if (nearby != null) {
      debugPrint('✅ NEARBY CACHE HIT: $nearby');
      return nearby;
    }
    
    // Fetch dari provider
    debugPrint('🌐 FETCHING from providers...');
    final address = await _fetchWithFallback(lat, lon);
    debugPrint('📝 FETCH RESULT: "${address}"');
    
    if (address.isNotEmpty && !address.contains('GPS:')) {
      _putExact(exactKey, address);
      _putNearby(lat, lon, address);
      _putGridCache(gridKey, address);
      await _persistCache();
      debugPrint('💾 CACHED: $address');
    }
    
    final result = address.isNotEmpty ? address : _toDMS(lat, lon);
    debugPrint('🎯 FINAL RESULT: $result');
    return result;
  }
  
  static String _gridKey(double lat, double lon) {
    final gridLat = (lat * _gridResolution).round();
    final gridLon = (lon * _gridResolution).round();
    return '$gridLat,$gridLon';
  }
  
  static void _putGridCache(String key, String value) {
    _gridCache[key] = value;
    if (_gridCache.length > _gridCacheMax) {
      final keysToRemove = _gridCache.keys.take(50).toList();
      for (var k in keysToRemove) _gridCache.remove(k);
    }
  }
  
  static Future<String> _fetchWithFallback(double lat, double lon) async {
    final latS = lat.toStringAsFixed(7);
    final lonS = lon.toStringAsFixed(7);
    
    // Nominatim
    for (final zoom in [18, 16, 14]) {
      try {
        final r = await _nominatim(latS, lonS, zoom: zoom);
        if (r.isNotEmpty && !r.contains('Unnamed Road')) {
          debugPrint('✅ Nominatim z$zoom: $r');
          return r;
        }
      } catch (e) {
        debugPrint('⚠️ Nominatim z$zoom error: $e');
      }
    }
    
    // Photon
    try {
      final r = await _photon(latS, lonS);
      if (r.isNotEmpty) {
        debugPrint('✅ Photon: $r');
        return r;
      }
    } catch (e) {
      debugPrint('⚠️ Photon error: $e');
    }
    
    // Android Geocoder
    try {
      final r = await _androidGeocoder(lat, lon);
      if (r.isNotEmpty && !r.contains('Unnamed Road')) {
        debugPrint('✅ Android Geocoder: $r');
        return r;
      }
    } catch (e) {
      debugPrint('⚠️ Android Geocoder error: $e');
    }
    
    debugPrint('❌ All providers failed');
    return '';
  }
  
  static Future<String> _nominatim(String lat, String lon, {int zoom = 18}) async {
    final now = DateTime.now();
    final elapsed = now.difference(_lastNominatim);
    if (elapsed < _nominatimInterval) {
      await Future.delayed(_nominatimInterval - elapsed);
    }
    _lastNominatim = DateTime.now();
    
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse'
          '?format=jsonv2&lat=$lat&lon=$lon'
          '&zoom=$zoom&addressdetails=1&accept-language=id'
        );
        
        debugPrint('🌐 Nominatim request: $uri');
        
        final res = await _client.get(
          uri,
          headers: {
            'User-Agent': _userAgent,
            'Accept-Language': 'id,en;q=0.8',
          },
        ).timeout(const Duration(seconds: 10));
        
        if (res.statusCode == 429) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        if (res.statusCode != 200) {
          debugPrint('⚠️ Nominatim HTTP ${res.statusCode}');
          return '';
        }
        
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final address = _parseNominatimAddress(data);
        debugPrint('📝 Nominatim parsed: "$address"');
        return address;
      } catch (e) {
        debugPrint('⚠️ Nominatim attempt $attempt error: $e');
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 600));
        }
      }
    }
    return '';
  }
  
  static String _parseNominatimAddress(Map<String, dynamic> data) {
    final addr = data['address'] as Map<String, dynamic>?;
    if (addr == null) {
      final display = data['display_name'] as String?;
      if (display != null && display.isNotEmpty) {
        return _cleanDisplayName(display);
      }
      return '';
    }
    
    String? _s(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }
    
    // Ambil komponen alamat
    final road = _s(addr['road']) ?? _s(addr['street']);
    final village = _s(addr['village']) ?? _s(addr['hamlet']) ?? _s(addr['suburb']);
    final district = _s(addr['subdistrict']) ?? _s(addr['district']);
    final city = _s(addr['city']) ?? _s(addr['town']) ?? _s(addr['county']);
    final state = _s(addr['state']);
    
    final parts = <String>[];
    if (road != null) parts.add(road);
    if (village != null && village != road) parts.add(village);
    if (district != null && district != village) parts.add(district);
    if (city != null) parts.add(city);
    if (state != null && state != city) parts.add(state);
    
    if (parts.isEmpty) {
      final display = data['display_name'] as String?;
      if (display != null && display.isNotEmpty) {
        return _cleanDisplayName(display);
      }
      return '';
    }
    
    return parts.join(', ');
  }
  
  static String _cleanDisplayName(String display) {
    final parts = display
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && !_isPlusCode(p))
        .take(5)
        .toList();
    return parts.isEmpty ? '' : parts.join(', ');
  }
  
  static Future<String> _photon(String lat, String lon) async {
    final now = DateTime.now();
    final elapsed = now.difference(_lastPhoton);
    if (elapsed < _photonInterval) {
      await Future.delayed(_photonInterval - elapsed);
    }
    _lastPhoton = DateTime.now();
    
    try {
      final uri = Uri.parse('https://photon.komoot.io/reverse?lat=$lat&lon=$lon&lang=id');
      final res = await _client.get(
        uri,
        headers: {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 10));
      
      if (res.statusCode != 200) return '';
      
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) return '';
      
      final props = features[0]['properties'] as Map<String, dynamic>? ?? {};
      
      final name = props['name']?.toString();
      final street = props['street']?.toString();
      final city = props['city']?.toString();
      final state = props['state']?.toString();
      
      final parts = <String>[];
      if (name != null && name.isNotEmpty && name != street) parts.add(name);
      if (street != null && street.isNotEmpty) parts.add(street);
      if (city != null && city.isNotEmpty) parts.add(city);
      if (state != null && state.isNotEmpty && state != city) parts.add(state);
      
      return parts.join(', ');
    } catch (e) {
      return '';
    }
  }
  
  static Future<String> _androidGeocoder(double lat, double lon) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        lat, lon,
        localeIdentifier: 'id_ID',
      ).timeout(const Duration(seconds: 10));
      
      if (placemarks.isEmpty) return '';
      final p = placemarks.first;
      
      final parts = <String>[];
      if (p.thoroughfare != null && p.thoroughfare!.isNotEmpty) parts.add(p.thoroughfare!);
      if (p.subLocality != null && p.subLocality!.isNotEmpty) parts.add(p.subLocality!);
      if (p.locality != null && p.locality!.isNotEmpty) parts.add(p.locality!);
      if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty) parts.add(p.administrativeArea!);
      
      return parts.join(', ');
    } catch (e) {
      return '';
    }
  }
  
  static String _cacheKey(double lat, double lon) =>
      '${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';
  
  static void _putExact(String key, String value) {
    if (_exactCache.length >= _exactCacheMax) {
      _exactCache.remove(_exactCache.keys.first);
    }
    _exactCache[key] = _CacheEntry(value, DateTime.now());
  }
  
  static void _putNearby(double lat, double lon, String address) {
    _nearbyCache.removeWhere((e) => DateTime.now().difference(e.savedAt) > _nearbyTtl);
    if (_nearbyCache.length >= _nearbyCacheMax) _nearbyCache.removeAt(0);
    _nearbyCache.add(_NearbyEntry(lat, lon, address, DateTime.now()));
  }
  
  static String? _nearbyLookup(double lat, double lon) {
    final now = DateTime.now();
    _NearbyEntry? best;
    double bestDist = double.infinity;
    for (final e in _nearbyCache) {
      if (now.difference(e.savedAt) > _nearbyTtl) continue;
      final d = Geolocator.distanceBetween(lat, lon, e.lat, e.lon);
      if (d <= _nearbyCacheRadius && d < bestDist) {
        bestDist = d;
        best = e;
      }
    }
    return best?.address;
  }
  
  static Future<void> _loadPersistentCache() async {
    if (_persistLoaded) return;
    _persistLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw == null || raw.isEmpty) {
        debugPrint('📦 No persistent cache found');
        return;
      }
      
      final Map<String, dynamic> rawMap = jsonDecode(raw) as Map<String, dynamic>;
      final now = DateTime.now();
      
      for (final entry in rawMap.entries) {
        final parts = entry.value.toString().split('|');
        if (parts.length >= 2) {
          final timestamp = DateTime.tryParse(parts[1]);
          if (timestamp != null && now.difference(timestamp) < _exactCacheTtl) {
            _exactCache[entry.key] = _CacheEntry(parts[0], timestamp);
          }
        }
      }
      
      debugPrint('📦 Loaded ${_exactCache.length} persisted entries');
    } catch (e) {
      debugPrint('⚠️ Load persistent error: $e');
    }
  }
  
  static Future<void> _persistCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = _exactCache.entries.toList();
      final now = DateTime.now();
      
      final freshEntries = entries.where((entry) {
        return now.difference(entry.value.timestamp) < _exactCacheTtl;
      }).toList();
      
      final slice = freshEntries.length > 20
          ? freshEntries.sublist(freshEntries.length - 20)
          : freshEntries;
      
      final map = <String, String>{};
      for (final e in slice) {
        map[e.key] = '${e.value.address}|${e.value.timestamp.toIso8601String()}';
      }
      
      await prefs.setString(_prefKey, jsonEncode(map));
      debugPrint('💾 Persisted ${map.length} entries');
    } catch (e) {
      debugPrint('⚠️ Persist error: $e');
    }
  }
  
  static List<String> _dedup(List<String> parts) => LinkedHashSet<String>.from(parts).toList();
  
  static String _toDMS(double lat, double lon) {
    final latDms = _dms(lat, true);
    final lonDms = _dms(lon, false);
    return 'GPS: $latDms, $lonDms';
  }
  
  static String _dms(double coord, bool isLat) {
    final abs = coord.abs();
    final deg = abs.floor();
    final min = ((abs - deg) * 60).floor();
    final sec = ((abs - deg - min / 60) * 3600).toStringAsFixed(1);
    final dir = isLat ? (coord >= 0 ? 'N' : 'S') : (coord >= 0 ? 'E' : 'W');
    return "$deg°$min'$sec\" $dir";
  }
  
  static void close() {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
  
  static void reopen() {
    if (!_closed) return;
    _client = http.Client();
    _closed = false;
  }
}
