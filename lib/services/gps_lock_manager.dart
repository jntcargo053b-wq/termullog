// lib/services/gps_lock_manager.dart
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'kalman_filter_4d.dart';

// ============================================================================
// Enums
// ============================================================================
enum GpsLockState {
  searching,
  acquiring,
  provisional,
  locked,
  stale,
}

// ============================================================================
// Geometry helpers
// ============================================================================
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

// ============================================================================
// Address cache (reduces geocode requests)
// ============================================================================
class _AddressCache {
  String address = '';
  String weather = '';
  double? cachedLat;
  double? cachedLon;
  static const double _staleDistanceM = 8.0;

  bool isValidFor(double lat, double lon) {
    if (address.isEmpty || cachedLat == null || cachedLon == null) return false;
    return _haversine(cachedLat!, cachedLon!, lat, lon) <= _staleDistanceM;
  }

  void update(double lat, double lon, String addr, String wx) {
    address = addr;
    weather = wx;
    cachedLat = lat;
    cachedLon = lon;
  }

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) *
            sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}

// ============================================================================
// Lock data
// ============================================================================
class GpsLockData {
  final Position position;
  final String address;
  final String weather;
  final DateTime lockedAt;
  final double accuracy;
  final String quality;
  final double confidence;
  final bool isProvisional;

  const GpsLockData({
    required this.position,
    required this.address,
    required this.weather,
    required this.lockedAt,
    required this.accuracy,
    required this.quality,
    required this.confidence,
    this.isProvisional = false,
  });

  bool get isValid => DateTime.now().difference(lockedAt) < const Duration(minutes: 5);

  GpsLockData copyWith({
    Position? position,
    String? address,
    String? weather,
    DateTime? lockedAt,
    double? accuracy,
    String? quality,
    double? confidence,
    bool? isProvisional,
  }) => GpsLockData(
        position: position ?? this.position,
        address: address ?? this.address,
        weather: weather ?? this.weather,
        lockedAt: lockedAt ?? this.lockedAt,
        accuracy: accuracy ?? this.accuracy,
        quality: quality ?? this.quality,
        confidence: confidence ?? this.confidence,
        isProvisional: isProvisional ?? this.isProvisional,
      );
}

// ============================================================================
// Warm-start seed
// ============================================================================
class GpsWarmStartSeed {
  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime savedAt;

  const GpsWarmStartSeed({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.savedAt,
  });

  bool get isUsable =>
      DateTime.now().difference(savedAt) < const Duration(hours: 1) &&
      accuracy <= 20.0;
}

// ============================================================================
// Main GpsLockManager
// ============================================================================
class GpsLockManager {
  GpsLockState _state = GpsLockState.searching;
  GpsLockData? _lockData;
  List<Position> _filteredSamples = [];

  // ENU reference
  double? _refLat, _refLon;
  KalmanFilter4D? _kalman;
  DateTime? _lastTimestamp;
  double? _lastFilteredEast, _lastFilteredNorth;

  // Stable-time accumulator (seconds)
  double _stableSeconds = 0.0;

  // Faster convergence thresholds
  static const double _requiredStableSeconds = 5.0;
  static const int _requiredSamples = 10;

  // Provisional lock thresholds
  static const double _provisionalStableSeconds = 2.5;
  static const int _provisionalSamples = 5;

  // Bootstrap samples
  final List<Position> _initialSamples = [];
  static const int _initialSamplesRequired = 3;

  // Heading
  double _lastHeading = 0.0;
  final List<double> _headingHistory = [];

  // Innovation RMS
  final List<double> _innovationHistory = [];
  double _innovationRms = 1.0;
  static const int _innovationWindow = 10;

  // Lock parameters
  static const double _requiredAccuracyMeters = 12.0;
  static const double _maxAllowedAccuracy = 20.0;
  static const int _maxSamples = 20;
  static const double _lockCovarianceThreshold = 20.0;
  static const double _lockVelCovThreshold = 3.0;

  // Movement detection
  static const double _maxMovementMeters = 4.0;
  static const double _movementSpeedThreshold = 2.0;
  static const double _movementDistanceThreshold = 2.5;
  static const double _maxSpeedMps = 60.0;
  static const double _maxRefDistance = 500.0;

  // Warmup
  static const int _warmupSeconds = 1;
  static const double _fastTrackAccuracy = 4.0;
  DateTime? _sessionStart;
  bool _warmupBypassed = false;

  // Altitude EMA
  double? _smoothedAltitude;
  static const double _altEmaAlpha = 0.2;

  // Address cache
  final _AddressCache _addressCache = _AddressCache();

