// lib/services/pod_gps_engine.dart
// ============================================================
// POD GPS ENGINE — Proof of Delivery Edition
// ============================================================
// Two-Phase Optimized Thresholds:
//   - Phase 1: Accept samples up to 50m for fast address (1-3 detik)
//   - Phase 2: Target 15m accuracy for precise address (5-8 detik)
//   - Reduced min samples for faster initial lock
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

  // ── Tuning parameters — Two-Phase Optimized ─────────────────
  // Sample requirements (lebih cepat untuk Phase 2)
  static const int    _minSamplesGood      = 6;    // Turun dari 10 → cukup 6 sample untuk good
  static const int    _minSamplesExcellent = 12;   // Turun dari 15 → 12 sample untuk excellent
  static const int    _maxWindowSize       = 20;
  static const int    _keepOnUnlock        = 6;

  // Accuracy filter — mendukung Two-Phase
  static const double _maxRawAccuracy      = 50.0; // Naik dari 25 → terima sample sampai 50m (Phase 1)
  static const double _excellentAccuracy   = 8.0;  // Premium: 8m untuk excellent
  static const double _goodAccuracy        = 15.0; // Turun dari 18 → 15m untuk good (Phase 2 trigger)

  // Cluster filter
  static const double _maxClusterRadius    = 12.0; // Naik dari 10 → 12m untuk excellent
  static const double _maxClusterRadiusGood = 20.0; // Naik dari 18 → 20m untuk good

  // Outlier rejection (3σ dari centroid, min 6m)
  static const double _outlierSigmaFactor  = 3.0;
  static const double _outlierMinMeters    = 6.0;

  // Movement detection (lebih toleran)
  static const double _moveThresholdMeters = 8.0;  // Naik dari 5 → 8m untuk unlock
  static const double _hardResetMeters     = 25.0; // Naik dari 15 → 25m untuk full reset

  // Kalman smoothing per-dimension
  static const double _kalmanQ             = 0.5;
  static const double _kalmanR             = 4.0;

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

  /// Progress 0.0–1.0 menuju lock (dioptimalkan untuk two-phase)
  double get lockProgress {
    if (_window.isEmpty) return 0.0;
    
    // Sample progress terhadap target good (6 sample)
    final sampleProgress = (_window.length / _minSamplesGood).clamp(0.0, 1.0);
    
    if (_window.length >= 2) {
      final radius = _computeClusterRadius();
      final radiusOk = radius <= _maxClusterRadiusGood;
      final avgAcc = _window.map((s) => s.accuracy).reduce((a, b) => a + b) / _window.length;
      final accOk = avgAcc <= _goodAccuracy;
      
      // Jika akurasi sudah ≤15m, progress lebih cepat
      if (avgAcc <= 15.0) {
        return (sampleProgress * 0.8 + 0.2).clamp(0.0, 1.0);
      }
      if (radiusOk && accOk) return sampleProgress;
      
      // Penalti jika cluster atau akurasi belum bagus
      return sampleProgress * 0.6;
    }
    return sampleProgress * 0.3;
  }

  // ── Main: proses satu sample dari OS ──────────────────────
  /// Returns true jika terjadi upgrade confidence
  bool processSample(Position rawPos) {
    // 1. Anti-spoof: tolak mock GPS + HARD RESET
    if (rawPos.isMocked) {
      if (kDebugMode) debugPrint('PodGpsEngine: MOCK GPS detected — HARD RESET');
      _hardReset();
      _confidence = PodConfidence.poor;
      return false;
    }

    // 2. Filter akurasi kasar (sekarang sampai 50m untuk Phase 1)
    if (rawPos.accuracy > _maxRawAccuracy) {
      if (kDebugMode) debugPrint('PodGpsEngine: acc=${rawPos.accuracy.toStringAsFixed(1)}m > ${_maxRawAccuracy.toInt()}m, skip');
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
      accuracy: rawPos.accuracy,
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
      final avgAcc = _weightedMeanAccuracy();
      debugPrint('PodGpsEngine: ${_confidence.label} | '
          'n=${_window.length} radius=${radius.toStringAsFixed(1)}m '
          'acc=${rawPos.accuracy.toStringAsFixed(1)}m '
          'avgAcc=${avgAcc.toStringAsFixed(1)}m '
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
    
    // Excellent: akurasi ≤8m, cluster ≤12m, minimal 12 sample
    if (_window.length >= _minSamplesExcellent &&
        radius <= _maxClusterRadius &&
        avgAcc <= _excellentAccuracy &&
        score >= 0.85) {
      newConf = PodConfidence.excellent;
    } 
    // Good: akurasi ≤15m, cluster ≤20m, minimal 6 sample
    else if (_window.length >= _minSamplesGood &&
        radius <= _maxClusterRadiusGood &&
        avgAcc <= _goodAccuracy &&
        score >= 0.65) {
      newConf = PodConfidence.good;
    } 
    // Fair: sudah ada beberapa sample dengan akurasi reasonable
    else if (_window.length >= 3 && avgAcc <= 35.0) {
      newConf = PodConfidence.fair;
    } 
    else {
      newConf = PodConfidence.poor;
    }

    _confidence = newConf;

    if (_confidence.canCapture) {
      _lockResult = _buildLockResult(score, radius);
    } else if (_window.isNotEmpty) {
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

    double sumLat = 0, sumLon = 0;
    for (final s in _window) { sumLat += s.lat; sumLon += s.lon; }
    final mLat = sumLat / _window.length;
    final mLon = sumLon / _window.length;

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

    // Factor 1: jumlah sample (bobot 30%)
    final fSample = (_window.length / _minSamplesExcellent).clamp(0.0, 1.0);

    // Factor 2: cluster radius (bobot 35%)
    final radius = _computeClusterRadius();
    final fRadius = radius.isInfinite ? 0.0 : 
        (1.0 - (radius / _maxClusterRadius).clamp(0.0, 1.0));

    // Factor 3: rata-rata akurasi (bobot 35%)
    final avgAcc = _weightedMeanAccuracy();
    final fAcc = (1.0 - (avgAcc / _maxRawAccuracy).clamp(0.0, 1.0));

    return (fSample * 0.30) + (fRadius * 0.35) + (fAcc * 0.35);
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

  // ── Haversine dengan NaN protection ───────────────────────
  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) *
            sin(dLon / 2) * sin(dLon / 2);
    
    // NaN protection
    final safeA = a.clamp(0.0, 1.0);
    return R * 2 * atan2(sqrt(safeA), sqrt(1.0 - safeA));
  }
}
