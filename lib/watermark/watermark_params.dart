// lib/watermark/watermark_params.dart
import 'dart:typed_data';

class WatermarkParams {
  final Uint8List imageBytes;
  final DateTime timestamp;
  final String address;
  final String weather;
  final int layoutIndex;
  final bool showWeather;
  final bool showAccuracy;
  final bool showAddress;
  final bool showCoordinates;
  final double opacity;
  final bool showBorder;
  final double? lat;
  final double? lon;
  final double? acc;
  final double fontScale;
  final int imageQuality;
  final String appName;
  final bool showMiniMap;
  final Uint8List? mapBytes;
  final int mapSize;
  final int mapZoomLevel;
  final String fontSize;
  final String dateFormat;
  final String timeFormat;
  
  const WatermarkParams({
    required this.imageBytes,
    required this.timestamp,
    required this.address,
    required this.weather,
    required this.layoutIndex,
    required this.showWeather,
    required this.showAccuracy,
    required this.showAddress,
    required this.showCoordinates,
    required this.opacity,
    required this.showBorder,
    this.lat,
    this.lon,
    this.acc,
    required this.fontScale,
    required this.imageQuality,
    required this.appName,
    required this.showMiniMap,
    this.mapBytes,
    required this.mapSize,
    required this.mapZoomLevel,
    required this.fontSize,
    required this.dateFormat,
    required this.timeFormat,
  });
}
