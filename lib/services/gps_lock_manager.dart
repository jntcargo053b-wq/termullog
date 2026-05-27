// lib/services/gps_lock_manager.dart
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

enum GpsLockState { searching, acquiring, locked, stale }

class GpsLockData {
  final Position position;
  final String address;
  final String weather;
  final DateTime lockedAt;
  final double accuracy;

  const GpsLockData({
    required this.position,
    required this.address,
    required this.weather,
    required this.lockedAt,
    required this.accuracy,
  });

  bool get isValid => DateTime.now().difference(lockedAt) < const Duration(minutes: 2);

  GpsLockData copyWith({String? address, String? weather}) => GpsLockData(
        position: position,
        address: address ?? this.address,
        weather: weather ?? this.weather,
        lockedAt: lockedAt,
        accuracy: accuracy,
      );
}

class GpsLockManager {
  GpsLockState _state = GpsLockState.searching;
  GpsLockData? _lockData;
  int _stationaryCount = 0;
  DateTime? _lastMovement;
  List<Position> _samples = [];

  // Parameter optimal untuk stabilitas GPS real-world
  static const int _requiredSamples = 8;          // 8 sampel stabil
  static const double _maxMovementMeters = 4.0;   // toleransi loncatan 4 meter
  static const int _requiredStableSeconds = 5;    // diam 5 detik
  static const double _requiredAccuracyMeters = 10.0; // akurasi minimal 10m
  static const double _maxAllowedAccuracy = 35.0;     // tolak sample >35m
  static const int _maxSamples = 15;                  // simpan maks 15 sample

  GpsLockState get state => _state;
  GpsLockData? get lockData => _lockData;
  bool get isLocked => _state == GpsLockState.locked && (_lockData?.isValid ?? false);
  int get stationaryProgress => ((_stationaryCount / _requiredSamples) * 100).clamp(0, 100).toInt();

  /// Proses sample GPS, return true jika baru saja lock
  bool processSample(Position newPos, Position? lastSampleHint) {
    // 1. Tolak sample stale (>3 detik)
    final age = DateTime.now().difference(newPos.timestamp);
    if (age.inSeconds > 3) {
      if (kDebugMode) debugPrint('GPS Lock: stale sample ignored (age ${age.inSeconds}s)');
      return false;
    }

    // 2. Tolak akurasi buruk
    if (newPos.accuracy > _maxAllowedAccuracy) {
      if (kDebugMode) debugPrint('GPS Lock: reject accuracy ${newPos.accuracy}m');
      return false;
    }

    // 3. Jika sudah locked, cek pergerakan atau perbaikan akurasi
    if (_state == GpsLockState.locked && _lockData != null) {
      final dist = _haversine(
        _lockData!.position.latitude, _lockData!.position.longitude,
        newPos.latitude, newPos.longitude,
      );
      if (dist > _maxMovementMeters * 1.5) {
        _unlock();
        if (kDebugMode) debugPrint('GPS Lock: UNLOCKED — moved ${dist.toStringAsFixed(1)}m');
      } else if (newPos.accuracy < _lockData!.accuracy - 2) {
        _lockData = GpsLockData(
          position: newPos,
          address: _lockData!.address,
          weather: _lockData!.weather,
          lockedAt: _lockData!.lockedAt,
          accuracy: newPos.accuracy,
        );
        if (kDebugMode) debugPrint('GPS Lock: accuracy improved to ${newPos.accuracy.toStringAsFixed(1)}m');
      }
      return false;
    }

    // 4. Belum locked: deteksi gerakan berdasarkan sample terakhir yang tersimpan
    final lastSample = _samples.isNotEmpty ? _samples.last : null;
    if (lastSample != null) {
      final dist = _haversine(
        lastSample.latitude, lastSample.longitude,
        newPos.latitude, newPos.longitude,
      );
      if (dist > _maxMovementMeters) {
        _stationaryCount = 0;
        _samples.clear();
        _lastMovement = DateTime.now();
        _state = GpsLockState.acquiring;
        if (kDebugMode) debugPrint('GPS Lock: movement detected ${dist.toStringAsFixed(1)}m, resetting');
        return false;
      }
    }

    // 5. Inisialisasi waktu diam jika belum
    _lastMovement ??= DateTime.now();

    // 6. Simpan sample
    _samples.add(newPos);
    if (_samples.length > _maxSamples) _samples.removeAt(0);
    _stationaryCount = _samples.length;
    _state = GpsLockState.acquiring;

    // 7. Cek syarat lock
    final bool enoughSamples = _stationaryCount >= _requiredSamples;
    final bool goodAccuracy = newPos.accuracy <= _requiredAccuracyMeters;
    final bool stableForTime = _lastMovement != null &&
        DateTime.now().difference(_lastMovement!).inSeconds >= _requiredStableSeconds;

    if (enoughSamples && goodAccuracy && stableForTime) {
      // --- OUTLIER REJECTION (sebelum averaging) ---
      if (_samples.length >= 3) {
        final double centerLat = _samples.map((p) => p.latitude).reduce((a, b) => a + b) / _samples.length;
        final double centerLon = _samples.map((p) => p.longitude).reduce((a, b) => a + b) / _samples.length;
        final filtered = _samples.where((p) {
          final dist = _haversine(centerLat, centerLon, p.latitude, p.longitude);
          return dist <= 8.0; // buang sampel yang loncat >8 meter dari pusat
        }).toList();
        if (filtered.length >= 3) {
          _samples.clear();
          _samples.addAll(filtered);
        }
      }

      // --- WEIGHTED AVERAGE berdasarkan akurasi (1/accuracy) ---
      double totalWeight = 0;
      double weightedLat = 0;
      double weightedLon = 0;
      double bestAcc = double.infinity;
      for (final p in _samples) {
        final weight = 1 / p.accuracy.clamp(0.5, 100);
        totalWeight += weight;
        weightedLat += p.latitude * weight;
        weightedLon += p.longitude * weight;
        if (p.accuracy < bestAcc) bestAcc = p.accuracy;
      }
      final avgLat = weightedLat / totalWeight;
      final avgLon = weightedLon / totalWeight;

      final averagedPosition = Position(
        latitude: avgLat,
        longitude: avgLon,
        accuracy: bestAcc, // gunakan akurasi terbaik, bukan rata-rata
        altitude: newPos.altitude,
        heading: newPos.heading,
        speed: newPos.speed,
        speedAccuracy: newPos.speedAccuracy,
        timestamp: newPos.timestamp,
        altitudeAccuracy: newPos.altitudeAccuracy,
        headingAccuracy: newPos.headingAccuracy,
      );

      _lockData = GpsLockData(
        position: averagedPosition,
        address: '',
        weather: '',
        lockedAt: DateTime.now(),
        accuracy: bestAcc,
      );
      _state = GpsLockState.locked;
      if (kDebugMode) debugPrint('GPS Lock: LOCKED with accuracy ${bestAcc.toStringAsFixed(1)}m (weighted avg of ${_samples.length} samples)');
      return true;
    }
    return false;
  }

  void updateLockAddress(String address, String weather) {
    if (_lockData != null) {
      _lockData = _lockData!.copyWith(address: address, weather: weather);
    }
  }

  void _unlock() {
    _state = GpsLockState.acquiring;
    _stationaryCount = 0;
    _samples.clear();
    _lastMovement = null;
  }

  void forceUnlock() {
    _state = GpsLockState.searching;
    _lockData = null;
    _stationaryCount = 0;
    _samples.clear();
    _lastMovement = null;
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}