  // ------------------------------------------------------------------------
  // Constructor
  // ------------------------------------------------------------------------
  GpsLockManager({GpsWarmStartSeed? warmStartSeed}) {
    _sessionStart = DateTime.now();
    if (warmStartSeed != null && warmStartSeed.isUsable) {
      _applyWarmStart(warmStartSeed);
    }
  }

  void _applyWarmStart(GpsWarmStartSeed seed) {
    _refLat = seed.latitude;
    _refLon = seed.longitude;
    _kalman = KalmanFilter4D();
    _warmupBypassed = true;
    _lastTimestamp = seed.savedAt;
    if (kDebugMode) {
      debugPrint('GPS Lock: warm-start applied from '
          '${seed.savedAt.toIso8601String()} '
          'acc=${seed.accuracy.toStringAsFixed(1)}m');
    }
  }

  // ------------------------------------------------------------------------
  // Public getters
  // ------------------------------------------------------------------------
  GpsLockState get state => _state;
  GpsLockData? get lockData => _lockData;

  bool get isLocked =>
      (_state == GpsLockState.locked || _state == GpsLockState.provisional) &&
      (_lockData?.isValid ?? false);

  int get stationaryProgress =>
      ((_stableSeconds / _requiredStableSeconds) * 100).clamp(0, 100).toInt();

  double get confidence => _lockData?.confidence ?? 0.0;

  static String getQualityFromAccuracy(double acc) {
    if (acc <= 3) return 'Excellent';
    if (acc <= 6) return 'Good';
    if (acc <= 12) return 'Fair';
    return 'Poor';
  }

  // ------------------------------------------------------------------------
  // ENU helpers
  // ------------------------------------------------------------------------
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

  // ------------------------------------------------------------------------
  // Heading
  // ------------------------------------------------------------------------
  double _bearingBetween(double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * pi / 180.0;
    final y = sin(dLon) * cos(lat2 * pi / 180.0);
    final x = cos(lat1 * pi / 180.0) * sin(lat2 * pi / 180.0) -
        sin(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) * cos(dLon);
    return ((atan2(y, x) * 180.0 / pi) + 360) % 360;
  }

