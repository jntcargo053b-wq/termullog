import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:geocoding/geocoding.dart';

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
    address = 'GPS: ${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}';

    // ─── PRIORITAS 1: Geocoding Package (lebih lengkap untuk Indonesia) ───
    try {
      final placemarks = await placemarkFromCoordinates(lat, lon).timeout(
        const Duration(seconds: 8),
      );
      
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[];
        
        // Urutan alamat Indonesia dari terkecil ke terbesar
        // Nomor rumah / blok
        if (p.subThoroughfare != null && p.subThoroughfare!.isNotEmpty) {
          parts.add(p.subThoroughfare!);
        }
        
        // Nama jalan
        if (p.thoroughfare != null && p.thoroughfare!.isNotEmpty) {
          parts.add(p.thoroughfare!);
        }
        
        // Kelurahan/Desa (subLocality)
        if (p.subLocality != null && p.subLocality!.isNotEmpty) {
          parts.add('Kel. ${p.subLocality}');
        }
        
        // Kecamatan (subAdministrativeArea)
        if (p.subAdministrativeArea != null && p.subAdministrativeArea!.isNotEmpty) {
          parts.add('Kec. ${p.subAdministrativeArea}');
        }
        
        // Kota/Kabupaten (locality)
        if (p.locality != null && p.locality!.isNotEmpty) {
          parts.add(p.locality!);
        }
        
        // Provinsi (administrativeArea)
        if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty) {
          parts.add(p.administrativeArea!);
        }
        
        // Kode Pos
        if (p.postalCode != null && p.postalCode!.isNotEmpty) {
          parts.add(p.postalCode!);
        }
        
        final resolved = parts.join(', ');
        if (resolved.isNotEmpty) {
          address = resolved;
          debugPrint('Address from geocoding: $address');
        }
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
    }

    // ─── PRIORITAS 2: Nominatim (OpenStreetMap) jika geocoding gagal ──────
    if (address.startsWith('GPS:')) {
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
            
            // Nomor rumah
            final houseNumber = addr['house_number'] as String?;
            if (houseNumber != null && houseNumber.isNotEmpty) {
              parts.add(houseNumber);
            }
            
            // Nama jalan
            final road = addr['road'] as String?;
            if (road != null && road.isNotEmpty) {
              parts.add(road);
            }
            
            // Kelurahan/desa
            final village = addr['village'] as String? ?? addr['suburb'] as String?;
            if (village != null && village.isNotEmpty) {
              parts.add('Kel. $village');
            }
            
            // Kecamatan
            final district = addr['suburb'] as String?;
            if (district != null && district.isNotEmpty && district != village) {
              parts.add('Kec. $district');
            }
            
            // Kota/kabupaten
            final city = addr['city'] as String? ?? addr['town'] as String? ?? addr['county'] as String?;
            if (city != null && city.isNotEmpty) {
              parts.add(city);
            }
            
            // Provinsi
            final province = addr['state'] as String?;
            if (province != null && province.isNotEmpty) {
              parts.add(province);
            }
            
            // Kode pos
            final postcode = addr['postcode'] as String?;
            if (postcode != null && postcode.isNotEmpty) {
              parts.add(postcode);
            }
            
            final resolved = parts.join(', ');
            if (resolved.isNotEmpty) {
              address = resolved;
              debugPrint('Address from Nominatim: $address');
            } else {
              final display = data['display_name'] as String?;
              if (display != null) {
                address = display.split(',').take(4).join(',').trim();
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Nominatim error: $e');
      }
    }

    // ─── PRIORITAS 3: Koordinat saja jika semua gagal ─────────────────────
    if (address.startsWith('GPS:')) {
      address = '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}';
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
    if (c == 0) return '🌞 Cerah';
    if (c <= 3) return '⛅ Berawan';
    if (c <= 49) return '🌫️ Berkabut';
    if (c <= 59) return '🌧️ Gerimis';
    if (c <= 67) return '🌧️ Hujan';
    if (c <= 77) return '❄️ Bersalju';
    if (c <= 82) return '🌧️ Hujan Lebat';
    if (c <= 86) return '❄️ Salju Lebat';
    if (c == 95) return '⚡ Badai Petir';
    if (c <= 99) return '🌨️ Badai+Hujan Es';
    return '🌡️ Tidak diketahui';
  }
}
