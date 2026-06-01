// lib/services/kalman_filter_4d.dart
// 4D Kalman filter untuk GPS mobile/logistik – responsif & stabil.
// - Process noise dinaikkan: qPos=6.0, qVel=7.0
// - Damping adaptif pow(0.92, dt.clamp(0.3, 2.5))
// - Gate threshold adaptif (tanpa minimum 20m statis)
// - Hard accept threshold = gate * 2.0
// - Adjusted R (measurement noise dikompres saat accuracy bagus)
// - Joseph form, symmetry, covariance floor, health check

import 'dart:math';

class KalmanFilter4D {
  List<double> _x = [0.0, 0.0, 0.0, 0.0];
  List<List<double>> _P = List.generate(4, (_) => List.filled(4, 0.0));

  // Process noise dinaikkan untuk responsivitas
  static const double _qPos = 6.0;
  static const double _qVel = 7.0;

  KalmanFilter4D() {
    _resetCovariance();
  }

  void _resetCovariance() {
    _P = [
      [25.0, 0.0, 0.0, 0.0],
      [0.0, 25.0, 0.0, 0.0],
      [0.0, 0.0, 4.0, 0.0],
      [0.0, 0.0, 0.0, 4.0],
    ];
  }

  List<List<double>> _getF(double dt) => [
        [1.0, 0.0, dt, 0.0],
        [0.0, 1.0, 0.0, dt],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
      ];

  List<List<double>> _getQ(double dt) {
    final dt2 = dt * dt;
    final dt3 = dt2 * dt;
    final dt4 = dt2 * dt2;
    return [
      [dt4 / 4 * _qPos, 0.0, dt3 / 2 * _qVel, 0.0],
      [0.0, dt4 / 4 * _qPos, 0.0, dt3 / 2 * _qVel],
      [dt3 / 2 * _qVel, 0.0, dt2 * _qVel, 0.0],
      [0.0, dt3 / 2 * _qVel, 0.0, dt2 * _qVel],
    ];
  }

