// lib/services/address_resolver.dart
import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

class AddressResolver {
  double? _lastLat;
  double? _lastLon;
  double? _lastAccuracy;
  DateTime? _lastTime;
  Timer? _debounceTimer;
  bool _pending = false;

  // Parameter throttle yang responsif
  static const double _minDistanceMeters = 5.0;      // 5 meter
  static const int _minIntervalSeconds = 5;          // 5 detik
  static const double _accuracyImprovementThreshold = 5.0; // 5 meter
  static const int _debounceMilliseconds = 1500;      // 1.5 detik

  void reset() {
    _lastLat = null;
    _lastLon = null;
    _lastAccuracy = null;
    _lastTime = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pending = false;
  }

  void onPositionUpdate(Position pos, Future<void> Function(Position) onGeocode) {
    if (_pending) return;

    final now = DateTime.now();
    bool shouldGeocode = false;

    if (_lastLat == null || _lastLon == null) {
      shouldGeocode = true;
    } else {
      final distance = _haversine(
        _lastLat!, _lastLon!,
        pos.latitude, pos.longitude,
      );
      final timeSinceLast = _lastTime == null ? 0 : now.difference(_lastTime!).inSeconds;
      final accuracyImproved = _lastAccuracy != null &&
          pos.accuracy < (_lastAccuracy! - _accuracyImprovementThreshold);

      if (distance >= _minDistanceMeters ||
          timeSinceLast >= _minIntervalSeconds ||
          accuracyImproved) {
        shouldGeocode = true;
      }
    }

    if (!shouldGeocode) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: _debounceMilliseconds), () async {
      _pending = true;
      _lastLat = pos.latitude;
      _lastLon = pos.longitude;
      _lastAccuracy = pos.accuracy;
      _lastTime = DateTime.now();
      _debounceTimer = null;

      try {
        await onGeocode(pos);
      } catch (e) {
        if (kDebugMode) debugPrint('AddressResolver: geocode failed - $e');
      } finally {
        _pending = false;
      }
    });
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

  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
}
