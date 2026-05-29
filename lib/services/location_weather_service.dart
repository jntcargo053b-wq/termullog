// lib/services/location_weather_service.dart
import 'dart:collection';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:geocoding/geocoding.dart';

class LocationWeatherResult {
  final String address;
  final String weather;
  final String rawAddress;
  const LocationWeatherResult({
    required this.address,
    required this.weather,
    this.rawAddress = '',
  });
}

class LocationWeatherService {
  LocationWeatherService._();

  static final http.Client _client = http.Client();
  static bool _isClosed = false;
  static const String _locationIqApiKey = 'pk.05a5be327fe64484e26fca823101a387';

  static void close() {
    if (_isClosed) return;
    _isClosed = true;
    _client.close();
  }

  static final RegExp _plusCodePattern = RegExp(
    r'(?:^|[\s,])([23456789CFGHJMPQRVWX]{4,8}\+[23456789CFGHJMPQRVWX]{2,3})(?:[\s,]|$)',
    caseSensitive: false,
  );

  static bool _isPlusCode(String? s) {
    if (s == null || s.isEmpty) return false;
    return _plusCodePattern.hasMatch(s.trim());
  }

  static String _stripPlusCode(String address) {
    final parts = address
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && !_isPlusCode(p))
        .toList();
    return parts.isEmpty ? address : parts.join(', ');
  }

  static List<String> _uniqueParts(List<String> parts) {
    return LinkedHashSet<String>.from(parts).toList();
  }

  static Future<LocationWeatherResult> fetchFromPosition(Position position) async {
    final lat = position.latitude;
    final lon = position.longitude;
    final latStr = lat.toStringAsFixed(6);
    final lonStr = lon.toStringAsFixed(6);

    // Tidak ada cache alamat – throttle sudah di AddressResolver
    final addressFuture = _fetchAddressParallel(lat, lon, latStr, lonStr);
    final weatherFuture = _fetchWeather(lat, lon);

    final results = await Future.wait([addressFuture, weatherFuture]);
    String finalAddress = results[0];
    String weather = results[1];

    if (finalAddress.isEmpty) {
      final dmsLat = _formatDMS(lat, true);
      final dmsLon = _formatDMS(lon, false);
      finalAddress = 'GPS: $dmsLat, $dmsLon';
    }

    return LocationWeatherResult(
      address: finalAddress,
      weather: weather,
      rawAddress: finalAddress,
    );
  }

  // 🔥 PRIORITAS: Google Geocoding (nama jalan lengkap) -> Nominatim -> Photon
  static Future<String> _fetchAddressParallel(
      double lat, double lon, String latStr, String lonStr) async {
    try {
      // 1. Google Geocoding (via geocoding package) – paling detail
      final geocoding = await _fetchFromGeocoding(lat, lon).timeout(const Duration(seconds: 3));
      if (geocoding.isNotEmpty && !geocoding.contains('Unnamed Road')) {
        return geocoding;
      }

      // 2. Nominatim (OpenStreetMap) – cadangan
      final nominatim = await _fetchFromNominatim(latStr, lonStr);
      if (nominatim.isNotEmpty) return nominatim;

      // 3. Photon (fallback terakhir)
      final photon = await _fetchFromPhoton(latStr, lonStr);
      return photon;
    } catch (_) {
      return '';
    }
  }

  static Future<String> _fetchFromGeocoding(double lat, double lon) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lon).timeout(const Duration(seconds: 4));
      if (placemarks.isEmpty) return '';

      Placemark? best;
      for (final p in placemarks) {
        if (!_isPlusCode(p.street)) {
          best = p;
          break;
        }
      }
      final p = best ?? placemarks.first;

      final parts = <String>[];
      final street = (!_isPlusCode(p.street) && p.street?.isNotEmpty == true)
          ? p.street
          : (!_isPlusCode(p.thoroughfare) && p.thoroughfare?.isNotEmpty == true)
              ? p.thoroughfare
              : null;
      if (street != null) parts.add(street);
      if (p.subLocality?.isNotEmpty == true && !_isPlusCode(p.subLocality)) parts.add(p.subLocality!);
      if (p.subAdministrativeArea?.isNotEmpty == true && !_isPlusCode(p.subAdministrativeArea)) parts.add(p.subAdministrativeArea!);
      if (p.locality?.isNotEmpty == true && !_isPlusCode(p.locality)) parts.add(p.locality!);
      if (p.administrativeArea?.isNotEmpty == true && p.administrativeArea != p.locality && !_isPlusCode(p.administrativeArea)) parts.add(p.administrativeArea!);

      if (parts.isEmpty) return '';
      return _uniqueParts(parts).join(', ');
    } catch (e) {
      return '';
    }
  }

  static Future<String> _fetchFromPhoton(String latStr, String lonStr) async {
    try {
      final uri = Uri.parse('https://photon.komoot.io/reverse?lat=$latStr&lon=$lonStr');
      final res = await _client.get(uri).timeout(const Duration(milliseconds: 1800));
      if (res.statusCode != 200) return '';

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) return '';

      final props = features[0]['properties'] as Map<String, dynamic>? ?? {};
      final name = _safeStr(props['name']);
      final housenumber = _safeStr(props['housenumber']);
      final street = _safeStr(props['street']);
      final district = _safeStr(props['district']);
      final city = _safeStr(props['city']);
      final state = _safeStr(props['state']);

      final parts = <String>[];
      if (name != null && name != street) parts.add(name);
      if (street != null) parts.add(housenumber != null ? '$street No.$housenumber' : street);
      if (district != null) parts.add(district);
      if (city != null) parts.add(city);
      if (state != null && state != city) parts.add(state);
      if (parts.isEmpty) return '';
      return _uniqueParts(parts).join(', ');
    } catch (e) {
      return '';
    }
  }

  static DateTime _lastNominatimRequest = DateTime.now().subtract(const Duration(seconds: 2));

  static Future<String> _fetchFromNominatim(String latStr, String lonStr) async {
    final wait = 1000 - DateTime.now().difference(_lastNominatimRequest).inMilliseconds;
    if (wait > 0) await Future.delayed(Duration(milliseconds: wait));

    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse'
          '?format=jsonv2&lat=$latStr&lon=$lonStr'
          '&zoom=18&addressdetails=1&accept-language=id',
        );
        final res = await _client.get(
          uri,
          headers: {'User-Agent': 'TermulLog/1.0', 'Accept-Language': 'id,en;q=0.8'},
        ).timeout(const Duration(seconds: 5));
        _lastNominatimRequest = DateTime.now();
        if (res.statusCode == 429) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        if (res.statusCode != 200) return '';

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>?;
        if (addr == null) return '';

        final road = _safeStr(addr['road']) ?? _safeStr(addr['pedestrian']) ?? _safeStr(addr['footway']) ?? _safeStr(addr['path']);
        final housenum = _safeStr(addr['house_number']);
        final suburb = _safeStr(addr['suburb']) ?? _safeStr(addr['neighbourhood']) ?? _safeStr(addr['village']) ?? _safeStr(addr['hamlet']);
        final district = _safeStr(addr['city_district']) ?? _safeStr(addr['district']) ?? _safeStr(addr['subdistrict']);
        final city = _safeStr(addr['city']) ?? _safeStr(addr['town']) ?? _safeStr(addr['municipality']) ?? _safeStr(addr['county']);

        final parts = <String>[];
        if (road != null) parts.add(housenum != null ? '$road No.$housenum' : road);
        if (suburb != null) parts.add(suburb);
        if (district != null && district != suburb) parts.add(district);
        if (city != null) parts.add(city);
        if (parts.isNotEmpty) return _uniqueParts(parts).join(', ');

        final display = data['display_name'] as String?;
        if (display != null && display.isNotEmpty) {
          return _stripPlusCode(display.split(',').take(4).join(', '));
        }
        return '';
      } catch (e) {
        return '';
      }
    }
    return '';
  }

  static Future<String> _fetchWeather(double lat, double lon) async {
    final weather = await _fetchWeatherFromApi(lat.toStringAsFixed(6), lon.toStringAsFixed(6));
    return weather;
  }

  static Future<String> _fetchWeatherFromApi(String latStr, String lonStr) async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$latStr&longitude=$lonStr'
        '&current=temperature_2m,weather_code&timezone=auto',
      );
      final res = await _client.get(uri).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final current = data['current'] as Map<String, dynamic>?;
        if (current != null) {
          final temp = (current['temperature_2m'] as num?)?.toStringAsFixed(0) ?? '--';
          final code = (current['weather_code'] as num?)?.toInt() ?? 0;
          return '${_wmoDesc(code)} $temp°C';
        }
      }
    } catch (e) {}
    return '';
  }

  static String _wmoDesc(int c) {
    if (c == 0) return '☀️ Cerah';
    if (c <= 3) return '⛅ Berawan';
    if (c <= 49) return '🌫️ Berkabut';
    if (c <= 59) return '🌦️ Gerimis';
    if (c <= 67) return '🌧️ Hujan';
    if (c <= 77) return '❄️ Salju';
    if (c <= 82) return '🌧️ Hujan Lebat';
    if (c <= 86) return '🌨️ Badai Salju';
    if (c <= 94) return '🌨️ Hujan Es';
    if (c <= 95) return '⚡ Badai Petir';
    if (c <= 99) return '⛈️ Badai Petir Hujan Es';
    return '🌡️';
  }

  static String _formatDMS(double coord, bool isLat) {
    final degrees = coord.abs().floor();
    final minutes = ((coord.abs() - degrees) * 60).floor();
    final seconds = ((coord.abs() - degrees - minutes / 60) * 3600).toStringAsFixed(1);
    final direction = isLat ? (coord >= 0 ? 'N' : 'S') : (coord >= 0 ? 'E' : 'W');
    return "${degrees}°${minutes}'${seconds}\" $direction";
  }

  static String? _safeStr(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}
