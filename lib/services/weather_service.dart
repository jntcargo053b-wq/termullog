// lib/services/weather_service.dart
// ============================================================
// WEATHER SERVICE — POD Edition
// ============================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WeatherService {
  static const String _userAgent = 'TermulLog-POD/2.0 (Android; +https://termullog.example.com)';
  
  Future<String> fetchWeather(double lat, double lon) async {
    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lon'
        '&current_weather=true'
        '&timezone=auto'
      );
      
      final response = await http.get(
        url,
        headers: {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode != 200) return '☁️ --°C';
      
      final data = jsonDecode(response.body);
      final current = data['current_weather'];
      if (current == null) return '☁️ --°C';
      
      final temp = current['temperature']?.round();
      final weatherCode = current['weathercode'];
      final weatherIcon = _getWeatherIcon(weatherCode);
      
      return '$weatherIcon ${temp ?? "--"}°C';
    } catch (e) {
      if (kDebugMode) debugPrint('WeatherService error: $e');
      return '☁️ --°C';
    }
  }
  
  String _getWeatherIcon(int? code) {
    if (code == null) return '☁️';
    if (code == 0) return '☀️';
    if (code >= 1 && code <= 3) return '⛅';
    if (code >= 45 && code <= 48) return '🌫️';
    if (code >= 51 && code <= 67) return '🌧️';
    if (code >= 71 && code <= 77) return '❄️';
    if (code >= 80 && code <= 99) return '⛈️';
    return '☁️';
  }
}
