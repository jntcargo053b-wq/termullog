// lib/services/gps_lock_manager.dart
// Final production untuk timemark/logistik
// - Weighted centroid lock (tidak berubah saat ada raw lebih akurat)
// - Unlock threshold adaptif dengan base dan clamp 8-15m
// - Rolling window dengan hard cluster reset minimal 12m
// - Safety clamp accuracy untuk weight calculation

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'kalman_filter_4d.dart';

enum GpsLockState { searching, acquiring, locked }

class LockData {
  final Position position;           // weighted centroid (stabil, referensi utama)
  final Position rawPosition;        // best raw sample selama lock (metadata)
  final double accuracy;             // weighted centroid accuracy
  final String quality;
  final double confidence;
  final DateTime lockedAt;
  final bool isFallbackLock;
  final double smoothedLatitude;     // hasil Kalman (jika valid) atau centroid
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
  final List<Position> _acquiringSamples = []; // rolling window
  int _stationaryCount = 0;
  double _stationaryProgress = 0.0;
  bool _isMovingFlag = false;
  double _prevRawLat = 0.0, _prevRawLon = 0.0;
  double _lastRawLat = 0.0, _lastRawLon = 0.0;
  DateTime? _lastMovementTime;

  final KalmanFilter4D _kalman = KalmanFilter4D();
  double? _kalmanOriginLat, _kalmanOriginLon;
  DateTime? _kalmanLastUpdate;

  // Parameter lock
  static const int _minSamplesForLock = 7;        // minimal 7 sample stabil
  static const int _maxWindowSize = 10;            // rolling window maksimal 10
  static const double _moveThreshold = 3.0;        // 3m deteksi gerakan
  static const double _unlockDriftBase = 8.0;      // base drift (minimal)
  static const double _unlockDriftFactor = 1.2;    // faktor adaptif
  static const double _unlockAccuracyRequired = 20.0;
  static const double _stationaryTimeoutSeconds = 4.0;

  // Adaptive lock threshold: clamp 8-15 meter
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

  // Unlock threshold adaptif dengan base dan clamp
  double get _unlockDriftThreshold {
    if (_lockData == null) return _unlockDriftBase;
    final adaptive = _lockData!.accuracy * _unlockDriftFactor;
    // Gunakan max(base, adaptive) lalu clamp antara base dan 15
    return max(_unlockDriftBase, adaptive).clamp(_unlockDriftBase, 15.0);
  }

  // Interval adaptif
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

