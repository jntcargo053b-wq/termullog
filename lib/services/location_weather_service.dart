// ════════════════════════════════════════════════════════════════════════════
//  services/location_weather_service.dart
//  Mengambil koordinat GPS, nama alamat (Nominatim), dan cuaca (Open-Meteo)
//
//  Fallback strategy:
//    • Alamat  → "GPS: lat, lon"  jika geocoding gagal  (tidak pernah kosong)
//    • Cuaca   → ""               jika API gagal         (tidak tampil di watermark)
// ════════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class LocationWeatherResult {
  final String address;
  final String weather;
  const LocationWeatherResult({required this.address, required this.weather});
}

class LocationWeatherService {
  LocationWeatherService._();

  static Future<LocationWeatherResult> fetch() async {
    String address = '';
    String weather  = '';

    try {
      // ── 1. Cek layanan & izin GPS ────────────────────────────────────────
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return LocationWeatherResult(address: address, weather: weather);

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return LocationWeatherResult(address: address, weather: weather);
      }

      // ── 2. Ambil posisi ──────────────────────────────────────────────────
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 15));

      final lat    = pos.latitude;
      final lon    = pos.longitude;
      final latStr = lat.toStringAsFixed(6);
      final lonStr = lon.toStringAsFixed(6);

      // Default address = koordinat GPS (bukan "tidak tersedia")
      address = 'GPS: ${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';

      // ── 3. Geocoding (Nominatim) ─────────────────────────────────────────
      try {
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse'
          '?format=json&lat=$latStr&lon=$lonStr&zoom=16&addressdetails=1',
        );
        final res = await http
            .get(uri, headers: {'User-Agent': 'TermulLog/1.0'})
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final addr = data['address'] as Map<String, dynamic>?;
          if (addr != null) {
            final parts  = <String>[];
            final road   = addr['road']   as String?;
            final suburb = addr['suburb'] as String? ?? addr['village'] as String?;
            final city   = addr['city']   as String?
                        ?? addr['town']   as String?
                        ?? addr['county'] as String?;
            if (road   != null && road.isNotEmpty)   parts.add(road);
            if (suburb != null && suburb.isNotEmpty) parts.add(suburb);
            if (city   != null && city.isNotEmpty)   parts.add(city);

            final resolved = parts.take(3).join(', ');
            if (resolved.isNotEmpty) {
              address = resolved;
            } else {
              final displayName = (data['display_name'] as String?) ?? '';
              final short = displayName.split(',').take(2).join(',').trim();
              if (short.isNotEmpty) address = short;
            }
          }
        }
      } catch (e) {
        debugPrint('Geocoding error: $e');
        // Tetap pakai "GPS: lat, lon"
      }

      // ── 4. Cuaca (Open-Meteo) ────────────────────────────────────────────
      try {
        final wUri = Uri.parse(
          'https://api.open-meteo.com/v1/forecast'
          '?latitude=$latStr&longitude=$lonStr'
          '&current=temperature_2m,weathercode&timezone=auto',
        );
        final wRes = await http.get(wUri).timeout(const Duration(seconds: 10));
        if (wRes.statusCode == 200) {
          final wData   = jsonDecode(wRes.body) as Map<String, dynamic>;
          final current = wData['current'] as Map<String, dynamic>?;
          if (current != null) {
            final temp = (current['temperature_2m'] as num?)
                    ?.toStringAsFixed(0) ?? '--';
            final code = (current['weathercode'] as num?)?.toInt() ?? 0;
            weather = '${_wmoDesc(code)} ${temp}°C';
          }
        }
        // Jika gagal → weather tetap '' (tidak tampil di watermark)
      } catch (e) {
        debugPrint('Weather error: $e');
      }
    } catch (e) {
      debugPrint('LocationWeatherService error: $e');
    }

    return LocationWeatherResult(address: address, weather: weather);
  }

  static String _wmoDesc(int c) {
    if (c == 0)  return 'Cerah';
    if (c <= 3)  return 'Berawan';
    if (c <= 49) return 'Berkabut';
    if (c <= 59) return 'Gerimis';
    if (c <= 67) return 'Hujan';
    if (c <= 77) return 'Bersalju';
    if (c <= 82) return 'Hujan Lebat';
    if (c <= 86) return 'Salju Lebat';
    if (c == 95) return 'Badai Petir';
    if (c <= 99) return 'Badai+Hujan Es';
    return '';
  }
}
