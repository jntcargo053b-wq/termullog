import 'package:geolocator/geolocator.dart';

class GpsFilter {
  static const double maxJumpMeters = 50.0; // loncatan maksimal
  static const int movingAverageWindow = 3;  // jumlah sampel untuk rata-rata

  static Position? lastPosition;
  static final List<Position> _positionHistory = [];

  /// Filter outlier: hanya terima jika jarak dari posisi terakhir <= maxJumpMeters
  static bool isValidJump(Position newPos) {
    if (lastPosition == null) return true;
    final distance = Geolocator.distanceBetween(
      lastPosition!.latitude,
      lastPosition!.longitude,
      newPos.latitude,
      newPos.longitude,
    );
    return distance <= maxJumpMeters;
  }

  /// Moving average untuk memperhalus koordinat
  static Position smoothPosition(Position newPos) {
    _positionHistory.add(newPos);
    if (_positionHistory.length > movingAverageWindow) {
      _positionHistory.removeAt(0);
    }

    if (_positionHistory.length < 2) return newPos;

    double avgLat = 0, avgLon = 0, avgAcc = 0;
    for (var p in _positionHistory) {
      avgLat += p.latitude;
      avgLon += p.longitude;
      avgAcc += p.accuracy;
    }
    avgLat /= _positionHistory.length;
    avgLon /= _positionHistory.length;
    avgAcc /= _positionHistory.length;

    return Position(
      accuracy: avgAcc,
      altitude: newPos.altitude,
      altitudeAccuracy: newPos.altitudeAccuracy,
      heading: newPos.heading,
      headingAccuracy: newPos.headingAccuracy,
      latitude: avgLat,
      longitude: avgLon,
      speed: newPos.speed,
      speedAccuracy: newPos.speedAccuracy,
      timestamp: newPos.timestamp,
      isMocked: newPos.isMocked,
    );
  }

  static void reset() {
    lastPosition = null;
    _positionHistory.clear();
  }
}
