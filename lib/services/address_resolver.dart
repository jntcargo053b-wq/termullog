// lib/services/address_resolver.dart
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

/// AddressResolver bertanggung jawab untuk memutuskan kapan perlu melakukan reverse geocode
/// berdasarkan posisi GPS terbaru. Menggunakan throttle cerdas:
/// - Jarak minimal (meter) dari geocode terakhir
/// - Interval waktu minimal (detik)
/// - Deteksi perbaikan akurasi yang signifikan
/// - Debounce untuk mencegah panggilan berlebihan saat GPS masih berfluktuasi
class AddressResolver {
  // State untuk throttle
  double? _lastLat;
  double? _lastLon;
  double? _lastAccuracy;
  DateTime? _lastTime;
  Timer? _debounceTimer;
  bool _pending = false;

  // Parameter throttle (dapat disesuaikan)
  static const double _minDistanceMeters = 15.0;      // jarak minimal untuk geocode ulang
  static const int _minIntervalSeconds = 5;           // interval minimal antar geocode
  static const double _accuracyImprovementThreshold = 8.0; // perbaikan akurasi >8m trigger refresh
  static const int _debounceMilliseconds = 1500;      // tunggu 1.5 detik sebelum eksekusi

  /// Reset semua state (dipanggil saat aplikasi resume atau force unlock)
  void reset() {
    _lastLat = null;
    _lastLon = null;
    _lastAccuracy = null;
    _lastTime = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pending = false;
  }

  /// Dipanggil setiap kali ada posisi GPS baru.
  /// `onGeocode` adalah callback async yang akan dipanggil jika throttle memutuskan perlu geocode.
  void onPositionUpdate(Position pos, Future<void> Function(Position) onGeocode) {
    // Jika sudah ada proses pending, abaikan (biarkan yang pertama selesai)
    if (_pending) return;

    final now = DateTime.now();
    bool shouldGeocode = false;

    // Kriteria pertama: belum pernah geocode
    if (_lastLat == null || _lastLon == null) {
      shouldGeocode = true;
    } else {
      // Hitung jarak dari posisi terakhir yang di-geocode
      final distance = _haversine(
        _lastLat!, _lastLon!,
        pos.latitude, pos.longitude,
      );
      final timeSinceLast = _lastTime == null ? 0 : now.difference(_lastTime!).inSeconds;
      final accuracyImproved = _lastAccuracy != null &&
          pos.accuracy < (_lastAccuracy! - _accuracyImprovementThreshold);

      // Geocode jika:
      // - jarak melebihi threshold, ATAU
      // - waktu melebihi interval, ATAU
      // - akurasi membaik secara signifikan (misal dari 20m ke 10m)
      if (distance >= _minDistanceMeters ||
          timeSinceLast >= _minIntervalSeconds ||
          accuracyImproved) {
        shouldGeocode = true;
      }
    }

    if (!shouldGeocode) return;

    // Debounce: batalkan timer sebelumnya jika ada
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: _debounceMilliseconds), () async {
      // Update state segera setelah debounce selesai (sebelum async)
      _pending = true;
      _lastLat = pos.latitude;
      _lastLon = pos.longitude;
      _lastAccuracy = pos.accuracy;
      _lastTime = DateTime.now();
      _debounceTimer = null;

      try {
        await onGeocode(pos);
      } catch (e) {
        if (kDebugMode) debugPrint('AddressResolver: geocode failed - $e');
        // Jika gagal, kita tidak rollback state karena sudah mencoba.
        // Biarkan state tetap update agar tidak langsung retry.
      } finally {
        _pending = false;
      }
    });
  }

  /// Helper haversine (sama seperti di GpsLockManager, di-copy untuk independensi)
  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) *
            sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  /// Bersihkan resource (panggil saat dispose)
  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
}
