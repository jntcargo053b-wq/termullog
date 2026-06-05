// lib/services/pod_gps_engine.dart
// ============================================================
// POD GPS ENGINE — Proof of Delivery Edition
// ============================================================
// Arsitektur baru yang menggantikan GpsLockManagerLogistics.
//
// Filosofi POD:
//   1. ANTI-SPOOF: Tolak mock GPS & deteksi anomali koordinat.
//   2. MULTI-SAMPLE CENTROID: Kumpulkan ≥10 sample, hitung weighted
//      centroid (bobot = 1/σ²). Centroid ini dipakai sebagai titik
//      resmi untuk alamat dan watermark.
//   3. CONFIDENCE BERJENJANG: 4 level (poor→fair→good→excellent).
//      Foto hanya bisa diambil di level good+.
//   4. KALMAN SMOOTHING PER-SAMPLE: Setiap sample dilewatkan filter
//      Kalman 1D sederhana (lat + lon terpisah) sebelum masuk window.
//   5. OUTLIER REJECTION: Sample dengan jarak >3σ dari mean window
//      dibuang (Chauvenet-style).
//   6. AUDIT TRAIL: Setiap lock menyimpan metadata lengkap:
//      rawBestAccuracy, samplesUsed, clusterStdDev, timestamps.
//   7. RE-LOCK CEPAT: Setelah bergerak, mode Stabilizing mempertahankan
//      sebagian window sehingga lock ulang 2× lebih cepat.
// ============================================================

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

// ── Confidence level ─────────────────────────────────────────
enum PodConfidence {
  searching,  // Belum ada data
  poor,       // Ada data, tapi belum stabil
  fair,       // Cukup untuk preview, tidak untuk capture
  good,       // OK untuk capture
  excellent,  // High-confidence POD
}

extension PodConfidenceLabel on PodConfidence {
  String get label {
    switch (this) {
      case PodConfidence.searching: return '🔍 Mencari…';
      case PodConfidence.poor:      return '📡 Sinyal Lemah';
      case PodConfidence.fair:      return '⚡ Stabilisasi…';
      case PodConfidence.good:      return '✅ Siap Foto';
      case PodConfidence.excellent: return '🎯 Terkunci';
    }
  }

  bool get canCapture => this == PodConfidence.good || this == PodConfidence.excellent;
  bool get isLocked   => this == PodConfidence.excellent;
}

// ── Satu snapshot GPS yang sudah divalidasi ───────────────────
class PodSample {
  final double lat;
  final double lon;
  final double accuracy;   // meter, dari OS
  final double weight;     // 1 / (accuracy^2), pre-computed
  final DateTime time;

  PodSample({
    required this.lat,
    required this.lon,
    required this.accuracy,
    required this.time,
  }) : weight = 1.0 / (accuracy.clamp(1.0, 200.0) * accuracy.clamp(1.0, 200.0));
}

// ── Hasil lock resmi untuk ditulis ke watermark / audit ──────
class PodLockResult {
  /// Titik stabil (weighted centroid) → dipakai untuk geocode & watermark
  final double centroidLat;
  final double centroidLon;

  /// Akurasi representatif (weighted mean accuracy)
  final double accuracy;

  /// Nilai confidence numerik 0–1
  final double confidenceScore;

  /// Level confidence enum
  final PodConfidence confidence;

  /// Sample terbaik (akurasi paling kecil) → disimpan sebagai raw audit
  final PodSample bestRaw;

  /// Statistik window
  final int samplesUsed;
  final double clusterStdDevMeters;  // std-dev dari centroid, dalam meter
  final double clusterRadiusMeters;  // radius maksimum dari centroid

  /// Waktu lock
  final DateTime lockedAt;

  /// Label singkat untuk UI
  String get qualityLabel {
    if (confidence == PodConfidence.excellent) return 'Excellent';
    if (confidence == PodConfidence.good)      return 'Good';
    if (confidence == PodConfidence.fair)      return 'Fair';
    return 'Poor';
  }

  const PodLockResult({
    required this.centroidLat,
    required this.centroidLon,
    required this.accuracy,
    required this.confidenceScore,
    required this.confidence,
    required this.bestRaw,
    required this.samplesUsed,
    required this.clusterStdDevMeters,
    required this.clusterRadiusMeters,
    required this.lockedAt,
  });

