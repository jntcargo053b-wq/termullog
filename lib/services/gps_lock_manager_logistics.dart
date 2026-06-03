// lib/services/gps_lock_manager_logistics.dart
// GPS LOCK MANAGER - LOGISTICS EDITION
// Fitur:
// - Dual position strategy (rawPosition + deliveryPosition)
// - Confidence-based lock (bukan hanya accuracy)
// - Weighted cluster center (geocode friendly)
// - Adaptive unlock threshold (responsif 6-12m)
// - Hard cluster reset (8m)
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum LogisticsLockState { searching, stabilizing, locked }

class DeliveryLockData {
  final Position rawPosition;        // GPS mentah terbaik → untuk audit
  final Position deliveryPosition;   // posisi stabil untuk alamat (weighted centroid)
  final double accuracy;
  final double confidence;           // 0-1, confidence untuk lock
  final String lockQuality;          // 'excellent', 'good', 'fair', 'poor'
  final DateTime lockedAt;
  final int samplesUsed;             // jumlah sample yang dipakai untuk lock
  final double clusterRadius;        // radius cluster saat lock

  DeliveryLockData({
    required this.rawPosition,
    required this.deliveryPosition,
    required this.accuracy,
    required this.confidence,
    required this.lockQuality,
    required this.lockedAt,
    required this.samplesUsed,
    required this.clusterRadius,
  });

  DeliveryLockData copyWith({
    Position? rawPosition,
    Position? deliveryPosition,
    double? accuracy,
    double? confidence,
    String? lockQuality,
    DateTime? lockedAt,
    int? samplesUsed,
    double? clusterRadius,
  }) {
    return DeliveryLockData(
      rawPosition: rawPosition ?? this.rawPosition,
      deliveryPosition: deliveryPosition ?? this.deliveryPosition,
      accuracy: accuracy ?? this.accuracy,
      confidence: confidence ?? this.confidence,
      lockQuality: lockQuality ?? this.lockQuality,
      lockedAt: lockedAt ?? this.lockedAt,
      samplesUsed: samplesUsed ?? this.samplesUsed,
      clusterRadius: clusterRadius ?? this.clusterRadius,
    );
  }
}

class GpsLockManagerLogistics {
  LogisticsLockState _state = LogisticsLockState.searching;
  DeliveryLockData? _lockData;
  Position? _bestRaw;               // raw terbaik sepanjang masa
  final List<Position> _window = []; // rolling window untuk cluster
  int _stableCount = 0;
  double _stationaryProgress = 0.0;
  bool _isMoving = false;
  double _lastRawLat = 0.0, _lastRawLon = 0.0;
  DateTime? _lastMovementTime;

  // ==================== PARAMETER LOGISTICS ====================
  static const int _minSamplesForLock = 8;           // 8 sample stabil
  static const double _maxClusterRadiusMeters = 8.0; // radius cluster max 8m
  static const double _minConfidenceForLock = 0.85;  // minimal confidence 85%
  static const double _maxAccuracyForLock = 18.0;    // akurasi maksimal 18m

  // Adaptive unlock: base 6m, naik sesuai akurasi * 0.9, clamp 6-12m
  static const double _unlockBaseMeters = 6.0;
  static const double _unlockFactor = 0.9;
  static const double _unlockMin = 6.0;
  static const double _unlockMax = 12.0;

  // Hard cluster reset
  static const double _hardResetMeters = 8.0;        // jika bergerak >8m, reset

  // Movement detection
  static const double _moveThresholdBase = 4.0;
  static const double _stationaryTimeoutSeconds = 4.0;

  // Adaptive interval
  static const int _intervalSearching = 2000;
  static const int _intervalStabilizing = 1000;
  static const int _intervalLockedStationary = 1500;
  static const int _intervalLockedMoving = 700;

  // ==================== GETTERS ====================
  bool get isLocked => _state == LogisticsLockState.locked;
  DeliveryLockData? get lockData => _lockData;
  Position? get bestRaw => _bestRaw;
  bool get isMoving => _isMoving;
  double get stationaryProgress => _stationaryProgress;

  double get _moveThreshold {
    if (_bestRaw == null) return _moveThresholdBase;
    return max(_moveThresholdBase, _bestRaw!.accuracy * 0.3).clamp(3.0, 6.0);
  }

  double get _unlockThreshold {
    if (_lockData == null) return _unlockBaseMeters;
    final adaptive = _lockData!.accuracy * _unlockFactor;
    return adaptive.clamp(_unlockMin, _unlockMax);
  }

