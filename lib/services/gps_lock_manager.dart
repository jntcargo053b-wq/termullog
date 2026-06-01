// lib/services/gps_lock_manager.dart
// - _stationaryCount hanya di-increment untuk sample dengan accuracy <= threshold
// - Tidak menggunakan _bestFix global untuk lock
// - Update rawPosition setelah lock jika akurasi membaik
// - Kalman filter 4D untuk menghaluskan koordinat lock
// - Weighted centroid untuk lock accuracy
// - Force geocode saat pertama lock (via return value processSample)
// - Deteksi pergerakan tidak dihitung dua kali
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'kalman_filter_4d.dart';

enum GpsLockState { searching, acquiring, locked }

class LockData {
  final Position position;           // raw terbaik selama lock (untuk referensi)
  final Position rawPosition;        // raw terbaik selama lock (untuk referensi)
  final double accuracy;             // weighted centroid accuracy
  final String quality;
  final double confidence;
  final DateTime lockedAt;
  final bool isFallbackLock;

  /// Koordinat hasil Kalman filter — lebih halus dari raw GPS.
  /// Gunakan ini untuk display koordinat di UI.
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
  Position? _bestFix;              // all-time best accuracy (fallback display saja)
  final List<Position> _acquiringSamples = []; // sample akurat dalam fase acquiring saat ini
  int _stationaryCount = 0;
  double _stationaryProgress = 0.0;
  bool _isMovingFlag = false;
  double _prevRawLat = 0.0, _prevRawLon = 0.0;
  double _lastRawLat = 0.0, _lastRawLon = 0.0;
  DateTime? _lastMovementTime;

  // Kalman filter 4D — aktif selama fase acquiring
  final KalmanFilter4D _kalman = KalmanFilter4D();
  double? _kalmanOriginLat, _kalmanOriginLon;
  DateTime? _kalmanLastUpdate;

  // Parameter lock untuk aplikasi timestamp/logistik (stabil)
  static const int _samplesBeforeLock = 5;
  static const double _lockAccuracyThreshold = 20.0;
  static const double _moveThreshold = 3.0;            // 3m deteksi gerakan (lebih sensitif)
  static const double _unlockDriftThreshold = 12.0;    // 12m drift baru unlock
  static const double _unlockAccuracyRequired = 15.0;  // dan akurasi ≤15m
  static const double _stationaryTimeoutSeconds = 4.0;

