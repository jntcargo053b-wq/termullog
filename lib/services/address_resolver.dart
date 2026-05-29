// lib/services/address_resolver.dart
//
// Mengelola kapan reverse geocode boleh dipanggil.
// Dipisahkan dari GPS stream agar mudah ditest dan tidak bloat CameraScreen.
//
// Aturan refresh alamat:
//   1. First-fix dengan accuracy <= 40m          → geocode
//   2. Accuracy membaik >= 10m dari geocode terakhir, AND acc <= 25m → geocode
//   3. Pindah > 15m (dengan acc <= 30m)           → geocode
//   4. Force setiap 15 detik (dengan acc <= 30m)  → geocode
//   5. Selalu debounce 2 detik agar tidak spam saat GPS masih hunting

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

typedef ReverseGeocodeCallback = Future<void> Function(Position pos);

class AddressResolver {
  // ─── Thresholds ──────────────────────────────────────────────────────────
  /// Jangan pernah geocode jika accuracy lebih buruk dari ini (cached / tower)
  static const double maxAccuracyM = 40.0;

  /// Accuracy cukup baik untuk address yang bisa dipercaya
  static const double goodAccuracyM = 25.0;

  /// Re-geocode jika accuracy membaik minimal sebesar ini
  static const double improvementThresholdM = 10.0;

  /// Re-geocode jika bergerak lebih dari ini
  static const double moveThresholdM = 15.0;

  /// Force re-geocode maksimal setiap N detik
  static const int forceIntervalSeconds = 15;

  /// Debounce: tunda geocode selama ini sebelum eksekusi
  static const Duration debounce = Duration(seconds: 2);

  // ─── State ───────────────────────────────────────────────────────────────
  Position? _lastGeocodedPos;   // posisi saat geocode terakhir BERHASIL
  double? _lastGeocodedAcc;     // accuracy saat geocode terakhir berhasil
  DateTime? _lastGeocodeTime;
  bool _isGeocoding = false;    // sedang fetch → jangan overlap

  Timer? _debounceTimer;

  // ─── Public API ──────────────────────────────────────────────────────────

  /// Panggil setiap kali ada sample GPS baru masuk.
  /// [onGeocode] dipanggil saat resolver memutuskan perlu refresh alamat.
  void onPositionUpdate(Position pos, ReverseGeocodeCallback onGeocode) {
    if (!_shouldSchedule(pos)) return;

    // Debounce: batalkan jadwal lama, set jadwal baru
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => _executeGeocode(pos, onGeocode));
  }

  /// Reset semua state — panggil saat app resume dari background.
  void reset() {
    _debounceTimer?.cancel();
    _lastGeocodedPos = null;
    _lastGeocodedAcc = null;
    _lastGeocodeTime = null;
    _isGeocoding = false;
  }

  void dispose() {
    _debounceTimer?.cancel();
  }

  // ─── Private ─────────────────────────────────────────────────────────────

  bool _shouldSchedule(Position pos) {
    final acc = pos.accuracy;

    // Jangan sentuh alamat jika GPS masih dari cache / tower
    if (acc > maxAccuracyM) {
      if (kDebugMode) debugPrint('[AddressResolver] skip: acc=${acc.toStringAsFixed(0)}m > $maxAccuracyM');
      return false;
    }

    // Sedang fetch → jangan overlap (debounce sudah pending)
    if (_isGeocoding) return false;

    // 1. First-fix
    if (_lastGeocodedPos == null) {
      if (kDebugMode) debugPrint('[AddressResolver] trigger: first-fix acc=${acc.toStringAsFixed(0)}m');
      return true;
    }

    // 2. Accuracy membaik signifikan
    final lastAcc = _lastGeocodedAcc ?? double.infinity;
    if (acc <= goodAccuracyM && (lastAcc - acc) >= improvementThresholdM) {
      if (kDebugMode) debugPrint('[AddressResolver] trigger: accuracy improved ${lastAcc.toStringAsFixed(0)}→${acc.toStringAsFixed(0)}m');
      return true;
    }

    // 3. Bergerak > moveThreshold (hanya jika akurasi cukup)
    if (acc <= goodAccuracyM) {
      final dist = Geolocator.distanceBetween(
        _lastGeocodedPos!.latitude,
        _lastGeocodedPos!.longitude,
        pos.latitude,
        pos.longitude,
      );
      if (dist > moveThresholdM) {
        if (kDebugMode) debugPrint('[AddressResolver] trigger: moved ${dist.toStringAsFixed(0)}m');
        return true;
      }
    }

    // 4. Force interval
    if (_lastGeocodeTime != null) {
      final elapsed = DateTime.now().difference(_lastGeocodeTime!).inSeconds;
      if (elapsed >= forceIntervalSeconds && acc <= goodAccuracyM) {
        if (kDebugMode) debugPrint('[AddressResolver] trigger: force interval ${elapsed}s');
        return true;
      }
    }

    return false;
  }

  Future<void> _executeGeocode(
    Position pos,
    ReverseGeocodeCallback onGeocode,
  ) async {
    if (_isGeocoding) return;
    _isGeocoding = true;

    try {
      await onGeocode(pos);

      // Commit setelah berhasil
      _lastGeocodedPos = pos;
      _lastGeocodedAcc = pos.accuracy;
      _lastGeocodeTime = DateTime.now();

      if (kDebugMode) {
        debugPrint(
          '[AddressResolver] geocode OK: acc=${pos.accuracy.toStringAsFixed(0)}m '
          'pos=(${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)})',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AddressResolver] geocode ERROR: $e');
      // Jangan commit _lastGeocodedPos → biarkan retry di sample berikutnya
    } finally {
      _isGeocoding = false;
    }
  }
}
