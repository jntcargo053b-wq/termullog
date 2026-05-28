// lib/services/gps_lock_manager.dart
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'kalman_filter_4d.dart';

enum GpsLockState { searching, acquiring, locked }

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
  DateTime? _lastTimestamp;
  KalmanFilter4D? _kalman;
  double? _lastFilteredEast, _lastFilteredNorth;
  double _stableSeconds = 0.0;
  double _lastHeading = 0.0;
  final List<double> _headingHistory = [];
  double _innovationRms = 1.0;
  final List<double> _innovationHistory = [];
  static const int _innovationWindow = 10;
  double? _refLat, _refLon;

  final List<Position> _bootstrapSamples = [];
  static const int _bootstrapRequired = 3;

  // Raw position terbaru (untuk keperluan lain)
  Position? _latestRawPosition;

  // Parameter
  static const double _requiredAccuracyMeters = 6.0;
  static const double _maxAllowedAccuracy = 35.0;
  static const double _requiredStableSeconds = 4.0;
  static const double _maxMovementMeters = 4.0;
  static const double _movementSpeedThreshold = 1.0;
  static const double _movementDistanceThreshold = 1.2;
  static const double _maxSpeedMps = 60.0;

  DateTime? _sessionStart;

  GpsLockManager() {
    _sessionStart = DateTime.now();
  }

  GpsLockState get state => _state;
  GpsLockData? get lockData => _lockData;
  bool get isLocked => _state == GpsLockState.locked && (_lockData?.isValid ?? false);
  int get stationaryProgress => ((_stableSeconds / _requiredStableSeconds) * 100).clamp(0, 100).toInt();
  double get confidence => _lockData?.confidence ?? 0.0;

  // 🔥 Sederhana: posisi raw terbaru untuk geocoding (tanpa best selection)
  Position? get rawPosition => _latestRawPosition;

  static String getQualityFromAccuracy(double acc) {
    if (acc <= 3) return 'Excellent';
    if (acc <= 6) return 'Good';
    if (acc <= 12) return 'Fair';
    return 'Poor';
  }

  // ENU helpers (sama seperti sebelumnya)
  LocalPoint? _toLocal(double lat, double lon) {
    if (_refLat == null || _refLon == null) return null;
    const R = 6371000.0;
    final dLat = (lat - _refLat!) * pi / 180.0;
    final dLon = (lon - _refLon!) * pi / 180.0;
    return LocalPoint(
      dLon * cos(_refLat! * pi / 180.0) * R,
      dLat * R,
    );
  }

  GlobalPoint _toGlobal(double east, double north) {
    const R = 6371000.0;
    final dLat = north / R;
    final dLon = east / (R * cos(_refLat! * pi / 180.0));
    return GlobalPoint(
      _refLat! + dLat * 180.0 / pi,
      _refLon! + dLon * 180.0 / pi,
    );
  }

  double _bearingBetween(double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * pi / 180.0;
    final y = sin(dLon) * cos(lat2 * pi / 180.0);
    final x = cos(lat1 * pi / 180.0) * sin(lat2 * pi / 180.0) -
        sin(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) * cos(dLon);
    return ((atan2(y, x) * 180.0 / pi) + 360) % 360;
  }

  void _updateHeading(double rawHeading, double speedMps, Position newPos, Position? lastPos) {
    if (lastPos != null && speedMps > 1.0) {
      final bearing = _bearingBetween(lastPos.latitude, lastPos.longitude, newPos.latitude, newPos.longitude);
      _lastHeading = bearing;
      _headingHistory.add(bearing);
    } else if (speedMps >= 2.8) {
      if (rawHeading.isFinite && rawHeading >= 0 && rawHeading <= 360) {
        _headingHistory.add(rawHeading);
        double sinSum = 0, cosSum = 0;
        for (final h in _headingHistory) {
          sinSum += sin(h * pi / 180.0);
          cosSum += cos(h * pi / 180.0);
        }
        _lastHeading = ((atan2(sinSum, cosSum) * 180.0 / pi) + 360) % 360;
      }
    }
    if (_headingHistory.length > 5) _headingHistory.removeAt(0);
  }

  double _getHeadingAccuracy() {
    if (_headingHistory.length < 2) return 20.0;
    double sinSum = 0, cosSum = 0;
    for (final h in _headingHistory) {
      sinSum += sin(h * pi / 180.0);
      cosSum += cos(h * pi / 180.0);
    }
    final r = sqrt(sinSum * sinSum + cosSum * cosSum) / _headingHistory.length;
    return ((1.0 - r) * 30.0).clamp(2.0, 30.0);
  }

  void _updateInnovationRms(double norm) {
    _innovationHistory.add(norm);
    if (_innovationHistory.length > _innovationWindow) _innovationHistory.removeAt(0);
    double sumSq = 0;
    for (final v in _innovationHistory) sumSq += v * v;
    _innovationRms = sqrt(sumSq / _innovationHistory.length).clamp(0.1, 10.0);
  }

  double _computeConfidence(double varPosX, double varPosY, double rms) {
    final posStd = sqrt((varPosX + varPosY) / 2.0);
    final posScore = exp(-posStd / 6.0);
    final innovScore = exp(-rms / 4.0);
    return (posScore * innovScore * 100.0).clamp(0.0, 100.0);
  }

  bool _isFilterHealthy() => _kalman?.isHealthy() ?? true;

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) * sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  bool processSample(Position newPos, {Position? lastPositionForBearing}) {
    // Stale detection
    if (_lastTimestamp != null && DateTime.now().difference(_lastTimestamp!).inSeconds > 5) {
      forceUnlock();
      return false;
    }

    // Simpan raw position terbaru
    _latestRawPosition = newPos;

    final timestamp = newPos.timestamp ?? DateTime.now();
    if (DateTime.now().difference(timestamp).inSeconds > 3) return false;
    if (newPos.accuracy > _maxAllowedAccuracy) return false;
    if (newPos.speed.isFinite && newPos.speed > _maxSpeedMps) return false;

    // Bootstrap ENU median
    if (_refLat == null) {
      _bootstrapSamples.add(newPos);
      if (_bootstrapSamples.length < _bootstrapRequired) return false;
      final lats = _bootstrapSamples.map((p) => p.latitude).toList()..sort();
      final lons = _bootstrapSamples.map((p) => p.longitude).toList()..sort();
      _refLat = lats[1];
      _refLon = lons[1];
      _kalman = KalmanFilter4D();
      _lastTimestamp = timestamp;
      _bootstrapSamples.clear();
      if (kDebugMode) debugPrint('GPS Lock: ENU bootstrap median set');
    }
    if (_refLat == null) return false;

    final rawDt = timestamp.difference(_lastTimestamp!).inMicroseconds / 1e6;
    final dt = rawDt.isFinite && rawDt > 0 ? rawDt.clamp(0.01, 1.5) : 0.1;
    _lastTimestamp = timestamp;

    final local = _toLocal(newPos.latitude, newPos.longitude);
    if (local == null) return false;

    final (predicted, Ppred) = _kalman!.predict(dt);
    if (!_isFilterHealthy()) {
      _kalman = KalmanFilter4D();
      _lastFilteredEast = null;
      _lastFilteredNorth = null;
      _stableSeconds = 0.0;
      return false;
    }

    final de = local.east - predicted[0];
    final dn = local.north - predicted[1];
    final innovationNorm = sqrt(de * de + dn * dn);

    final adaptive = 1.0 + (_innovationRms * 0.05);
    final sigma = (newPos.accuracy * adaptive).clamp(1.5, 8.0);
    final R = sigma * sigma;
    final Sx = Ppred[0][0] + R;
    final Sy = Ppred[1][1] + R;
    final mahal2 = (de * de) / Sx + (dn * dn) / Sy;

    if (mahal2 > 12.0) {
      if (kDebugMode) debugPrint('GPS Lock: outlier mahal2=${mahal2.toStringAsFixed(1)}');
      return false;
    }
    _updateInnovationRms(innovationNorm);

    final (updated, Pupd) = _kalman!.update(de, dn, R, Ppred);
    if (!_isFilterHealthy()) {
      _kalman = KalmanFilter4D();
      _lastFilteredEast = null;
      _lastFilteredNorth = null;
      _stableSeconds = 0.0;
      return false;
    }

    final speedMps = sqrt(updated[2] * updated[2] + updated[3] * updated[3]);
    double movedDistance = 0.0;
    if (_lastFilteredEast != null && _lastFilteredNorth != null) {
      final dx = updated[0] - _lastFilteredEast!;
      final dy = updated[1] - _lastFilteredNorth!;
      movedDistance = sqrt(dx * dx + dy * dy);
    }
    _lastFilteredEast = updated[0];
    _lastFilteredNorth = updated[1];

    final bool isMoving = ((speedMps > _movementSpeedThreshold && movedDistance > _movementDistanceThreshold) ||
            movedDistance > 3.0) &&
        _innovationRms > 1.2;

    if (!isMoving && mahal2 < 2.5) {
      _stableSeconds += dt;
    } else {
      _stableSeconds = (_stableSeconds - dt * 0.5).clamp(0.0, double.infinity);
    }

    final rawHeading = (newPos.heading.isFinite && newPos.heading >= 0 && newPos.heading <= 360)
        ? newPos.heading
        : _lastHeading;
    _updateHeading(rawHeading, speedMps, newPos, lastPositionForBearing);
    if (!isMoving && speedMps < 0.5) {
      _headingHistory.clear();
    }

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
      headingAccuracy: _getHeadingAccuracy(),
      floor: newPos.floor,
      isMocked: newPos.isMocked,
    );

    // Hybrid position (70% raw, 30% smoothed)
    final hybridLat = newPos.latitude * 0.7 + smoothedPosition.latitude * 0.3;
    final hybridLon = newPos.longitude * 0.7 + smoothedPosition.longitude * 0.3;
    final hybridPosition = Position(
      latitude: hybridLat,
      longitude: hybridLon,
      accuracy: newPos.accuracy,
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

    // State machine
    if (_state == GpsLockState.locked) {
      if (isMoving) {
        _state = GpsLockState.acquiring;
        _kalman!.inflateCovariance(3.0);
        _stableSeconds = 0.0;
        return false;
      }
      if (_lockData != null && newPos.accuracy < _lockData!.accuracy - 1.5) {
        final conf = _computeConfidence(Pupd[0][0], Pupd[1][1], _innovationRms);
        _lockData = _lockData!.copyWith(
          position: hybridPosition,
          accuracy: newPos.accuracy,
          quality: getQualityFromAccuracy(newPos.accuracy),
          confidence: conf,
        );
      }
      if (_lockData != null && !_lockData!.isValid) {
        _state = GpsLockState.searching;
        _lockData = null;
        _stableSeconds = 0.0;
      }
      return false;
    }

    _state = GpsLockState.acquiring;
    final goodAccuracy = newPos.accuracy <= _requiredAccuracyMeters;
    final enoughStable = _stableSeconds >= _requiredStableSeconds;

    if (goodAccuracy && enoughStable && !isMoving) {
      final conf = _computeConfidence(Pupd[0][0], Pupd[1][1], _innovationRms);
      _lockData = GpsLockData(
        position: hybridPosition,
        address: '',
        weather: '',
        lockedAt: DateTime.now(),
        accuracy: newPos.accuracy,
        quality: getQualityFromAccuracy(newPos.accuracy),
        confidence: conf,
      );
      _state = GpsLockState.locked;
      if (kDebugMode) debugPrint('GPS Lock: LOCKED acc=${newPos.accuracy.toStringAsFixed(1)}m conf=${conf.toStringAsFixed(0)}%');
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
    _stableSeconds = 0.0;
    _refLat = _refLon = null;
    _kalman = null;
    _lastTimestamp = null;
    _lastFilteredEast = null;
    _lastFilteredNorth = null;
    _innovationHistory.clear();
    _headingHistory.clear();
    _innovationRms = 1.0;
    _lastHeading = 0.0;
    _bootstrapSamples.clear();
    _latestRawPosition = null;
    _sessionStart = DateTime.now();
    if (kDebugMode) debugPrint('GPS Lock: force unlocked');
  }
}

class LocalPoint {
  final double east;
  final double north;
  const LocalPoint(this.east, this.north);
}

class GlobalPoint {
  final double lat;
  final double lon;
  const GlobalPoint(this.lat, this.lon);
}
