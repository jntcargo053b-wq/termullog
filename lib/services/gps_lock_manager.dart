// lib/services/gps_lock_manager.dart
// Final – kompatibel dengan camera_screen v4
// Fitur: stationary progress, adaptive interval, isMoving detection
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum GpsLockState { searching, acquiring, locked }

class LockData {
  final Position position;      // smoothed / filtered (untuk display)
  final Position rawPosition;   // raw terbaik (untuk geocoding & watermark)
  final double accuracy;
  final String quality;
  final double confidence;
  final DateTime lockedAt;
  final bool isFallbackLock;

  // stability = confidence, untuk UI camera_screen
  double get stability => confidence;

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
  int _stationaryCount = 0;
  DateTime? _lastMovementTime;
  double _stationaryProgress = 0.0;
  bool _isMovingFlag = false;
  double _lastRawLat = 0.0, _lastRawLon = 0.0;
  static const double _moveThreshold = 3.0;
  static const double _stationaryTimeoutSeconds = 4.0;

  // Parameter lock
  static const int _samplesBeforeLock = 8;
  static const double _lockAccuracyThreshold = 20.0;

  // Adaptive interval (ms)
  static const int _intervalSearching = 2500;
  static const int _intervalAcquiring = 1200;
  static const int _intervalLockedStationary = 1500;
  static const int _intervalLockedMoving = 700;

  bool get isLocked => _state == GpsLockState.locked;
  LockData? get lockData => _lockData;
  Position? get bestFix => _bestFix;

  double get stationaryProgress {
    if (_state == GpsLockState.searching) return 0.0;
    if (_state == GpsLockState.acquiring) {
      return (_stationaryCount / _samplesBeforeLock).clamp(0.0, 1.0);
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
    // Update all‑time best fix
    if (_bestFix == null || newPos.accuracy < _bestFix!.accuracy) {
      _bestFix = newPos;
      if (kDebugMode) debugPrint('GpsLockManager: bestFix acc=${newPos.accuracy.toStringAsFixed(1)}m');
    }

    // Movement detection (gunakan raw position terbaru)
    final moved = _haversine(_lastRawLat, _lastRawLon, newPos.latitude, newPos.longitude);
    if (_lastRawLat != 0.0 && moved > _moveThreshold) {
      _isMovingFlag = true;
      _lastMovementTime = DateTime.now();
      _stationaryProgress = 0.0;
    } else {
      // Update stationary progress jika tidak bergerak
      if (_isMovingFlag) {
        // baru berhenti, reset hitungan stationary
        _isMovingFlag = false;
        _lastMovementTime = DateTime.now();
      } else if (_lastMovementTime != null) {
        final stationaryDuration = DateTime.now().difference(_lastMovementTime!).inSeconds.toDouble();
        _stationaryProgress = (stationaryDuration / _stationaryTimeoutSeconds).clamp(0.0, 1.0);
      }
    }
    _lastRawLat = newPos.latitude;
    _lastRawLon = newPos.longitude;

    // Jika sudah locked, update data dan cek apakah perlu unlock
    if (_state == GpsLockState.locked) {
      if (_lockData != null) {
        final distFromLock = _haversine(
          _lockData!.rawPosition.latitude, _lockData!.rawPosition.longitude,
          newPos.latitude, newPos.longitude,
        );
        // Unlock jika bergerak terlalu jauh dari posisi lock
        if (distFromLock > _moveThreshold * 2.5) {
          _unlock();
          if (kDebugMode) debugPrint('GpsLockManager: UNLOCKED — moved ${distFromLock.toStringAsFixed(1)}m');
          // Setelah unlock, lanjutkan ke proses acquiring
          return _handleAcquiring(newPos);
        }
        // Update rawPosition jika akurasi membaik cukup
        if (newPos.accuracy < (_lockData!.accuracy - 2.0)) {
          _lockData = _lockData!.copyWith(
            position: newPos,
            rawPosition: newPos,
            accuracy: newPos.accuracy,
            quality: _getQualityFromAccuracy(newPos.accuracy),
            confidence: _computeConfidence(newPos.accuracy),
          );
          if (kDebugMode) debugPrint('GpsLockManager: improved acc=${newPos.accuracy.toStringAsFixed(1)}m');
        }
      }
      return false;
    }

    // Belum locked: hitung stationary count
    return _handleAcquiring(newPos);
  }

  bool _handleAcquiring(Position newPos) {
    // Cek apakah bergerak dari sample terbaik sebelumnya
    if (_bestFix != null && _bestFix != newPos) {
      final dist = _haversine(
        _bestFix!.latitude, _bestFix!.longitude,
        newPos.latitude, newPos.longitude,
      );
      if (dist > _moveThreshold) {
        _stationaryCount = 0;
        _state = GpsLockState.acquiring;
        return false;
      }
    }

    _stationaryCount++;
    _state = GpsLockState.acquiring;

    final readyToLock = _stationaryCount >= _samplesBeforeLock &&
        newPos.accuracy <= _lockAccuracyThreshold;

    if (readyToLock) {
      _lockData = LockData(
        position: newPos,
        rawPosition: _bestFix ?? newPos,
        accuracy: newPos.accuracy,
        quality: _getQualityFromAccuracy(newPos.accuracy),
        confidence: _computeConfidence(newPos.accuracy),
        lockedAt: DateTime.now(),
        isFallbackLock: false,
      );
      _state = GpsLockState.locked;
      _stationaryProgress = 1.0;
      if (kDebugMode) {
        debugPrint('GpsLockManager: LOCKED acc=${newPos.accuracy.toStringAsFixed(1)}m bestFix=${(_bestFix ?? newPos).accuracy.toStringAsFixed(1)}m');
      }
      return true;
    }
    return false;
  }

  void _unlock() {
    _state = GpsLockState.acquiring;
    _stationaryCount = 0;
    _lockData = null;
  }

  void reset() {
    _state = GpsLockState.searching;
    _lockData = null;
    _bestFix = null;
    _stationaryCount = 0;
    _isMovingFlag = false;
    _lastMovementTime = null;
    _stationaryProgress = 0.0;
    _lastRawLat = 0.0;
    _lastRawLon = 0.0;
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
