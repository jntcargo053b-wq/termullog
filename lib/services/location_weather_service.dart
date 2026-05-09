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

  // Method baru: menerima Position langsung
  static Future<LocationWeatherResult> fetchFromPosition(Position position) async {
    String address = '';
    String weather = '';

    final lat = position.latitude;
    final lon = position.longitude;
    final latStr = lat.toStringAsFixed(6);
    final lonStr = lon.toStringAsFixed(6);

    // Default fallback
    address = 'GPS: ${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';

    // Geocoding via Nominatim
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json&lat=$latStr&lon=$lonStr&zoom=16&addressdetails=1',
      );
      final res = await http
          .get(uri, headers: {'User-Agent': 'TermulLog/1.0'})
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>?;
        if (addr != null) {
          final parts = <String>[];
          final house = addr['house_number'] as String?;
          final road = addr['road'] as String?;
          final suburb = addr['suburb'] ?? addr['village'];
          final city = addr['city'] ?? addr['town'] ?? addr['county'];
          if (house != null && house.isNotEmpty) parts.add(house);
          if (road != null && road.isNotEmpty) parts.add(road);
          if (suburb != null && suburb.toString().isNotEmpty) parts.add(suburb.toString());
          if (city != null && city.toString().isNotEmpty) parts.add(city.toString());
          final resolved = parts.join(', ');
          if (resolved.isNotEmpty) address = resolved;
          else {
            final display = data['display_name'] as String?;
            if (display != null) address = display.split(',').take(2).join(',').trim();
          }
        }
      }
    } catch (e) {
      debugPrint('Nominatim error: $e');
    }

    // Cuaca
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