  List<List<double>> _enforceSymmetry(List<List<double>> M) {
    final sym = List.generate(4, (i) => List.filled(4, 0.0));
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        sym[i][j] = (M[i][j] + M[j][i]) / 2.0;
      }
    }
    return sym;
  }

  void _applyCovarianceFloor() {
    for (int i = 0; i < 4; i++) {
      if (_P[i][i] < 0.001) _P[i][i] = 0.001;
    }
  }

  // Prediction dengan damping adaptif (base 0.92)
  (List<double>, List<List<double>>) predict(double dt) {
    final F = _getF(dt);
    final Q = _getQ(dt);

    List<double> xPred = _matMulVec(F, _x);
    final clampedDt = dt.clamp(0.3, 2.5);
    final damping = pow(0.92, clampedDt).toDouble();
    xPred[2] *= damping;
    xPred[3] *= damping;

    final FP = _matMul(F, _P);
    final FPFt = _matMul(FP, _transpose(F));
    final PPred = _matAdd(FPFt, Q);

    _x = xPred;
    _P = _enforceSymmetry(PPred);
    _applyCovarianceFloor();

    return (_x, _P);
  }

  // Update step (Joseph form)
  (List<double>, List<List<double>>) update(
      double measurementEast,
      double measurementNorth,
      double R,
      List<List<double>> Ppred) {
    final H = [
      [1.0, 0.0, 0.0, 0.0],
      [0.0, 1.0, 0.0, 0.0],
    ];
    final innovation = [
      measurementEast - _x[0],
      measurementNorth - _x[1],
    ];

    final HP = _matMul(H, Ppred);
    final HPHt = _matMul(HP, _transpose(H));
    final S = [
      [HPHt[0][0] + R, HPHt[0][1]],
      [HPHt[1][0], HPHt[1][1] + R],
    ];

    final det = S[0][0] * S[1][1] - S[0][1] * S[1][0];
    if (det.abs() < 1e-12) return (_x, _P);
    final invS = [
      [S[1][1] / det, -S[0][1] / det],
      [-S[1][0] / det, S[0][0] / det],
    ];

    final PHt = _matMul(Ppred, _transpose(H));
    final K = _matMul(PHt, invS);

    final xUpd = List<double>.from(_x);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 2; j++) {
        xUpd[i] += K[i][j] * innovation[j];
      }
    }

    final I = [
      [1.0, 0.0, 0.0, 0.0],
      [0.0, 1.0, 0.0, 0.0],
      [0.0, 0.0, 1.0, 0.0],
      [0.0, 0.0, 0.0, 1.0],
    ];
    final KH = _matMul(K, H);
    final I_KH = _matSub(I, KH);
    final I_KH_P = _matMul(I_KH, Ppred);
    final term1 = _matMul(I_KH_P, _transpose(I_KH));
    final KR = _matMul(K, [[R, 0], [0, R]]);
    final term2 = _matMul(KR, _transpose(K));
    final PUpd = _matAdd(term1, term2);

    _x = xUpd;
    _P = _enforceSymmetry(PUpd);
    _applyCovarianceFloor();

    return (_x, _P);
  }

  // Predict + update dengan outlier rejection adaptif dan adjusted R
  (List<double>, List<List<double>>) predictAndUpdate(
      double dt,
      double measurementEast,
      double measurementNorth,
      double R) {
    final (_, Ppred) = predict(dt);

    if (!isHealthy()) {
      reset(measurementEast, measurementNorth);
      return (_x, _P);
    }

    final measurementSigma = sqrt(R);
    final dx = measurementEast - _x[0];
    final dy = measurementNorth - _x[1];
    final innovationDistance = sqrt(dx * dx + dy * dy);

    // Gate threshold adaptif (tanpa minimum statis 20m)
    final gateThreshold = measurementSigma <= 10
        ? max(8.0, measurementSigma * 1.8)
        : max(15.0, measurementSigma * 2.2);

    final hardAcceptThreshold = gateThreshold * 2.0; // 2x gate, lebih responsif

    // Adjusted R: kompres measurement noise saat accuracy bagus
    double adjustedR = R;
    if (measurementSigma <= 10) {
      adjustedR *= 0.35;
    } else if (measurementSigma <= 20) {
      adjustedR *= 0.6;
    }

    if (innovationDistance <= gateThreshold) {
      // Loncatan kecil → terima dengan adjusted R
      return update(measurementEast, measurementNorth, adjustedR, Ppred);
    } else if (innovationDistance > hardAcceptThreshold) {
      // Loncatan besar → hanya terima jika akurasi cukup baik
      if (measurementSigma <= 15.0) {
        inflateCovariance(2.0);
        return update(measurementEast, measurementNorth, adjustedR, _P);
      } else {
        inflateCovariance(1.2);
        return (_x, _P);
      }
    } else {
      // Loncatan menengah → tolak, inflate kecil
      inflateCovariance(1.2);
      return (_x, _P);
    }
  }

  void inflateCovariance([double factor = 3.0]) {
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        _P[i][j] *= factor;
      }
    }
  }

  void reset(double east, double north) {
    _x = [east, north, 0.0, 0.0];
    _resetCovariance();
  }

  bool isHealthy() {
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        final v = _P[i][j];
        if (!v.isFinite || v.abs() > 1e6) return false;
      }
      if (_P[i][i] < 0) return false;
    }
    return true;
  }

  // ========== Matrix utilities ==========
  List<List<double>> _matMul(List<List<double>> A, List<List<double>> B) {
    final int aRows = A.length, aCols = A[0].length, bCols = B[0].length;
    final result = List.generate(aRows, (_) => List.filled(bCols, 0.0));
    for (int i = 0; i < aRows; i++) {
      for (int j = 0; j < bCols; j++) {
        double sum = 0.0;
        for (int k = 0; k < aCols; k++) sum += A[i][k] * B[k][j];
        result[i][j] = sum;
      }
    }
    return result;
  }

  List<double> _matMulVec(List<List<double>> M, List<double> v) {
    final result = List.filled(M.length, 0.0);
    for (int i = 0; i < M.length; i++) {
      double sum = 0.0;
      for (int j = 0; j < v.length; j++) sum += M[i][j] * v[j];
      result[i] = sum;
    }
    return result;
  }

  List<List<double>> _transpose(List<List<double>> M) {
    final int rows = M.length, cols = M[0].length;
    final result = List.generate(cols, (_) => List.filled(rows, 0.0));
    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) result[j][i] = M[i][j];
    }
    return result;
  }

  List<List<double>> _matAdd(List<List<double>> A, List<List<double>> B) {
    final result = List.generate(A.length, (i) => List.filled(A[0].length, 0.0));
    for (int i = 0; i < A.length; i++) {
      for (int j = 0; j < A[0].length; j++) result[i][j] = A[i][j] + B[i][j];
    }
    return result;
  }

  List<List<double>> _matSub(List<List<double>> A, List<List<double>> B) {
    final result = List.generate(A.length, (i) => List.filled(A[0].length, 0.0));
    for (int i = 0; i < A.length; i++) {
      for (int j = 0; j < A[0].length; j++) result[i][j] = A[i][j] - B[i][j];
    }
    return result;
  }
}
