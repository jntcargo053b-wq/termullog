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
  List<Position> _filteredSamples = [];

  // ENU reference
  double? _refLat, _refLon;
  KalmanFilter4D? _kalman;
  DateTime? _lastTimestamp;
  double? _lastFilteredEast, _lastFilteredNorth;

  // Stationary time (seconds)
  double _stableSeconds = 0.0;
  static const double _defaultRequiredStableSeconds = 6.0;
  double _requiredStableSeconds = _defaultRequiredStableSeconds;

  // Smoothed accuracy (low-pass filter)
  double _smoothedAccuracy = 999.0;
  double _smoothedAltitude = 0.0;
  bool _hasAltitude = false;

  // Heading from Kalman velocity (more accurate than GPS heading)
  double _lastHeading = 0.0;

  // Innovation RMS tracking (updated after outlier check)
  final List<double> _innovationHistory = [];
  double _innovationRms = 1.0;
  static const int _innovationWindow = 10;

  // Lock parameters (adaptive)
  static const double _requiredBaseAccuracyMeters = 15.0;
  static const double _maxAllowedAccuracy = 35.0;
  static const int _maxSamples = 15;
  static const double _lockCovarianceThreshold = 25.0;
  static const double _lockVelCovThreshold = 4.0;

  // Speed sanity
  static const double _maxSpeedMps = 60.0;

  // ENU re-centering (reduced to 250m)
  static const double _maxRefDistance = 250.0;

  // Session start for warm-up (5 seconds)
  DateTime? _sessionStart;

  // Stale detection
  static const int _maxNoDataSeconds = 5;

  // Consistency counter
  int _consistentGoodSamples = 0;

  // Chi-squared threshold for 2-DOF (95% confidence = 5.99, 99% = 9.21)
  static const double _chiSquared2Dof95 = 5.99;
  static const double _chiSquared2Dof99 = 9.21;

  GpsLockManager() {
    _sessionStart = DateTime.now();
  }

  GpsLockState get state => _state;
  GpsLockData? get lockData => _lockData;
  bool get isLocked => _state == GpsLockState.locked && (_lockData?.isValid ?? false);
  int get stationaryProgress {
    if (_requiredStableSeconds <= 0) return 0;
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

  // --- Compute heading from Kalman velocity (east, north components) ---
  double _headingFromVelocity(double vx, double vy) {
    // atan2 returns radians, convert to degrees, 0 = north, clockwise
    double heading = atan2(vx, vy) * 180.0 / pi;
    if (heading < 0) heading += 360.0;
    return heading;
  }

  // --- Confidence decay over time (exponential) ---
  double _applyConfidenceDecay(double confidence, DateTime lockedAt) {
    final age = DateTime.now().difference(lockedAt).inSeconds;
    if (age <= 0) return confidence;
    // Decay factor: 0.99 per second -> after 120 seconds ~30% left
    final decay = pow(0.99, age).toDouble();
    return (confidence * decay).clamp(0.0, 100.0);
  }

  // --- Innovation RMS (only updated after passing outlier test) ---
  void _updateInnovationRms(double innovationNorm) {
    _innovationHistory.add(innovationNorm);
    if (_innovationHistory.length > _innovationWindow) _innovationHistory.removeAt(0);
    double sumSq = 0;
    for (final val in _innovationHistory) sumSq += val * val;
    _innovationRms = sqrt(sumSq / _innovationHistory.length);
    if (_innovationRms < 0.1) _innovationRms = 0.1;
  }

  // --- Confidence score (more realistic) ---
  double _computeConfidence(double varPosX, double varPosY, double rms) {
    final posStd = sqrt((varPosX + varPosY) / 2.0);
    final posScore = exp(-posStd / 10.0);
    final innovationScore = exp(-rms / 8.0);
    return (posScore * innovationScore * 100.0).clamp(0.0, 100.0);
  }

  // --- Health check (soft reset) ---
  bool _isFilterHealthy() => _kalman != null && _kalman!.isHealthy();

  // --- Haversine distance ---
  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) * sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  // --- Process sample ---
  bool processSample(Position newPos) {
    // Warm-up: 5 seconds
    if (_sessionStart != null && DateTime.now().difference(_sessionStart!).inSeconds < 5) {
      return false;
    }

    // Validate sample
    final timestamp = newPos.timestamp ?? DateTime.now();
    final age = DateTime.now().difference(timestamp);
    if (age.inSeconds > 3) return false;
    if (newPos.accuracy > _maxAllowedAccuracy) return false;
    if (newPos.speed.isFinite && newPos.speed > _maxSpeedMps) return false;

    // Stale detection: if no data > _maxNoDataSeconds, reset
    if (_lastTimestamp != null && DateTime.now().difference(_lastTimestamp!).inSeconds > _maxNoDataSeconds) {
      if (kDebugMode) debugPrint('GPS Lock: stale stream, resetting');
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
      _smoothedAccuracy = newPos.accuracy;
      _consistentGoodSamples = 0;
    }

    // Initialize reference and Kalman on first good sample
    if (_refLat == null && newPos.accuracy <= 20) {
      _refLat = newPos.latitude;
      _refLon = newPos.longitude;
      _kalman = KalmanFilter4D();
      _lastTimestamp = timestamp;
      _lastFilteredEast = null;
      _lastFilteredNorth = null;
      _stableSeconds = 0.0;
      _smoothedAccuracy = newPos.accuracy;
      _hasAltitude = false;
    }
    if (_refLat == null) return false;

    // dt with negative/zero guard
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
      if (kDebugMode) debugPrint('GPS Lock: Kalman unhealthy, recreated');
      return false;
    }

    // Innovation and Normalised Innovation Squared (NIS) for 2-DOF
    final de = local.east - predicted[0];
    final dn = local.north - predicted[1];
    final double sigma = (newPos.accuracy * (1.0 + _innovationRms * 0.3)).clamp(1.0, 50.0);
    final double R = sigma * sigma;
    final Sx = Ppred[0][0] + R;
    final Sy = Ppred[1][1] + R;
    final nis = (de * de) / Sx + (dn * dn) / Sy; // Normalised Innovation Squared

    // Outlier check using chi-squared threshold (dynamic)
    final nisThreshold = _state == GpsLockState.locked ? _chiSquared2Dof99 : _chiSquared2Dof95;
    if (nis > nisThreshold) {
      if (kDebugMode) debugPrint('GPS Lock: outlier nis=$nis (threshold=$nisThreshold)');
      return false;
    }

    // Innovation RMS updated AFTER passing outlier test
    final innovationNorm = sqrt(de * de + dn * dn);
    _updateInnovationRms(innovationNorm);

    // Adaptive process noise: higher motion -> higher Q
    double speedEst = sqrt(predicted[2] * predicted[2] + predicted[3] * predicted[3]);
    if (speedEst < 1.0) {
      _kalman!.setProcessNoiseScale(1.0); // stationary
    } else if (speedEst < 5.0) {
      _kalman!.setProcessNoiseScale(2.0); // walking
    } else {
      _kalman!.setProcessNoiseScale(4.0); // vehicle
    }

    // Kalman update
    final (updated, Pupd) = _kalman!.update(de, dn, R, Ppred);
    if (!_isFilterHealthy()) {
      _kalman = KalmanFilter4D();
      _stableSeconds = 0.0;
      return false;
    }

    // Hybrid speed with damping
    final gpsSpeed = (newPos.speed.isFinite && newPos.speed >= 0) ? newPos.speed : 0.0;
    final kalmanSpeed = sqrt(updated[2] * updated[2] + updated[3] * updated[3]);
    double rawSpeed = (kalmanSpeed * 0.7) + (gpsSpeed * 0.3);
    final dampedSpeed = rawSpeed < 0.5 ? 0.0 : rawSpeed;
    final speedMps = dampedSpeed;

    // Movement delta
    double movedDistance = 0.0;
    if (_lastFilteredEast != null && _lastFilteredNorth != null) {
      final dx = updated[0] - _lastFilteredEast!;
      final dy = updated[1] - _lastFilteredNorth!;
      movedDistance = sqrt(dx * dx + dy * dy);
    }
    _lastFilteredEast = updated[0];
    _lastFilteredNorth = updated[1];

    // Update smoothed altitude
    if (!_hasAltitude) {
      _smoothedAltitude = newPos.altitude;
      _hasAltitude = true;
    } else {
      _smoothedAltitude = _smoothedAltitude * 0.9 + newPos.altitude * 0.1;
    }

    // Update smoothed accuracy first
    _smoothedAccuracy = _smoothedAccuracy * 0.8 + newPos.accuracy * 0.2;

    // Then adaptive stable seconds based on new smoothed accuracy
    _requiredStableSeconds = _smoothedAccuracy < 8 ? 4.0 : _defaultRequiredStableSeconds;

    // Movement detection (more sensitive for slow vehicles)
    final bool isMoving = (((speedMps > 2.2 && movedDistance > 1.5) || movedDistance > 4.0) &&
            _innovationRms > 1.2) &&
        _smoothedAccuracy < 20;

    // Update stationary time with less sensitive threshold
    if (!isMoving && nis < 4.0) {
      _stableSeconds += dt;
    } else {
      _stableSeconds = 0.0;
      if (isMoving) {
        _consistentGoodSamples = 0; // reset consistency on movement
      }
    }

    // Heading: use Kalman velocity when moving, otherwise keep last
    double heading;
    if (speedMps > 1.0) {
      heading = _headingFromVelocity(updated[2], updated[3]);
      _lastHeading = heading;
    } else {
      heading = _lastHeading;
    }

    // Convert smoothed ENU back to lat/lon, using smoothed accuracy & altitude
    final smoothedLatLon = _toGlobal(updated[0], updated[1]);
    final smoothedPosition = Position(
      latitude: smoothedLatLon.lat,
      longitude: smoothedLatLon.lon,
      accuracy: _smoothedAccuracy,
      altitude: _smoothedAltitude,
      heading: heading,
      speed: speedMps,
      speedAccuracy: newPos.speedAccuracy,
      timestamp: timestamp,
      altitudeAccuracy: newPos.altitudeAccuracy,
      headingAccuracy: 5.0, // approximate
      floor: newPos.floor,
      isMocked: newPos.isMocked,
    );

    // Update samples with partial clear on movement
    _filteredSamples.add(smoothedPosition);
    if (_filteredSamples.length > _maxSamples) _filteredSamples.removeAt(0);
    if (isMoving && _filteredSamples.length > 4) {
      _filteredSamples.removeRange(0, _filteredSamples.length ~/ 2);
    }

    // Consistency counter for good samples
    if (_smoothedAccuracy < 15 && nis < _chiSquared2Dof95) {
      _consistentGoodSamples++;
    } else {
      _consistentGoodSamples = 0;
    }

    // Update UI counter
    _stationaryCount = (_stableSeconds / 1.0).round().clamp(0, _requiredStableSeconds.toInt());

    // ENU re-centering before lock attempt (to avoid lock then recenter)
    if (_refLat != null) {
      final distFromRef = _haversine(_refLat!, _refLon!, newPos.latitude, newPos.longitude);
      if (distFromRef > _maxRefDistance) {
        _refLat = newPos.latitude;
        _refLon = newPos.longitude;
        _kalman?.reset(0.0, 0.0);
        _lastFilteredEast = _lastFilteredNorth = null;
        _stableSeconds = 0.0;
        _smoothedAccuracy = newPos.accuracy;
        _consistentGoodSamples = 0;
        if (kDebugMode) debugPrint('GPS Lock: re-centering ENU reference');
      }
    }

    // Locked state
    if (_state == GpsLockState.locked) {
      if (isMoving) {
        _state = GpsLockState.acquiring;
        // Adaptive covariance inflation
        final inflate = speedMps > 10 ? 5.0 : 2.5;
        _kalman!.inflateCovariance(inflate);
        _stableSeconds = 0.0;
        _consistentGoodSamples = 0;
        if (kDebugMode) debugPrint('GPS Lock: movement detected, re-acquiring');
        return false;
      }
      if (_lockData != null && newPos.accuracy < _lockData!.accuracy - 2) {
        final conf = _computeConfidence(Pupd[0][0], Pupd[1][1], _innovationRms);
        // Apply confidence decay based on age
        final decayedConf = _applyConfidenceDecay(conf, _lockData!.lockedAt);
        _lockData = _lockData!.copyWith(
          position: smoothedPosition,
          accuracy: _smoothedAccuracy,
          quality: getQualityFromAccuracy(_smoothedAccuracy),
          confidence: decayedConf,
        );
      }
      if (_lockData != null && !_lockData!.isValid) {
        _state = GpsLockState.stale;
        _lockData = null;
        _filteredSamples.clear();
        _consistentGoodSamples = 0;
        _stableSeconds = 0.0;
        if (kDebugMode) debugPrint('GPS Lock: stale lock expired');
      }
      return false;
    }

    // Acquiring state
    _state = GpsLockState.acquiring;
    final enoughStableTime = _stableSeconds >= _requiredStableSeconds;
    final goodAccuracy = _smoothedAccuracy <= _requiredBaseAccuracyMeters;
    final covConverged = (Pupd[0][0] < _lockCovarianceThreshold && Pupd[1][1] < _lockCovarianceThreshold);
    final velConverged = (Pupd[2][2] < _lockVelCovThreshold && Pupd[3][3] < _lockVelCovThreshold);
    final enoughSamples = _filteredSamples.length >= 8;
    final enoughConsistency = _consistentGoodSamples >= 5;

    if (enoughSamples && goodAccuracy && covConverged && velConverged && enoughStableTime && enoughConsistency) {
      // Final variance validation
      if (_filteredSamples.length >= 3) {
        final meters = <(double e, double n)>[];
        for (final p in _filteredSamples) {
          final loc = _toLocal(p.latitude, p.longitude)!;
          meters.add((loc.east, loc.north));
        }
        double sumE = 0, sumN = 0;
        for (final m in meters) {
          sumE += m.e;
          sumN += m.n;
        }
        final meanE = sumE / meters.length;
        final meanN = sumN / meters.length;
        double varE = 0, varN = 0;
        for (final m in meters) {
          varE += (m.e - meanE) * (m.e - meanE);
          varN += (m.n - meanN) * (m.n - meanN);
        }
        varE /= meters.length;
        varN /= meters.length;
        if (varE > 100 || varN > 100) {
          if (kDebugMode) debugPrint('GPS Lock: high variance, retry');
          return false;
        }
      }

      // Weighted average with power 1.5
      double totalWeight = 0, weightedLat = 0, weightedLon = 0, bestAcc = double.infinity;
      for (final p in _filteredSamples) {
        final acc = p.accuracy.clamp(3.0, 30.0);
        final weight = 1.0 / pow(acc, 1.5);
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
        altitude: _smoothedAltitude,
        heading: heading,
        speed: speedMps,
        speedAccuracy: newPos.speedAccuracy,
        timestamp: timestamp,
        altitudeAccuracy: newPos.altitudeAccuracy,
        headingAccuracy: 5.0,
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
    _innovationHistory.clear();
    _innovationRms = 1.0;
    _lastHeading = 0.0;
    _stableSeconds = 0.0;
    _smoothedAccuracy = 999.0;
    _hasAltitude = false;
    _smoothedAltitude = 0.0;
    _sessionStart = DateTime.now();
    _consistentGoodSamples = 0;
  }
}
