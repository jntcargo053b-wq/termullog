// lib/services/gps_lock_manager.dart
// FINAL PRODUCTION – GPS Lock Manager untuk timemark/logistik
// - Weighted centroid lock, rolling window, hard cluster reset min 15m
// - Adaptive movement threshold dengan minimum reset 8m
// - Unlock threshold adaptif faktor 1.5, clamp 10-18m
// - Unlock memerlukan 2 consecutive samples
// - Bootstrap reset dengan Kalman update dinamis
// - SoftUnlock dengan reset Kalman hanya jika perpindahan >30m
// - Stationary count incremental (min +1) – lebih responsif di GPS noisy
// - Fungsi _handleLocked tanpa parameter movedDistance yang tidak dipakai

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'kalman_filter_4d.dart';

enum GpsLockState { searching, acquiring, locked }

class LockData {
  final Position position;
  final Position rawPosition;
  final double accuracy;
  final String quality;
  final double confidence;
  final DateTime lockedAt;
  final bool isFallbackLock;
  final double smoothedLatitude;
  final double smoothedLongitude;

  double get stability => confidence;

  LockData({
    required this.position,
    required this.rawPosition,
    required this.accuracy,
    required this.quality,
    required this.confidence,
    required this.lockedAt,
    required this.smoothedLatitude,
    required this.smoothedLongitude,
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
    double? smoothedLatitude,
    double? smoothedLongitude,
  }) {
    return LockData(
      position: position ?? this.position,
      rawPosition: rawPosition ?? this.rawPosition,
      accuracy: accuracy ?? this.accuracy,
      quality: quality ?? this.quality,
      confidence: confidence ?? this.confidence,
      lockedAt: lockedAt ?? this.lockedAt,
      isFallbackLock: isFallbackLock ?? this.isFallbackLock,
      smoothedLatitude: smoothedLatitude ?? this.smoothedLatitude,
      smoothedLongitude: smoothedLongitude ?? this.smoothedLongitude,
    );
  }
}

class GpsLockManager {
  GpsLockState _state = GpsLockState.searching;
  LockData? _lockData;
  Position? _bestFix;
  DateTime? _bestFixAt;
  final List<Position> _acquiringSamples = [];
  int _stationaryCount = 0;
  double _stationaryProgress = 0.0;
  bool _isMovingFlag = false;
  double _lastRawLat = 0.0, _lastRawLon = 0.0;
  double _prevRawLat = 0.0, _prevRawLon = 0.0;
  DateTime? _lastMovementTime;
  int _unlockCandidateCount = 0;

  final KalmanFilter4D _kalman = KalmanFilter4D();
  double? _kalmanOriginLat, _kalmanOriginLon;
  DateTime? _kalmanLastUpdate;

  static const int _minSamplesForLock = 9;
  static const int _maxWindowSize = 10;
  static const double _unlockDriftBase = 10.0;
  static const double _unlockDriftFactor = 1.5;
  static const double _unlockAccuracyRequired = 20.0;
  static const double _stationaryTimeoutSeconds = 4.0;
  static const Duration _bestFixMaxAge = Duration(seconds: 20);
  static const double _resetWindowMovementMultiplier = 1.5;
  static const double _resetWindowMinMeters = 8.0;
  static const double _hardJumpMinMeters = 15.0;
  static const double _kalmanResetDistance = 30.0;

  // Movement threshold adaptif
  double _getMoveThreshold(Position pos) {
    return max(4.0, pos.accuracy * 0.35).clamp(3.0, 8.0);
  }

  double get _lockAccuracyThreshold {
    if (_acquiringSamples.isEmpty) return 15.0;
    double sumW = 0.0, sumAcc = 0.0;
    for (final s in _acquiringSamples) {
      final safeAcc = s.accuracy.clamp(3.0, 100.0);
      final w = 1.0 / (safeAcc * safeAcc);
      sumW += w;
      sumAcc += s.accuracy * w;
    }
    final weightedAcc = sumW > 0 ? sumAcc / sumW : 15.0;
    return (weightedAcc * 1.1).clamp(8.0, 15.0);
  }

  double get _unlockDriftThreshold {
    if (_lockData == null) return _unlockDriftBase;
    final adaptive = _lockData!.accuracy * _unlockDriftFactor;
    return max(_unlockDriftBase, adaptive).clamp(_unlockDriftBase, 18.0);
  }

  static const int _intervalSearching = 1000;
  static const int _intervalAcquiring = 800;
  static const int _intervalLockedStationary = 1500;
  static const int _intervalLockedMoving = 700;

  bool get isLocked => _state == GpsLockState.locked;
  LockData? get lockData => _lockData;
  Position? get bestFix => _bestFix;

