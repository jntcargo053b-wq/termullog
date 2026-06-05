// lib/services/pod_address_resolver.dart
// ============================================================
// POD ADDRESS RESOLVER — Proof of Delivery Edition
// ============================================================
// Strategi:
//   1. Nominatim (OSM) — primary, level jalan + RT/RW/kel/kec/kota
//   2. Photon (Komoot) — fallback 1
//   3. Android Geocoder — fallback 2
//   4. Koordinat DMS    — last resort (tidak pernah kosong)
//
// Fitur khusus POD:
//   - Multi-query Nominatim dengan zoom berurutan (18→16→14) agar
//     alamat selalu ada walaupun di area rural/terpencil.
//   - Normalisasi: hapus plus-code, deduplikasi, urutkan dari
//     spesifik ke umum (jalan → kelurahan → kecamatan → kota).
//   - Cache LRU 100 entri + nearby-cache radius 8m (10 menit).
//   - Retry otomatis sekali jika HTTP timeout.
//   - Cross-session persistence via SharedPreferences (20 entri).
// ============================================================

import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _NearbyEntry {
  final double lat, lon;
  final String address;
  final DateTime savedAt;
  _NearbyEntry(this.lat, this.lon, this.address, this.savedAt);
}

class PodAddressResolver {
  // ── HTTP Client ──────────────────────────────────────────
  static http.Client _client = http.Client();
  static bool _closed = false;

  static void close() {
    if (_closed) return;
    _closed = true;
    _client.close();
  }

  static void reopen() {
    if (!_closed) return;
    _client = http.Client();
    _closed = false;
  }

  // ── Exact-coordinate cache (LRU, 5 desimal = ~1.1m) ─────
  static final LinkedHashMap<String, String> _exactCache =
      LinkedHashMap();
  static const int _exactCacheMax = 100;

  // ── Nearby cache (radius 8m, TTL 10 menit) ───────────────
  static final List<_NearbyEntry> _nearbyCache = [];
  static const double _nearbyCacheRadius = 8.0;  // meter
  static const Duration _nearbyTtl = Duration(minutes: 10);
  static const int _nearbyCacheMax = 50;

  // ── Rate limiting Nominatim (1 req/detik sesuai ToS) ─────
  static DateTime _lastNominatim = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _nominatimInterval = Duration(seconds: 1);

  // ── Cross-session persistence ─────────────────────────────
  static const String _prefKey = 'pod_address_cache_v2';
  static bool _persistLoaded = false;

