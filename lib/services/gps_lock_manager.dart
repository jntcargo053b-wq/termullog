// ============================================================================
// 2. lib/services/gps_lock_manager.dart
// ============================================================================
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum GpsLockState { searching, bootstrapping, locked }

class LockData {
  final Position position;      // hybrid (simple average) for display
  final Position rawPosition;   // best sample (lowest accuracy) for geocoding/watermark
  final double accuracy;
  final String quality;
  final double confidence;
  final DateTime lockedAt;
  final bool isFallbackLock;

  LockData({
    required this.position,
    required this.rawPosition,
    required this.accuracy,
    required this.quality,
    required this.confidence,
    required this.lockedAt,
    this.isFallbackLock = false,
  });

  LockData copyWith({
    Position? position,
    Position? rawPosition,
    double? accuracy,
    String? quality,
    double? confidence,
    DateTime? lockedAt,
    bool? isFallbackLock,
  }) {
    return LockData(
      position: position ?? this.position,
      rawPosition: rawPosition ?? this.rawPosition,
      accuracy: accuracy ?? this.accuracy,
      quality: quality ?? this.quality,
      confidence: confidence ?? this.confidence,
      lockedAt: lockedAt ?? this.lockedAt,
      isFallbackLock: isFallbackLock ?? this.isFallbackLock,
    );
  }
}

class GpsLockManager {
  GpsLockState _state = GpsLockState.searching;
  LockData? _lockData;
  Position? _bestFix; // all-time best accuracy sample

  // Parameter optimal untuk timestamp/logistik
  static const int _samplesBeforeLock = 6;            // 6 sample cukup
  static const double _lockAccuracyThreshold = 15.0;  // lock saat akurasi ≤15m
  static const double _moveThreshold = 2.0;           // untuk low-pass filter (2m)
  static const double _unlockThreshold = 10.0;        // bergerak >10m → unlock

  // Bootstrapping storage
  final List<Position> _bootstrapSamples = [];
  Position? _bestDuringBootstrap;

  // Stationary progress (0..1)
  DateTime? _lastMovementTime;
  double _stationaryProgress = 0.0;
  static const double _stationaryTimeoutSeconds = 4.0;

  bool get isLocked => _state == GpsLockState.locked;
  LockData? get lockData => _lockData;
  double get stationaryProgress => _stationaryProgress;
  Position? get bestFix => _bestFix;

  bool processSample(Position newPos) {
    if (_bestFix == null || newPos.accuracy < _bestFix!.accuracy) {
      _bestFix = newPos;
      if (kDebugMode) debugPrint('GpsLockManager: New best fix acc=${newPos.accuracy.toStringAsFixed(1)}m');
    }

    switch (_state) {
      case GpsLockState.searching:
        return _handleSearching(newPos);
      case GpsLockState.bootstrapping:
        return _handleBootstrapping(newPos);
      case GpsLockState.locked:
        return _handleLocked(newPos);
    }
  }

  bool _handleSearching(Position newPos) {
    if (newPos.accuracy <= _lockAccuracyThreshold) {
      _state = GpsLockState.bootstrapping;
      _bootstrapSamples.clear();
      _bootstrapSamples.add(newPos);
      _bestDuringBootstrap = newPos;
      if (kDebugMode) {
        debugPrint('GpsLockManager: bootstrapping started (1/$_samplesBeforeLock) acc=${newPos.accuracy.toStringAsFixed(1)}m');
      }
    }
    return false;
  }

  bool _handleBootstrapping(Position newPos) {
    if (newPos.accuracy <= _lockAccuracyThreshold) {
      _bootstrapSamples.add(newPos);
      if (_bestDuringBootstrap == null || newPos.accuracy < _bestDuringBootstrap!.accuracy) {
        _bestDuringBootstrap = newPos;
      }
      if (kDebugMode) {
        debugPrint('GpsLockManager: bootstrapping ${_bootstrapSamples.length}/$_samplesBeforeLock acc=${newPos.accuracy.toStringAsFixed(1)}m');
      }
    }

    if (_bootstrapSamples.length >= _samplesBeforeLock) {
      double avgLat = 0, avgLon = 0, avgAcc = 0;
      for (var p in _bootstrapSamples) {
        avgLat += p.latitude;
        avgLon += p.longitude;
        avgAcc += p.accuracy;
      }
      avgLat /= _bootstrapSamples.length;
      avgLon /= _bootstrapSamples.length;
      avgAcc /= _bootstrapSamples.length;

      final hybridPos = Position(
        latitude: avgLat,
        longitude: avgLon,
        accuracy: avgAcc,
        altitude: _bestDuringBootstrap!.altitude,
        heading: _bestDuringBootstrap!.heading,
        speed: _bestDuringBootstrap!.speed,
        speedAccuracy: _bestDuringBootstrap!.speedAccuracy,
        timestamp: DateTime.now(),
        altitudeAccuracy: _bestDuringBootstrap!.altitudeAccuracy,
        headingAccuracy: _bestDuringBootstrap!.headingAccuracy,
      );

      _lockData = LockData(
        position: hybridPos,
        rawPosition: _bestDuringBootstrap!,
        accuracy: avgAcc,
        quality: _getQualityFromAccuracy(avgAcc),
        confidence: _computeConfidence(avgAcc),
        lockedAt: DateTime.now(),
        isFallbackLock: false,
      );
      _state = GpsLockState.locked;
      _lastMovementTime = DateTime.now();
      _stationaryProgress = 0.0;

      if (kDebugMode) {
        debugPrint('GpsLockManager: LOCKED with ${_bootstrapSamples.length} samples, bestRawAcc=${_bestDuringBootstrap!.accuracy.toStringAsFixed(1)}m, hybridAcc=${avgAcc.toStringAsFixed(1)}m');
      }
      return true;
    }
    return false;
  }