  double get stationaryProgress {
    if (_state == GpsLockState.searching) return 0.0;
    if (_state == GpsLockState.acquiring) {
      return (_stationaryCount / _minSamplesForLock).clamp(0.0, 1.0);
    }
    return _stationaryProgress;
  }

  bool get isMoving => _isMovingFlag;

  int get currentIntervalMs {
    switch (_state) {
      case GpsLockState.searching:
        return _intervalSearching;
      case GpsLockState.acquiring:
        return _intervalAcquiring;
      case GpsLockState.locked:
        return _isMovingFlag ? _intervalLockedMoving : _intervalLockedStationary;
    }
  }

  bool processSample(Position newPos) {
    // BestFix update & reset with aging
    if (_bestFix != null && _bestFixAt != null &&
        DateTime.now().difference(_bestFixAt!) > _bestFixMaxAge) {
      _bestFix = newPos;
      _bestFixAt = DateTime.now();
      if (kDebugMode) debugPrint('GpsLockManager: bestFix aged out, replaced');
    } else if (_bestFix != null) {
      final drift = _haversine(
        _bestFix!.latitude, _bestFix!.longitude,
        newPos.latitude, newPos.longitude,
      );
      if (drift > 40.0 &&
          newPos.accuracy <= _unlockAccuracyRequired &&
          newPos.accuracy < (_bestFix!.accuracy + 10.0)) {
        _bestFix = newPos;
        _bestFixAt = DateTime.now();
        if (kDebugMode) debugPrint('GpsLockManager: bestFix reset (moved ${drift.toStringAsFixed(1)}m, acc ${newPos.accuracy.toStringAsFixed(0)}m)');
      }
    }
    if (_bestFix == null || newPos.accuracy < _bestFix!.accuracy) {
      _bestFix = newPos;
      _bestFixAt = DateTime.now();
      if (kDebugMode) debugPrint('GpsLockManager: bestFix acc=${newPos.accuracy.toStringAsFixed(1)}m');
    }

    // Jarak dari posisi raw terakhir
    double movedDistance = 0.0;
    if (_lastRawLat != 0.0 && _lastRawLon != 0.0) {
      movedDistance = _haversine(
        _lastRawLat, _lastRawLon,
        newPos.latitude, newPos.longitude,
      );
    }

    // Movement flag adaptif
    final moveThreshold = _getMoveThreshold(newPos);
    if (_lastRawLat != 0.0) {
      if (movedDistance > moveThreshold) {
        _isMovingFlag = true;
        _lastMovementTime = DateTime.now();
        _stationaryProgress = 0.0;
      } else {
        if (_isMovingFlag) {
          _isMovingFlag = false;
          _lastMovementTime = DateTime.now();
        } else if (_lastMovementTime != null) {
          final stationaryDuration = DateTime.now().difference(_lastMovementTime!).inSeconds.toDouble();
          _stationaryProgress = (stationaryDuration / _stationaryTimeoutSeconds).clamp(0.0, 1.0);
        }
      }
    }

    // Panggil handler dengan state LAMA
    final result = (_state == GpsLockState.locked)
        ? _handleLocked(newPos)
        : _handleAcquiring(newPos, movedDistance);

    // Update history SETELAH processing
    _prevRawLat = _lastRawLat;
    _prevRawLon = _lastRawLon;
    _lastRawLat = newPos.latitude;
    _lastRawLon = newPos.longitude;

    return result;
  }

  bool _handleLocked(Position newPos) {
    if (_lockData == null) return false;

    final distFromLock = _haversine(
      _lockData!.smoothedLatitude, _lockData!.smoothedLongitude,
      newPos.latitude, newPos.longitude,
    );

    final bool isUnlockCandidate = distFromLock > _unlockDriftThreshold &&
        newPos.accuracy <= _unlockAccuracyRequired;

    if (isUnlockCandidate) {
      _unlockCandidateCount++;
      if (_unlockCandidateCount >= 2) {
        softUnlock(distFromLock);
        if (kDebugMode) debugPrint('GpsLockManager: HARD UNLOCK (drift ${distFromLock.toStringAsFixed(1)}m, threshold $_unlockDriftThreshold)');
        return _handleAcquiring(newPos, distFromLock);
      }
    } else {
      _unlockCandidateCount = 0;
    }

    // Update raw position (metadata) jika akurasi lebih baik
    if (newPos.accuracy < (_lockData!.rawPosition.accuracy - 2.0)) {
      _lockData = _lockData!.copyWith(
        rawPosition: newPos,
        quality: _getQualityFromAccuracy(_lockData!.accuracy),
        confidence: _computeConfidence(_lockData!.accuracy),
      );
      if (kDebugMode) debugPrint('GpsLockManager: improved raw acc=${newPos.accuracy.toStringAsFixed(1)}m');
    }
    return false;
  }

