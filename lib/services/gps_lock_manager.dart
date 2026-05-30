// lib/services/gps_lock_manager.dart
// PERBAIKAN LENGKAP:
// 1. rawPosition selalu diupdate setiap sample saat locked
// 2. Bootstrap accuracy diturunkan ke 15m
// 3. Required stable seconds diturunkan ke 2 detik
// 4. Logging detail

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum GpsLockState { searching, bootstrapping, locked }

class LockData {
  final Position position;      // posisi hybrid (terfilter) untuk tampilan
  final Position rawPosition;   // posisi GPS mentah terbaru → KRUSIAL untuk geocoding
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
  
  // Konfigurasi (diperketat)
  static const double _bootstrapMaxAccuracy = 15.0;   // dari 25.0
  static const double _requiredStableSeconds = 2.0;   // dari 4.0
  static const double _maxAllowedAccuracy = 35.0;     // tetap, tapi hanya untuk filter awal
  
  // Untuk bootstrap
  List<Position> _bootstrapSamples = [];
  DateTime? _bootstrapStart;
  
  // Untuk stationary detection (tidak diubah)
  DateTime? _lastMovementTime;
  double _stationaryProgress = 0.0;
  static const double _stationaryTimeoutSeconds = 3.0;
  
  bool get isLocked => _state == GpsLockState.locked;
  LockData? get lockData => _lockData;
  double get stationaryProgress => _stationaryProgress;
  
  /// Process raw GPS sample.
  /// Return true jika terjadi transisi ke locked (new lock).
  bool processSample(Position newPos) {
    // Filter awal: akurasi terlalu buruk? (tetap dipertahankan)
    if (newPos.accuracy > _maxAllowedAccuracy) {
      if (kDebugMode) {
        debugPrint('GpsLockManager: discard accuracy=${newPos.accuracy.toStringAsFixed(1)}m > $_maxAllowedAccuracy');
      }
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
    if (kDebugMode) {
      debugPrint('GpsLockManager: searching acc=${newPos.accuracy.toStringAsFixed(1)}m');
    }
    // Mulai bootstrap jika accuracy cukup baik
    if (newPos.accuracy <= _bootstrapMaxAccuracy) {
      _state = GpsLockState.bootstrapping;
      _bootstrapSamples = [newPos];
      _bootstrapStart = DateTime.now();
      if (kDebugMode) {
        debugPrint('GpsLockManager: bootstrapping started with acc=${newPos.accuracy.toStringAsFixed(1)}m');
      }
      return false;
    }
    return false;
  }
  
  bool _handleBootstrapping(Position newPos) {
    _bootstrapSamples.add(newPos);
    
    // Hitung durasi stabil
    final now = DateTime.now();
    final duration = now.difference(_bootstrapStart!).inSeconds.toDouble();
    
    // Cek apakah akurasi semua sample dalam batas wajar
    bool allGood = _bootstrapSamples.every((p) => p.accuracy <= _bootstrapMaxAccuracy);
    
    if (allGood && duration >= _requiredStableSeconds) {
      // Hitung rata-rata posisi untuk initial lock
      double avgLat = 0, avgLon = 0, avgAcc = 0;
      for (var p in _bootstrapSamples) {
        avgLat += p.latitude;
        avgLon += p.longitude;
        avgAcc += p.accuracy;
      }
      avgLat /= _bootstrapSamples.length;
      avgLon /= _bootstrapSamples.length;
      avgAcc /= _bootstrapSamples.length;
      
      // Buat posisi hybrid awal (sama dengan raw, karena belum ada filter)
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
        confidence: 1.0,
        lockedAt: DateTime.now(),
      );
      _state = GpsLockState.locked;
      _lastMovementTime = DateTime.now();
      _stationaryProgress = 0.0;
      
      if (kDebugMode) {
        debugPrint('GpsLockManager: LOCKED with acc=${avgAcc.toStringAsFixed(1)}m');
      }
      return true; // New lock
    }
    return false;
  }
  
  bool _handleLocked(Position newPos) {
    if (_lockData == null) return false;
    
    // 🔥 PERBAIKAN UTAMA: rawPosition selalu diupdate setiap sample
    final oldRaw = _lockData!.rawPosition;
    final newRaw = newPos;
    
    // Hitung jarak perpindahan raw
    final movedDistance = _haversine(
      oldRaw.latitude, oldRaw.longitude,
      newRaw.latitude, newRaw.longitude,
    );
    
    // Hitung peningkatan akurasi (gunakan threshold kecil)
    final accuracyImproved = newPos.accuracy < (_lockData!.accuracy - 1.0);
    
    // Update rawPosition SETIAP KALI
    // Buat hybrid position (filter sederhana: jika bergerak kecil, lakukan low-pass)
    Position newHybrid;
    if (movedDistance < 2.0) {
      // Low-pass filter: kombinasi posisi lama dan baru untuk mengurangi noise
      final alpha = 0.3;
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
      newHybrid = newPos; // pergerakan signifikan, langsung pakai raw
    }
    
    // Selalu update rawPosition, dan update hybrid jika accuracyImproved atau pergerakan signifikan
    LockData newLockData = _lockData!.copyWith(
      rawPosition: newRaw,   // 🔥 selalu update raw
    );
    
    if (accuracyImproved || movedDistance > 2.0) {
      newLockData = newLockData.copyWith(
        position: newHybrid,
        accuracy: newPos.accuracy,
        quality: _getQualityFromAccuracy(newPos.accuracy),
        confidence: 1.0,
        lockedAt: DateTime.now(),
      );
      
      if (kDebugMode) {
        debugPrint(
          'GpsLockManager: UPDATE raw & hybrid - '
          'acc=${newPos.accuracy.toStringAsFixed(1)}m '
          'dist=${movedDistance.toStringAsFixed(1)}m '
          'improved=$accuracyImproved'
        );
      }
    } else {
      if (kDebugMode) {
        debugPrint(
          'GpsLockManager: UPDATE raw only (acc=${newPos.accuracy.toStringAsFixed(1)}m, hybrid unchanged)'
        );
      }
    }
    
    _lockData = newLockData;
    
    // Update stationary progress
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
    
    return false; // tidak menghasilkan transisi lock baru
  }
  
  String _getQualityFromAccuracy(double acc) {
    if (acc <= 10) return 'excellent';
    if (acc <= 20) return 'good';
    if (acc <= 35) return 'fair';
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
    _bootstrapSamples = [];
    _bootstrapStart = null;
    _lastMovementTime = null;
    _stationaryProgress = 0.0;
  }
}
