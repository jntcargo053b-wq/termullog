// lib/services/gps_lock_manager.dart
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'kalman_filter.dart';

enum GpsLockState { searching, acquiring, locked, stale }

class GpsLockData {
  final Position position;
  final String address;
  final String weather;
  final DateTime lockedAt;
  final double accuracy;
  final String quality; // Excellent, Good, Fair, Poor

  const GpsLockData({
    required this.position,
    required this.address,
    required this.weather,
    required this.lockedAt,
    required this.accuracy,
    required this.quality,
  });

  bool get isValid => DateTime.now().difference(lockedAt) < const Duration(minutes: 2);

  GpsLockData copyWith({String? address, String? weather}) => GpsLockData(
        position: position,
        address: address ?? this.address,
        weather: weather ?? this.weather,
        lockedAt: lockedAt,
        accuracy: accuracy,
        quality: quality,
      );
}

class GpsLockManager {
  GpsLockState _state = GpsLockState.searching;
  GpsLockData? _lockData;
  int _stationaryCount = 0;
  DateTime? _lastMovement;
  List<Position> _rawSamples = [];      // raw samples sebelum filter
  List<Position> _filteredSamples = []; // setelah Kalman filter

  // Kalman filters for lat and lon
  late KalmanFilter _kalmanLat;
  late KalmanFilter _kalmanLon;

  // Parameter optimal untuk stabilitas GPS real-world
  static const int _requiredSamples = 8;          // 8 sampel stabil
  static const double _maxMovementMeters = 4.0;   // toleransi loncatan 4 meter
  static const int _requiredStableSeconds = 5;    // diam 5 detik
  static const double _requiredAccuracyMeters = 10.0; // akurasi minimal 10m
  static const double _maxAllowedAccuracy = 35.0;     // tolak sample >35m
  static const int _maxSamples = 15;                  // simpan maks 15 sample

  GpsLockManager() {
    _kalmanLat = KalmanFilter(
      initialValue: 0.0,
      processNoise: 0.005,
      measurementNoise: 4.0,
    );
    _kalmanLon = KalmanFilter(
      initialValue: 0.0,
      processNoise: 0.005,
      measurementNoise: 4.0,
    );
  }

  GpsLockState get state => _state;
  GpsLockData? get lockData => _lockData;
  bool get isLocked => _state == GpsLockState.locked && (_lockData?.isValid ?? false);
  int get stationaryProgress => ((_stationaryCount / _requiredSamples) * 100).clamp(0, 100).toInt();

  /// Get quality string based on accuracy
  static String getQualityFromAccuracy(double acc) {
    if (acc <= 3) return 'Excellent';
    if (acc <= 8) return 'Good';
    if (acc <= 15) return 'Fair';
    return 'Poor';
  }

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

    // 3. Apply Kalman filter to smooth position
    final smoothedLat = _kalmanLat.update(newPos.latitude);
    final smoothedLon = _kalmanLon.update(newPos.longitude);
    final smoothedPosition = Position(
      latitude: smoothedLat,
      longitude: smoothedLon,
      accuracy: newPos.accuracy,
      altitude: newPos.altitude,
      heading: newPos.heading,
      speed: newPos.speed,
      speedAccuracy: newPos.speedAccuracy,
      timestamp: newPos.timestamp,
      altitudeAccuracy: newPos.altitudeAccuracy,
      headingAccuracy: newPos.headingAccuracy,
    );
    _rawSamples.add(newPos);
    _filteredSamples.add(smoothedPosition);
    if (_filteredSamples.length > _maxSamples) {
      _filteredSamples.removeAt(0);
    }

    // 4. Jika sudah locked, cek pergerakan atau perbaikan akurasi
    if (_state == GpsLockState.locked && _lockData != null) {
      final dist = _haversine(
        _lockData!.position.latitude, _lockData!.position.longitude,
        smoothedLat, smoothedLon,
      );
      if (dist > _maxMovementMeters * 1.5) {
        _unlock();
        if (kDebugMode) debugPrint('GPS Lock: UNLOCKED — moved ${dist.toStringAsFixed(1)}m');
      } else if (newPos.accuracy < _lockData!.accuracy - 2) {
        _lockData = GpsLockData(
          position: smoothedPosition,
          address: _lockData!.address,
          weather: _lockData!.weather,
          lockedAt: _lockData!.lockedAt,
          accuracy: newPos.accuracy,
          quality: getQualityFromAccuracy(newPos.accuracy),
        );
        if (kDebugMode) debugPrint('GPS Lock: accuracy improved to ${newPos.accuracy.toStringAsFixed(1)}m');
      }
      return false;
    }