  void _updateHeadingFromBearing(
      double rawHeading, double speedMps, Position newPos, Position? lastPos) {
    if (lastPos != null && speedMps > 1.0) {
      final bearing = _bearingBetween(
          lastPos.latitude, lastPos.longitude,
          newPos.latitude, newPos.longitude);
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

  // ------------------------------------------------------------------------
  // Innovation RMS
  // ------------------------------------------------------------------------
  void _updateInnovationRms(double norm) {
    _innovationHistory.add(norm);
    if (_innovationHistory.length > _innovationWindow) {
      _innovationHistory.removeAt(0);
    }
    double sumSq = 0;
    for (final v in _innovationHistory) sumSq += v * v;
    _innovationRms = sqrt(sumSq / _innovationHistory.length).clamp(0.1, 1e9);
  }

  // ------------------------------------------------------------------------
  // Confidence scoring
  // ------------------------------------------------------------------------
  double _computeConfidence(
      double varPosX, double varPosY, double rms, int sampleCount) {
    final posStd = sqrt((varPosX + varPosY) / 2.0);
    final posScore = exp(-posStd / 6.0);
    final innovScore = exp(-rms / 4.0);
    final sampleScore = (sampleCount / _requiredSamples).clamp(0.0, 1.0);
    final stableScore = (_stableSeconds / _requiredStableSeconds).clamp(0.0, 1.0);
    return (posScore * innovScore * sampleScore * stableScore * 100.0)
        .clamp(0.0, 100.0);
  }

  bool _isFilterHealthy() => _kalman?.isHealthy() ?? true;

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) *
            sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _smoothAltitude(double raw) {
    _smoothedAltitude =
        _smoothedAltitude == null ? raw : _altEmaAlpha * raw + (1 - _altEmaAlpha) * _smoothedAltitude!;
    return _smoothedAltitude!;
  }

  // ------------------------------------------------------------------------
  // Main processing
  // ------------------------------------------------------------------------
  bool processSample(Position newPos, {Position? lastPositionForBearing}) {
    final bool fastTrack = newPos.accuracy <= _fastTrackAccuracy;
    if (!_warmupBypassed) {
      if (fastTrack) {
        _warmupBypassed = true;
        if (kDebugMode) debugPrint('GPS Lock: fast-track warmup bypass (acc=${newPos.accuracy.toStringAsFixed(1)}m)');
      } else if (_sessionStart != null &&
          DateTime.now().difference(_sessionStart!).inSeconds < _warmupSeconds) {
        return false;
      } else {
        _warmupBypassed = true;
      }
    }

    final timestamp = newPos.timestamp ?? DateTime.now();
    if (DateTime.now().difference(timestamp).inSeconds > 3) return false;
    if (newPos.accuracy > _maxAllowedAccuracy) return false;
    if (newPos.speed.isFinite && newPos.speed > _maxSpeedMps) return false;

    if (_lastTimestamp != null &&
        DateTime.now().difference(_lastTimestamp!).inSeconds > 5) {
      _resetFilter(keepAddressCache: true);
    }

    // Bootstrap ENU reference menggunakan sample terbaik
    if (_refLat == null) {
      _initialSamples.add(newPos);
      if (_initialSamples.length < _initialSamplesRequired) return false;

      _initialSamples.sort((a, b) => a.accuracy.compareTo(b.accuracy));
      _refLat = _initialSamples.first.latitude;
      _refLon = _initialSamples.first.longitude;

      _kalman = KalmanFilter4D();
      _lastTimestamp = timestamp;
      _lastFilteredEast = _lastFilteredNorth = null;
      _stableSeconds = 0.0;
      _initialSamples.clear();

      if (kDebugMode) debugPrint('GPS Lock: ENU reference set using best initial accuracy');
    }

    final rawDt = timestamp.difference(_lastTimestamp!).inMicroseconds / 1e6;
    final dt = rawDt.isFinite && rawDt > 0 ? rawDt.clamp(0.01, 1.5) : 0.1;
    _lastTimestamp = timestamp;

    final local = _toLocal(newPos.latitude, newPos.longitude);
    if (local == null) return false;

    final (predicted, Ppred) = _kalman!.predict(dt);
    if (!_isFilterHealthy()) {
      _kalman = KalmanFilter4D();
      _stableSeconds = 0.0;
      return false;
    }

    final de = local.east - predicted[0];
    final dn = local.north - predicted[1];
    final innovationNorm = sqrt(de * de + dn * dn);

    // Adaptive measurement noise (lebih kecil, agresif rendah)
    final adaptive = 1.0 + (_innovationRms * 0.12);
    final sigma = (newPos.accuracy * adaptive).clamp(2.0, 12.0);
    final R = sigma * sigma;
    final Sx = Ppred[0][0] + R;
    final Sy = Ppred[1][1] + R;
    final mahal2 = (de * de) / Sx + (dn * dn) / Sy;

    double mahalThreshold;
    if (_state == GpsLockState.locked || _state == GpsLockState.provisional) {
      mahalThreshold = 12.0;
    } else if (_state == GpsLockState.acquiring) {
      mahalThreshold = 25.0;
    } else {
      mahalThreshold = 30.0;
    }

    // Soft reject: jika outlier, inflate R dan update
    if (mahal2 > mahalThreshold) {
      final softenedR = R * 3.0;
      final (updatedSoft, PupdSoft) = _kalman!.update(de, dn, softenedR, Ppred);
      return _processUpdatedState(
        updatedSoft,
        PupdSoft,
        newPos,
        timestamp,
        dt,
        lastPositionForBearing,
        isOutlier: true,
      );
    }

    _updateInnovationRms(innovationNorm);
    final (updated, Pupd) = _kalman!.update(de, dn, R, Ppred);
    return _processUpdatedState(
      updated,
      Pupd,
      newPos,
      timestamp,
      dt,
      lastPositionForBearing,
      isOutlier: false,
    );
  }

  bool _processUpdatedState(
    List<double> updated,
    List<List<double>> Pupd,
    Position newPos,
    DateTime timestamp,
    double dt,
    Position? lastPositionForBearing, {
    bool isOutlier = false,
  }) {
    if (!_isFilterHealthy()) {
      _kalman = KalmanFilter4D();
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

    final bool isMoving =
        ((speedMps > _movementSpeedThreshold && movedDistance > _movementDistanceThreshold) ||
            movedDistance > 3.0) &&
        _innovationRms > 1.2;

    if (!isMoving && (isOutlier ? (movedDistance < 1.0) : true)) {
      _stableSeconds += dt;
    } else {
      _stableSeconds = 0.0;
    }

    final rawHeading = (newPos.heading.isFinite &&
            newPos.heading >= 0 &&
            newPos.heading <= 360)
        ? newPos.heading
        : _lastHeading;
    _updateHeadingFromBearing(rawHeading, speedMps, newPos, lastPositionForBearing);
    if (isMoving) _headingHistory.clear();
    if (isMoving) _filteredSamples.clear();

    final smoothedAlt = _smoothAltitude(newPos.altitude);
    final smoothedLatLon = _toGlobal(updated[0], updated[1]);
    final smoothedPosition = Position(
      latitude: smoothedLatLon.lat,
      longitude: smoothedLatLon.lon,
      accuracy: newPos.accuracy,
      altitude: smoothedAlt,
      heading: _lastHeading,
      speed: speedMps,
      speedAccuracy: newPos.speedAccuracy,
      timestamp: timestamp,
      altitudeAccuracy: newPos.altitudeAccuracy,
      headingAccuracy: _getHeadingAccuracy(),
      floor: newPos.floor,
      isMocked: newPos.isMocked,
    );

    _filteredSamples.add(smoothedPosition);
    if (_filteredSamples.length > _maxSamples) _filteredSamples.removeAt(0);

    // State machine
    if (_state == GpsLockState.locked || _state == GpsLockState.provisional) {
      if (isMoving) {
        _state = GpsLockState.acquiring;
        _kalman!.inflateCovariance(3.0);
        _stableSeconds = 0.0;
        if (kDebugMode) debugPrint('GPS Lock: movement → re-acquiring');
        return false;
      }

      if (_lockData != null) {
        final conf = _computeConfidence(Pupd[0][0], Pupd[1][1], _innovationRms,
            _filteredSamples.length);
        final shouldUpgrade =
            _state == GpsLockState.provisional && conf >= 70.0;

        if (newPos.accuracy < _lockData!.accuracy - 1.5 || shouldUpgrade) {
          _lockData = _lockData!.copyWith(
            position: smoothedPosition,
            accuracy: newPos.accuracy,
            quality: getQualityFromAccuracy(newPos.accuracy),
            confidence: conf,
            lockedAt: shouldUpgrade ? DateTime.now() : null,
            isProvisional: shouldUpgrade ? false : _lockData!.isProvisional,
          );
          if (shouldUpgrade) {
            _state = GpsLockState.locked;
            if (kDebugMode) debugPrint('GPS Lock: provisional → LOCKED');
          }
        }

        if (!_lockData!.isValid) {
          _state = GpsLockState.stale;
          _lockData = null;
          _filteredSamples.clear();
          _stableSeconds = 0.0;
          if (kDebugMode) debugPrint('GPS Lock: stale lock expired');
        }
      }
      return false;
    }

    _state = GpsLockState.acquiring;

    final goodAccuracy = newPos.accuracy <= _requiredAccuracyMeters;
    final covConverged = Pupd[0][0] < _lockCovarianceThreshold &&
                         Pupd[1][1] < _lockCovarianceThreshold;
    final velConverged = Pupd[2][2] < _lockVelCovThreshold &&
                         Pupd[3][3] < _lockVelCovThreshold;
    final enoughSamples = _filteredSamples.length >= _requiredSamples;
    final enoughStable = _stableSeconds >= _requiredStableSeconds;

    final provSamples = _filteredSamples.length >= _provisionalSamples;
    final provStable = _stableSeconds >= _provisionalStableSeconds;
    if (!enoughSamples && provSamples && provStable && goodAccuracy && !isMoving &&
        _state != GpsLockState.provisional) {
      final provConf = _computeConfidence(
              Pupd[0][0], Pupd[1][1], _innovationRms, _filteredSamples.length) *
          0.7;
      final cachedAddr = _addressCache.isValidFor(smoothedLatLon.lat, smoothedLatLon.lon)
          ? _addressCache.address
          : '';
      final cachedWx = _addressCache.isValidFor(smoothedLatLon.lat, smoothedLatLon.lon)
          ? _addressCache.weather
          : '';
      _lockData = GpsLockData(
        position: smoothedPosition,
        address: cachedAddr,
        weather: cachedWx,
        lockedAt: DateTime.now(),
        accuracy: newPos.accuracy,
        quality: getQualityFromAccuracy(newPos.accuracy),
        confidence: provConf,
        isProvisional: true,
      );
      _state = GpsLockState.provisional;
      if (kDebugMode) {
        debugPrint('GPS Lock: PROVISIONAL '
            'acc=${newPos.accuracy.toStringAsFixed(1)}m '
            'conf=${provConf.toStringAsFixed(0)}%');
      }
      return true;
    }

    if (enoughSamples && goodAccuracy && covConverged && velConverged && enoughStable) {
      if (_filteredSamples.length >= 3) {
        final locs = _filteredSamples
            .map((p) => _toLocal(p.latitude, p.longitude)!)
            .toList();
        final meanE = locs.map((l) => l.east).reduce((a, b) => a + b) / locs.length;
        final meanN = locs.map((l) => l.north).reduce((a, b) => a + b) / locs.length;
        double varE = 0, varN = 0;
        for (final l in locs) {
          varE += (l.east - meanE) * (l.east - meanE);
          varN += (l.north - meanN) * (l.north - meanN);
        }
        varE /= locs.length;
        varN /= locs.length;
        if (varE > 100 || varN > 100) {
          if (kDebugMode) debugPrint('GPS Lock: high variance, retrying');
          return false;
        }
      }

      double totalW = 0, wLat = 0, wLon = 0, bestAcc = double.infinity;
      for (final p in _filteredSamples) {
        final acc = p.accuracy.clamp(3.0, 30.0);
        final weight = 1.0 / (acc * acc);
        totalW += weight;
        wLat += p.latitude * weight;
        wLon += p.longitude * weight;
        if (p.accuracy < bestAcc) bestAcc = p.accuracy;
      }
      if (totalW <= 0) return false;

      final lockedPos = Position(
        latitude: wLat / totalW,
        longitude: wLon / totalW,
        accuracy: bestAcc,
        altitude: smoothedAlt,
        heading: _lastHeading,
        speed: speedMps,
        speedAccuracy: newPos.speedAccuracy,
        timestamp: timestamp,
        altitudeAccuracy: newPos.altitudeAccuracy,
        headingAccuracy: _getHeadingAccuracy(),
        floor: newPos.floor,
        isMocked: newPos.isMocked,
      );

      final conf = _computeConfidence(
          Pupd[0][0], Pupd[1][1], _innovationRms, _filteredSamples.length);

      final useCache = _addressCache.isValidFor(lockedPos.latitude, lockedPos.longitude);
      _lockData = GpsLockData(
        position: lockedPos,
        address: useCache ? _addressCache.address : '',
        weather: useCache ? _addressCache.weather : '',
        lockedAt: DateTime.now(),
        accuracy: bestAcc,
        quality: getQualityFromAccuracy(bestAcc),
        confidence: conf,
        isProvisional: false,
      );
      _state = GpsLockState.locked;
      if (kDebugMode) {
        debugPrint('GPS Lock: LOCKED '
            'acc=${bestAcc.toStringAsFixed(1)}m '
            'conf=${conf.toStringAsFixed(0)}% '
            'addrCached=$useCache');
      }
      return true;
    }

    if (_refLat != null) {
      final dist = _haversine(_refLat!, _refLon!, newPos.latitude, newPos.longitude);
      if (dist > _maxRefDistance) {
        _refLat = newPos.latitude;
        _refLon = newPos.longitude;
        _kalman?.reset(0.0, 0.0);
        _lastFilteredEast = _lastFilteredNorth = null;
        _stableSeconds = 0.0;
        if (kDebugMode) debugPrint('GPS Lock: ENU re-centered');
      }
    }

    return false;
  }

  void updateLockAddress(String address, String weather) {
    if (_lockData == null) return;
    final lat = _lockData!.position.latitude;
    final lon = _lockData!.position.longitude;
    _addressCache.update(lat, lon, address, weather);
    _lockData = _lockData!.copyWith(address: address, weather: weather);
  }

  bool get hasValidCachedAddress {
    if (_lockData == null) return false;
    return _addressCache.isValidFor(
        _lockData!.position.latitude, _lockData!.position.longitude) &&
        _addressCache.address.isNotEmpty;
  }

  GpsWarmStartSeed? get warmStartSnapshot {
    if (_lockData == null || !_lockData!.isValid) return null;
    return GpsWarmStartSeed(
      latitude: _lockData!.position.latitude,
      longitude: _lockData!.position.longitude,
      accuracy: _lockData!.accuracy,
      savedAt: DateTime.now(),
    );
  }

  void _resetFilter({bool keepAddressCache = false}) {
    _state = GpsLockState.searching;
    _stableSeconds = 0.0;
    _filteredSamples.clear();
    _kalman = KalmanFilter4D();
    _lastFilteredEast = _lastFilteredNorth = null;
    _refLat = _refLon = null;
    _initialSamples.clear();
    _innovationHistory.clear();
    _innovationRms = 1.0;
    _headingHistory.clear();
    _lastTimestamp = null;
    if (!keepAddressCache) {
      _addressCache.address = '';
      _addressCache.weather = '';
    }
  }

  void forceUnlock() {
    _lockData = null;
    _lastHeading = 0.0;
    _smoothedAltitude = null;
    _warmupBypassed = false;
    _sessionStart = DateTime.now();
    _resetFilter(keepAddressCache: true);
    if (kDebugMode) debugPrint('GPS Lock: force unlocked');
  }

  int _stationaryCount = 0;
}
