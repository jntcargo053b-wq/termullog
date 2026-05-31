// lib/services/gps_lock_manager.dart
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum GpsLockState { searching, stabilizing, locked }

class LockData {
  final Position position;      // filtered position for display
  final Position rawPosition;   // best raw sample for geocoding/watermark
  final double accuracy;
  final String quality;
  final double confidence;
  final DateTime lockedAt;
  final bool isFallbackLock;
  final double stability;       // 0..1, 1 = very stable

  LockData({
    required this.position,
    required this.rawPosition,
    required this.accuracy,
    required this.quality,
    required this.confidence,
    required this.lockedAt,
    this.isFallbackLock = false,
    this.stability = 0.0,
  });

  LockData copyWith({
    Position? position,
    Position? rawPosition,
    double? accuracy,
    String? quality,
    double? confidence,
    DateTime? lockedAt,
    bool? isFallbackLock,
    double? stability,
  }) {
    return LockData(
      position: position ?? this.position,
      rawPosition: rawPosition ?? this.rawPosition,
      accuracy: accuracy ?? this.accuracy,
      quality: quality ?? this.quality,
      confidence: confidence ?? this.confidence,
      lockedAt: lockedAt ?? this.lockedAt,
      isFallbackLock: isFallbackLock ?? this.isFallbackLock,
      stability: stability ?? this.stability,
    );
  }
}

class GpsLockManager {
  GpsLockState _state = GpsLockState.searching;
  LockData? _lockData;
  Position? _bestFix; // all-time best accuracy

  // Lock parameters (professional)
  static const int _minSamplesForLock = 6;          // 6 good samples
  static const double _lockAccuracyThreshold = 15.0; // max accuracy to consider lock
  static const double _stabilityThreshold = 0.7;    // need 70% stability
  static const double _moveThreshold = 3.0;          // considered moving if >3m per sample
  static const double _unlockThreshold = 10.0;       // if moved >10m from lock, unlock
  static const int _stabilizingWindowSize = 5;      // last 5 samples for variance

  // Sampling adaptation
  static const int _slowIntervalMs = 1500;           // stationary
  static const int _fastIntervalMs = 700;            // moving

  // Bootstrapping storage
  final List<Position> _stabilizingSamples = [];
  Position? _bestDuringStabilizing;
  DateTime? _lockStartTime;

  // For movement detection
  DateTime? _lastMovementTime;
  double _stationaryProgress = 0.0;
  static const double _stationaryTimeoutSeconds = 4.0;

  // For adaptive interval
  int _currentIntervalMs = _slowIntervalMs;
  bool _wasMoving = false;

  bool get isLocked => _state == GpsLockState.locked;
  LockData? get lockData => _lockData;
  double get stationaryProgress => _stationaryProgress;
  Position? get bestFix => _bestFix;
  int get currentIntervalMs => _currentIntervalMs;

  bool processSample(Position newPos) {
    // Update all-time best
    if (_bestFix == null || newPos.accuracy < _bestFix!.accuracy) {
      _bestFix = newPos;
      if (kDebugMode) debugPrint('GpsLockManager: New best fix acc=${newPos.accuracy.toStringAsFixed(1)}m');
    }

    switch (_state) {
      case GpsLockState.searching:
        return _handleSearching(newPos);
      case GpsLockState.stabilizing:
        return _handleStabilizing(newPos);
      case GpsLockState.locked:
        return _handleLocked(newPos);
    }
  }

  bool _handleSearching(Position newPos) {
    if (newPos.accuracy <= _lockAccuracyThreshold) {
      _state = GpsLockState.stabilizing;
      _stabilizingSamples.clear();
      _stabilizingSamples.add(newPos);
      _bestDuringStabilizing = newPos;
      _lockStartTime = DateTime.now();
      if (kDebugMode) {
        debugPrint('GpsLockManager: STABILIZING started, acc=${newPos.accuracy.toStringAsFixed(1)}m');
      }
    }
    return false;
  }

  bool _handleStabilizing(Position newPos) {
    if (newPos.accuracy <= _lockAccuracyThreshold) {
      _stabilizingSamples.add(newPos);
      if (_bestDuringStabilizing == null || newPos.accuracy < _bestDuringStabilizing!.accuracy) {
        _bestDuringStabilizing = newPos;
      }
      if (kDebugMode) {
        debugPrint('GpsLockManager: stabilizing ${_stabilizingSamples.length}/$_minSamplesForLock acc=${newPos.accuracy.toStringAsFixed(1)}m');
      }
    }

    // Check if we have enough samples and stability is high
    if (_stabilizingSamples.length >= _minSamplesForLock) {
      final stability = _computeStability(_stabilizingSamples);
      final avgAccuracy = _stabilizingSamples.fold(0.0, (s,p)=>s+p.accuracy) / _stabilizingSamples.length;
      if (stability >= _stabilityThreshold && avgAccuracy <= _lockAccuracyThreshold) {
        // Lock achieved
        double avgLat=0, avgLon=0;
        for (var p in _stabilizingSamples) {
          avgLat += p.latitude;
          avgLon += p.longitude;
        }
        avgLat /= _stabilizingSamples.length;
        avgLon /= _stabilizingSamples.length;

        final hybridPos = Position(
          latitude: avgLat,
          longitude: avgLon,
          accuracy: avgAccuracy,
          altitude: _bestDuringStabilizing!.altitude,
          heading: _bestDuringStabilizing!.heading,
          speed: _bestDuringStabilizing!.speed,
          speedAccuracy: _bestDuringStabilizing!.speedAccuracy,
          timestamp: DateTime.now(),
          altitudeAccuracy: _bestDuringStabilizing!.altitudeAccuracy,
          headingAccuracy: _bestDuringStabilizing!.headingAccuracy,
        );

        _lockData = LockData(
          position: hybridPos,
          rawPosition: _bestDuringStabilizing!,
          accuracy: avgAccuracy,
          quality: _getQualityFromAccuracy(avgAccuracy),
          confidence: _computeConfidence(avgAccuracy),
          lockedAt: DateTime.now(),
          stability: stability,
        );
        _state = GpsLockState.locked;
        _lastMovementTime = DateTime.now();
        _stationaryProgress = 0.0;
        if (kDebugMode) {
          debugPrint('GpsLockManager: LOCKED with stability=${stability.toStringAsFixed(2)}, bestRawAcc=${_bestDuringStabilizing!.accuracy.toStringAsFixed(1)}m');
        }
        return true;
      }
    }
    return false;
  }

