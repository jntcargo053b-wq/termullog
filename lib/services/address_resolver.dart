// lib/services/address_resolver.dart
import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

class AddressResolver {
  double? _lastLat;
  double? _lastLon;
  double? _lastAccuracy;
  Timer? _debounceTimer;
  bool _pending = false;
  Position? _queuedPosition;

  static const double _minDistanceMeters = 20.0;
  static const double _accuracyImprovementThreshold = 8.0;
  static const int _debounceMilliseconds = 800;

  void reset() {
    _lastLat = null;
    _lastLon = null;
    _lastAccuracy = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pending = false;
    _queuedPosition = null;
  }

  void onPositionUpdate(Position pos, Future<void> Function(Position) onGeocode) {
    if (_pending) {
      if (_queuedPosition == null || pos.accuracy < _queuedPosition!.accuracy) {
        _queuedPosition = pos;
        if (kDebugMode) debugPrint('AddressResolver: pending, update queue acc=${pos.accuracy.toStringAsFixed(1)}m');
      }
      return;
    }

    bool shouldGeocode = false;

    if (_lastLat == null || _lastLon == null) {
      shouldGeocode = true;
      if (kDebugMode) debugPrint('AddressResolver: first geocode');
    } else {
      final distance = _haversine(
        _lastLat!, _lastLon!,
        pos.latitude, pos.longitude,
      );
      final accuracyImproved = _lastAccuracy != null &&
          pos.accuracy < (_lastAccuracy! - _accuracyImprovementThreshold);

      shouldGeocode = distance >= _minDistanceMeters || accuracyImproved;

      if (kDebugMode && shouldGeocode) {
        debugPrint(
          'AddressResolver: trigger — dist=${distance.toStringAsFixed(1)}m '
          'accImprove=$accuracyImproved '
          '(lastAcc=${_lastAccuracy?.toStringAsFixed(1)}m nowAcc=${pos.accuracy.toStringAsFixed(1)}m)',
        );
      }
    }

    if (!shouldGeocode) return;

    _lastLat = pos.latitude;
    _lastLon = pos.longitude;
    _lastAccuracy = pos.accuracy;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: _debounceMilliseconds), () async {
      _pending = true;
      _debounceTimer = null;
      try {
        await onGeocode(pos);
      } catch (e) {
        if (kDebugMode) debugPrint('AddressResolver: geocode failed - $e');
      } finally {
        _pending = false;
        if (_queuedPosition != null) {
          final queued = _queuedPosition!;
          _queuedPosition = null;
          final d = _haversine(_lastLat!, _lastLon!, queued.latitude, queued.longitude);
          if (d >= _minDistanceMeters) {
            onPositionUpdate(queued, onGeocode);
          }
        }
      }
    });
  }

  void forceRefresh(Position pos, Future<void> Function(Position) onGeocode) {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pending = false;
    _queuedPosition = null;
    _lastLat = pos.latitude;
    _lastLon = pos.longitude;
    _lastAccuracy = pos.accuracy;
    _pending = true;

    if (kDebugMode) {
      debugPrint('AddressResolver: forceRefresh acc=${pos.accuracy.toStringAsFixed(1)}m');
    }

    onGeocode(pos).then((_) {
      _pending = false;
    }).catchError((e) {
      if (kDebugMode) debugPrint('AddressResolver: force geocode failed - $e');
      _pending = false;
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
    _pending = false;
    _queuedPosition = null;
  }
}
