// lib/services/gps_lock_manager.dart
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'kalman_filter_4d.dart';

enum GpsLockState { searching, acquiring, locked, stale }

class LocalPoint {
  final double east;
  final double north;
  LocalPoint(this.east, this.north);
}

class GlobalPoint {
  final double lat;
  final double lon;
  GlobalPoint(this.lat, this.lon);
}

class GpsLockData {
  final Position position;
  final String address;
  final String weather;
  final DateTime lockedAt;
  final double accuracy;
  final String quality;
  final double confidence;

  const GpsLockData({
    required this.position,
    required this.address,
    required this.weather,
    required this.lockedAt,
    required this.accuracy,
    required this.quality,
    required this.confidence,
  });

  bool get isValid => DateTime.now().difference(lockedAt) < const Duration(minutes: 2);

  GpsLockData copyWith({
    Position? position,
    String? address,
    String? weather,
    DateTime? lockedAt,
    double? accuracy,
    String? quality,
    double? confidence,
  }) {
    return GpsLockData(
      position: position ?? this.position,
      address: address ?? this.address,
      weather: weather ?? this.weather,
      lockedAt: lockedAt ?? this.lockedAt,
      accuracy: accuracy ?? this.accuracy,
      quality: quality ?? this.quality,
      confidence: confidence ?? this.confidence,
    );
  }
}

class GpsLockManager {
  GpsLockState _state = GpsLockState.searching;
  GpsLockData? _lockData;
  int _stationaryCount = 0;
  DateTime? _lastMovement;
  List<Position> _filteredSamples = [];

  // ENU reference
  double? _refLat, _refLon;
  KalmanFilter4D? _kalman;
  DateTime? _lastTimestamp;
  double? _lastFilteredEast, _lastFilteredNorth;

  // Stationary time (seconds) – menggunakan akumulasi dt (fix #4)
  double _stableSeconds = 0.0;
  static const double _requiredStableSeconds = 6.0;

  // Heading smoothing & history
  double _lastHeading = 0.0;
  final List<double> _headingHistory = [];

  // Innovation RMS tracking – berdasarkan magnitude (fix #2)
  final List<double> _innovationHistory = [];
  double _innovationRms = 1.0;
  static const int _innovationWindow = 10;

  // Lock parameters (lebih stabil)
  static const int _requiredSamples = 8;
  static const double _requiredAccuracyMeters = 10.0;
  static const double _maxAllowedAccuracy = 35.0;
  static const int _maxSamples = 15;
  static const double _lockCovarianceThreshold = 25.0;
  static const double _lockVelCovThreshold = 4.0;

  // Movement detection
  static const double _maxMovementMeters = 4.0;

  // Speed sanity
  static const double _maxSpeedMps = 60.0;

  // ENU re-centering (fix #9)
  static const double _maxRefDistance = 500.0;

  // Warmup (detik)
  DateTime? _sessionStart;

  GpsLockManager() {
    _sessionStart = DateTime.now();
  }

  GpsLockState get state => _state;
  GpsLockData? get lockData => _lockData;
  bool get isLocked => _state == GpsLockState.locked && (_lockData?.isValid ?? false);
  int get stationaryProgress {
    // Progress berbasis waktu, bukan count
    return ((_stableSeconds / _requiredStableSeconds) * 100).clamp(0, 100).toInt();
  }
  double get confidence => _lockData?.confidence ?? 0.0;

  static String getQualityFromAccuracy(double acc) {
    if (acc <= 3) return 'Excellent';
    if (acc <= 8) return 'Good';
    if (acc <= 15) return 'Fair';
    return 'Poor';
  }

  // --- ENU helpers ---
  LocalPoint? _toLocal(double lat, double lon) {
    if (_refLat == null || _refLon == null) return null;
    const double R = 6371000.0;
    final double dLat = (lat - _refLat!) * pi / 180.0;
    final double dLon = (lon - _refLon!) * pi / 180.0;
    final double east = dLon * cos(_refLat! * pi / 180.0) * R;
    final double north = dLat * R;
    return LocalPoint(east, north);
  }

  GlobalPoint _toGlobal(double east, double north) {
    const double R = 6371000.0;
    final double dLat = north / R;
    final double dLon = east / (R * cos(_refLat! * pi / 180.0));
    return GlobalPoint(_refLat! + dLat * 180.0 / pi, _refLon! + dLon * 180.0 / pi);
  }

  // --- Heading smoothing (circular) ---
  double _angleDiff(double a, double b) {
    double d = (a - b).abs() % 360.0;
    return d > 180.0 ? 360.0 - d : d;
  }

