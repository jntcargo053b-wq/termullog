// lib/services/gps_lock_manager.dart
// FINAL – perbaikan lock menggunakan sample terbaik dalam window acquiring
// - _stationaryCount hanya di-increment untuk sample dengan accuracy <= threshold
// - Tidak menggunakan _bestFix global untuk lock
// - Update rawPosition setelah lock jika akurasi membaik
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum GpsLockState { searching, acquiring, locked }

class LockData {
  final Position position;      // smoothed / filtered (untuk display)
  final Position rawPosition;   // raw terbaik selama lock (untuk referensi)
  final double accuracy;
  final String quality;
  final double confidence;
  final DateTime lockedAt;
  final bool isFallbackLock;

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
  Position? _bestFix;              // all-time best accuracy (fallback display saja)
  final List<Position> _acquiringSamples = []; // sample akurat dalam fase acquiring saat ini
  int _stationaryCount = 0;
  double _stationaryProgress = 0.0;
  bool _isMovingFlag = false;
  double _prevRawLat = 0.0, _prevRawLon = 0.0;
  double _lastRawLat = 0.0, _lastRawLon = 0.0;
  DateTime? _lastMovementTime;

  // Parameter lock untuk aplikasi timestamp/logistik (stabil)
  static const int _samplesBeforeLock = 8;
  static const double _lockAccuracyThreshold = 20.0;
  static const double _moveThreshold = 5.0;            // 5m deteksi gerakan
  static const double _unlockDriftThreshold = 12.0;    // 12m drift baru unlock
  static const double _unlockAccuracyRequired = 15.0;  // dan akurasi ≤15m
  static const double _stationaryTimeoutSeconds = 4.0;

  // Interval adaptif (ms)
  static const int _intervalSearching = 1000;
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

  // --------------------------------------------------------------
  // Proses setiap sample GPS (dipanggil dari stream)
  // --------------------------------------------------------------
  bool processSample(Position newPos) {
    // Update all‑time best fix
    if (_bestFix == null || newPos.accuracy < _bestFix!.accuracy) {
      _bestFix = newPos;
      if (kDebugMode) debugPrint('GpsLockManager: bestFix acc=${newPos.accuracy.toStringAsFixed(1)}m');
    }

    // Deteksi pergerakan menggunakan previous raw position (hanya jika kedua sumbu tersedia)
    if (_prevRawLat != 0.0 && _prevRawLon != 0.0) {
      final moved = _haversine(_prevRawLat, _prevRawLon, newPos.latitude, newPos.longitude);
      if (moved > _moveThreshold) {
        _isMovingFlag = true;
        _lastMovementTime = DateTime.now();
        _stationaryProgress = 0.0;
        _stationaryCount = 0;
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

    // Simpan previous sebelum update last
    _prevRawLat = _lastRawLat;
    _prevRawLon = _lastRawLon;
    _lastRawLat = newPos.latitude;
    _lastRawLon = newPos.longitude;

    // Proses berdasarkan state
    final result = (_state == GpsLockState.locked)
        ? _handleLocked(newPos)
        : _handleAcquiring(newPos);

    return result;
  }

  // --------------------------------------------------------------
  // Handler saat sudah locked
  // --------------------------------------------------------------
  bool _handleLocked(Position newPos) {
    if (_lockData == null) return false;

    final distFromLock = _haversine(
      _lockData!.rawPosition.latitude, _lockData!.rawPosition.longitude,
      newPos.latitude, newPos.longitude,
    );

    // Hard unlock jika drift signifikan dengan akurasi bagus
    if (distFromLock > _unlockDriftThreshold && newPos.accuracy <= _unlockAccuracyRequired) {
      softUnlock();
      if (kDebugMode) debugPrint('GpsLockManager: HARD UNLOCK (drift ${distFromLock.toStringAsFixed(1)}m)');
      return _handleAcquiring(newPos);
    }

    // Update raw position jika akurasi membaik
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
    return false;
  }

  // --------------------------------------------------------------
  // Handler untuk searching atau acquiring
  // --------------------------------------------------------------
  bool _handleAcquiring(Position newPos) {
    // Deteksi gerakan menggunakan previous raw position (hanya jika kedua sumbu tersedia)
    if (_prevRawLat != 0.0 && _prevRawLon != 0.0) {
      final dist = _haversine(_prevRawLat, _prevRawLon, newPos.latitude, newPos.longitude);
      if (dist > _moveThreshold) {
        _stationaryCount = 0;
        _acquiringSamples.clear(); // buang sample lama – lokasi sudah berpindah
        _state = GpsLockState.acquiring;
        return false;
      }
    }

    // Hanya kumpulkan sample yang akurat dan increment stationaryCount jika sample memenuhi threshold
    if (newPos.accuracy <= _lockAccuracyThreshold) {
      _acquiringSamples.add(newPos);
      _stationaryCount++;
    }
    _state = GpsLockState.acquiring;

    final readyToLock = _stationaryCount >= _samplesBeforeLock &&
        newPos.accuracy <= _lockAccuracyThreshold;

    if (readyToLock) {
      // Gunakan sample terbaik dalam window acquiring ini, bukan _bestFix global
      final bestInWindow = _acquiringSamples.isNotEmpty
          ? _acquiringSamples.reduce((a, b) => a.accuracy < b.accuracy ? a : b)
          : newPos;
      _acquiringSamples.clear();
      _lockData = LockData(
        position: bestInWindow,
        rawPosition: bestInWindow,
        accuracy: bestInWindow.accuracy,
        quality: _getQualityFromAccuracy(bestInWindow.accuracy),
        confidence: _computeConfidence(bestInWindow.accuracy),
        lockedAt: DateTime.now(),
        isFallbackLock: false,
      );
      _state = GpsLockState.locked;
      _stationaryProgress = 1.0;
      if (kDebugMode) {
        debugPrint('GpsLockManager: LOCKED bestInWindow=${bestInWindow.accuracy.toStringAsFixed(1)}m');
      }
      return true;
    }
    return false;
  }

  // --------------------------------------------------------------
  // Soft unlock – hanya lepas lock, tidak menghapus bestFix / raw history
  // --------------------------------------------------------------
  void softUnlock() {
    if (_state != GpsLockState.locked) return;
    _state = GpsLockState.acquiring;
    _stationaryCount = 0;
    _acquiringSamples.clear();
    _lockData = null;
    _isMovingFlag = false;
    _stationaryProgress = 0.0;
    _lastMovementTime = null;
    if (kDebugMode) debugPrint('GpsLockManager: softUnlock');
  }

  // Reset total (hanya untuk inisialisasi atau error)
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
