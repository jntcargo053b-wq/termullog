// lib/services/location_weather_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

class LocationWeatherService {
  final String address;
  final String weather;

  LocationWeatherService({
    required this.address,
    required this.weather,
  });

  /// Fetch address dan weather dari posisi GPS
  static Future<LocationWeatherService> fetchFromPosition(Position position) async {
    String address = '';
    String weather = '';

    try {
      // Fetch address dari Nominatim OpenStreetMap
      final nominatimUrl = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=jsonv2'
        '&lat=${position.latitude}'
        '&lon=${position.longitude}'
        '&zoom=18'
        '&addressdetails=1'
        '&accept-language=id',
      );

      final nominatimResponse = await http.get(
        nominatimUrl,
        headers: {
          'User-Agent': 'TermulLog/1.0',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (nominatimResponse.statusCode == 200) {
        final data = jsonDecode(nominatimResponse.body);
        if (data != null && data['display_name'] != null) {
          address = data['display_name'];
          debugPrint('📍 Address: $address');
        }
      } else {
        debugPrint('❌ Nominatim error: ${nominatimResponse.statusCode}');
      }

      // Fetch weather dari Open-Meteo (gratis, tanpa API key)
      final weatherUrl = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${position.latitude}'
        '&longitude=${position.longitude}'
        '&current_weather=true',
      );

      final weatherResponse = await http.get(
        weatherUrl,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (weatherResponse.statusCode == 200) {
        final data = jsonDecode(weatherResponse.body);
        if (data != null && data['current_weather'] != null) {
          final current = data['current_weather'];
          final temp = current['temperature']?.round();
          final code = current['weathercode'];
          final condition = _weatherCodeToString(code);
          weather = '$condition • $temp°C';
          debugPrint('🌤️ Weather: $weather');
        }
      } else {
        debugPrint('❌ Weather API error: ${weatherResponse.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ fetchFromPosition error: $e');
    }

    return LocationWeatherService(address: address, weather: weather);
  }

  /// Convert weather code ke string deskripsi
  static String _weatherCodeToString(int? code) {
    if (code == null) return 'Tidak diketahui';
    switch (code) {
      case 0:
        return 'Cerah';
      case 1:
      case 2:
      case 3:
        return 'Berawan';
      case 45:
      case 48:
        return 'Berkabut';
      case 51:
      case 53:
      case 55:
        return 'Gerimis';
      case 61:
      case 63:
      case 65:
        return 'Hujan';
      case 71:
      case 73:
      case 75:
        return 'Salju';
      case 80:
      case 81:
      case 82:
        return 'Hujan Lebat';
      case 95:
      case 96:
      case 99:
        return 'Badai Petir';
      default:
        return 'Berawan';
    }
  }

  /// Fetch mini map dengan fallback provider (FIX FINAL)
  static Future<Uint8List?> fetchMapWithRetry(
    double lat,
    double lon, {
    int maxRetries = 3,
  }) async {
    final urls = [
      // Provider utama: OpenStreetMap static map
      Uri.parse(
        'https://staticmap.openstreetmap.de/staticmap.php'
        '?center=$lat,$lon'
        '&zoom=16'
        '&size=400x300'
        '&maptype=mapnik'
        '&markers=$lat,$lon,red-pushpin',
      ),
      // Fallback provider: LocationIQ (ganti API key jika perlu)
      Uri.parse(
        'https://maps.locationiq.com/v3/staticmap'
        '?key=pk.8c0f4d6c7d8f4d6c7d8f4d6c7d8f4d6c'   // <-- GANTI dengan API key Anda sendiri!
        '&center=$lat,$lon'
        '&zoom=16'
        '&size=400x300'
        '&markers=icon:large-red-cutout|$lat,$lon',
      ),
    ];

    for (final url in urls) {
      for (int attempt = 1; attempt <= maxRetries; attempt++) {
        http.Client? client;

        try {
          debugPrint('🗺️ Fetching mini map');
          debugPrint('URL: $url');
          debugPrint('Attempt: $attempt/$maxRetries');

          client = http.Client();

          final response = await client
              .get(
                url,
                headers: {
                  'User-Agent': 'Mozilla/5.0',
                  'Accept': 'image/png,image/*,*/*',
                  'Connection': 'keep-alive',
                },
              )
              .timeout(const Duration(seconds: 20));

          if (response.statusCode == 200 &&
              response.bodyBytes.isNotEmpty) {
            final bytes = Uint8List.fromList(response.bodyBytes);

            // Validasi PNG/JPG
            final isPng =
                bytes.length > 4 &&
                bytes[0] == 0x89 &&
                bytes[1] == 0x50;

            final isJpg =
                bytes.length > 4 &&
                bytes[0] == 0xFF &&
                bytes[1] == 0xD8;

            if (isPng || isJpg) {
              debugPrint('✅ Mini map berhasil diunduh');
              return bytes;
            }

            debugPrint('❌ Response bukan image valid');
          } else {
            debugPrint(
              '❌ HTTP ${response.statusCode} - ${response.reasonPhrase}',
            );
          }
        } catch (e) {
          debugPrint('❌ Mini map error: $e');
        } finally {
          client?.close();
        }

        await Future.delayed(const Duration(seconds: 2));
      }
    }

    debugPrint('❌ Semua provider mini map gagal');
    return null;
  }
}
