import 'dart:math';  // WAJIB ADA
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

enum GpsLockState { searching, acquiring, locked, stale }

class GpsLockData {
  final Position position;
  final String address;
  final String weather;
  final DateTime lockedAt;

  const GpsLockData({
    required this.position,
    required this.address,
    required this.weather,
    required this.lockedAt,
  });

  bool get isValid => DateTime.now().difference(lockedAt) < const Duration(minutes: 15);

  GpsLockData copyWith({String? address, String? weather}) => GpsLockData(
        position: position,
        address: address ?? this.address,
        weather: weather ?? this.weather,
        lockedAt: lockedAt,
      );
}

class GpsLockManager {
  GpsLockState _state = GpsLockState.searching;
  GpsLockData? _lockData;
  int _stationaryCount = 0;
  DateTime? _lastMovement;

  static const int _samplesBeforeLock = 8;
  static const double _moveThreshold = 3.0;
  static const double _lockAccuracyThreshold = 20.0;

  GpsLockState get state => _state;
  GpsLockData? get lockData => _lockData;
  bool get isLocked => _state == GpsLockState.locked && (_lockData?.isValid ?? false);

  bool processSample(Position newPos, Position? lastBest) {
    if (_state == GpsLockState.locked) {
      if (_lockData != null) {
        final dist = _haversine(
          _lockData!.position.latitude, _lockData!.position.longitude,
          newPos.latitude, newPos.longitude,
        );
        if (dist > _moveThreshold * 2) {
          _unlock();
          debugPrint('GPS Lock: UNLOCKED — moved ${dist.toStringAsFixed(1)}m');
        } else if (newPos.accuracy < _lockData!.position.accuracy - 2) {
          _lockData = GpsLockData(
            position: newPos,
            address: _lockData!.address,
            weather: _lockData!.weather,
            lockedAt: _lockData!.lockedAt,
          );
        }
      }
      return false;
    }

    if (lastBest != null) {
      final dist = _haversine(
        lastBest.latitude, lastBest.longitude,
        newPos.latitude, newPos.longitude,
      );
      if (dist > _moveThreshold) {
        _stationaryCount = 0;
        _lastMovement = DateTime.now();
        _state = GpsLockState.acquiring;
        return false;
      }
    }

    _stationaryCount++;
    _state = GpsLockState.acquiring;

    final readyToLock = _stationaryCount >= _samplesBeforeLock &&
        newPos.accuracy <= _lockAccuracyThreshold;

    if (readyToLock) {
      _lockData = GpsLockData(
        position: newPos,
        address: '',
        weather: '',
        lockedAt: DateTime.now(),
      );
      _state = GpsLockState.locked;
      debugPrint('GPS Lock: LOCKED at ${newPos.latitude}, ${newPos.longitude} ±${newPos.accuracy.toStringAsFixed(0)}m');
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
  }

  void forceUnlock() {
    _state = GpsLockState.searching;
    _lockData = null;
    _stationaryCount = 0;
  }

  int get stationaryProgress =>
      (_stationaryCount / _samplesBeforeLock * 100).clamp(0, 100).toInt();

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }
}