  int get currentIntervalMs {
    switch (_state) {
      case LogisticsLockState.searching:
        return _intervalSearching;
      case LogisticsLockState.stabilizing:
        return _intervalStabilizing;
      case LogisticsLockState.locked:
        return _isMoving ? _intervalLockedMoving : _intervalLockedStationary;
    }
  }

  // ==================== MAIN PROCESS ====================
  bool processSample(Position newPos) {
    // Update best raw
    if (_bestRaw == null || newPos.accuracy < _bestRaw!.accuracy) {
      _bestRaw = newPos;
      if (kDebugMode) debugPrint('GpsLockManagerLogistics: bestRaw acc=${newPos.accuracy.toStringAsFixed(1)}m');
    }

    // Hitung pergerakan
    double moved = 0.0;
    if (_lastRawLat != 0.0) {
      moved = _haversine(_lastRawLat, _lastRawLon, newPos.latitude, newPos.longitude);
    }

    // Update movement flag
    if (moved > _moveThreshold) {
      if (!_isMoving) {
        _isMoving = true;
        _lastMovementTime = DateTime.now();
        _stationaryProgress = 0.0;
        if (kDebugMode) debugPrint('GpsLockManagerLogistics: MOVING detected (${moved.toStringAsFixed(1)}m)');
      }
    } else {
      if (_isMoving) {
        _isMoving = false;
        _lastMovementTime = DateTime.now();
        if (kDebugMode) debugPrint('GpsLockManagerLogistics: STOPPED moving');
      } else if (_lastMovementTime != null) {
        final duration = DateTime.now().difference(_lastMovementTime!).inSeconds.toDouble();
        _stationaryProgress = (duration / _stationaryTimeoutSeconds).clamp(0.0, 1.0);
      }
    }

    // Simpan history raw
    _lastRawLat = newPos.latitude;
    _lastRawLon = newPos.longitude;

    // Proses berdasarkan state
    final result = (_state == LogisticsLockState.locked)
        ? _handleLocked(newPos, moved)
        : _handleAcquiring(newPos, moved);

    return result;
  }

  // ==================== HANDLE LOCKED ====================
  bool _handleLocked(Position newPos, double moved) {
    if (_lockData == null) return false;

    // Adaptive unlock: jika bergerak melebihi threshold
    if (moved > _unlockThreshold) {
      _softUnlock(moved);
      if (kDebugMode) {
        debugPrint('GpsLockManagerLogistics: UNLOCKED (moved ${moved.toStringAsFixed(1)}m > ${_unlockThreshold.toStringAsFixed(1)}m)');
      }
      return _handleAcquiring(newPos, moved);
    }

    // Update raw position jika akurasi lebih baik (untuk audit)
    if (newPos.accuracy < _lockData!.rawPosition.accuracy - 2.0) {
      _lockData = _lockData!.copyWith(
        rawPosition: newPos,
      );
      if (kDebugMode) debugPrint('GpsLockManagerLogistics: raw updated to acc=${newPos.accuracy.toStringAsFixed(1)}m');
    }

    return false;
  }

