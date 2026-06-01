// lib/services/address_resolver.dart
// Adapter: wraps LocationWeatherService address lookup with debounce + cache
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'location_weather_service.dart';

class AddressResolver {
  double? _lastLat, _lastLon;
  bool _pending = false;
  Timer? _debounce;
  static const double _minDist = 10.0;
  static const int _debounceMs = 800;

  /// Returns address string or empty if unavailable.
  Future<String> resolve(Position pos) async {
    if (!_needsUpdate(pos)) return '';
    _lastLat = pos.latitude;
    _lastLon = pos.longitude;
    _debounce?.cancel();
    if (_pending) return '';
    _pending = true;
    try {
      final result = await LocationWeatherService.fetchFromPosition(pos);
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
    return _haversine(_lastLat!, _lastLon!, pos.latitude, pos.longitude) >= _minDist;
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) * sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  void reset() {
    _lastLat = null; _lastLon = null;
    _debounce?.cancel(); _pending = false;
  }

  void dispose() { reset(); }
}
