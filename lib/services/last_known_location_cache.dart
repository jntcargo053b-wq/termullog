// lib/services/last_known_location_cache.dart
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class CachedLocation {
  final double latitude;
  final double longitude;
  final double accuracy;
  final String address;
  final String weather;
  final DateTime cachedAt;

  const CachedLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.address,
    required this.weather,
    required this.cachedAt,
  });

  String get ageLabel {
    final diff = DateTime.now().difference(cachedAt);
    if (diff.inSeconds < 60) return '${diff.inSeconds} detik lalu';
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    return DateFormat('dd/MM HH:mm').format(cachedAt);
  }

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'address': address,
        'weather': weather,
        'cachedAt': cachedAt.toIso8601String(),
      };

  factory CachedLocation.fromJson(Map<String, dynamic> json) {
    return CachedLocation(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: (json['accuracy'] as num).toDouble(),
      address: json['address'] as String,
      weather: json['weather'] as String? ?? '',
      cachedAt: DateTime.parse(json['cachedAt'] as String),
    );
  }
}

class LastKnownLocationCache {
  static const _key = 'last_known_location';

  static Future<void> save({
    required Position position,
    required String address,
    String weather = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final entry = CachedLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      address: address,
      weather: weather,
      cachedAt: DateTime.now(),
    );
    await prefs.setString(_key, jsonEncode(entry.toJson()));
  }

  static Future<CachedLocation?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return CachedLocation.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
