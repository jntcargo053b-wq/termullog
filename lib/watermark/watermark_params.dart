// lib/watermark/watermark_params.dart
import 'dart:typed_data';

class WatermarkParams {
  Uint8List imageBytes;
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

  // Fields baru untuk mini map
  final bool showMiniMap;
  final Uint8List? mapBytes;
  final int mapSize;      // ukuran dalam pixel (misal 120)
  final int mapZoomLevel;
  final String fontSize;  // 'small', 'normal', 'large'
  final String dateFormat;
  final String timeFormat;

  WatermarkParams({
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
    this.appName = 'TermulLog',
    this.showMiniMap = false,
    this.mapBytes,
    this.mapSize = 120,
    this.mapZoomLevel = 15,
    this.fontSize = 'normal',
    this.dateFormat = 'dd/MM/yyyy',
    this.timeFormat = 'HH:mm:ss',
  });

  /// Konversi ke Map untuk dikirim ke isolate (jika diperlukan)
  Map<String, dynamic> toMap() {
    return {
      'imageBytes': imageBytes,
      'timestamp': timestamp.toIso8601String(),
      'address': address,
      'weather': weather,
      'layoutIndex': layoutIndex,
      'showWeather': showWeather,
      'showAccuracy': showAccuracy,
      'showAddress': showAddress,
      'showCoordinates': showCoordinates,
      'opacity': opacity,
      'showBorder': showBorder,
      'lat': lat,
      'lon': lon,
      'acc': acc,
      'fontScale': fontScale,
      'imageQuality': imageQuality,
      'appName': appName,
      'showMiniMap': showMiniMap,
      'mapBytes': mapBytes,
      'mapSize': mapSize,
      'mapZoomLevel': mapZoomLevel,
      'fontSize': fontSize,
      'dateFormat': dateFormat,
      'timeFormat': timeFormat,
    };
  }

  /// Buat dari Map (kebalikan toMap)
  factory WatermarkParams.fromMap(Map<String, dynamic> map) {
    return WatermarkParams(
      imageBytes: map['imageBytes'] as Uint8List,
      timestamp: DateTime.parse(map['timestamp'] as String),
      address: map['address'] as String,
      weather: map['weather'] as String,
      layoutIndex: map['layoutIndex'] as int,
      showWeather: map['showWeather'] as bool,
      showAccuracy: map['showAccuracy'] as bool,
      showAddress: map['showAddress'] as bool,
      showCoordinates: map['showCoordinates'] as bool,
      opacity: map['opacity'] as double,
      showBorder: map['showBorder'] as bool,
      lat: map['lat'] as double?,
      lon: map['lon'] as double?,
      acc: map['acc'] as double?,
      fontScale: map['fontScale'] as double,
      imageQuality: map['imageQuality'] as int,
      appName: map['appName'] as String? ?? 'TermulLog',
      showMiniMap: map['showMiniMap'] as bool? ?? false,
      mapBytes: map['mapBytes'] as Uint8List?,
      mapSize: map['mapSize'] as int? ?? 120,
      mapZoomLevel: map['mapZoomLevel'] as int? ?? 15,
      fontSize: map['fontSize'] as String? ?? 'normal',
      dateFormat: map['dateFormat'] as String? ?? 'dd/MM/yyyy',
      timeFormat: map['timeFormat'] as String? ?? 'HH:mm:ss',
    );
  }
}