  bool _handleLocked(Position newPos) {
    if (_lockData == null) return false;

    // Calculate movement from last raw position
    final movedDistance = _haversine(
      _lockData!.rawPosition.latitude, _lockData!.rawPosition.longitude,
      newPos.latitude, newPos.longitude,
    );

    // Hard unlock if moved too far
    if (movedDistance > _unlockThreshold) {
      if (kDebugMode) {
        debugPrint('GpsLockManager: UNLOCKED - moved ${movedDistance.toStringAsFixed(1)}m > $_unlockThreshold');
      }
      reset();
      return processSample(newPos);
    }

    // Update raw position if better accuracy
    Position updatedRaw = _lockData!.rawPosition;
    if (newPos.accuracy < _lockData!.rawPosition.accuracy) {
      updatedRaw = newPos;
      if (kDebugMode) debugPrint('GpsLockManager: raw updated to acc=${newPos.accuracy.toStringAsFixed(1)}m');
    }

    // Adaptive smoothing: only smooth when moving slowly
    final isMoving = movedDistance > _moveThreshold;
    Position hybridPos;
    if (!isMoving) {
      // Low-pass filter when stationary
      const double alpha = 0.2;
      hybridPos = Position(
        latitude: _lockData!.position.latitude * (1-alpha) + newPos.latitude * alpha,
        longitude: _lockData!.position.longitude * (1-alpha) + newPos.longitude * alpha,
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
      hybridPos = newPos; // raw when moving
    }

    // Update lock data
    _lockData = _lockData!.copyWith(
      rawPosition: updatedRaw,
      position: hybridPos,
      accuracy: newPos.accuracy,
      quality: _getQualityFromAccuracy(newPos.accuracy),
      confidence: _computeConfidence(newPos.accuracy),
      lockedAt: DateTime.now(),
      stability: _computeStability([newPos, _lockData!.position]), // simplified
    );

    // Update stationary progress
    final now = DateTime.now();
    if (movedDistance < _moveThreshold) {
      if (_lastMovementTime != null) {
        final stationaryDuration = now.difference(_lastMovementTime!).inSeconds.toDouble();
        _stationaryProgress = min(1.0, stationaryDuration / _stationaryTimeoutSeconds);
      }
    } else {
      _lastMovementTime = now;
      _stationaryProgress = 0.0;
    }

    // Adaptive interval: change if movement state changed
    final currentlyMoving = movedDistance > _moveThreshold;
    if (currentlyMoving != _wasMoving) {
      _wasMoving = currentlyMoving;
      _currentIntervalMs = currentlyMoving ? _fastIntervalMs : _slowIntervalMs;
      if (kDebugMode) {
        debugPrint('GpsLockManager: adaptive interval -> ${_currentIntervalMs}ms (moving=$currentlyMoving)');
      }
    }

    if (kDebugMode) {
      debugPrint('GpsLockManager: locked moved=${movedDistance.toStringAsFixed(1)}m smooth=${!isMoving} stationary=${(_stationaryProgress*100).toInt()}%');
    }
    return false;
  }

  double _computeStability(List<Position> samples) {
    if (samples.length < 2) return 0.5;
    // Compute variance of latitude and longitude (in meters)
    double latMean=0, lonMean=0;
    for (var p in samples) {
      latMean += p.latitude;
      lonMean += p.longitude;
    }
    latMean /= samples.length;
    lonMean /= samples.length;
    double latVar=0, lonVar=0;
    for (var p in samples) {
      final dLat = (p.latitude - latMean) * 111319.9; // meters per degree approx
      final dLon = (p.longitude - lonMean) * 111319.9 * cos(latMean * pi/180);
      latVar += dLat*dLat;
      lonVar += dLon*dLon;
    }
    latVar /= samples.length;
    lonVar /= samples.length;
    final rms = sqrt(latVar + lonVar);
    // stability = 1 when rms < 1 meter, 0 when > 10 meters
    return (1.0 - (rms / 10.0)).clamp(0.0, 1.0);
  }

  double _computeConfidence(double accuracy) {
    if (accuracy <= 5) return 0.98;
    if (accuracy <= 8) return 0.95;
    if (accuracy <= 12) return 0.90;
    if (accuracy <= 18) return 0.80;
    if (accuracy <= 28) return 0.70;
    return 0.50;
  }

  String _getQualityFromAccuracy(double acc) {
    if (acc <= 8) return 'excellent';
    if (acc <= 15) return 'good';
    if (acc <= 25) return 'fair';
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
    // Keep _bestFix
    _stabilizingSamples.clear();
    _bestDuringStabilizing = null;
    _lockStartTime = null;
    _lastMovementTime = null;
    _stationaryProgress = 0.0;
    _wasMoving = false;
    _currentIntervalMs = _slowIntervalMs;
  }
}