  static Future<void> loadPersistentCache() async {
    if (_persistLoaded) return;
    _persistLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw == null || raw.isEmpty) return;
      final map = Map<String, String>.from(jsonDecode(raw) as Map);
      for (final e in map.entries) {
        _exactCache[e.key] = e.value;
      }
      if (kDebugMode) debugPrint('PodAddressResolver: loaded ${_exactCache.length} persisted entries');
    } catch (_) {}
  }

  static Future<void> _persistCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Simpan max 20 entri terbaru
      final entries = _exactCache.entries.toList();
      final slice = entries.length > 20
          ? entries.sublist(entries.length - 20)
          : entries;
      final map = Map.fromEntries(slice);
      await prefs.setString(_prefKey, jsonEncode(map));
    } catch (_) {}
  }

  // ── Regex plus-code ───────────────────────────────────────
  static final RegExp _plusCodeRe = RegExp(
    r'(?:^|[\s,])([23456789CFGHJMPQRVWX]{4,8}\+[23456789CFGHJMPQRVWX]{2,3})(?:[\s,]|$)',
    caseSensitive: false,
  );

  static bool _isPlusCode(String? s) =>
      s != null && _plusCodeRe.hasMatch(s.trim());

  // ── PUBLIC ENTRY POINT ────────────────────────────────────
  /// Resolves centroid coordinates to a clean Indonesian address.
  /// Always returns non-empty string (DMS fallback if all fail).
  static Future<String> resolve(double lat, double lon) async {
    final key = _cacheKey(lat, lon);

    // 1. Exact cache
    final exact = _exactCache[key];
    if (exact != null) {
      _exactCache.remove(key);
      _exactCache[key] = exact; // LRU: move to end
      if (kDebugMode) debugPrint('PodAddressResolver: exact cache hit → $exact');
      return exact;
    }

    // 2. Nearby cache
    final nearby = _nearbyLookup(lat, lon);
    if (nearby != null) {
      if (kDebugMode) debugPrint('PodAddressResolver: nearby cache hit → $nearby');
      return nearby;
    }

    // 3. Fetch from providers
    final address = await _fetchWithFallback(lat, lon);

    if (address.isNotEmpty) {
      _putExact(key, address);
      _putNearby(lat, lon, address);
      await _persistCache();
    }

    return address.isNotEmpty ? address : _toDMS(lat, lon);
  }

  // ── Fetch dengan fallback chain ───────────────────────────
  static Future<String> _fetchWithFallback(double lat, double lon) async {
    final latS = lat.toStringAsFixed(7);
    final lonS = lon.toStringAsFixed(7);

    // Nominatim: coba zoom 18 → 16 → 14
    for (final zoom in [18, 16, 14]) {
      try {
        final r = await _nominatim(latS, lonS, zoom: zoom);
        if (r.isNotEmpty) {
          if (kDebugMode) debugPrint('PodAddressResolver: Nominatim z$zoom → $r');
          return r;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('PodAddressResolver: Nominatim z$zoom error → $e');
      }
    }

    // Photon fallback
    try {
      final r = await _photon(latS, lonS);
      if (r.isNotEmpty) {
        if (kDebugMode) debugPrint('PodAddressResolver: Photon → $r');
        return r;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PodAddressResolver: Photon error → $e');
    }

    // Android Geocoder
    try {
      final r = await _androidGeocoder(lat, lon);
      if (r.isNotEmpty && !r.contains('Unnamed Road')) {
        if (kDebugMode) debugPrint('PodAddressResolver: Android → $r');
        return r;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PodAddressResolver: Android error → $e');
    }

    return '';
  }

  // ── Nominatim ─────────────────────────────────────────────
  static Future<String> _nominatim(String lat, String lon, {int zoom = 18}) async {
    if (_closed) return '';

    // Rate limit
    final now = DateTime.now();
    final elapsed = now.difference(_lastNominatim);
    if (elapsed < _nominatimInterval) {
      await Future.delayed(_nominatimInterval - elapsed);
    }
    _lastNominatim = DateTime.now();

    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse'
          '?format=jsonv2&lat=$lat&lon=$lon'
          '&zoom=$zoom&addressdetails=1&accept-language=id',
        );
        final res = await _client.get(uri, headers: {
          'User-Agent': 'TermulLog/2.0 (termullog@example.com)',
          'Accept-Language': 'id,en;q=0.8',
        }).timeout(const Duration(seconds: 7));

        if (res.statusCode == 429) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        if (res.statusCode != 200) return '';

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return _parseNominatimAddress(data);
      } catch (_) {
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 600));
          continue;
        }
        return '';
      }
    }
    return '';
  }

  static String _parseNominatimAddress(Map<String, dynamic> data) {
    final addr = data['address'] as Map<String, dynamic>?;
    if (addr == null) {
      // Fallback ke display_name
      final display = data['display_name'] as String?;
      if (display != null && display.isNotEmpty) {
        return _cleanDisplayName(display);
      }
      return '';
    }

    String? _s(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    // Jalan (prioritas: road > residential > pedestrian > service)
    final road = _s(addr['road'])
        ?? _s(addr['residential'])
        ?? _s(addr['pedestrian'])
        ?? _s(addr['footway'])
        ?? _s(addr['path'])
        ?? _s(addr['service'])
        ?? _s(addr['track'])
        ?? _s(addr['cycleway']);
    final houseNum = _s(addr['house_number']);

    // Sub-area (RT/RW level)
    final suburb = _s(addr['suburb'])
        ?? _s(addr['neighbourhood'])
        ?? _s(addr['quarter'])
        ?? _s(addr['allotments']);

    // Kelurahan/desa
    final village = _s(addr['village'])
        ?? _s(addr['hamlet'])
        ?? _s(addr['isolated_dwelling'])
        ?? _s(addr['locality']);

    // Kecamatan
    final subdistrict = _s(addr['subdistrict'])
        ?? _s(addr['city_district'])
        ?? _s(addr['district']);

    // Kota/kabupaten
    final city = _s(addr['city'])
        ?? _s(addr['town'])
        ?? _s(addr['municipality'])
        ?? _s(addr['county']);

    // Provinsi (opsional, hanya jika tidak ada kota)
    final state = city == null ? (_s(addr['state'])) : null;

    final parts = <String>[];

    // Jalan + nomor
    if (road != null) {
      parts.add(houseNum != null ? '$road No.$houseNum' : road);
    }

    // Tambah sub-area
    if (suburb != null && suburb != road) parts.add(suburb);

    // Kelurahan/desa (jika beda dari suburb)
    if (village != null && village != suburb) parts.add(village);

    // Kecamatan (deduplikasi)
    if (subdistrict != null &&
        subdistrict != suburb &&
        subdistrict != village) {
      parts.add(subdistrict);
    }

    // Kota
    if (city != null) parts.add(city);
    if (state != null) parts.add(state);

    if (parts.isEmpty) {
      // Gunakan display_name sebagai last resort
      final display = data['display_name'] as String?;
      if (display != null && display.isNotEmpty) {
        return _cleanDisplayName(display);
      }
      return '';
    }

    return _dedup(parts).join(', ');
  }

  static String _cleanDisplayName(String display) {
    // Ambil max 5 bagian, hapus plus code, strip whitespace
    final parts = display
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && !_isPlusCode(p))
        .take(5)
        .toList();
    return parts.isEmpty ? '' : parts.join(', ');
  }

  // ── Photon ────────────────────────────────────────────────
  static Future<String> _photon(String lat, String lon) async {
    if (_closed) return '';
    try {
      final uri = Uri.parse(
          'https://photon.komoot.io/reverse?lat=$lat&lon=$lon&lang=id');
      final res = await _client.get(uri, headers: {
        'User-Agent': 'TermulLog/2.0 (termullog@example.com)',
      }).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return '';

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) return '';

      final props = features[0]['properties'] as Map<String, dynamic>? ?? {};

      String? _s(String k) {
        final v = props[k];
        if (v == null) return null;
        final s = v.toString().trim();
        return s.isEmpty ? null : s;
      }

      final name     = _s('name');
      final street   = _s('street');
      final housenum = _s('housenumber');
      final district = _s('district');
      final city     = _s('city');
      final state    = _s('state');

      final parts = <String>[];
      if (name != null && name != street) parts.add(name);
      if (street != null) {
        parts.add(housenum != null ? '$street No.$housenum' : street);
      }
      if (district != null) parts.add(district);
      if (city != null) parts.add(city);
      if (state != null && state != city) parts.add(state);

      return parts.isEmpty ? '' : _dedup(parts).join(', ');
    } catch (_) {
      return '';
    }
  }

  // ── Android Geocoder ──────────────────────────────────────
  static Future<String> _androidGeocoder(double lat, double lon) async {
    if (_closed) return '';
    try {
      final placemarks = await placemarkFromCoordinates(
        lat, lon,
        localeIdentifier: 'id_ID',
      ).timeout(const Duration(seconds: 6));
      if (placemarks.isEmpty) return '';
      final p = placemarks.first;

      final parts = <String>[];
      final road = p.thoroughfare ?? p.street ?? '';
      if (road.isNotEmpty && !_isPlusCode(road)) parts.add(road);
      if ((p.subLocality ?? '').isNotEmpty && !_isPlusCode(p.subLocality)) {
        parts.add(p.subLocality!);
      }
      if ((p.locality ?? '').isNotEmpty && !_isPlusCode(p.locality)) {
        parts.add(p.locality!);
      }
      if ((p.administrativeArea ?? '').isNotEmpty &&
          !_isPlusCode(p.administrativeArea)) {
        parts.add(p.administrativeArea!);
      }
      return parts.isEmpty ? '' : _dedup(parts).join(', ');
    } catch (_) {
      return '';
    }
  }

  // ── Cache helpers ─────────────────────────────────────────
  static String _cacheKey(double lat, double lon) =>
      '${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';

  static void _putExact(String key, String value) {
    if (_exactCache.length >= _exactCacheMax) {
      _exactCache.remove(_exactCache.keys.first);
    }
    _exactCache[key] = value;
  }

  static void _putNearby(double lat, double lon, String address) {
    _nearbyCache.removeWhere(
        (e) => DateTime.now().difference(e.savedAt) > _nearbyTtl);
    if (_nearbyCache.length >= _nearbyCacheMax) _nearbyCache.removeAt(0);
    _nearbyCache.add(_NearbyEntry(lat, lon, address, DateTime.now()));
  }

  static String? _nearbyLookup(double lat, double lon) {
    final now = DateTime.now();
    _NearbyEntry? best;
    double bestDist = double.infinity;
    for (final e in _nearbyCache) {
      if (now.difference(e.savedAt) > _nearbyTtl) continue;
      final d = Geolocator.distanceBetween(lat, lon, e.lat, e.lon);
      if (d <= _nearbyCacheRadius && d < bestDist) {
        bestDist = d;
        best = e;
      }
    }
    return best?.address;
  }

  // ── Helpers ───────────────────────────────────────────────
  static List<String> _dedup(List<String> parts) =>
      LinkedHashSet<String>.from(parts).toList();

  static String _toDMS(double lat, double lon) {
    final latDms = _dms(lat, true);
    final lonDms = _dms(lon, false);
    return 'GPS: $latDms, $lonDms';
  }

  static String _dms(double coord, bool isLat) {
    final abs = coord.abs();
    final deg = abs.floor();
    final min = ((abs - deg) * 60).floor();
    final sec = ((abs - deg - min / 60) * 3600).toStringAsFixed(1);
    final dir = isLat ? (coord >= 0 ? 'N' : 'S') : (coord >= 0 ? 'E' : 'W');
    return "$deg°$min'$sec\" $dir";
  }
}