  // --------------------------------------------------------------
  // Proses setiap sample GPS
  // --------------------------------------------------------------
  bool processSample(Position newPos) {
    // Update all‑time best fix
    if (_bestFix == null || newPos.accuracy < _bestFix!.accuracy) {
      _bestFix = newPos;
      if (kDebugMode) debugPrint('GpsLockManager: bestFix acc=${newPos.accuracy.toStringAsFixed(1)}m');
    }

    // Hitung jarak dari previous
    double movedDistance = 0.0;
    if (_prevRawLat != 0.0 && _prevRawLon != 0.0) {
      movedDistance = _haversine(_prevRawLat, _prevRawLon, newPos.latitude, newPos.longitude);
    }

    // Update moving flag
    if (_prevRawLat != 0.0) {
      if (movedDistance > _moveThreshold) {
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

    // Simpan previous
    _prevRawLat = _lastRawLat;
    _prevRawLon = _lastRawLon;
    _lastRawLat = newPos.latitude;
    _lastRawLon = newPos.longitude;

    return (_state == GpsLockState.locked)
        ? _handleLocked(newPos)
        : _handleAcquiring(newPos, movedDistance);
  }

  // --------------------------------------------------------------
  // Handler saat locked
  // --------------------------------------------------------------
  bool _handleLocked(Position newPos) {
    if (_lockData == null) return false;

    // Gunakan smoothed coordinate sebagai referensi lock (posisi stabil)
    final distFromLock = _haversine(
      _lockData!.smoothedLatitude, _lockData!.smoothedLongitude,
      newPos.latitude, newPos.longitude,
    );

    // Hard unlock jika drift melebihi threshold adaptif dan akurasi baru bagus
    if (distFromLock > _unlockDriftThreshold && newPos.accuracy <= _unlockAccuracyRequired) {
      softUnlock();
      if (kDebugMode) debugPrint('GpsLockManager: HARD UNLOCK (drift ${distFromLock.toStringAsFixed(1)}m, threshold $_unlockDriftThreshold)');
      return _handleAcquiring(newPos, distFromLock);
    }

    // Update raw position saja (metadata) jika akurasi sample baru lebih baik
    // JANGAN ubah centroid lock (position & smoothed)
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

  // --------------------------------------------------------------
  // Handler untuk fase acquiring (rolling window + hard cluster reset)
  // --------------------------------------------------------------
  bool _handleAcquiring(Position newPos, double movedDistance) {
    // Jika bergerak signifikan, reset window (karena lokasi berubah)
    if (_prevRawLat != 0.0 && movedDistance > _moveThreshold) {
      _stationaryCount = 0;
      _acquiringSamples.clear();
      _resetKalman();
      _state = GpsLockState.acquiring;
      return false;
    }

    // Filter sample: hanya yang akurasinya <= threshold
    if (newPos.accuracy <= _lockAccuracyThreshold) {
      // Toleransi stabilitas adaptif: clamp(5.0, 8.0)
      final double coordStableTolerance = (newPos.accuracy * 0.3).clamp(5.0, 8.0);
      
      // Cek apakah ini loncatan besar dari sample terakhir
      bool isHardJump = false;
      if (_acquiringSamples.isNotEmpty) {
        final jumpDistance = _haversine(
          _acquiringSamples.last.latitude, _acquiringSamples.last.longitude,
          newPos.latitude, newPos.longitude,
        );
        // Hard jump threshold: minimal 12 meter (untuk menghindari reset berlebihan)
        final hardJumpThreshold = max(coordStableTolerance * 2.0, 12.0);
        if (jumpDistance > hardJumpThreshold) {
          isHardJump = true;
          if (kDebugMode) debugPrint('GpsLockManager: HARD CLUSTER RESET (jump ${jumpDistance.toStringAsFixed(1)}m, threshold ${hardJumpThreshold.toStringAsFixed(1)}m)');
        }
      }

      if (isHardJump) {
        // Reset total cluster: clear window dan start ulang
        _acquiringSamples.clear();
        _acquiringSamples.add(newPos);
        _stationaryCount = 1;
        _resetKalman();
        _initKalmanIfNeeded(newPos);
      } else {
        // Rolling window normal (termasuk jika koordinat tidak stabil tapi dalam toleransi)
        if (_acquiringSamples.length >= _maxWindowSize) {
          _acquiringSamples.removeAt(0);
        }
        _acquiringSamples.add(newPos);
        _stationaryCount = _acquiringSamples.length;

        // Update Kalman filter hanya jika tidak hard jump
        _initKalmanIfNeeded(newPos);
        final dt = _kalmanLastUpdate != null
            ? DateTime.now().difference(_kalmanLastUpdate!).inMilliseconds / 1000.0
            : 0.8;
        _kalmanLastUpdate = DateTime.now();

        const degToMeter = 111320.0;
        final east = (newPos.longitude - _kalmanOriginLon!) *
            degToMeter * cos(_kalmanOriginLat! * pi / 180.0);
        final north = (newPos.latitude - _kalmanOriginLat!) * degToMeter;
        final R = (newPos.accuracy.clamp(3.0, 50.0) * newPos.accuracy.clamp(3.0, 50.0)).clamp(9.0, 2500.0);
        _kalman.predictAndUpdate(dt.clamp(0.1, 5.0), east, north, R);
      }
    }
    _state = GpsLockState.acquiring;

    final readyToLock = _stationaryCount >= _minSamplesForLock &&
        newPos.accuracy <= _lockAccuracyThreshold;

    if (readyToLock) {
      // Hitung weighted centroid dari semua sample di window
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

      // Best raw (metadata) adalah sample dengan akurasi terbaik
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

      // Kalman smoothing
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

  // --------------------------------------------------------------
  // Soft unlock & reset
  // --------------------------------------------------------------
  void softUnlock() {
    if (_state != GpsLockState.locked) return;
    _state = GpsLockState.acquiring;
    _stationaryCount = 0;
    _acquiringSamples.clear();
    _resetKalman();
    _lockData = null;
    _isMovingFlag = false;
    _stationaryProgress = 0.0;
    _lastMovementTime = null;
    if (kDebugMode) debugPrint('GpsLockManager: softUnlock');
  }

  void reset() {
    _state = GpsLockState.searching;
    _lockData = null;
    _bestFix = null;
    _acquiringSamples.clear();
    _stationaryCount = 0;
    _isMovingFlag = false;
    _stationaryProgress = 0.0;
    _lastMovementTime = null;
    _prevRawLat = 0.0;
    _prevRawLon = 0.0;
    _lastRawLat = 0.0;
    _lastRawLon = 0.0;
    _resetKalman();
  }

  // --------------------------------------------------------------
  // Kalman helpers
  // --------------------------------------------------------------
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

  // --------------------------------------------------------------
  // Helper functions
  // --------------------------------------------------------------
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
