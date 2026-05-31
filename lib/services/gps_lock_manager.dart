// lib/services/gps_lock_manager.dart
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum GpsLockState { searching, bootstrapping, locked }

class LockData {
  final Position position;      // smoothed untuk tampilan
  final Position rawPosition;   // raw untuk geocode & watermark
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
  Position? _bestFix;

  static const double _baseAccuracyThreshold = 15.0;
  static const double _fallbackAccuracyThreshold = 22.0;
  static const double _maxAllowedAccuracy = 22.0;
  static const int _medianWindowSize = 6;
  static const double _stationaryTimeoutSeconds = 4.0;

  static const double _fastLockAccuracy = 10.0;
  static const double _slowLockAccuracy = 15.0;
  static const double _minStableSeconds = 3.0;
  static const double _maxStableSeconds = 7.0;

  static const double _timeout1 = 10.0;
  static const double _timeout2 = 15.0;
  static const double _threshold1 = 18.0;
  static const double _threshold2 = 22.0;

  List<Position> _bootstrapSamples = [];
  DateTime? _bootstrapStart;
  List<double> _recentAccuracies = [];

  DateTime? _lastMovementTime;
  double _stationaryProgress = 0.0;

  bool get isLocked => _state == GpsLockState.locked;
  LockData? get lockData => _lockData;
  double get stationaryProgress => _stationaryProgress;
  Position? get bestFix => _bestFix;

  double get _effectiveAccuracyThreshold {
    if (_bootstrapStart == null) return _baseAccuracyThreshold;
    final waited = DateTime.now().difference(_bootstrapStart!).inSeconds.toDouble();
    if (waited >= _timeout2) return _threshold2;
    if (waited >= _timeout1) return _threshold1;
    return _baseAccuracyThreshold;
  }

  double _requiredStableSeconds(double avgAccuracy) {
    if (avgAccuracy <= _fastLockAccuracy) return _minStableSeconds;
    if (avgAccuracy >= _slowLockAccuracy) return _maxStableSeconds;
    final t = (avgAccuracy - _fastLockAccuracy) / (_slowLockAccuracy - _fastLockAccuracy);
    return _minStableSeconds + t * (_maxStableSeconds - _minStableSeconds);
  }

  bool processSample(Position newPos) {
    if (_bestFix == null || newPos.accuracy < _bestFix!.accuracy) {
      _bestFix = newPos;
      if (kDebugMode) debugPrint('GpsLockManager: New best fix acc=${newPos.accuracy.toStringAsFixed(1)}m');
    }

    if (newPos.accuracy > _maxAllowedAccuracy) {
      if (kDebugMode) debugPrint('GpsLockManager: discard acc=${newPos.accuracy.toStringAsFixed(1)}m > $_maxAllowedAccuracy');
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
    if (newPos.accuracy <= _effectiveAccuracyThreshold) {
      _state = GpsLockState.bootstrapping;
      _bootstrapSamples = [newPos];
      _bootstrapStart = DateTime.now();
      _recentAccuracies = [newPos.accuracy];
      if (kDebugMode) {
        debugPrint('GpsLockManager: bootstrapping started with acc=${newPos.accuracy.toStringAsFixed(1)}m, threshold=${_effectiveAccuracyThreshold.toStringAsFixed(1)}m');
      }
    }
    return false;
  }

  // 🔥 PERBAIKAN: Hanya gunakan sample dengan akurasi ≤ 15m untuk hitung posisi lock
  bool _handleBootstrapping(Position newPos) {
    _bootstrapSamples.add(newPos);
    _recentAccuracies.add(newPos.accuracy);
    if (_recentAccuracies.length > _medianWindowSize) {
      _recentAccuracies.removeAt(0);
    }

    final now = DateTime.now();
    final duration = now.difference(_bootstrapStart!).inSeconds.toDouble();

    double medianAcc = _computeMedian(_recentAccuracies);
    double avgAcc = _bootstrapSamples.fold(0.0, (sum, p) => sum + p.accuracy) / _bootstrapSamples.length;
    double requiredSeconds = _requiredStableSeconds(avgAcc);
    double currentThreshold = _effectiveAccuracyThreshold;

    bool stable = medianAcc <= currentThreshold && duration >= requiredSeconds;

    if (stable) {
      // Filter: hanya gunakan sample dengan akurasi ≤ _baseAccuracyThreshold (15m)
      final goodSamples = _bootstrapSamples
          .where((p) => p.accuracy <= _baseAccuracyThreshold)
          .toList();
      final samplesToUse = goodSamples.isNotEmpty ? goodSamples : _bootstrapSamples;

      double avgLat = 0, avgLon = 0, avgAccLock = 0;
      for (var p in samplesToUse) {
        avgLat += p.latitude;
        avgLon += p.longitude;
        avgAccLock += p.accuracy;
      }
      avgLat /= samplesToUse.length;
      avgLon /= samplesToUse.length;
      avgAccLock /= samplesToUse.length;

      final hybridPos = Position(
        latitude: avgLat,
        longitude: avgLon,
        accuracy: avgAccLock,
        altitude: newPos.altitude,
        heading: newPos.heading,
        speed: newPos.speed,
        speedAccuracy: newPos.speedAccuracy,
        timestamp: DateTime.now(),
        altitudeAccuracy: newPos.altitudeAccuracy,
        headingAccuracy: newPos.headingAccuracy,
      );

      final bool isFallback = currentThreshold > _baseAccuracyThreshold;
      _lockData = LockData(
        position: hybridPos,
        rawPosition: hybridPos,
        accuracy: avgAccLock,
        quality: _getQualityFromAccuracy(avgAccLock),
        confidence: _computeConfidence(avgAccLock),
        lockedAt: DateTime.now(),
        isFallbackLock: isFallback,
      );
      _state = GpsLockState.locked;
      _lastMovementTime = DateTime.now();
      _stationaryProgress = 0.0;

      if (kDebugMode) {
        debugPrint('GpsLockManager: LOCKED after ${duration.toStringAsFixed(1)}s, median=${medianAcc.toStringAsFixed(1)}m, avgLock=${avgAccLock.toStringAsFixed(1)}m, fallback=$isFallback, samplesUsed=${samplesToUse.length}');
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

    LockData newLockData = _lockData!.copyWith(rawPosition: newPos);

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
    _bestFix = null;
    _bootstrapSamples = [];
    _bootstrapStart = null;
    _recentAccuracies = [];
    _lastMovementTime = null;
    _stationaryProgress = 0.0;
  }
}
