// lib/services/address_resolver.dart
// v4: cache key 5 desimal (≈1.1m), _minDist = 10.0, forceRefresh method.
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'location_weather_service.dart';

class AddressResolver {
  double? _lastLat, _lastLon;
  double? _lastResolvedAcc;
  bool _pending = false;
  Timer? _debounce;
  DateTime? _lastRequestTime;

  static const double _minDist = 10.0;               // jarak minimal re-geocode (meter)
  static const double _accImprovementThreshold = 10.0;
  static const Duration _cooldown = Duration(seconds: 8);
  static const double _minAccuracy = 15.0;

  // In-memory cache dengan presisi 5 desimal (≈1.1m), konsisten dengan location_weather_service
  static final Map<String, String> _cache = {};
  static const int _maxCacheSize = 200;

  static String _cacheKey(double lat, double lon) =>
      '${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';

  static void _putCache(double lat, double lon, String address) {
    if (address.isEmpty) return;
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[_cacheKey(lat, lon)] = address;
  }

  static String? _getCache(double lat, double lon) =>
      _cache[_cacheKey(lat, lon)];

  /// Paksa reset cache lokal dan history (dipanggil saat unlock atau perpindahan besar)
  void forceRefresh() {
    _lastLat = null;
    _lastLon = null;
    _lastResolvedAcc = null;
    _lastRequestTime = null;
    if (kDebugMode) debugPrint('AddressResolver: forceRefresh');
  }

  Future<String> resolve(Position pos) async {
    if (pos.accuracy > _minAccuracy) {
      if (kDebugMode) debugPrint('AddressResolver: skip, accuracy ${pos.accuracy.toStringAsFixed(0)}m > $_minAccuracy m');
      return '';
    }

    final cached = _getCache(pos.latitude, pos.longitude);
    if (cached != null) {
      _lastLat = pos.latitude;
      _lastLon = pos.longitude;
      _lastResolvedAcc = pos.accuracy;
      return cached;
    }

    if (!_needsUpdate(pos)) return '';

    if (_lastRequestTime != null) {
      final elapsed = DateTime.now().difference(_lastRequestTime!);
      if (elapsed < _cooldown) {
        if (kDebugMode) debugPrint('AddressResolver: cooldown');
        return '';
      }
    }

    _debounce?.cancel();
    if (_pending) return '';
    _pending = true;
    _lastRequestTime = DateTime.now();

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
    if (_lastLat == null) return true;

    final distance = _haversine(_lastLat!, _lastLon!, pos.latitude, pos.longitude);
    if (distance >= _minDist) return true;

    if (_lastResolvedAcc != null &&
        (_lastResolvedAcc! - pos.accuracy) >= _accImprovementThreshold) {
      if (kDebugMode) debugPrint('AddressResolver: force refresh acc improvement');
      return true;
    }
    return false;
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) *
            sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  void reset() {
    _lastLat = null;
    _lastLon = null;
    _lastResolvedAcc = null;
    _lastRequestTime = null;
    _debounce?.cancel();
    _pending = false;
  }

  void dispose() => reset();
}