  void _updateHeading(double rawHeading, double speedMps) {
    if (speedMps < 2.8) return;
    if (!rawHeading.isFinite || rawHeading < 0 || rawHeading > 360) return;
    if (_headingHistory.isNotEmpty && _angleDiff(rawHeading, _lastHeading) > 90 && speedMps < 5.0) return;

    _headingHistory.add(rawHeading);
    if (_headingHistory.length > 5) _headingHistory.removeAt(0);
    double sinSum = 0, cosSum = 0;
    for (final h in _headingHistory) {
      final rad = h * pi / 180.0;
      sinSum += sin(rad);
      cosSum += cos(rad);
    }
    _lastHeading = atan2(sinSum, cosSum) * 180.0 / pi;
    if (_lastHeading < 0) _lastHeading += 360;
  }

  // Heading accuracy berdasarkan circular variance (fix #7)
  double _getHeadingAccuracy() {
    if (_headingHistory.length < 2) return 20.0;
    double sinSum = 0, cosSum = 0;
    for (final h in _headingHistory) {
      final rad = h * pi / 180.0;
      sinSum += sin(rad);
      cosSum += cos(rad);
    }
    final r = sqrt(sinSum * sinSum + cosSum * cosSum) / _headingHistory.length;
    final circularVar = 1.0 - r;
    return (circularVar * 30.0).clamp(2.0, 30.0);
  }

  // --- Innovation RMS berdasarkan magnitude, bukan mahal2 (fix #2) ---
  void _updateInnovationRms(double innovationNorm) {
    _innovationHistory.add(innovationNorm);
    if (_innovationHistory.length > _innovationWindow) _innovationHistory.removeAt(0);
    double sumSq = 0;
    for (final val in _innovationHistory) sumSq += val * val;
    _innovationRms = sqrt(sumSq / _innovationHistory.length);
    // Floor lebih rendah (fix #3)
    if (_innovationRms < 0.1) _innovationRms = 0.1;
  }

  // --- Confidence score (exponential) ---
  double _computeConfidence(double varPosX, double varPosY, double rms) {
    final posStd = sqrt((varPosX + varPosY) / 2.0);
    final posScore = exp(-posStd / 8.0);
    final innovationScore = exp(-rms / 5.0);
    return (posScore * innovationScore * 100.0).clamp(0.0, 100.0);
  }

  // --- Health check lengkap (fix #10) ---
  bool _isFilterHealthy() {
    if (_kalman == null) return true;
   // final P = _kalman!._P; // asumsi kita akses private, perlu getter. Untuk sementara kita buat public method di Kalman.
    // Untuk mengakses, kita akan panggil method isHealthy() dari Kalman. Asumsikan sudah ada.
    return _kalman!.isHealthy();
  }

