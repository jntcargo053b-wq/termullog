// lib/services/address_resolver.dart
// PERBAIKAN LENGKAP:
// 1. Antrikan posisi saat pending
// 2. Threshold jarak 5m (dari 15m)
// 3. Threshold peningkatan akurasi 3m (dari 8m)
// 4. (Tidak perlu di sini, tapi dipastikan di caller)
// 5. Sudah siap untuk forceRefresh dari luar

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
  
  // 🔥 PERBAIKAN 1: Antrikan posisi terbaru saat pending
  Position? _queuedPosition;

  // 🔥 PERBAIKAN 2 & 3: Threshold lebih kecil
  static const double _minDistanceMeters = 5.0;      // dari 15.0
  static const int _minIntervalSeconds = 30;
  static const double _accuracyImprovementThreshold = 3.0; // dari 8.0
  static const int _debounceMilliseconds = 800;

  void reset() {
    _lastLat = null;
    _lastLon = null;
    _lastAccuracy = null;
    _lastTime = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pending = false;
    _queuedPosition = null;
  }

  void onPositionUpdate(Position pos, Future<void> Function(Position) onGeocode) {
    // 🔥 PERBAIKAN 1: Jika sedang geocode, simpan posisi terbaru
    if (_pending) {
      _queuedPosition = pos;
      if (kDebugMode) {
        debugPrint('AddressResolver: pending, queue pos (acc=${pos.accuracy.toStringAsFixed(1)}m)');
      }
      return;
    }

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
          'AddressResolver: trigger — dist=${distance.toStringAsFixed(1)}m '
          'time=${timeSinceLast}s accImprove=$accuracyImproved '
          '(lastAcc=${_lastAccuracy?.toStringAsFixed(1)}m nowAcc=${pos.accuracy.toStringAsFixed(1)}m)',
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
        
        // 🔥 PERBAIKAN 1: Proses antrian jika ada
        if (_queuedPosition != null) {
          final queued = _queuedPosition!;
          _queuedPosition = null;
          if (kDebugMode) {
            debugPrint('AddressResolver: processing queued position acc=${queued.accuracy.toStringAsFixed(1)}m');
          }
          // Panggil ulang onPositionUpdate dengan posisi yang diantri
          onPositionUpdate(queued, onGeocode);
        }
      }
    });
  }

  void forceRefresh(Position pos, Future<void> Function(Position) onGeocode) {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pending = false;       // Batalin antrian juga
    _queuedPosition = null; // Kosongkan antrian
    _lastLat = pos.latitude;
    _lastLon = pos.longitude;
    _lastAccuracy = pos.accuracy;
    _lastTime = DateTime.now();
    _pending = true;

    if (kDebugMode) {
      debugPrint(
        'AddressResolver: forceRefresh raw (${pos.latitude.toStringAsFixed(7)}, '
        '${pos.longitude.toStringAsFixed(7)}) acc=${pos.accuracy.toStringAsFixed(1)}m',
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
    _queuedPosition = null;
  }
}
