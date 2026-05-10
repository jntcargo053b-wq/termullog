import 'dart:convert';
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
  
  // Cache sederhana untuk alamat (avoid rate limit)
  static final Map<String, String> _addressCache = {};
  static const int _cacheMaxSize = 50;
  static DateTime _lastNominatimRequest = DateTime.now().subtract(const Duration(seconds: 2));

  static Future<LocationWeatherResult> fetchFromPosition(Position position) async {
    final lat = position.latitude;
    final lon = position.longitude;
    final latStr = lat.toStringAsFixed(6);
    final lonStr = lon.toStringAsFixed(6);
    
    // Cek cache
    final cacheKey = '${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}';
    if (_addressCache.containsKey(cacheKey)) {
      debugPrint('Address from cache: ${_addressCache[cacheKey]}');
      
      // Weather tetap diambil fresh (parallel)
      final weather = await _fetchWeather(latStr, lonStr);
      return LocationWeatherResult(
        address: _addressCache[cacheKey]!,
        weather: weather,
        rawAddress: _addressCache[cacheKey]!,
      );
    }

    // ─── PARALLEL REQUEST: Address + Weather ──────────────────────────────
    final results = await Future.wait([
      _fetchAddressWithProviders(lat, lon, latStr, lonStr),
      _fetchWeather(latStr, lonStr),
    ]);

    String finalAddress = results[0];
    String weather = results[1];
    String rawAddress = finalAddress;

    // Ultimate fallback jika alamat kosong
    if (finalAddress.isEmpty) {
      finalAddress = '📍 ${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}';
      rawAddress = finalAddress;
    } else {
      // Simpan ke cache
      if (_addressCache.length >= _cacheMaxSize) {
        _addressCache.remove(_addressCache.keys.first);
      }
      _addressCache[cacheKey] = finalAddress;
    }

    return LocationWeatherResult(address: finalAddress, weather: weather, rawAddress: rawAddress);
  }

  // ─── FETCH ADDRESS DENGAN MULTIPLE PROVIDERS (DENGAN RATE LIMIT) ─────────
  static Future<String> _fetchAddressWithProviders(
    double lat, double lon, String latStr, String lonStr
  ) async {
    String address = '';

    // PROVIDER 1: Geocoding Package (Offline/Online, tanpa rate limit)
    address = await _fetchFromGeocoding(lat, lon);
    if (address.isNotEmpty) return address;

    // PROVIDER 2: Photon (OpenStreetMap, rate limit lebih longgar)
    address = await _fetchFromPhoton(latStr, lonStr);
    if (address.isNotEmpty) return address;

    // PROVIDER 3: Nominatim (dengan rate limit compliance)
    address = await _fetchFromNominatim(latStr, lonStr);
    if (address.isNotEmpty) return address;

    // PROVIDER 4: LocationIQ (gratis terbatas, 10k request/bulan)
    // address = await _fetchFromLocationIQ(latStr, lonStr);
    // if (address.isNotEmpty) return address;

    return address;
  }

  // ─── PROVIDER 1: Geocoding Package ──────────────────────────────────────
  static Future<String> _fetchFromGeocoding(double lat, double lon) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lon).timeout(
        const Duration(seconds: 5),
      );
      
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[];
        
        if (p.street?.isNotEmpty == true) parts.add(p.street!);
        if (p.subLocality?.isNotEmpty == true) parts.add(p.subLocality!);
        if (p.subAdministrativeArea?.isNotEmpty == true) parts.add(p.subAdministrativeArea!);
        if (p.locality?.isNotEmpty == true) parts.add(p.locality!);
        if (p.administrativeArea?.isNotEmpty == true && p.locality != p.administrativeArea) {
          parts.add(p.administrativeArea!);
        }
        if (p.postalCode?.isNotEmpty == true) parts.add(p.postalCode!);
        
        if (parts.isNotEmpty) {
          final address = parts.join(', ');
          debugPrint('Address from Geocoding: $address');
          return address;
        }
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
    }
    return '';
  }

  // ─── PROVIDER 2: Photon (OpenStreetMap, lebih ramah rate limit) ─────────
  static Future<String> _fetchFromPhoton(String latStr, String lonStr) async {
    try {
      final uri = Uri.parse(
        'https://photon.komoot.io/reverse'
        '?lat=$latStr&lon=$lonStr',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final features = data['features'] as List?;
        
        if (features != null && features.isNotEmpty) {
          final properties = features[0]['properties'] as Map<String, dynamic>?;
          if (properties != null) {
            final parts = <String>[];
            
            final street = properties['street'] as String?;
            final city = properties['city'] as String?;
            final state = properties['state'] as String?;
            final country = properties['country'] as String?;
            final postcode = properties['postcode'] as String?;
            
            if (street?.isNotEmpty == true) parts.add(street!);
            if (city?.isNotEmpty == true) parts.add(city!);
            if (state?.isNotEmpty == true) parts.add(state!);
            if (postcode?.isNotEmpty == true) parts.add(postcode!);
            if (country?.isNotEmpty == true && country != 'Indonesia') parts.add(country!);
            
            if (parts.isNotEmpty) {
              final address = parts.join(', ');
              debugPrint('Address from Photon: $address');
              return address;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Photon error: $e');
    }
    return '';
  }

  // ─── PROVIDER 3: Nominatim (DENGAN RATE LIMIT 1 request/detik) ──────────
  static Future<String> _fetchFromNominatim(String latStr, String lonStr) async {
    // Rate limit compliance: minimum 1 detik antar request
    final now = DateTime.now();
    final timeSinceLastRequest = now.difference(_lastNominatimRequest);
    if (timeSinceLastRequest.inMilliseconds < 1000) {
      final waitTime = Duration(milliseconds: 1000 - timeSinceLastRequest.inMilliseconds);
      debugPrint('Nominatim rate limit: waiting ${waitTime.inMilliseconds}ms');
      await Future.delayed(waitTime);
    }
    
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json&lat=$latStr&lon=$lonStr&zoom=18&addressdetails=1',
      );
      final res = await http
          .get(uri, headers: {'User-Agent': 'TermulLog/1.0'})
          .timeout(const Duration(seconds: 5));

      _lastNominatimRequest = DateTime.now();
      
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final displayName = data['display_name'] as String?;
        if (displayName != null && displayName.isNotEmpty) {
          final parts = displayName.split(',').take(4).toList();
          final address = parts.join(', ');
          debugPrint('Address from Nominatim: $address');
          return address;
        }
      }
    } catch (e) {
      debugPrint('Nominatim error: $e');
    }
    return '';
  }

  // ─── PROVIDER 4: LocationIQ (optional, perlu API Key) ───────────────────
  // static Future<String> _fetchFromLocationIQ(String latStr, String lonStr) async {
  //   const apiKey = 'YOUR_LOCATIONIQ_API_KEY';
  //   if (apiKey == 'YOUR_LOCATIONIQ_API_KEY') return '';
  //   
  //   try {
  //     final uri = Uri.parse(
  //       'https://us1.locationiq.com/v1/reverse'
  //       '?key=$apiKey&lat=$latStr&lon=$lonStr&format=json',
  //     );
  //     final res = await http.get(uri).timeout(const Duration(seconds: 5));
  //     
  //     if (res.statusCode == 200) {
  //       final data = jsonDecode(res.body) as Map<String, dynamic>;
  //       final displayName = data['display_name'] as String?;
  //       if (displayName != null && displayName.isNotEmpty) {
  //         return displayName;
  //       }
  //     }
  //   } catch (e) {
  //     debugPrint('LocationIQ error: $e');
  //   }
  //   return '';
  // }

  // ─── FETCH WEATHER (PARALLEL FRIENDLY) ──────────────────────────────────
  static Future<String> _fetchWeather(String latStr, String lonStr) async {
    String weather = '';
    
    try {
      final wUri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$latStr&longitude=$lonStr'
        '&current=temperature_2m,weather_code&timezone=auto',
      );
      final wRes = await http.get(wUri).timeout(const Duration(seconds: 6));
      
      if (wRes.statusCode == 200) {
        final wData = jsonDecode(wRes.body) as Map<String, dynamic>;
        final current = wData['current'] as Map<String, dynamic>?;
        if (current != null) {
          final temp = (current['temperature_2m'] as num?)?.toStringAsFixed(0) ?? '--';
          final code = (current['weather_code'] as num?)?.toInt() ?? 0;
          weather = '${_wmoDesc(code)} ${temp}°C';
          debugPrint('Weather: $weather');
        }
      }
    } catch (e) {
      debugPrint('Weather error: $e');
    }
    
    return weather;
  }

  static String _wmoDesc(int c) {
    if (c == 0) return '☀️';
    if (c <= 3) return '⛅';
    if (c <= 49) return '🌫️';
    if (c <= 59) return '🌦️';
    if (c <= 67) return '🌧️';
    if (c <= 77) return '❄️';
    if (c <= 82) return '🌧️☔';
    if (c <= 86) return '❄️🌨️';
    if (c == 95) return '⚡';
    return '🌡️';
  }
}
