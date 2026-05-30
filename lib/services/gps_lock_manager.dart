// lib/services/gps_lock_manager.dart
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum GpsLockState { searching, bootstrapping, locked }

class LockData {
  final Position position;      // hybrid smoothed
  final Position rawPosition;   // raw terbaru
  final double accuracy;
  final String quality;
  final double confidence;
  final DateTime lockedAt;

  LockData({
    required this.position,
    required this.rawPosition,
    required this.accuracy,
    required this.quality,
    required this.confidence,
    required this.lockedAt,
  });

  LockData copyWith({
    Position? position,
    Position? rawPosition,
    double? accuracy,
    String? quality,
    double? confidence,
    DateTime? lockedAt,
  }) {
    return LockData(
      position: position ?? this.position,
      rawPosition: rawPosition ?? this.rawPosition,
      accuracy: accuracy ?? this.accuracy,
      quality: quality ?? this.quality,
      confidence: confidence ?? this.confidence,
      lockedAt: lockedAt ?? this.lockedAt,
    );
  }
}

class GpsLockManager {
  GpsLockState _state = GpsLockState.searching;
  LockData? _lockData;
  Position? _bestFix;  // best position ever seen (lowest accuracy)

  // Konfigurasi
  static const double _bootstrapMaxAccuracy = 15.0;
  static const double _requiredStableSeconds = 2.0;
  static const double _maxAllowedAccuracy = 20.0;
  static const int _medianWindowSize = 5;  // untuk lock

  List<Position> _bootstrapSamples = [];
  DateTime? _bootstrapStart;

  // Median-based lock
  List<double> _recentAccuracies = [];

  // Stationary progress
  DateTime? _lastMovementTime;
  double _stationaryProgress = 0.0;
  static const double _stationaryTimeoutSeconds = 3.0;

  bool get isLocked => _state == GpsLockState.locked;
  LockData? get lockData => _lockData;
  double get stationaryProgress => _stationaryProgress;
  Position? get bestFix => _bestFix;

  /// Process raw GPS sample. Return true jika terjadi transisi ke locked.
  bool processSample(Position newPos) {
    // Update best fix
    if (_bestFix == null || newPos.accuracy < _bestFix!.accuracy) {
      _bestFix = newPos;
      if (kDebugMode) {
        debugPrint('GpsLockManager: New best fix acc=${newPos.accuracy.toStringAsFixed(1)}m');
      }
    }

    if (newPos.accuracy > _maxAllowedAccuracy) {
      if (kDebugMode) debugPrint('GpsLockManager: discard acc=${newPos.accuracy.toStringAsFixed(1)}m');
      return false;
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
    if (newPos.accuracy <= _bootstrapMaxAccuracy) {
      _state = GpsLockState.bootstrapping;
      _bootstrapSamples = [newPos];
      _bootstrapStart = DateTime.now();
      _recentAccuracies = [newPos.accuracy];
      if (kDebugMode) {
        debugPrint('GpsLockManager: bootstrapping started with acc=${newPos.accuracy.toStringAsFixed(1)}m');
      }
    }
    return false;
  }

  bool _handleBootstrapping(Position newPos) {
    _bootstrapSamples.add(newPos);
    _recentAccuracies.add(newPos.accuracy);
    if (_recentAccuracies.length > _medianWindowSize) {
      _recentAccuracies.removeAt(0);
    }

    final now = DateTime.now();
    final duration = now.difference(_bootstrapStart!).inSeconds.toDouble();

    // Hitung median akurasi dari window
    double medianAcc = _computeMedian(_recentAccuracies);
    bool stable = medianAcc <= _bootstrapMaxAccuracy && duration >= _requiredStableSeconds;

    if (stable) {
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
        altitude: newPos.altitude,
        heading: newPos.heading,
        speed: newPos.speed,
        speedAccuracy: newPos.speedAccuracy,
        timestamp: DateTime.now(),
        altitudeAccuracy: newPos.altitudeAccuracy,
        headingAccuracy: newPos.headingAccuracy,
      );

      _lockData = LockData(
        position: hybridPos,
        rawPosition: hybridPos,
        accuracy: avgAcc,
        quality: _getQualityFromAccuracy(avgAcc),
        confidence: _computeConfidence(avgAcc),
        lockedAt: DateTime.now(),
      );
      _state = GpsLockState.locked;
      _lastMovementTime = DateTime.now();
      _stationaryProgress = 0.0;

      if (kDebugMode) {
        debugPrint('GpsLockManager: LOCKED with median acc=${medianAcc.toStringAsFixed(1)}m');
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
    final accuracyImproved = newPos.accuracy < (_lockData!.accuracy - 1.0);

    // Update raw always
    LockData newLockData = _lockData!.copyWith(rawPosition: newPos);

    // Hybrid filter
    Position newHybrid;
    if (movedDistance < 2.0) {
      const double alpha = 0.3;
      newHybrid = Position(
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
      newHybrid = newPos;
    }

    if (accuracyImproved || movedDistance > 2.0) {
      newLockData = newLockData.copyWith(
        position: newHybrid,
        accuracy: newPos.accuracy,
        quality: _getQualityFromAccuracy(newPos.accuracy),
        confidence: _computeConfidence(newPos.accuracy),
        lockedAt: DateTime.now(),
      );
      if (kDebugMode) {
        debugPrint('GpsLockManager: UPDATE hybrid+raw acc=${newPos.accuracy.toStringAsFixed(1)}m');
      }
    } else {
      if (kDebugMode) {
        debugPrint('GpsLockManager: UPDATE raw only acc=${newPos.accuracy.toStringAsFixed(1)}m');
      }
    }
    _lockData = newLockData;

    // Stationary progress
    final now = DateTime.now();
    if (movedDistance < 1.0) {
      if (_lastMovementTime != null) {
        final stationaryDuration = now.difference(_lastMovementTime!).inSeconds.toDouble();
        _stationaryProgress = min(1.0, stationaryDuration / _stationaryTimeoutSeconds);
      }
    } else {
      _lastMovementTime = now;
      _stationaryProgress = 0.0;
    }
    return false;
  }

  double _computeMedian(List<double> values) {
    if (values.isEmpty) return double.infinity;
    List<double> sorted = List.from(values)..sort();
    int mid = sorted.length ~/ 2;
    if (sorted.length % 2 == 0) {
      return (sorted[mid - 1] + sorted[mid]) / 2;
    } else {
      return sorted[mid];
    }
  }

  double _computeConfidence(double accuracy) {
    if (accuracy <= 5) return 0.98;
    if (accuracy <= 10) return 0.95;
    if (accuracy <= 15) return 0.90;
    if (accuracy <= 25) return 0.80;
    if (accuracy <= 40) return 0.60;
    return 0.40;
  }

  String _getQualityFromAccuracy(double acc) {
    if (acc <= 8) return 'excellent';
    if (acc <= 15) return 'good';
    if (acc <= 25) return 'fair';
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
    _bestFix = null;
    _bootstrapSamples = [];
    _bootstrapStart = null;
    _recentAccuracies = [];
    _lastMovementTime = null;
    _stationaryProgress = 0.0;
  }
}
