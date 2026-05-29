// lib/services/address_resolver.dart
// PERBAIKAN: throttle berbasis rawPosition, debounce lebih responsif
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

  // ── Threshold ──────────────────────────────────────────────────────────
  // Geocode ulang hanya jika:
  //   • Pindah ≥ 15m dari koordinat geocode terakhir, ATAU
  //   • Sudah > 30 detik sejak geocode terakhir, ATAU
  //   • Akurasi membaik ≥ 8m (misal dari 30m → 20m)
  //
  // Timemark menggunakan ~15m / 30s / 8m — cocok untuk kondisi diam/parkir.
  static const double _minDistanceMeters = 15.0;
  static const int _minIntervalSeconds = 30;
  static const double _accuracyImprovementThreshold = 8.0;
  static const int _debounceMilliseconds = 800; // lebih cepat dari 1500ms

  void reset() {
    _lastLat = null;
    _lastLon = null;
    _lastAccuracy = null;
    _lastTime = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pending = false;
  }

  /// Dipanggil setiap ada sample GPS baru.
  /// [pos] HARUS rawPosition (bukan hybrid) agar throttle berbasis posisi fisik.
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

      shouldGeocode = distance >= _minDistanceMeters ||
          timeSinceLast >= _minIntervalSeconds ||
          accuracyImproved;

      if (kDebugMode && shouldGeocode) {
        debugPrint(
          'AddressResolver: trigger geocode — '
          'dist=${distance.toStringAsFixed(1)}m '
          'time=${timeSinceLast}s '
          'accImprove=$accuracyImproved',
        );
      }
    }

    if (!shouldGeocode) return;

    _lastTime = now;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: _debounceMilliseconds), () async {
      _pending = true;
      _lastLat = pos.latitude;
      _lastLon = pos.longitude;
      _lastAccuracy = pos.accuracy;
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

  /// Force geocode langsung — bypass throttle dan pending.
  /// Selalu dipanggil dengan rawPosition saat GPS baru locked.
  void forceRefresh(Position pos, Future<void> Function(Position) onGeocode) {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pending = false;
    _lastLat = pos.latitude;
    _lastLon = pos.longitude;
    _lastAccuracy = pos.accuracy;
    _lastTime = DateTime.now();
    _pending = true;

    if (kDebugMode) {
      debugPrint(
        'AddressResolver: forceRefresh rawPos='
        '(${pos.latitude.toStringAsFixed(7)}, ${pos.longitude.toStringAsFixed(7)})',
      );
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
  }
}