  PodLockResult copyWith({
    double? accuracy,
    double? confidenceScore,
    PodConfidence? confidence,
    PodSample? bestRaw,
  }) {
    return PodLockResult(
      centroidLat: centroidLat,
      centroidLon: centroidLon,
      accuracy: accuracy ?? this.accuracy,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      confidence: confidence ?? this.confidence,
      bestRaw: bestRaw ?? this.bestRaw,
      samplesUsed: samplesUsed,
      clusterStdDevMeters: clusterStdDevMeters,
      clusterRadiusMeters: clusterRadiusMeters,
      lockedAt: lockedAt,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// PodGpsEngine — MAIN CLASS
// ═══════════════════════════════════════════════════════════════
class PodGpsEngine {

  // ── Tuning parameters ──────────────────────────────────────
  // Sample requirements
  static const int    _minSamplesGood      = 10;   // samples untuk "good"
  static const int    _minSamplesExcellent = 15;   // samples untuk "excellent"
  static const int    _maxWindowSize       = 20;   // rolling window max
  static const int    _keepOnUnlock        = 6;    // sisa sample saat unlock

  // Accuracy filter
  static const double _maxRawAccuracy      = 25.0; // buang sample >25m
  static const double _excellentAccuracy   = 8.0;  // threshold excellent
  static const double _goodAccuracy        = 18.0; // threshold good

  // Cluster filter
  static const double _maxClusterRadius    = 10.0; // cluster radius max untuk excellent
  static const double _maxClusterRadiusGood = 18.0; // cluster radius max untuk good

  // Outlier rejection (3σ dari centroid, min 6m)
  static const double _outlierSigmaFactor  = 3.0;
  static const double _outlierMinMeters    = 6.0;

  // Movement detection
  static const double _moveThresholdMeters = 5.0;  // bergerak >5m → unlock
  static const double _hardResetMeters     = 15.0; // bergerak >15m → full reset

  // Kalman smoothing per-dimension (sederhana, bukan 4D)
  // Process noise Q, measurement noise R
  static const double _kalmanQ             = 0.5;
  static const double _kalmanR             = 4.0;  // ~2m std-dev

  // ── State ──────────────────────────────────────────────────
  final List<PodSample> _window = [];
  PodLockResult? _lockResult;
  PodConfidence _confidence = PodConfidence.searching;

  // Kalman state per-dimensi
  double _kfLat = 0.0, _kfLon = 0.0;
  double _kfPLat = 1.0, _kfPLon = 1.0;
  bool _kfInitialized = false;

  // Movement tracking
  double _lastLat = 0.0, _lastLon = 0.0;
  bool _positionInitialized = false;

  // ── Public getters ─────────────────────────────────────────
  PodConfidence get confidence => _confidence;
  PodLockResult? get lockResult => _lockResult;
  bool get canCapture => _confidence.canCapture;
  bool get isLocked => _confidence == PodConfidence.excellent;
  int get sampleCount => _window.length;
  int get samplesNeeded => _minSamplesGood;

  /// Progress 0.0–1.0 menuju lock
  double get lockProgress {
    if (_window.isEmpty) return 0.0;
    final sampleProgress = (_window.length / _minSamplesGood).clamp(0.0, 1.0);
    if (_window.length >= 2) {
      final radius = _computeClusterRadius();
      final radiusOk = radius <= _maxClusterRadius;
      final avgAcc = _window.map((s) => s.accuracy).reduce((a, b) => a + b) / _window.length;
      final accOk = avgAcc <= _goodAccuracy;
      if (radiusOk && accOk) return sampleProgress;
      // Penalti jika cluster atau akurasi belum bagus
      return sampleProgress * 0.6;
    }
    return sampleProgress * 0.3;
  }

  // ── Main: proses satu sample dari OS ──────────────────────
  /// Returns true jika terjadi upgrade confidence (termasuk ke locked/good).
  bool processSample(Position rawPos) {
    // 1. Anti-spoof: tolak mock GPS
    if (rawPos.isMocked) {
      if (kDebugMode) debugPrint('PodGpsEngine: MOCK GPS rejected');
      _confidence = PodConfidence.poor;
      return false;
    }

    // 2. Filter akurasi kasar
    if (rawPos.accuracy > _maxRawAccuracy) {
      if (kDebugMode) debugPrint('PodGpsEngine: acc=${rawPos.accuracy.toStringAsFixed(1)}m too low, skip');
      if (_confidence == PodConfidence.searching && _window.isEmpty) {
        _confidence = PodConfidence.poor;
      }
      return false;
    }

    // 3. Kalman smoothing (per-dimensi)
    final (smoothLat, smoothLon) = _kalmanUpdate(rawPos.latitude, rawPos.longitude, rawPos.accuracy);

    // 4. Deteksi pergerakan
    final movedMeters = _positionInitialized
        ? _haversine(_lastLat, _lastLon, smoothLat, smoothLon)
        : 0.0;

    _lastLat = smoothLat;
    _lastLon = smoothLon;
    _positionInitialized = true;

    if (movedMeters >= _hardResetMeters) {
      _hardReset();
      if (kDebugMode) debugPrint('PodGpsEngine: HARD RESET (moved ${movedMeters.toStringAsFixed(1)}m)');
    } else if (movedMeters >= _moveThresholdMeters && _confidence.canCapture) {
      _softUnlock();
      if (kDebugMode) debugPrint('PodGpsEngine: SOFT UNLOCK (moved ${movedMeters.toStringAsFixed(1)}m)');
    }

    // 5. Tambah sample ke window
    final sample = PodSample(
      lat: smoothLat,
      lon: smoothLon,
      accuracy: rawPos.accuracy, // pakai akurasi asli, bukan smoothed
      time: rawPos.timestamp ?? DateTime.now(),
    );

    _window.add(sample);
    if (_window.length > _maxWindowSize) _window.removeAt(0);

    // 6. Outlier rejection setelah cukup sample
    if (_window.length >= 5) _rejectOutliers();

    // 7. Evaluasi confidence
    final prevConf = _confidence;
    _evaluateConfidence();
    final upgraded = _confidence.index > prevConf.index;

    if (kDebugMode && _window.isNotEmpty) {
      final radius = _window.length >= 2 ? _computeClusterRadius() : 0.0;
      debugPrint('PodGpsEngine: ${_confidence.label} | '
          'n=${_window.length} radius=${radius.toStringAsFixed(1)}m '
          'acc=${rawPos.accuracy.toStringAsFixed(1)}m '
          'score=${(_computeScore() * 100).toInt()}%');
    }

    return upgraded;
  }

  // ── Evaluasi dan bangun lockResult ────────────────────────
  void _evaluateConfidence() {
    if (_window.isEmpty) {
      _confidence = PodConfidence.searching;
      _lockResult = null;
      return;
    }

    final score = _computeScore();
    final radius = _computeClusterRadius();
    final avgAcc = _weightedMeanAccuracy();

    PodConfidence newConf;
    if (_window.length >= _minSamplesExcellent &&
        radius <= _maxClusterRadius &&
        avgAcc <= _excellentAccuracy &&
        score >= 0.88) {
      newConf = PodConfidence.excellent;
    } else if (_window.length >= _minSamplesGood &&
        radius <= _maxClusterRadiusGood &&
        avgAcc <= _goodAccuracy &&
        score >= 0.72) {
      newConf = PodConfidence.good;
    } else if (_window.length >= 4 && avgAcc <= 30.0) {
      newConf = PodConfidence.fair;
    } else {
      newConf = PodConfidence.poor;
    }

    _confidence = newConf;

    if (_confidence.canCapture) {
      _lockResult = _buildLockResult(score, radius);
    } else if (_window.isNotEmpty) {
      // Fair/poor: simpan partial result untuk display
      _lockResult = _buildLockResult(score, radius);
    }
  }

  PodLockResult _buildLockResult(double score, double radius) {
    // Weighted centroid
    double sumW = 0, sumLat = 0, sumLon = 0, sumAcc = 0;
    PodSample? bestRaw;
    for (final s in _window) {
      sumW   += s.weight;
      sumLat += s.lat * s.weight;
      sumLon += s.lon * s.weight;
      sumAcc += s.accuracy * s.weight;
      if (bestRaw == null || s.accuracy < bestRaw.accuracy) bestRaw = s;
    }
    final cLat = sumLat / sumW;
    final cLon = sumLon / sumW;
    final wAcc = sumAcc / sumW;

    // Std-dev dari centroid (dalam meter)
    double sumSq = 0;
    for (final s in _window) {
      final d = _haversine(cLat, cLon, s.lat, s.lon);
      sumSq += d * d;
    }
    final stdDev = sqrt(sumSq / _window.length);

    return PodLockResult(
      centroidLat: cLat,
      centroidLon: cLon,
      accuracy: wAcc,
      confidenceScore: score,
      confidence: _confidence,
      bestRaw: bestRaw!,
      samplesUsed: _window.length,
      clusterStdDevMeters: stdDev,
      clusterRadiusMeters: radius,
      lockedAt: DateTime.now(),
    );
  }

  // ── Outlier rejection (Chauvenet 3σ) ─────────────────────
  void _rejectOutliers() {
    if (_window.length < 4) return;

    // Hitung centroid sementara (unweighted cukup)
    double sumLat = 0, sumLon = 0;
    for (final s in _window) { sumLat += s.lat; sumLon += s.lon; }
    final mLat = sumLat / _window.length;
    final mLon = sumLon / _window.length;

    // Hitung std-dev jarak
    double sumSq = 0;
    for (final s in _window) {
      final d = _haversine(mLat, mLon, s.lat, s.lon);
      sumSq += d * d;
    }
    final stdDev = sqrt(sumSq / _window.length);
    final threshold = max(_outlierSigmaFactor * stdDev, _outlierMinMeters);

    final before = _window.length;
    _window.removeWhere((s) {
      final d = _haversine(mLat, mLon, s.lat, s.lon);
      return d > threshold;
    });

    if (kDebugMode && _window.length < before) {
      debugPrint('PodGpsEngine: outlier removed ${before - _window.length} samples '
          '(threshold=${threshold.toStringAsFixed(1)}m)');
    }
  }

  // ── Kalman 1D per-dimensi ─────────────────────────────────
  (double, double) _kalmanUpdate(double lat, double lon, double accuracy) {
    if (!_kfInitialized) {
      _kfLat = lat;
      _kfLon = lon;
      _kfPLat = accuracy * accuracy;
      _kfPLon = accuracy * accuracy;
      _kfInitialized = true;
      return (lat, lon);
    }

    final R = accuracy * accuracy;

    // Lat
    _kfPLat += _kalmanQ;
    final kLat = _kfPLat / (_kfPLat + max(R, _kalmanR));
    _kfLat += kLat * (lat - _kfLat);
    _kfPLat *= (1 - kLat);

    // Lon
    _kfPLon += _kalmanQ;
    final kLon = _kfPLon / (_kfPLon + max(R, _kalmanR));
    _kfLon += kLon * (lon - _kfLon);
    _kfPLon *= (1 - kLon);

    return (_kfLat, _kfLon);
  }

  // ── Score komposit ────────────────────────────────────────
  double _computeScore() {
    if (_window.isEmpty) return 0.0;

    // Factor 1: jumlah sample (bobot 35%)
    final fSample = (_window.length / _minSamplesExcellent).clamp(0.0, 1.0);

    // Factor 2: cluster radius (bobot 40%)
    final radius = _computeClusterRadius();
    final fRadius = (1.0 - (radius / _maxClusterRadius).clamp(0.0, 1.0));

    // Factor 3: rata-rata akurasi (bobot 25%)
    final avgAcc = _weightedMeanAccuracy();
    final fAcc = (1.0 - (avgAcc / _maxRawAccuracy).clamp(0.0, 1.0));

    return (fSample * 0.35) + (fRadius * 0.40) + (fAcc * 0.25);
  }

  double _computeClusterRadius() {
    if (_window.length < 2) return double.infinity;
    double sumLat = 0, sumLon = 0;
    for (final s in _window) { sumLat += s.lat; sumLon += s.lon; }
    final cLat = sumLat / _window.length;
    final cLon = sumLon / _window.length;
    double maxDist = 0;
    for (final s in _window) {
      final d = _haversine(cLat, cLon, s.lat, s.lon);
      if (d > maxDist) maxDist = d;
    }
    return maxDist;
  }

  double _weightedMeanAccuracy() {
    if (_window.isEmpty) return 999.0;
    double sumW = 0, sumAcc = 0;
    for (final s in _window) {
      sumW += s.weight;
      sumAcc += s.accuracy * s.weight;
    }
    return sumAcc / sumW;
  }

  // ── Reset helpers ─────────────────────────────────────────
  void _softUnlock() {
    // Pertahankan sebagian sample terbaru agar re-lock lebih cepat
    while (_window.length > _keepOnUnlock) _window.removeAt(0);
    _confidence = PodConfidence.fair;
    _lockResult = null;
  }

  void _hardReset() {
    _window.clear();
    _lockResult = null;
    _confidence = PodConfidence.searching;
    _kfInitialized = false;
    _positionInitialized = false;
  }

  void reset() => _hardReset();

  // ── Haversine ─────────────────────────────────────────────
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
