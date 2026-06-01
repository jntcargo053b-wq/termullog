// lib/services/address_resolver.dart
// Adapter: wraps LocationWeatherService address lookup with debounce + cache
// v2: in-memory geocoding cache + accuracy-based force refresh
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'location_weather_service.dart';

class AddressResolver {
  double? _lastLat, _lastLon;
  double? _lastResolvedAcc;        // akurasi saat resolve terakhir
  bool _pending = false;
  Timer? _debounce;

  static const double _minDist = 10.0;         // jarak minimum untuk re-geocode
  static const double _accImprovementThreshold = 10.0; // m — jika akurasi membaik ≥10m, geocode ulang

  // ── In-memory geocoding cache ──────────────────────────────────────────────
  // key: "lat4.lon4" (4 desimal ≈ presisi ~11m, cukup untuk cache alamat)
  static final Map<String, String> _cache = {};
  static const int _maxCacheSize = 200;

  static String _cacheKey(double lat, double lon) =>
      '${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}';

  static void _putCache(double lat, double lon, String address) {
    if (address.isEmpty) return;
    if (_cache.length >= _maxCacheSize) {
      // Buang entry pertama (simple FIFO)
      _cache.remove(_cache.keys.first);
    }
    _cache[_cacheKey(lat, lon)] = address;
  }

  static String? _getCache(double lat, double lon) =>
      _cache[_cacheKey(lat, lon)];

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns address string. Empty string = tidak ada update baru (gunakan nilai lama).
  Future<String> resolve(Position pos) async {
    // 1. Cek cache dulu — hampir instan
    final cached = _getCache(pos.latitude, pos.longitude);
    if (cached != null) {
      // Update posisi terakhir tanpa network call
      _lastLat = pos.latitude;
      _lastLon = pos.longitude;
      _lastResolvedAcc = pos.accuracy;
      return cached;
    }

    // 2. Cek apakah perlu update (jarak atau akurasi membaik)
    if (!_needsUpdate(pos)) return '';

    _debounce?.cancel();
    if (_pending) return '';
    _pending = true;

    _lastLat = pos.latitude;
    _lastLon = pos.longitude;
    _lastResolvedAcc = pos.accuracy;

    try {
      final result = await LocationWeatherService.fetchFromPosition(pos);
      if (result.address.isNotEmpty) {
        _putCache(pos.latitude, pos.longitude, result.address);
      }
      return result.address;
    } catch (e) {
      debugPrint('AddressResolver: $e');
      return '';
    } finally {
      _pending = false;
    }
  }

  bool _needsUpdate(Position pos) {
    // Belum pernah resolve
    if (_lastLat == null) return true;

    // Pindah lokasi ≥ _minDist meter
    if (_haversine(_lastLat!, _lastLon!, pos.latitude, pos.longitude) >= _minDist) {
      return true;
    }

    // Akurasi membaik signifikan (mis. 30m → 10m) → geocode ulang dengan posisi lebih tepat
    if (_lastResolvedAcc != null &&
        (_lastResolvedAcc! - pos.accuracy) >= _accImprovementThreshold) {
      if (kDebugMode) {
        debugPrint(
            'AddressResolver: force refresh acc ${_lastResolvedAcc!.toStringAsFixed(0)}m → ${pos.accuracy.toStringAsFixed(0)}m');
      }
      return true;
    }

    return false;
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) *
            cos(lat2 * pi / 180.0) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  void reset() {
    _lastLat = null;
    _lastLon = null;
    _lastResolvedAcc = null;
    _debounce?.cancel();
    _pending = false;
  }

  void dispose() => reset();
}