  bool _handleAcquiring(Position newPos, double movedDistance) {
    // Reset window dengan bootstrap
    final moveThreshold = _getMoveThreshold(newPos);
    final effectiveResetThreshold = max(
      moveThreshold * _resetWindowMovementMultiplier,
      _resetWindowMinMeters,
    );
    if (_lastRawLat != 0.0 && _prevRawLat != 0.0 &&
        movedDistance > effectiveResetThreshold &&
        newPos.accuracy > 12.0) {
      _stationaryCount = 1;
      _acquiringSamples.clear();
      _acquiringSamples.add(newPos);
      _resetKalman();
      _initKalmanIfNeeded(newPos);
      _updateKalmanWithSample(newPos);
      _state = GpsLockState.acquiring;
      if (kDebugMode) debugPrint('GpsLockManager: reset window (moved ${movedDistance.toStringAsFixed(1)}m, acc ${newPos.accuracy.toStringAsFixed(0)}m) - bootstrapped');
      return false;
    }

    if (newPos.accuracy <= _lockAccuracyThreshold) {
      final double coordStableTolerance = (newPos.accuracy * 0.3).clamp(5.0, 8.0);
      bool isHardJump = false;
      if (_acquiringSamples.isNotEmpty) {
        final jumpDistance = _haversine(
          _acquiringSamples.last.latitude, _acquiringSamples.last.longitude,
          newPos.latitude, newPos.longitude,
        );
        final hardJumpThreshold = max(coordStableTolerance * 2.5, _hardJumpMinMeters);
        if (jumpDistance > hardJumpThreshold) {
          isHardJump = true;
          if (kDebugMode) debugPrint('GpsLockManager: HARD CLUSTER RESET (jump ${jumpDistance.toStringAsFixed(1)}m, threshold ${hardJumpThreshold.toStringAsFixed(1)}m)');
        }
      }

      if (isHardJump) {
        _acquiringSamples.clear();
        _acquiringSamples.add(newPos);
        _stationaryCount = 1;
        _resetKalman();
        _initKalmanIfNeeded(newPos);
        _updateKalmanWithSample(newPos);
      } else {
        if (_acquiringSamples.length >= _maxWindowSize) {
          _acquiringSamples.removeAt(0);
        }
        _acquiringSamples.add(newPos);
        // Stationary count incremental (min +1) – lebih responsif
        _stationaryCount = min(_stationaryCount + 1, _maxWindowSize);

        _initKalmanIfNeeded(newPos);
        _updateKalmanWithSample(newPos);
      }
    }
    _state = GpsLockState.acquiring;

    final readyToLock = _stationaryCount >= _minSamplesForLock &&
        newPos.accuracy <= _lockAccuracyThreshold;

    if (readyToLock) {
      double sumW = 0.0, sumLat = 0.0, sumLon = 0.0, sumAccW = 0.0, sumAcc = 0.0;
      for (final s in _acquiringSamples) {
        final safeAcc = s.accuracy.clamp(3.0, 100.0);
        final w = 1.0 / (safeAcc * safeAcc);
        sumW += w;
        sumLat += s.latitude * w;
        sumLon += s.longitude * w;
        sumAccW += w;
        sumAcc += s.accuracy * w;
      }
      final centroidLat = sumW > 0 ? sumLat / sumW : newPos.latitude;
      final centroidLon = sumW > 0 ? sumLon / sumW : newPos.longitude;
      final lockedAccuracy = sumAccW > 0 ? sumAcc / sumAccW : newPos.accuracy;

      final bestRaw = _acquiringSamples.reduce((a, b) => a.accuracy < b.accuracy ? a : b);
      final centroidPosition = Position(
        latitude: centroidLat,
        longitude: centroidLon,
        accuracy: lockedAccuracy,
        timestamp: DateTime.now(),
        altitude: bestRaw.altitude,
        altitudeAccuracy: bestRaw.altitudeAccuracy,
        heading: bestRaw.heading,
        headingAccuracy: bestRaw.headingAccuracy,
        speed: bestRaw.speed,
        speedAccuracy: bestRaw.speedAccuracy,
      );

      double smoothedLat = centroidLat;
      double smoothedLon = centroidLon;
      if (_kalmanOriginLat != null && _kalman.isHealthy()) {
        final (state, _) = _kalman.predict(0.0);
        const degToMeter = 111320.0;
        smoothedLat = _kalmanOriginLat! + state[1] / degToMeter;
        smoothedLon = _kalmanOriginLon! +
            state[0] / (degToMeter * cos(_kalmanOriginLat! * pi / 180.0));

        final kalmanOffset = _haversine(centroidLat, centroidLon, smoothedLat, smoothedLon);
        if (kalmanOffset > 8.0) {
          if (kDebugMode) debugPrint('GpsLockManager: Kalman offset too large (${kalmanOffset.toStringAsFixed(1)}m), using centroid');
          smoothedLat = centroidLat;
          smoothedLon = centroidLon;
        } else if (kDebugMode) {
          debugPrint('GpsLockManager: Kalman smoothing offset=${kalmanOffset.toStringAsFixed(1)}m');
        }
      }

      _acquiringSamples.clear();
      _lockData = LockData(
        position: centroidPosition,
        rawPosition: bestRaw,
        accuracy: lockedAccuracy,
        quality: _getQualityFromAccuracy(lockedAccuracy),
        confidence: _computeConfidence(lockedAccuracy),
        lockedAt: DateTime.now(),
        isFallbackLock: false,
        smoothedLatitude: smoothedLat,
        smoothedLongitude: smoothedLon,
      );
      _state = GpsLockState.locked;
      _stationaryProgress = 1.0;
      if (kDebugMode) {
        debugPrint('GpsLockManager: LOCKED acc=${lockedAccuracy.toStringAsFixed(1)}m '
            'centroid=(${centroidLat.toStringAsFixed(6)}, ${centroidLon.toStringAsFixed(6)}) '
            'smoothed=(${smoothedLat.toStringAsFixed(6)}, ${smoothedLon.toStringAsFixed(6)})');
      }
      return true;
    }
    return false;
  }