  bool _handleLocked(Position newPos) {
    if (_lockData == null) return false;

    final movedDistance = _haversine(
      _lockData!.rawPosition.latitude, _lockData!.rawPosition.longitude,
      newPos.latitude, newPos.longitude,
    );

    // UNLOCK jika bergerak terlalu jauh dari posisi lock
    if (movedDistance > _unlockThreshold) {
      if (kDebugMode) {
        debugPrint('GpsLockManager: UNLOCKED - moved ${movedDistance.toStringAsFixed(1)}m > $_unlockThreshold');
      }
      reset();
      return processSample(newPos);
    }

    // Update raw position jika sample lebih akurat
    Position updatedRaw = _lockData!.rawPosition;
    if (newPos.accuracy < _lockData!.rawPosition.accuracy) {
      updatedRaw = newPos;
      if (kDebugMode) debugPrint('GpsLockManager: raw updated to better acc=${newPos.accuracy.toStringAsFixed(1)}m');
    }

    // Hybrid display: low-pass hanya jika bergerak lambat (<_moveThreshold)
    final bool movingSlowly = movedDistance < _moveThreshold;
    Position hybridPos;
    if (movingSlowly) {
      const double alpha = 0.3;
      hybridPos = Position(
        latitude: _lockData!.position.latitude * (1 - alpha) + newPos.latitude * alpha,
        longitude: _lockData!.position.longitude * (1 - alpha) + newPos.longitude * alpha,
        accuracy: newPos.accuracy,
        altitude: newPos.altitude,
        heading: newPos.heading,
        speed: newPos.speed,
        speedAccuracy: newPos.speedAccuracy,
        timestamp: DateTime.now(),
        altitudeAccuracy: newPos.altitudeAccuracy,
        headingAccuracy: newPos.headingAccuracy,
      );
    } else {
      hybridPos = newPos;
    }

    _lockData = _lockData!.copyWith(
      rawPosition: updatedRaw,
      position: hybridPos,
      accuracy: newPos.accuracy,
      quality: _getQualityFromAccuracy(newPos.accuracy),
      confidence: _computeConfidence(newPos.accuracy),
      lockedAt: DateTime.now(),
    );

    // Update stationary progress
    final now = DateTime.now();
    if (movedDistance < _moveThreshold) {
      if (_lastMovementTime != null) {
        final stationaryDuration = now.difference(_lastMovementTime!).inSeconds.toDouble();
        _stationaryProgress = min(1.0, stationaryDuration / _stationaryTimeoutSeconds);
      }
    } else {
      _lastMovementTime = now;
      _stationaryProgress = 0.0;
    }

    if (kDebugMode) {
      debugPrint('GpsLockManager: locked update rawAcc=${updatedRaw.accuracy.toStringAsFixed(1)}m moved=${movedDistance.toStringAsFixed(1)}m stationary=${(_stationaryProgress*100).toInt()}%');
    }
    return false;
  }

  double _computeConfidence(double accuracy) {
    if (accuracy <= 8) return 0.98;
    if (accuracy <= 12) return 0.95;
    if (accuracy <= 18) return 0.90;
    if (accuracy <= 28) return 0.80;
    return 0.60;
  }

  String _getQualityFromAccuracy(double acc) {
    if (acc <= 10) return 'excellent';
    if (acc <= 18) return 'good';
    if (acc <= 28) return 'fair';
    return 'poor';
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
    _state = GpsLockState.searching;
    _lockData = null;
    // Do NOT clear _bestFix (keep all-time best)
    _bootstrapSamples.clear();
    _bestDuringBootstrap = null;
    _lastMovementTime = null;
    _stationaryProgress = 0.0;
  }
}
