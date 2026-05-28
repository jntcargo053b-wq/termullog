// lib/services/kalman_filter.dart
class KalmanFilter {
  double _x;  // state estimate (latitude or longitude)
  double _p;  // estimation error covariance
  final double _q; // process noise covariance (tuning)
  final double _r; // measurement noise covariance (tuning)

  KalmanFilter({
    double initialValue = 0.0,
    double initialError = 1.0,
    double processNoise = 0.005,   // tuning: GPS movement smoothness
    double measurementNoise = 5.0, // tuning: trust sensor (lower = trust more)
  })  : _x = initialValue,
        _p = initialError,
        _q = processNoise,
        _r = measurementNoise;

  double update(double measurement) {
    // Prediction
    _p = _p + _q;

    // Kalman gain
    final double k = _p / (_p + _r);

    // Update estimate
    _x = _x + k * (measurement - _x);
    _p = (1 - k) * _p;

    return _x;
  }

  void reset(double value) {
    _x = value;
    _p = 1.0;
  }
}
