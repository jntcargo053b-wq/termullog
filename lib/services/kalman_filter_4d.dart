import 'dart:math';

/// 4D Kalman filter for GPS smoothing in ENU coordinates (east, north, vx, vy)
/// Uses constant velocity model with dynamic process noise scaled by dt.
/// Implements Joseph form for numerical stability.
class KalmanFilter4D {
  // State vector [east, north, vx, vy] in meters and m/s
  List<double> _x = [0.0, 0.0, 0.0, 0.0];
  // Covariance matrix 4x4 (row-major)
  List<List<double>> _P = List.generate(4, (_) => List.filled(4, 0.0));

  // Process noise intensity (m²/s³)
  static const double _qPos = 0.8;
  static const double _qVel = 0.8;

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

  /// State transition matrix for given dt (seconds)
  List<List<double>> _getF(double dt) => [
        [1.0, 0.0, dt, 0.0],
        [0.0, 1.0, 0.0, dt],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
      ];

  /// Dynamic process noise covariance matrix (scaled with dt)
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

  /// Ensure covariance matrix symmetry (avoid numerical drift)
  List<List<double>> _enforceSymmetry(List<List<double>> M) {
    final sym = List.generate(4, (i) => List.filled(4, 0.0));
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        sym[i][j] = (M[i][j] + M[j][i]) / 2.0;
      }
    }
    return sym;
  }

  /// Apply a floor to diagonal covariance to prevent collapse
  void _applyCovarianceFloor() {
    for (int i = 0; i < 4; i++) {
      if (_P[i][i] < 0.001) _P[i][i] = 0.001;
    }
  }

  /// Prediction step: updates state and covariance based on dt.
  /// Returns (state, covariance) after prediction.
  (List<double>, List<List<double>>) predict(double dt) {
    final F = _getF(dt);
    final Q = _getQ(dt);

    // x = F * x
    final xPred = _matMulVec(F, _x);

    // P = F * P * F^T + Q
    final FP = _matMul(F, _P);
    final FPFt = _matMul(FP, _transpose(F));
    final PPred = _matAdd(FPFt, Q);

    _x = xPred;
    _P = _enforceSymmetry(PPred);
    _applyCovarianceFloor();

    return (_x, _P);
  }

  /// Update step: incorporate measurement (innovation: de, dn) and measurement noise R (m²).
  /// Uses Joseph form for numerical stability.
  /// Returns (state, covariance) after update.
  (List<double>, List<List<double>>) update(double de, double dn, double R, List<List<double>> Ppred) {
    final H = [
      [1.0, 0.0, 0.0, 0.0],
      [0.0, 1.0, 0.0, 0.0],
    ];
    final z = [de, dn];

    // Innovation covariance S = H * Ppred * H^T + R*I
    final HP = _matMul(H, Ppred);
    final HPHt = _matMul(HP, _transpose(H));
    final S = [
      [HPHt[0][0] + R, HPHt[0][1]],
      [HPHt[1][0], HPHt[1][1] + R],
    ];

    // Kalman gain K = Ppred * H^T * inv(S)
    final PHt = _matMul(Ppred, _transpose(H));
    final det = S[0][0] * S[1][1] - S[0][1] * S[1][0];
    if (det.abs() < 1e-12) return (_x, _P); // singular, skip update
    final invS = [
      [S[1][1] / det, -S[0][1] / det],
      [-S[1][0] / det, S[0][0] / det],
    ];
    final K = _matMul(PHt, invS); // 4x2

    // x = x + K * z
    final xUpd = List<double>.from(_x);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 2; j++) {
        xUpd[i] += K[i][j] * z[j];
      }
    }

    // Joseph form: P = (I - K*H) * Ppred * (I - K*H)^T + K*R*K^T
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

  /// Inflate covariance (soft reset) by factor (default 6)
  void inflateCovariance([double factor = 6.0]) {
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        _P[i][j] *= factor;
      }
    }
  }

  /// Reset filter state to initial
  void reset(double east, double north) {
    _x = [east, north, 0.0, 0.0];
    _resetCovariance();
  }

  /// Check if covariance is healthy (no NaN/Inf and finite)
  bool isHealthy() {
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        final v = _P[i][j];
        if (v.isNaN || v.isInfinite || v.abs() > 1e6) return false;
      }
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
