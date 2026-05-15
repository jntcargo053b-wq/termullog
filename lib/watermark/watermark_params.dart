import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Data class untuk parameter watermark yang diserialisasi ke isolate
class WatermarkParams {
  final TransferableTypedData transferable;
  final TransferableTypedData? mapTransferable;
  final DateTime timestamp;
  final String address;
  final String weather;
  final int layoutIndex;
  final bool showWeather;
  final bool showAccuracy;
  final String watermarkPosition;
  final bool showMiniMap;
  final double? lat;
  final double? lon;
  final double? acc;
  final String mapSize;        // <-- TAMBAHKAN
  final int mapZoomLevel;      // <-- TAMBAHKAN (opsional, untuk zoom level)

  const WatermarkParams({
    required this.transferable,
    this.mapTransferable,
    required this.timestamp,
    required this.address,
    required this.weather,
    required this.layoutIndex,
    required this.showWeather,
    required this.showAccuracy,
    required this.watermarkPosition,
    required this.showMiniMap,
    this.lat,
    this.lon,
    this.acc,
    this.mapSize = 'medium',        // default
    this.mapZoomLevel = 16,         // default
  });

  /// Serialisasi ke Map untuk dikirim ke isolate
  Map<String, dynamic> toMap() {
    return {
      'transferable': transferable,
      'mapTransferable': mapTransferable,
      'timestamp': timestamp,
      'address': address,
      'weather': weather,
      'layoutIndex': layoutIndex,
      'showWeather': showWeather,
      'showAccuracy': showAccuracy,
      'watermarkPosition': watermarkPosition,
      'showMiniMap': showMiniMap,
      'lat': lat,
      'lon': lon,
      'acc': acc,
      'mapSize': mapSize,            // <-- TAMBAHKAN
      'mapZoomLevel': mapZoomLevel,  // <-- TAMBAHKAN
    };
  }

  /// Deserialisasi dari Map (dipakai di dalam isolate)
  factory WatermarkParams.fromMap(Map<String, dynamic> map) {
    return WatermarkParams(
      transferable: map['transferable'] as TransferableTypedData,
      mapTransferable: map['mapTransferable'] as TransferableTypedData?,
      timestamp: map['timestamp'] as DateTime,
      address: map['address'] as String? ?? '',
      weather: map['weather'] as String? ?? '',
      layoutIndex: map['layoutIndex'] as int,
      showWeather: map['showWeather'] as bool? ?? true,
      showAccuracy: map['showAccuracy'] as bool? ?? true,
      watermarkPosition: map['watermarkPosition'] as String? ?? 'bottom',
      showMiniMap: map['showMiniMap'] as bool? ?? false,
      lat: map['lat'] as double?,
      lon: map['lon'] as double?,
      acc: map['acc'] as double?,
      mapSize: map['mapSize'] as String? ?? 'medium',           // <-- TAMBAHKAN
      mapZoomLevel: map['mapZoomLevel'] as int? ?? 16,          // <-- TAMBAHKAN
    );
  }
}