  void _updateKalmanWithSample(Position pos) {
    if (_kalmanOriginLat == null || _kalmanOriginLon == null) return;
    const degToMeter = 111320.0;
    final east = (pos.longitude - _kalmanOriginLon!) *
        degToMeter * cos(_kalmanOriginLat! * pi / 180.0);
    final north = (pos.latitude - _kalmanOriginLat!) * degToMeter;
    final R = (pos.accuracy.clamp(3.0, 50.0) * pos.accuracy.clamp(3.0, 50.0)).clamp(9.0, 2500.0);
    
    final now = DateTime.now();
    final dt = _kalmanLastUpdate != null
        ? now.difference(_kalmanLastUpdate!).inMilliseconds / 1000.0
        : 0.8;
    _kalman.predictAndUpdate(dt.clamp(0.1, 5.0), east, north, R);
    _kalmanLastUpdate = now;
  }

  void softUnlock([double movedDistance = 0.0]) {
    if (_state != GpsLockState.locked) return;
    _state = GpsLockState.acquiring;
    
    final lockData = _lockData; // capture before nulling
    if (movedDistance > _kalmanResetDistance) {
      _resetKalman();
      _stationaryCount = 0;
      _acquiringSamples.clear();
      if (kDebugMode) debugPrint('GpsLockManager: softUnlock with Kalman reset (moved ${movedDistance.toStringAsFixed(1)}m)');
    } else {
      // Preserve Kalman, bootstrap dengan 1 sample terbaik
      _acquiringSamples.clear();
      final seed = _bestFix ?? lockData?.rawPosition;
      if (seed != null) {
        _acquiringSamples.add(seed);
        _stationaryCount = 1;
        _initKalmanIfNeeded(seed);
        _updateKalmanWithSample(seed);
      } else {
        _stationaryCount = 0;
      }
      if (kDebugMode) debugPrint('GpsLockManager: softUnlock (Kalman preserved), bootstrapped with ${seed != null ? "seed" : "null"}');
    }
    _lockData = null;
    _isMovingFlag = false;
    _stationaryProgress = 0.0;
    _lastMovementTime = null;
    _unlockCandidateCount = 0;
  }

  void reset() {
    _state = GpsLockState.searching;
    _lockData = null;
    _bestFix = null;
    _bestFixAt = null;
    _acquiringSamples.clear();
    _stationaryCount = 0;
    _isMovingFlag = false;
    _stationaryProgress = 0.0;
    _lastMovementTime = null;
    _lastRawLat = 0.0;
    _lastRawLon = 0.0;
    _prevRawLat = 0.0;
    _prevRawLon = 0.0;
    _unlockCandidateCount = 0;
    _resetKalman();
  }

  void _initKalmanIfNeeded(Position pos) {
    if (_kalmanOriginLat == null) {
      _kalmanOriginLat = pos.latitude;
      _kalmanOriginLon = pos.longitude;
      _kalman.reset(0.0, 0.0);
      _kalmanLastUpdate = DateTime.now();
    }
  }

  void _resetKalman() {
    _kalmanOriginLat = null;
    _kalmanOriginLon = null;
    _kalmanLastUpdate = null;
    _kalman.reset(0.0, 0.0);
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
    if (lat1 == 0.0 && lon1 == 0.0) return 0.0;
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) *
            sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}
