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
  final bool showAddress;
  final bool showCoordinates;
  final double opacity;
  final bool showBorder;
  final String fontSize;
  final bool showMiniMap;
  final double? lat;
  final double? lon;
  final double? acc;
  final String mapSize;
  final int mapZoomLevel;
  final int imageQuality;
  final String dateFormat;
  final String timeFormat;

  const WatermarkParams({
    required this.transferable,
    this.mapTransferable,
    required this.timestamp,
    required this.address,
    required this.weather,
    required this.layoutIndex,
    required this.showWeather,
    required this.showAccuracy,
    this.showAddress = true,
    this.showCoordinates = true,
    this.opacity = 0.85,
    this.showBorder = true,
    this.fontSize = 'normal',
    required this.showMiniMap,
    this.lat,
    this.lon,
    this.acc,
    this.mapSize = 'medium',
    this.mapZoomLevel = 16,
    this.imageQuality = 90,
    this.dateFormat = 'dd MMM yyyy',
    this.timeFormat = 'HH:mm:ss',
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
      'showAddress': showAddress,
      'showCoordinates': showCoordinates,
      'opacity': opacity,
      'showBorder': showBorder,
      'fontSize': fontSize,
      'showMiniMap': showMiniMap,
      'lat': lat,
      'lon': lon,
      'acc': acc,
      'mapSize': mapSize,
      'mapZoomLevel': mapZoomLevel,
      'imageQuality': imageQuality,
      'dateFormat': dateFormat,
      'timeFormat': timeFormat,
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
      showAddress: map['showAddress'] as bool? ?? true,
      showCoordinates: map['showCoordinates'] as bool? ?? true,
      opacity: (map['opacity'] as num?)?.toDouble() ?? 0.85,
      showBorder: map['showBorder'] as bool? ?? true,
      fontSize: map['fontSize'] as String? ?? 'normal',
      showMiniMap: map['showMiniMap'] as bool? ?? false,
      lat: map['lat'] as double?,
      lon: map['lon'] as double?,
      acc: map['acc'] as double?,
      mapSize: map['mapSize'] as String? ?? 'medium',
      mapZoomLevel: map['mapZoomLevel'] as int? ?? 16,
      imageQuality: map['imageQuality'] as int? ?? 90,
      dateFormat: map['dateFormat'] as String? ?? 'dd MMM yyyy',
      timeFormat: map['timeFormat'] as String? ?? 'HH:mm:ss',
    );
  }
}
