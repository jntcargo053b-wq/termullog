// lib/services/gps_lock_manager.dart
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'kalman_filter_4d.dart';

enum GpsLockState { searching, acquiring, locked, stale }

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

  GpsLockData copyWith({String? address, String? weather}) => GpsLockData(
        position: position,
        address: address ?? this.address,
        weather: weather ?? this.weather,
        lockedAt: lockedAt,
        accuracy: accuracy,
        quality: quality,
        confidence: confidence,
      );
}

class GpsLockManager {
  GpsLockState _state = GpsLockState.searching;
  GpsLockData? _lockData;
  int _stationaryCounter = 0;
  DateTime? _lastMovementTime;
  List<Position> _filteredSamples = [];

  // ENU reference
  double? _refLat, _refLon;
  KalmanFilter4D? _kalman;
  DateTime? _lastTimestamp;
  double? _lastFilteredEast, _lastFilteredNorth;

  // Heading smoothing
  double _lastHeading = 0.0;
  final List<double> _headingHistory = [];

  // Innovation RMS tracking
  final List<double> _innovationHistory = [];
  double _innovationRms = 1.0;
  static const int _innovationWindow = 10;

  // Lock parameters
  static const int _requiredSamples = 8;
  static const double _requiredAccuracyMeters = 10.0;
  static const double _maxAllowedAccuracy = 35.0;
  static const int _maxSamples = 15;
  static const double _lockCovarianceThreshold = 25.0;
  static const double _lockVelCovThreshold = 4.0;

  // Speed sanity
  static const double _maxSpeedMps = 60.0;

  // Session start for warm-up
  DateTime? _sessionStart;

  GpsLockManager() {
    _sessionStart = DateTime.now();
  }

  GpsLockState get state => _state;
  GpsLockData? get lockData => _lockData;
  bool get isLocked => _state == GpsLockState.locked && (_lockData?.isValid ?? false);
  int get stationaryProgress => ((_stationaryCounter / _requiredSamples) * 100).clamp(0, 100).toInt();
  double get confidence => _lockData?.confidence ?? 0.0;

  static String getQualityFromAccuracy(double acc) {
    if (acc <= 3) return 'Excellent';
    if (acc <= 8) return 'Good';
    if (acc <= 15) return 'Fair';
    return 'Poor';
  }

  // --- ENU helpers ---
  (double east, double north)? _toLocal(double lat, double lon) {
    if (_refLat == null || _refLon == null) return null;
    const double R = 6371000.0;
    final double dLat = (lat - _refLat!) * pi / 180.0;
    final double dLon = (lon - _refLon!) * pi / 180.0;
    final double east = dLon * cos(_refLat! * pi / 180.0) * R;
    final double north = dLat * R;
    return (east, north);
  }

  (double lat, double lon) _toGlobal(double east, double north) {
    const double R = 6371000.0;
    final double dLat = north / R;
    final double dLon = east / (R * cos(_refLat! * pi / 180.0));
    return (_refLat! + dLat * 180.0 / pi, _refLon! + dLon * 180.0 / pi);
  }

  // --- Heading smoothing with circular average and speed gating ---
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

  // --- Innovation RMS ---
  void _updateInnovationRms(double mahal2) {
    _innovationHistory.add(mahal2);
    if (_innovationHistory.length > _innovationWindow) _innovationHistory.removeAt(0);
    double sumSq = 0;
    for (final val in _innovationHistory) sumSq += val * val;
    _innovationRms = sqrt(sumSq / _innovationHistory.length);
    // Prevent RMS from being too low initially
    if (_innovationRms < 0.5) _innovationRms = 0.5;
  }

  // --- Confidence score ---
  double _computeConfidence(double varPosX, double varPosY, double rms) {
    final posStd = sqrt((varPosX + varPosY) / 2.0);
    final posScore = exp(-posStd / 6.0);
    final innovationScore = exp(-rms / 6.0);
    return (posScore * innovationScore * 100.0).clamp(0.0, 100.0);
  }

  // --- Health check ---
  bool _isFilterHealthy() => _kalman != null && _kalman!.isHealthy();

