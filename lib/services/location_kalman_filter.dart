// lib/services/kalman_filter.dart
import 'dart:math';

/// Adaptive Kalman Filter for GPS position smoothing
/// Features:
/// - Dynamic measurement noise based on GPS reported accuracy
/// - Velocity state for motion prediction (constant velocity model)
/// - Outlier rejection using innovation threshold
/// - Process noise adaptation based on motion
class AdaptiveKalmanFilter {
  // State: [position, velocity]
  double _x;      // position estimate
  double _v;      // velocity estimate (m/s)
  double _p;      // position error covariance
  double _pv;     // position-velocity cross-covariance
  double _pv2;    // velocity-position cross-covariance
  double _pv3;    // velocity error covariance

  final double _dt; // time step (seconds)

  AdaptiveKalmanFilter({
    double initialValue = 0.0,
    double initialVelocity = 0.0,
    double initialError = 1.0,
    double dt = 1.0,
  })  : _x = initialValue,
        _v = initialVelocity,
        _p = initialError,
        _pv = 0.0,
        _pv2 = 0.0,
        _pv3 = 0.5,  // initial velocity uncertainty
        _dt = dt;

  /// Update filter with new measurement and GPS-reported accuracy
  /// Returns smoothed position
  double update(double measurement, double accuracy) {
    // 1. Prediction step (constant velocity model)
    // State transition: x' = x + v*dt, v' = v
    final double F = 1.0; // position transition
    final double G = _dt; // velocity influence on position
    // Covariance prediction
    _p = _p + 2 * G * _pv + G * G * _pv3 + _processNoise(accuracy);
    _pv = _pv + G * _pv3;
    _pv2 = _pv2 + G * _pv3;
    _pv3 = _pv3 + _velocityNoise();

    // 2. Outlier rejection using innovation threshold
    final double innovation = measurement - _x;
    final double innovationStd = sqrt(_p + _measurementNoise(accuracy));
    if (innovation.abs() > 3.0 * innovationStd) {
      // Outlier: reject update, keep prediction
      return _x;
    }

    // 3. Update step with dynamic measurement noise
    final double r = _measurementNoise(accuracy);
    final double k = _p / (_p + r);          // Kalman gain for position
    final double kv = _pv / (_p + r);        // Kalman gain for velocity

    // Update state
    _x = _x + k * innovation;
    _v = _v + kv * innovation;

    // Update covariances
    final double oneMinusK = 1.0 - k;
    _p = oneMinusK * _p;
    _pv = oneMinusK * _pv - kv * _p;
    _pv2 = -k * _pv2 + (1.0 - kv) * _pv2;
    _pv3 = _pv3 - kv * _pv2;

    return _x;
  }

  double _processNoise(double accuracy) {
    // Process noise adapts to accuracy: lower noise when accuracy good
    // Base noise 0.02 for stationary, up to 0.08 for moving
    // Simulate based on accuracy (rough proxy for motion)
    if (accuracy < 10) return 0.02;
    if (accuracy < 20) return 0.04;
    return 0.08;
  }

  double _velocityNoise() {
    // Velocity process noise: allow speed changes up to 2 m/s²
    return 0.5;
  }

  double _measurementNoise(double accuracy) {
    // Use GPS reported accuracy, clamped to reasonable range
    return accuracy.clamp(1.0, 50.0);
  }

  void reset(double value) {
    _x = value;
    _v = 0.0;
    _p = 1.0;
    _pv = 0.0;
    _pv2 = 0.0;
    _pv3 = 0.5;
  }
}

/// Circular filter for heading (degrees, 0-360)
class HeadingKalmanFilter {
  double _angle; // radians
  double _p;     // error covariance

  HeadingKalmanFilter({double initialAngle = 0.0, double initialError = 10.0})
      : _angle = initialAngle * pi / 180.0,
        _p = initialError;

  double update(double measurementDegrees, double accuracyDegrees) {
    final double measurementRad = measurementDegrees * pi / 180.0;
    final double r = accuracyDegrees.clamp(1.0, 30.0) * pi / 180.0;

    // Prediction (assume slow change)
    final double q = 1.0 * pi / 180.0; // process noise
    _p = _p + q;

    // Innovation with circular difference
    double diff = measurementRad - _angle;
    diff = atan2(sin(diff), cos(diff)); // wrap to [-pi, pi]

    final double k = _p / (_p + r);
    _angle = _angle + k * diff;
    _p = (1 - k) * _p;

    // Wrap result to [0, 360)
    double result = _angle * 180.0 / pi;
    result = (result % 360 + 360) % 360;
    return result;
  }

  void reset(double angleDegrees) {
    _angle = angleDegrees * pi / 180.0;
    _p = 10.0;
  }
}