  // ==================== HANDLE ACQUIRING ====================
  bool _handleAcquiring(Position newPos, double moved) {
    // Hard cluster reset: jika bergerak >8m, reset window
    if (moved > _hardResetMeters) {
      _window.clear();
      _stableCount = 0;
      _state = LogisticsLockState.stabilizing;
      if (kDebugMode) debugPrint('GpsLockManagerLogistics: HARD RESET (moved ${moved.toStringAsFixed(1)}m)');
    }

    // Tambahkan sample ke window jika akurasi memenuhi
    if (newPos.accuracy <= _maxAccuracyForLock) {
      _window.add(newPos);
      if (_window.length > _minSamplesForLock) {
        _window.removeAt(0);
      }
    }

    // Hitung cluster radius dan confidence
    final clusterRadius = _computeClusterRadius();
    final confidence = _computeConfidence();

    _state = LogisticsLockState.stabilizing;
    _stableCount = _window.length;

    if (kDebugMode && _window.isNotEmpty) {
      debugPrint('GpsLockManagerLogistics: stabilizing ${_window.length}/$_minSamplesForLock '
          'radius=${clusterRadius.toStringAsFixed(1)}m conf=${confidence.toStringAsFixed(2)}');
    }

    // Lock condition
    final readyToLock = _window.length >= _minSamplesForLock &&
        clusterRadius <= _maxClusterRadiusMeters &&
        confidence >= _minConfidenceForLock &&
        newPos.accuracy <= _maxAccuracyForLock;

    if (readyToLock) {
      // Hitung weighted centroid (bobot = 1/σ²)
      double sumW = 0.0, sumLat = 0.0, sumLon = 0.0, sumAcc = 0.0;
      for (final s in _window) {
        final safeAcc = s.accuracy.clamp(3.0, 100.0);
        final w = 1.0 / (safeAcc * safeAcc);
        sumW += w;
        sumLat += s.latitude * w;
        sumLon += s.longitude * w;
        sumAcc += s.accuracy * w;
      }
      final centroidLat = sumLat / sumW;
      final centroidLon = sumLon / sumW;
      final avgAccuracy = sumAcc / sumW;

      final deliveryPosition = Position(
        latitude: centroidLat,
        longitude: centroidLon,
        accuracy: avgAccuracy,
        altitude: newPos.altitude,
        altitudeAccuracy: newPos.altitudeAccuracy,
        heading: newPos.heading,
        headingAccuracy: newPos.headingAccuracy,
        speed: newPos.speed,
        speedAccuracy: newPos.speedAccuracy,
        timestamp: DateTime.now(),
      );

      final bestRaw = _window.reduce((a, b) => a.accuracy < b.accuracy ? a : b);

      _lockData = DeliveryLockData(
        rawPosition: bestRaw,
        deliveryPosition: deliveryPosition,
        accuracy: avgAccuracy,
        confidence: confidence,
        lockQuality: _getLockQuality(confidence, avgAccuracy),
        lockedAt: DateTime.now(),
        samplesUsed: _window.length,
        clusterRadius: clusterRadius,
      );

      _state = LogisticsLockState.locked;
      _stationaryProgress = 1.0;

      if (kDebugMode) {
        debugPrint('GpsLockManagerLogistics: ✅ LOCKED | acc=${avgAccuracy.toStringAsFixed(1)}m '
            'conf=${(confidence * 100).toInt()}% samples=${_window.length} '
            'radius=${clusterRadius.toStringAsFixed(1)}m');
      }
      return true;
    }

    return false;
  }

  // ==================== SOFT UNLOCK ====================
  void _softUnlock([double movedDistance = 0.0]) {
    if (_state != LogisticsLockState.locked) return;
    _state = LogisticsLockState.stabilizing;
    // Jangan clear window agar bisa cepat lock ulang
    // Tapi kurangi sample lama jika perlu
    while (_window.length > _minSamplesForLock ~/ 2) {
      _window.removeAt(0);
    }
    _lockData = null;
    _isMoving = false;
    _stationaryProgress = 0.0;
    _lastMovementTime = null;
  }

  // ==================== RESET ====================
  void reset() {
    _state = LogisticsLockState.searching;
    _lockData = null;
    _bestRaw = null;
    _window.clear();
    _stableCount = 0;
    _isMoving = false;
    _stationaryProgress = 0.0;
    _lastMovementTime = null;
    _lastRawLat = 0.0;
    _lastRawLon = 0.0;
  }

  // ==================== HELPER ====================
  double _computeClusterRadius() {
    if (_window.length < 2) return double.infinity;

    double sumLat = 0, sumLon = 0;
    for (final p in _window) {
      sumLat += p.latitude;
      sumLon += p.longitude;
    }
    final centerLat = sumLat / _window.length;
    final centerLon = sumLon / _window.length;

    double maxDist = 0;
    for (final p in _window) {
      final dist = _haversine(centerLat, centerLon, p.latitude, p.longitude);
      if (dist > maxDist) maxDist = dist;
    }
    return maxDist;
  }

  double _computeConfidence() {
    if (_window.length < 2) return 0.0;

    // 1. Faktor jumlah sample (40% bobot)
    final sampleFactor = (_window.length / _minSamplesForLock).clamp(0.0, 1.0);

    // 2. Faktor cluster radius (40% bobot)
    final radius = _computeClusterRadius();
    final radiusFactor = (1.0 - (radius / _maxClusterRadiusMeters)).clamp(0.0, 1.0);

    // 3. Faktor akurasi rata-rata (20% bobot)
    double avgAcc = 0;
    for (final p in _window) avgAcc += p.accuracy;
    avgAcc /= _window.length;
    final accFactor = (1.0 - (avgAcc / _maxAccuracyForLock)).clamp(0.0, 1.0);

    // Weighted final confidence
    final confidence = (sampleFactor * 0.4) + (radiusFactor * 0.4) + (accFactor * 0.2);
    return confidence.clamp(0.0, 0.99);
  }

  String _getLockQuality(double confidence, double accuracy) {
    if (confidence >= 0.95 && accuracy <= 10) return 'excellent';
    if (confidence >= 0.85 && accuracy <= 18) return 'good';
    if (confidence >= 0.75 && accuracy <= 28) return 'fair';
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