    // 5. Belum locked: deteksi gerakan berdasarkan smoothed sample terakhir
    final lastSample = _filteredSamples.isNotEmpty ? _filteredSamples.last : null;
    if (lastSample != null) {
      final dist = _haversine(
        lastSample.latitude, lastSample.longitude,
        smoothedLat, smoothedLon,
      );
      if (dist > _maxMovementMeters) {
        _stationaryCount = 0;
        _filteredSamples.clear();
        _rawSamples.clear();
        _lastMovement = DateTime.now();
        _state = GpsLockState.acquiring;
        // Reset Kalman filters
        _kalmanLat.reset(smoothedLat);
        _kalmanLon.reset(smoothedLon);
        if (kDebugMode) debugPrint('GPS Lock: movement detected ${dist.toStringAsFixed(1)}m, resetting');
        return false;
      }
    }

    // 6. Inisialisasi waktu diam jika belum
    _lastMovement ??= DateTime.now();
    _stationaryCount = _filteredSamples.length;
    _state = GpsLockState.acquiring;

    // 7. Cek syarat lock
    final bool enoughSamples = _stationaryCount >= _requiredSamples;
    final bool goodAccuracy = newPos.accuracy <= _requiredAccuracyMeters;
    final bool stableForTime = _lastMovement != null &&
        DateTime.now().difference(_lastMovement!).inSeconds >= _requiredStableSeconds;

    if (enoughSamples && goodAccuracy && stableForTime) {
      // --- OUTLIER REJECTION (MAD-based) pada filtered samples ---
      final filteredForAvg = _rejectOutliers(_filteredSamples);
      if (filteredForAvg.length >= 3) {
        // Weighted average based on accuracy
        double totalWeight = 0;
        double weightedLat = 0;
        double weightedLon = 0;
        double bestAcc = double.infinity;
        for (final p in filteredForAvg) {
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
          accuracy: bestAcc,
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
          quality: getQualityFromAccuracy(bestAcc),
        );
        _state = GpsLockState.locked;
        if (kDebugMode) debugPrint('GPS Lock: LOCKED with accuracy ${bestAcc.toStringAsFixed(1)}m (${_filteredSamples.length} samples)');
        return true;
      }
    }
    return false;
  }

  /// Robust outlier rejection using Median Absolute Deviation (MAD)
  List<Position> _rejectOutliers(List<Position> samples) {
    if (samples.length < 4) return samples;

    // Compute centroid
    double sumLat = 0, sumLon = 0;
    for (final p in samples) {
      sumLat += p.latitude;
      sumLon += p.longitude;
    }
    final centerLat = sumLat / samples.length;
    final centerLon = sumLon / samples.length;

    // Compute distances to centroid
    final distances = samples.map((p) => _haversine(centerLat, centerLon, p.latitude, p.longitude)).toList();
    distances.sort();
    final medianDist = distances[distances.length ~/ 2];
    final mad = distances.map((d) => (d - medianDist).abs()).reduce((a,b) => a+b) / distances.length;
    final threshold = medianDist + 2.5 * mad; // 2.5 sigma

    // Filter outliers
    final List<Position> filtered = [];
    for (int i = 0; i < samples.length; i++) {
      final dist = _haversine(centerLat, centerLon, samples[i].latitude, samples[i].longitude);
      if (dist <= threshold) {
        filtered.add(samples[i]);
      }
    }
    return filtered.length >= 3 ? filtered : samples;
  }

  void updateLockAddress(String address, String weather) {
    if (_lockData != null) {
      _lockData = _lockData!.copyWith(address: address, weather: weather);
    }
  }

  void _unlock() {
    _state = GpsLockState.acquiring;
    _stationaryCount = 0;
    _filteredSamples.clear();
    _rawSamples.clear();
    _lastMovement = null;
  }

  void forceUnlock() {
    _state = GpsLockState.searching;
    _lockData = null;
    _stationaryCount = 0;
    _filteredSamples.clear();
    _rawSamples.clear();
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