  // --- Process sample ---
  bool processSample(Position newPos) {
    // Warm-up: ignore first 3 seconds
    if (_sessionStart != null && DateTime.now().difference(_sessionStart!).inSeconds < 3) {
      return false;
    }

    // Validate sample
    final timestamp = newPos.timestamp ?? DateTime.now();
    final age = DateTime.now().difference(timestamp);
    if (age.inSeconds > 3) return false;
    if (newPos.accuracy > _maxAllowedAccuracy) return false;

    // Speed sanity check
    if (newPos.speed.isFinite && newPos.speed > _maxSpeedMps) return false;

    // Initialize reference and Kalman on first good sample
    if (_refLat == null && newPos.accuracy <= 20) {
      _refLat = newPos.latitude;
      _refLon = newPos.longitude;
      _kalman = KalmanFilter4D();
      _lastTimestamp = timestamp;
      _lastFilteredEast = null;
      _lastFilteredNorth = null;
    }
    if (_refLat == null) return false;

    // dt using GPS timestamp (clamp positive)
    double dt = (timestamp.difference(_lastTimestamp!).inMicroseconds / 1e6).clamp(0.01, 1.5);
    _lastTimestamp = timestamp;

    // Convert to ENU
    final local = _toLocal(newPos.latitude, newPos.longitude);
    if (local == null) return false;

    // Kalman prediction
    final (predicted, Ppred) = _kalman!.predict(dt);
    if (!_isFilterHealthy()) { forceUnlock(); return false; }

    // Innovation and Mahalanobis distance (2D)
    final de = local.east - predicted[0];
    final dn = local.north - predicted[1];
    final R = (newPos.accuracy * (1.0 + _innovationRms)).clamp(1.0, 100.0);
    final Sx = Ppred[0][0] + R;
    final Sy = Ppred[1][1] + R;
    final mahal2 = (de * de) / Sx + (dn * dn) / Sy;
    _updateInnovationRms(mahal2);

    // Outlier rejection: 3σ gate
    if (mahal2 > 9.0) {
      if (kDebugMode) debugPrint('GPS Lock: outlier mahal2=$mahal2');
      return false;
    }

    // Kalman update
    final (updated, Pupd) = _kalman!.update((de, dn), R, Ppred);
    if (!_isFilterHealthy()) { forceUnlock(); return false; }

    // Compute speed and movement delta (corrected)
    final speedMps = sqrt(updated[2] * updated[2] + updated[3] * updated[3]);
    double movedDistance = 0.0;
    if (_lastFilteredEast != null && _lastFilteredNorth != null) {
      final dx = updated[0] - _lastFilteredEast!;
      final dy = updated[1] - _lastFilteredNorth!;
      movedDistance = sqrt(dx * dx + dy * dy);
    }
    _lastFilteredEast = updated[0];
    _lastFilteredNorth = updated[1];

    // Heading update (speed gated)
    final rawHeading = (newPos.heading.isFinite && newPos.heading >= 0 && newPos.heading <= 360)
        ? newPos.heading
        : _lastHeading;
    _updateHeading(rawHeading, speedMps);

    // Convert smoothed ENU back to lat/lon
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
      headingAccuracy: newPos.headingAccuracy,
    );
    _filteredSamples.add(smoothedPosition);
    if (_filteredSamples.length > _maxSamples) _filteredSamples.removeAt(0);

    // Movement detection using real delta
    final bool isMoving = (speedMps > 2.0 && movedDistance > 1.0) || (movedDistance > 3.0);
    if (isMoving) {
      _stationaryCounter = 0;
      _lastMovementTime = DateTime.now();
      if (_state == GpsLockState.locked) {
        _state = GpsLockState.acquiring;
        _kalman!.inflateCovariance(6.0);
        if (kDebugMode) debugPrint('GPS Lock: movement speed=${speedMps.toStringAsFixed(1)}m/s, moved=${movedDistance.toStringAsFixed(1)}m');
        return false;
      }
    }

    // Update stationary counter
    if (!isMoving && mahal2 < 2.5) {
      _stationaryCounter++;
    } else if (_stationaryCounter > 0) {
      _stationaryCounter = (_stationaryCounter - 2).clamp(0, 100);
    }

    // Already locked: check stale and improvement
    if (_state == GpsLockState.locked) {
      if (_lockData != null && newPos.accuracy < _lockData!.accuracy - 2) {
        final conf = _computeConfidence(Pupd[0][0], Pupd[1][1], _innovationRms);
        _lockData = GpsLockData(
          position: smoothedPosition,
          address: _lockData!.address,
          weather: _lockData!.weather,
          lockedAt: _lockData!.lockedAt,
          accuracy: newPos.accuracy,
          quality: getQualityFromAccuracy(newPos.accuracy),
          confidence: conf,
        );
      }
      if (_lockData != null && !_lockData!.isValid) {
        _state = GpsLockState.stale;
        _lockData = null;
        if (kDebugMode) debugPrint('GPS Lock: stale lock expired');
      }
      return false;
    }

    // Acquiring state
    _state = GpsLockState.acquiring;
    final enoughSamples = _stationaryCounter >= _requiredSamples;
    final goodAccuracy = newPos.accuracy <= _requiredAccuracyMeters;
    final covConverged = (Pupd[0][0] < _lockCovarianceThreshold && Pupd[1][1] < _lockCovarianceThreshold);
    final velConverged = (Pupd[2][2] < _lockVelCovThreshold && Pupd[3][3] < _lockVelCovThreshold);
    final stableForTime = _lastMovementTime == null || DateTime.now().difference(_lastMovementTime!).inSeconds >= 5;

    if (enoughSamples && goodAccuracy && covConverged && velConverged && stableForTime) {
      // Final variance validation
      if (_filteredSamples.length >= 3) {
        final meters = _filteredSamples.map((p) {
          final loc = _toLocal(p.latitude, p.longitude)!;
          return (e: loc.east, n: loc.north);
        }).toList();
        double sumE = 0, sumN = 0;
        for (final m in meters) { sumE += m.e; sumN += m.n; }
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

      // Weighted average (weight = 1/accuracy²)
      double totalWeight = 0, weightedLat = 0, weightedLon = 0, bestAcc = double.infinity;
      for (final p in _filteredSamples) {
        final acc = p.accuracy.clamp(1.0, 100.0);
        final weight = 1.0 / (acc * acc);
        totalWeight += weight;
        weightedLat += p.latitude * weight;
        weightedLon += p.longitude * weight;
        if (p.accuracy < bestAcc) bestAcc = p.accuracy;
      }
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
        headingAccuracy: newPos.headingAccuracy,
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
    _stationaryCounter = 0;
    _filteredSamples.clear();
    _refLat = _refLon = null;
    _kalman = null;
    _lastTimestamp = null;
    _lastFilteredEast = _lastFilteredNorth = null;
    _lastMovementTime = null;
    _innovationHistory.clear();
    _headingHistory.clear();
    _innovationRms = 1.0;
    _lastHeading = 0.0;
    _sessionStart = DateTime.now();
  }
}
