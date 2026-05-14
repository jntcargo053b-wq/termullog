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

  /// Fetch peta mini dari OpenStreetMap static map API
  static Future<Uint8List?> fetchMapWithRetry(
    double lat,
    double lon, {
    int maxRetries = 2,
  }) async {
    int attempt = 0;

    while (attempt < maxRetries) {
      try {
        attempt++;
        debugPrint('🗺️ Map fetch attempt $attempt/$maxRetries');
        debugPrint('   lat: $lat, lon: $lon');

        final client = http.Client();

        // Valid markers: ol-marker, ol-marker-blue, ol-marker-green,
        // ol-marker-red, ol-marker-gold, ol-marker-black
        final url = Uri.parse(
          'https://staticmap.openstreetmap.de/staticmap.php'
          '?center=$lat,$lon'
          '&zoom=16'
          '&size=400x300'
          '&maptype=mapnik'
          '&markers=$lat,$lon,ol-marker',
        );

        debugPrint('🗺️ Map URL: $url');

        final response = await client.get(
          url,
          headers: {
            'User-Agent': 'TermulLog/1.0',
            'Accept': 'image/png',
          },
        ).timeout(const Duration(seconds: 15));

        client.close();

        if (response.statusCode == 200) {
          final bytes = Uint8List.fromList(response.bodyBytes);

          // Validasi bahwa response benar-benar gambar PNG
          if (bytes.length > 8 &&
              bytes[0] == 0x89 &&
              bytes[1] == 0x50 &&
              bytes[2] == 0x4E &&
              bytes[3] == 0x47) {
            debugPrint('✅ Valid PNG map received: ${bytes.length} bytes');
            return bytes;
          } else {
            // Mungkin error text dari server
            if (bytes.isNotEmpty && bytes.length < 1000) {
              final text = utf8.decode(bytes, allowMalformed: true);
              debugPrint('❌ Response bukan gambar PNG (${bytes.length} bytes): $text');
            } else {
              debugPrint('❌ Response bukan gambar PNG: ${bytes.length} bytes');
            }
            return null;
          }
        } else {
          debugPrint('❌ Map API returned HTTP ${response.statusCode}');
          if (response.body.isNotEmpty) {
            debugPrint('   Response body: ${response.body.substring(0, 200)}');
          }
          if (attempt < maxRetries) {
            await Future.delayed(Duration(seconds: attempt * 2));
          }
        }
      } on TimeoutException {
        debugPrint('⏱️ Map fetch timeout (attempt $attempt)');
        if (attempt >= maxRetries) return null;
        await Future.delayed(Duration(seconds: attempt * 2));
      } catch (e) {
        debugPrint('❌ Map fetch error (attempt $attempt): $e');
        if (attempt >= maxRetries) return null;
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }

    return null;
  }
}