  // --- Haversine distance ---
  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) * sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  // --- Proses sample utama (dengan semua perbaikan) ---
  bool processSample(Position newPos) {
    // Warm-up 3 detik
    if (_sessionStart != null && DateTime.now().difference(_sessionStart!).inSeconds < 3) {
      return false;
    }

    // Validasi dasar
    final timestamp = newPos.timestamp ?? DateTime.now();
    final age = DateTime.now().difference(timestamp);
    if (age.inSeconds > 3) return false;
    if (newPos.accuracy > _maxAllowedAccuracy) return false;
    if (newPos.speed.isFinite && newPos.speed > _maxSpeedMps) return false;

    // Stale detection: jika tidak ada data >5 detik, reset
    if (_lastTimestamp != null && DateTime.now().difference(_lastTimestamp!).inSeconds > 5) {
      _state = GpsLockState.searching;
      _stableSeconds = 0.0;
      _filteredSamples.clear();
      _kalman = KalmanFilter4D();
      _lastFilteredEast = null;
      _lastFilteredNorth = null;
      _refLat = newPos.latitude;
      _refLon = newPos.longitude;
      _kalman?.reset(0.0, 0.0);
      _lastTimestamp = timestamp;
      _innovationHistory.clear();
      _innovationRms = 1.0;
      _headingHistory.clear();
    }

    // Inisialisasi referensi dan Kalman
    if (_refLat == null && newPos.accuracy <= 20) {
      _refLat = newPos.latitude;
      _refLon = newPos.longitude;
      _kalman = KalmanFilter4D();
      _lastTimestamp = timestamp;
      _lastFilteredEast = null;
      _lastFilteredNorth = null;
      _stableSeconds = 0.0;
    }
    if (_refLat == null) return false;

    // dt dengan guard negative/zero
    final rawDt = timestamp.difference(_lastTimestamp!).inMicroseconds / 1e6;
    double dt;
    if (!rawDt.isFinite || rawDt <= 0) {
      dt = 0.1;
    } else {
      dt = rawDt.clamp(0.01, 1.5);
    }
    _lastTimestamp = timestamp;

    // ENU conversion
    final local = _toLocal(newPos.latitude, newPos.longitude);
    if (local == null) return false;

    // Kalman prediction
    final (predicted, Ppred) = _kalman!.predict(dt);
    if (!_isFilterHealthy()) {
      _kalman = KalmanFilter4D();
      _stableSeconds = 0.0;
      return false;
    }

    // Innovation components
    final de = local.east - predicted[0];
    final dn = local.north - predicted[1];
    final innovationNorm = sqrt(de * de + dn * dn);

    // Hitung R dengan satuan yang benar (variance) – fix #1
    final double sigma = (newPos.accuracy * (1.0 + _innovationRms * 0.3)).clamp(1.0, 50.0);
    final double R = sigma * sigma; // variance
    final Sx = Ppred[0][0] + R;
    final Sy = Ppred[1][1] + R;
    final mahal2 = (de * de) / Sx + (dn * dn) / Sy;

    // Innovation RMS update hanya jika bukan outlier (fix #2)
    final double mahalThreshold = _state == GpsLockState.locked ? 12.0 : 20.0;
    final bool isOutlier = mahal2 > mahalThreshold;
    if (!isOutlier) {
      _updateInnovationRms(innovationNorm);
    }

    if (isOutlier) {
      if (kDebugMode) debugPrint('GPS Lock: outlier mahal2=$mahal2');
      return false;
    }

    // Kalman update
    final (updated, Pupd) = _kalman!.update(de, dn, R, Ppred);
    if (!_isFilterHealthy()) {
      _kalman = KalmanFilter4D();
      _stableSeconds = 0.0;
      return false;
    }

    // Speed & movement delta
    final speedMps = sqrt(updated[2] * updated[2] + updated[3] * updated[3]);
    double movedDistance = 0.0;
    if (_lastFilteredEast != null && _lastFilteredNorth != null) {
      final dx = updated[0] - _lastFilteredEast!;
      final dy = updated[1] - _lastFilteredNorth!;
      movedDistance = sqrt(dx * dx + dy * dy);
    }
    _lastFilteredEast = updated[0];
    _lastFilteredNorth = updated[1];

    // Movement detection dengan innovation gating (fix #5)
    final bool isMoving = ((speedMps > 2.0 && movedDistance > 1.0) || movedDistance > 3.0) &&
        _innovationRms > 1.2;

    // Update stationary time (dt accumulation) – fix #4
    if (!isMoving && mahal2 < 2.5) {
      _stableSeconds += dt;
    } else {
      _stableSeconds = 0.0;
    }

    // Update heading dan reset history jika bergerak (fix #6)
    final rawHeading = (newPos.heading.isFinite && newPos.heading >= 0 && newPos.heading <= 360)
        ? newPos.heading
        : _lastHeading;
    if (isMoving) {
      _headingHistory.clear();
      _lastHeading = rawHeading;
    } else {
      _updateHeading(rawHeading, speedMps);
    }

    // Clear filtered samples jika bergerak (fix #8)
    if (isMoving) {
      _filteredSamples.clear();
    }

    // Konversi smoothed ENU ke lat/lon
    final smoothedLatLon = _toGlobal(updated[0], updated[1]);
    final smoothedPosition = Position(
      latitude: smoothedLatLon.lat,
      longitude: smoothedLatLon.lon,
      accuracy: newPos.accuracy,
      altitude: newPos.altitude,
      heading: _lastHeading,
      speed: speedMps,
      speedAccuracy: newPos.speedAccuracy,
      timestamp: timestamp,
      altitudeAccuracy: newPos.altitudeAccuracy,
      headingAccuracy: _getHeadingAccuracy(), // fix #7
      floor: newPos.floor,
      isMocked: newPos.isMocked,
    );

    _filteredSamples.add(smoothedPosition);
    if (_filteredSamples.length > _maxSamples) _filteredSamples.removeAt(0);

    // Update stationary counter untuk UI (berdasarkan waktu)
    _stationaryCount = (_stableSeconds / 1.0).round().clamp(0, _requiredStableSeconds.toInt());

    // Jika sudah locked, cek pergerakan
    if (_state == GpsLockState.locked) {
      if (isMoving) {
        _state = GpsLockState.acquiring;
        _kalman!.inflateCovariance(3.0);
        _stableSeconds = 0.0;
        if (kDebugMode) debugPrint('GPS Lock: movement detected, re-acquiring');
        return false;
      }
      if (_lockData != null && newPos.accuracy < _lockData!.accuracy - 2) {
        final conf = _computeConfidence(Pupd[0][0], Pupd[1][1], _innovationRms);
        _lockData = _lockData!.copyWith(
          position: smoothedPosition,
          accuracy: newPos.accuracy,
          quality: getQualityFromAccuracy(newPos.accuracy),
          confidence: conf,
        );
      }
      if (_lockData != null && !_lockData!.isValid) {
        _state = GpsLockState.stale;
        _lockData = null;
        _filteredSamples.clear();
        _stableSeconds = 0.0;
        if (kDebugMode) debugPrint('GPS Lock: stale lock expired');
      }
      return false;
    }

    // Acquiring state
    _state = GpsLockState.acquiring;
    final enoughStableTime = _stableSeconds >= _requiredStableSeconds;
    final goodAccuracy = newPos.accuracy <= _requiredAccuracyMeters;
    final covConverged = (Pupd[0][0] < _lockCovarianceThreshold && Pupd[1][1] < _lockCovarianceThreshold);
    final velConverged = (Pupd[2][2] < _lockVelCovThreshold && Pupd[3][3] < _lockVelCovThreshold);
    final enoughSamples = _filteredSamples.length >= _requiredSamples;

    if (enoughSamples && goodAccuracy && covConverged && velConverged && enoughStableTime) {
      // Validasi varians akhir
      if (_filteredSamples.length >= 3) {
        final meters = <(double e, double n)>[];
        for (final p in _filteredSamples) {
          final loc = _toLocal(p.latitude, p.longitude)!;
          meters.add((loc.east, loc.north));
        }
        double sumE = 0, sumN = 0;
        for (final m in meters) {
          sumE += m.$1;
          sumN += m.$2;
        }
        final meanE = sumE / meters.length;
        final meanN = sumN / meters.length;
        double varE = 0, varN = 0;
        for (final m in meters) {
          varE += (m.$1 - meanE) * (m.$1 - meanE);
          varN += (m.$2 - meanN) * (m.$2 - meanN);
        }
        varE /= meters.length;
        varN /= meters.length;
        if (varE > 100 || varN > 100) {
          if (kDebugMode) debugPrint('GPS Lock: high variance, retry');
          return false;
        }
      }

      // Weighted average (weight = 1/accuracy²)
      double totalWeight = 0, weightedLat = 0, weightedLon = 0, bestAcc = double.infinity;
      for (final p in _filteredSamples) {
        final acc = p.accuracy.clamp(3.0, 30.0);
        final weight = 1.0 / (acc * acc);
        totalWeight += weight;
        weightedLat += p.latitude * weight;
        weightedLon += p.longitude * weight;
        if (p.accuracy < bestAcc) bestAcc = p.accuracy;
      }
      if (totalWeight <= 0) return false;
      final avgLat = weightedLat / totalWeight;
      final avgLon = weightedLon / totalWeight;

      final lockedPosition = Position(
        latitude: avgLat,
        longitude: avgLon,
        accuracy: bestAcc,
        altitude: newPos.altitude,
        heading: _lastHeading,
        speed: speedMps,
        speedAccuracy: newPos.speedAccuracy,
        timestamp: timestamp,
        altitudeAccuracy: newPos.altitudeAccuracy,
        headingAccuracy: _getHeadingAccuracy(),
        floor: newPos.floor,
        isMocked: newPos.isMocked,
      );

      final confidence = _computeConfidence(Pupd[0][0], Pupd[1][1], _innovationRms);
      _lockData = GpsLockData(
        position: lockedPosition,
        address: '',
        weather: '',
        lockedAt: DateTime.now(),
        accuracy: bestAcc,
        quality: getQualityFromAccuracy(bestAcc),
        confidence: confidence,
      );
      _state = GpsLockState.locked;
      if (kDebugMode) debugPrint('GPS Lock: LOCKED accuracy=${bestAcc.toStringAsFixed(1)}m, confidence=${confidence.toStringAsFixed(0)}%');
      return true;
    }

    // ENU re-centering (fix #9)
    if (_refLat != null) {
      final distFromRef = _haversine(_refLat!, _refLon!, newPos.latitude, newPos.longitude);
      if (distFromRef > _maxRefDistance) {
        _refLat = newPos.latitude;
        _refLon = newPos.longitude;
        _kalman?.reset(0.0, 0.0);
        _lastFilteredEast = _lastFilteredNorth = null;
        _stableSeconds = 0.0;
        if (kDebugMode) debugPrint('GPS Lock: re-centering ENU reference');
      }
    }

    return false;
  }

  void updateLockAddress(String address, String weather) {
    if (_lockData != null) {
      _lockData = _lockData!.copyWith(address: address, weather: weather);
    }
  }

  void forceUnlock() {
    _state = GpsLockState.searching;
    _lockData = null;
    _stationaryCount = 0;
    _filteredSamples.clear();
    _refLat = _refLon = null;
    _kalman = null;
    _lastTimestamp = null;
    _lastFilteredEast = _lastFilteredNorth = null;
    _lastMovement = null;
    _innovationHistory.clear();
    _headingHistory.clear();
    _innovationRms = 1.0;
    _lastHeading = 0.0;
    _stableSeconds = 0.0;
    _sessionStart = DateTime.now();
  }
}
