// lib/watermark/watermark_params.dart
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class WatermarkParams {
  final TransferableTypedData transferable;
  final TransferableTypedData? mapTransferable;
  final DateTime timestamp;
  final String address;
  final String weather;
  final String layoutType;  // ← String, BUKAN int!
  final bool showWeather;
  final bool showAccuracy;
  final bool showAddress;
  final bool showCoordinates;
  final double opacity;
  final bool showBorder;
  final String fontSize;
  final String watermarkPosition;
  final bool showMiniMap;
  final double? lat;
  final double? lon;
  final double? acc;
  final String mapSize;
  final int mapZoomLevel;

  const WatermarkParams({
    required this.transferable,
    this.mapTransferable,
    required this.timestamp,
    required this.address,
    required this.weather,
    required this.layoutType,
    required this.showWeather,
    required this.showAccuracy,
    this.showAddress = true,
    this.showCoordinates = true,
    this.opacity = 0.85,
    this.showBorder = true,
    this.fontSize = 'normal',
    required this.watermarkPosition,
    required this.showMiniMap,
    this.lat,
    this.lon,
    this.acc,
    this.mapSize = 'medium',
    this.mapZoomLevel = 16,
  });

  Map<String, dynamic> toMap() {
    return {
      'transferable': transferable,
      'mapTransferable': mapTransferable,
      'timestamp': timestamp,
      'address': address,
      'weather': weather,
      'layoutType': layoutType,
      'showWeather': showWeather,
      'showAccuracy': showAccuracy,
      'showAddress': showAddress,
      'showCoordinates': showCoordinates,
      'opacity': opacity,
      'showBorder': showBorder,
      'fontSize': fontSize,
      'watermarkPosition': watermarkPosition,
      'showMiniMap': showMiniMap,
      'lat': lat,
      'lon': lon,
      'acc': acc,
      'mapSize': mapSize,
      'mapZoomLevel': mapZoomLevel,
    };
  }

  factory WatermarkParams.fromMap(Map<String, dynamic> map) {
    return WatermarkParams(
      transferable: map['transferable'] as TransferableTypedData,
      mapTransferable: map['mapTransferable'] as TransferableTypedData?,
      timestamp: map['timestamp'] as DateTime,
      address: map['address'] as String? ?? '',
      weather: map['weather'] as String? ?? '',
      layoutType: map['layoutType'] as String? ?? 'modern',
      showWeather: map['showWeather'] as bool? ?? true,
      showAccuracy: map['showAccuracy'] as bool? ?? true,
      showAddress: map['showAddress'] as bool? ?? true,
      showCoordinates: map['showCoordinates'] as bool? ?? true,
      opacity: (map['opacity'] as num?)?.toDouble() ?? 0.85,
      showBorder: map['showBorder'] as bool? ?? true,
      fontSize: map['fontSize'] as String? ?? 'normal',
      watermarkPosition: map['watermarkPosition'] as String? ?? 'bottom',
      showMiniMap: map['showMiniMap'] as bool? ?? false,
      lat: map['lat'] as double?,
      lon: map['lon'] as double?,
      acc: map['acc'] as double?,
      mapSize: map['mapSize'] as String? ?? 'medium',
      mapZoomLevel: map['mapZoomLevel'] as int? ?? 16,
    );
  }
}