  // Interval adaptif (ms)
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
  // Mengembalikan true saat baru saja terjadi lock (untuk trigger geocode).
  // --------------------------------------------------------------
  bool processSample(Position newPos) {
    // Update all‑time best fix
    if (_bestFix == null || newPos.accuracy < _bestFix!.accuracy) {
      _bestFix = newPos;
      if (kDebugMode) debugPrint('GpsLockManager: bestFix acc=${newPos.accuracy.toStringAsFixed(1)}m');
    }

    // Hitung jarak dari previous — dilakukan SEKALI di sini, dipakai oleh semua handler.
    double movedDistance = 0.0;
    if (_prevRawLat != 0.0 && _prevRawLon != 0.0) {
      movedDistance = _haversine(_prevRawLat, _prevRawLon, newPos.latitude, newPos.longitude);
    }

    // Update moving flag berdasarkan movedDistance
    if (_prevRawLat != 0.0) {
      if (movedDistance > _moveThreshold) {
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

    // Proses berdasarkan state — pass movedDistance agar tidak dihitung ulang
    return (_state == GpsLockState.locked)
        ? _handleLocked(newPos)
        : _handleAcquiring(newPos, movedDistance);
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
      return _handleAcquiring(newPos, distFromLock);
    }

    // Update raw position jika akurasi membaik (tetap pertahankan smoothed coords dari Kalman)
    if (newPos.accuracy < (_lockData!.accuracy - 2.0)) {
      _lockData = _lockData!.copyWith(
        position: newPos,
        rawPosition: newPos,
        accuracy: newPos.accuracy,
        quality: _getQualityFromAccuracy(newPos.accuracy),
        confidence: _computeConfidence(newPos.accuracy),
        // smoothedLatitude/Longitude tetap dari lock awal — tidak di-override
      );
      if (kDebugMode) debugPrint('GpsLockManager: improved acc=${newPos.accuracy.toStringAsFixed(1)}m');
    }
    return false;
  }

  // --------------------------------------------------------------
  // Handler untuk searching atau acquiring
  // movedDistance sudah dihitung di processSample — tidak dihitung ulang.
  // --------------------------------------------------------------
  bool _handleAcquiring(Position newPos, double movedDistance) {
    // Jika bergerak: reset window, buang state Kalman
    if (_prevRawLat != 0.0 && movedDistance > _moveThreshold) {
      _stationaryCount = 0;
      _acquiringSamples.clear();
      _resetKalman();
      _state = GpsLockState.acquiring;
      return false;
    }

    // Hanya kumpulkan sample yang akurat DAN koordinat tidak bergeser > 3m dari sample sebelumnya.
    if (newPos.accuracy <= _lockAccuracyThreshold) {
      final isCoordStable = _acquiringSamples.isEmpty ||
          _haversine(
            _acquiringSamples.last.latitude, _acquiringSamples.last.longitude,
            newPos.latitude, newPos.longitude,
          ) < 3.0;

      if (isCoordStable) {
        _acquiringSamples.add(newPos);
        _stationaryCount++;

        // ── Saran 1: update Kalman filter ──────────────────────────────────
        _initKalmanIfNeeded(newPos);
        final dt = _kalmanLastUpdate != null
            ? DateTime.now().difference(_kalmanLastUpdate!).inMilliseconds / 1000.0
            : 0.8;
        _kalmanLastUpdate = DateTime.now();

        const degToMeter = 111320.0;
        final east = (newPos.longitude - _kalmanOriginLon!) *
            degToMeter * cos(_kalmanOriginLat! * pi / 180.0);
        final north = (newPos.latitude - _kalmanOriginLat!) * degToMeter;
        // R = variance GPS (accuracy²), clamp agar tidak terlalu kecil
        final R = (newPos.accuracy * newPos.accuracy).clamp(4.0, 2500.0);
        _kalman.predictAndUpdate(dt.clamp(0.1, 5.0), east, north, R);

      } else {
        // Koordinat masih loncat — reset window + Kalman mulai dari posisi baru
        _acquiringSamples
          ..clear()
          ..add(newPos);
        _stationaryCount = 1;
        _resetKalman();
        _initKalmanIfNeeded(newPos);
        if (kDebugMode) debugPrint('GpsLockManager: coord jump reset (_stationaryCount=1)');
      }
    }
    _state = GpsLockState.acquiring;

    final readyToLock = _stationaryCount >= _samplesBeforeLock &&
        newPos.accuracy <= _lockAccuracyThreshold;

    if (readyToLock) {
      final best = _acquiringSamples.isNotEmpty
          ? _acquiringSamples.reduce((a, b) => a.accuracy < b.accuracy ? a : b)
          : newPos;

      // ── Saran 2: weighted centroid accuracy ────────────────────────────────
      // Bobot = 1/accuracy² — sample dengan akurasi lebih baik mendapat bobot lebih besar
      double sumW = 0.0, sumAcc = 0.0;
      for (final s in _acquiringSamples) {
        final w = 1.0 / (s.accuracy * s.accuracy);
        sumW += w;
        sumAcc += s.accuracy * w;
      }
      final lockedAccuracy = sumW > 0 ? sumAcc / sumW : best.accuracy;

      // ── Saran 1: koordinat dari Kalman filter ──────────────────────────────
      double smoothedLat = best.latitude;
      double smoothedLon = best.longitude;
      if (_kalmanOriginLat != null && _kalman.isHealthy()) {
        final (state, _) = _kalman.predict(0.0); // snapshot tanpa advance waktu
        const degToMeter = 111320.0;
        smoothedLat = _kalmanOriginLat! + state[1] / degToMeter;
        smoothedLon = _kalmanOriginLon! +
            state[0] / (degToMeter * cos(_kalmanOriginLat! * pi / 180.0));
        if (kDebugMode) {
          final rawDist = _haversine(best.latitude, best.longitude, smoothedLat, smoothedLon);
          debugPrint('GpsLockManager: Kalman smoothing offset=${rawDist.toStringAsFixed(1)}m');
        }
      }

      _acquiringSamples.clear();
      _lockData = LockData(
        position: best,
        rawPosition: best,
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
            'smoothed=(${smoothedLat.toStringAsFixed(6)}, ${smoothedLon.toStringAsFixed(6)})');
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
    _resetKalman();
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
