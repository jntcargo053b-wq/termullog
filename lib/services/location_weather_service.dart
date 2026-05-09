import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:geocoding/geocoding.dart'; // Tambahkan import ini

class LocationWeatherResult {
  final String address;
  final String weather;
  const LocationWeatherResult({required this.address, required this.weather});
}

class LocationWeatherService {
  LocationWeatherService._();

  static Future<LocationWeatherResult> fetchFromPosition(Position position) async {
    String address = '';
    String weather = '';

    final lat = position.latitude;
    final lon = position.longitude;
    final latStr = lat.toStringAsFixed(6);
    final lonStr = lon.toStringAsFixed(6);

    // Fallback koordinat
    address = 'GPS: ${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';

    // ─── PRIORITAS 1: Nominatim (OpenStreetMap) ─────────────────────────
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json&lat=$latStr&lon=$lonStr&zoom=18&addressdetails=1',
      );
      final res = await http
          .get(uri, headers: {'User-Agent': 'TermulLog/1.0'})
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>?;
        
        if (addr != null) {
          final parts = <String>[];
          
          // Urutan alamat Indonesia yang benar
          final houseNumber = addr['house_number'] as String?;
          final road = addr['road'] as String?;
          final village = addr['village'] as String? ?? addr['suburb'] as String?;
          final subDistrict = addr['suburb'] as String?; // kecamatan
          final city = addr['city'] as String? ?? addr['town'] as String? ?? addr['county'] as String?;
          final regency = addr['county'] as String?; // kabupaten
          final province = addr['state'] as String?;
          final postcode = addr['postcode'] as String?;
          
          // Bangun alamat lengkap
          if (houseNumber != null && houseNumber.isNotEmpty) parts.add(houseNumber);
          if (road != null && road.isNotEmpty) parts.add(road);
          if (village != null && village.isNotEmpty) parts.add(village);
          if (subDistrict != null && subDistrict.isNotEmpty) parts.add('Kec. $subDistrict');
          if (city != null && city.isNotEmpty) parts.add(city);
          if (regency != null && regency.isNotEmpty && regency != city) parts.add(regency);
          if (province != null && province.isNotEmpty) parts.add(province);
          if (postcode != null && postcode.isNotEmpty) parts.add(postcode);
          
          final resolved = parts.join(', ');
          if (resolved.isNotEmpty) {
            address = resolved;
          } else {
            final display = data['display_name'] as String?;
            if (display != null) {
              // Ambil 4 komponen pertama dari display_name
              final short = display.split(',').take(4).join(',').trim();
              if (short.isNotEmpty) address = short;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Nominatim error: $e');
    }

    // ─── PRIORITAS 2: Geocoding package (fallback jika Nominatim gagal) ───
    if (address.startsWith('GPS:')) {
      try {
        final placemarks = await placemarkFromCoordinates(lat, lon).timeout(
          const Duration(seconds: 5),
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = <String>[];
          
          if (p.subThoroughfare != null && p.subThoroughfare!.isNotEmpty) parts.add(p.subThoroughfare!);
          if (p.thoroughfare != null && p.thoroughfare!.isNotEmpty) parts.add(p.thoroughfare!);
          if (p.subLocality != null && p.subLocality!.isNotEmpty) parts.add(p.subLocality!);
          if (p.subAdministrativeArea != null && p.subAdministrativeArea!.isNotEmpty) {
            parts.add('Kec. ${p.subAdministrativeArea}');
          }
          if (p.locality != null && p.locality!.isNotEmpty) parts.add(p.locality!);
          if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty) parts.add(p.administrativeArea!);
          if (p.postalCode != null && p.postalCode!.isNotEmpty) parts.add(p.postalCode!);
          
          final fallbackAddr = parts.join(', ');
          if (fallbackAddr.isNotEmpty) address = fallbackAddr;
        }
      } catch (e) {
        debugPrint('Geocoding fallback error: $e');
      }
    }

    // ─── Cuaca Open-Meteo ────────────────────────────────────────────────
    try {
      final wUri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$latStr&longitude=$lonStr'
        '&current=temperature_2m,weathercode&timezone=auto',
      );
      final wRes = await http.get(wUri).timeout(const Duration(seconds: 8));
      if (wRes.statusCode == 200) {
        final wData = jsonDecode(wRes.body) as Map<String, dynamic>;
        final current = wData['current'] as Map<String, dynamic>?;
        if (current != null) {
          final temp = (current['temperature_2m'] as num?)?.toStringAsFixed(0) ?? '--';
          final code = (current['weathercode'] as num?)?.toInt() ?? 0;
          weather = '${_wmoDesc(code)} ${temp}°C';
        }
      }
    } catch (e) {
      debugPrint('Weather error: $e');
    }

    return LocationWeatherResult(address: address, weather: weather);
  }

  static String _wmoDesc(int c) {
    if (c == 0) return 'Cerah';
    if (c <= 3) return 'Berawan';
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
