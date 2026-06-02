import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';

class LastKnownLocationCache {
  static const String _key = 'last_location_cache';
  static const Duration _maxAge = Duration(hours: 12);
  static const double _maxLoadAccuracy = 20.0;   // hanya simpan/muat jika ≤20m

  static Future<void> save({
    required Position position,
    required String address,
    required String weather,
  }) async {
    if (address.isEmpty) return;
    if (position.accuracy > _maxLoadAccuracy) return;

    final prefs = await SharedPreferences.getInstance();
    final data = {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'address': address,
      'weather': weather,
      'cachedAt': DateTime.now().toIso8601String(),
    };
    await prefs.setString(_key, jsonEncode(data));
  }

  static Future<({
    double latitude,
    double longitude,
    double accuracy,
    String address,
    String weather,
    DateTime cachedAt
  })?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;

    try {
      final Map<String, dynamic> map = jsonDecode(raw);
      final cachedAt = DateTime.parse(map['cachedAt'] as String);
      final age = DateTime.now().difference(cachedAt);
      if (age > _maxAge) return null;

      final accuracy = (map['accuracy'] as num).toDouble();
      if (accuracy > _maxLoadAccuracy) return null;

      final address = map['address'] as String;
      if (address.isEmpty) return null;

      return (
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        accuracy: accuracy,
        address: address,
        weather: map['weather'] as String? ?? '',
        cachedAt: cachedAt,
      );
    } catch (e) {
      return null;
    }
  }
}
