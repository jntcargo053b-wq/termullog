import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GPS STABILIZER
//
// Masalah:  GPS ponsel memberi reading yang loncat-loncat karena sensor belum
//           stabil (terutama 1–3 detik pertama). Reverse geocoding yang dijalankan
//           di koordinat berbeda menghasilkan nama jalan/alamat yang berbeda.
//
// Solusi:   1. Kumpulkan beberapa reading selama maksimum [maxWaitMs] ms.
//           2. Pilih reading dengan accuracy terkecil (paling akurat).
//           3. Tolak reading yang accuracy-nya di atas [maxAccuracyMeters].
//           4. Cache hasil geocoding: jika foto berikutnya diambil di titik
//              yang berjarak < [cacheRadiusMeters] dari cache, gunakan alamat
//              yang sudah ada tanpa request baru ke geocoder.
// ─────────────────────────────────────────────────────────────────────────────

class GpsStabilizer {
  GpsStabilizer._();
  static final GpsStabilizer instance = GpsStabilizer._();

  // ── Konfigurasi ────────────────────────────────────────────────────────────
  /// Jumlah reading yang dikumpulkan sebelum memilih yang terbaik.
  static const int _sampleCount = 8;

  /// Batas accuracy maksimum (meter). Reading di atas ini diabaikan.
  /// 30 m cukup untuk nama jalan; turunkan ke 15 m untuk presisi tinggi.
  static const double _maxAccuracyMeters = 30.0;

  /// Waktu tunggu maksimum keseluruhan (ms). Jika habis, pakai reading terbaik
  /// yang sudah terkumpul meski belum mencapai [_sampleCount].
  static const int _maxWaitMs = 15000;

  /// Jarak (meter) dari posisi cache sebelumnya. Jika foto baru diambil
  /// di dalam radius ini, skip geocoding & pakai alamat dari cache.
  static const double _cacheRadiusMeters = 50.0;

  // ── Cache internal ─────────────────────────────────────────────────────────
  _GeoCache? _cache;

  // ─────────────────────────────────────────────────────────────────────────
  // getBestPosition
  //
  // Kumpulkan [_sampleCount] reading dari stream GPS, kembalikan yang paling
  // akurat. Timeout ke [_maxWaitMs] ms jika GPS lambat.
  // ─────────────────────────────────────────────────────────────────────────
  Future<Position?> getBestPosition() async {
    final List<Position> samples = [];
    final Completer<void> done = Completer();

    final LocationSettings settings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,          // terima semua perubahan koordinat
      intervalDuration: const Duration(milliseconds: 500),
    );

    late StreamSubscription<Position> sub;
    sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        // Hanya simpan reading dengan accuracy yang masuk threshold
        if (pos.accuracy <= _maxAccuracyMeters) {
          samples.add(pos);
          debugPrint(
            'GPS sample ${samples.length}/$_sampleCount'
            ' — acc: ${pos.accuracy.toStringAsFixed(1)}m'
            ' (${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)})',
          );
        } else {
          debugPrint(
            'GPS sample dibuang — acc: ${pos.accuracy.toStringAsFixed(1)}m'
            ' (melebihi batas $_maxAccuracyMeters m)',
          );
        }

        if (samples.length >= _sampleCount && !done.isCompleted) {
          done.complete();
        }
      },
      onError: (e) {
        debugPrint('GPS stream error: $e');
        if (!done.isCompleted) done.complete();
      },
    );

    // Timeout paksa supaya tidak menunggu selamanya
    await done.future.timeout(
      Duration(milliseconds: _maxWaitMs),
      onTimeout: () {
        debugPrint('GPS stabilizer timeout — pakai ${samples.length} sample');
      },
    );

    await sub.cancel();

    if (samples.isEmpty) {
      debugPrint('Tidak ada GPS sample valid, fallback ke getCurrentPosition');
      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('getCurrentPosition fallback gagal: $e');
        return null;
      }
    }

    // Pilih reading dengan accuracy terkecil (paling akurat)
    samples.sort((a, b) => a.accuracy.compareTo(b.accuracy));
    final best = samples.first;
    debugPrint(
      'GPS terpilih: acc=${best.accuracy.toStringAsFixed(1)}m'
      ' dari ${samples.length} sample',
    );
    return best;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // getAddressCached
  //
  // Kembalikan alamat dari cache jika posisi [pos] masih di dalam radius
  // [_cacheRadiusMeters] dari cache sebelumnya. Jika tidak, kosongkan cache
  // dan biarkan caller melakukan geocoding baru.
  //
  // Kembalikan: (address, weather) — keduanya nullable.
  //   null berarti caller harus fetch ulang.
  // ─────────────────────────────────────────────────────────────────────────
  ({String? address, String? weather}) getCachedGeoData(Position pos) {
    final c = _cache;
    if (c == null) return (address: null, weather: null);

    final dist = _distanceMeters(
      c.latitude, c.longitude, pos.latitude, pos.longitude,
    );

    if (dist <= _cacheRadiusMeters) {
      debugPrint(
        'GeoCache HIT — jarak ${dist.toStringAsFixed(1)}m'
        ' (cache radius $_cacheRadiusMeters m)',
      );
      return (address: c.address, weather: c.weather);
    }

    debugPrint(
      'GeoCache MISS — jarak ${dist.toStringAsFixed(1)}m'
      ' (melebihi radius $_cacheRadiusMeters m), fetch ulang',
    );
    return (address: null, weather: null);
  }

  /// Simpan hasil geocoding baru ke cache.
  void saveToCache({
    required double latitude,
    required double longitude,
    required String address,
    required String weather,
  }) {
    _cache = _GeoCache(
      latitude: latitude,
      longitude: longitude,
      address: address,
      weather: weather,
      savedAt: DateTime.now(),
    );
    debugPrint('GeoCache disimpan: "$address"');
  }

  /// Hapus cache (misalnya saat app di-background lama).
  void clearCache() => _cache = null;

  // ─────────────────────────────────────────────────────────────────────────
  // Haversine distance (meter)
  // ─────────────────────────────────────────────────────────────────────────
  static double _distanceMeters(
    double lat1, double lon1, double lat2, double lon2,
  ) {
    const r = 6371000.0; // radius bumi (meter)
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _toRad(double deg) => deg * math.pi / 180;
}

// ─────────────────────────────────────────────────────────────────────────────
// Model cache internal
// ─────────────────────────────────────────────────────────────────────────────
class _GeoCache {
  final double latitude;
  final double longitude;
  final String address;
  final String weather;
  final DateTime savedAt;

  const _GeoCache({
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.weather,
    required this.savedAt,
  });
}
