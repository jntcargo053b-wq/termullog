import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'location_weather_service.dart';

class AddressResolver {
  double? _lastLat, _lastLon;
  double? _lastResolvedAcc;
  bool _pending = false;
  Timer? _debounceTimer;
  DateTime? _lastRequestTime;

  static const double _minDist = 15.0;          // tetap 15m, untuk menghindari spam
  static const double _accImprovementThreshold = 5.0;
  static const Duration _cooldown = Duration(seconds: 4);
  static const double _minAccuracy = 50.0;     // 🔥 dinaikkan dari 15 ke 50

  static final Map<String, String> _cache = {};
  static const int _maxCacheSize = 80;

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

  void forceRefresh() {
    _lastLat = null;
    _lastLon = null;
    _lastResolvedAcc = null;
    _lastRequestTime = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
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

    _debounceTimer?.cancel();
    final completer = Completer<String>();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (_pending) {
        completer.complete('');
        return;
      }
      _pending = true;
      _lastRequestTime = DateTime.now();

      try {
        final result = await LocationWeatherService.fetchFromPosition(pos);
        if (result.address.isNotEmpty) {
          _lastLat = pos.latitude;
          _lastLon = pos.longitude;
          _lastResolvedAcc = pos.accuracy;
          _putCache(pos.latitude, pos.longitude, result.address);
        }
        completer.complete(result.address);
      } catch (e) {
        debugPrint('AddressResolver: $e');
        completer.complete('');
      } finally {
        _pending = false;
        _debounceTimer = null;
      }
    });

    return completer.future;
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
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pending = false;
  }

  void dispose() => reset();
}
