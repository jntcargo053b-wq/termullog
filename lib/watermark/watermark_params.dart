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
  final String layoutType;  // ← GANTI: dari int layoutIndex menjadi String layoutType
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
    required this.layoutType,  // ← GANTI: dari layoutIndex
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

  /// Serialisasi ke Map untuk dikirim ke isolate
  Map<String, dynamic> toMap() {
    return {
      'transferable': transferable,
      'mapTransferable': mapTransferable,
      'timestamp': timestamp,
      'address': address,
      'weather': weather,
      'layoutType': layoutType,  // ← GANTI: dari layoutIndex
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

  /// Deserialisasi dari Map (dipakai di dalam isolate)
  factory WatermarkParams.fromMap(Map<String, dynamic> map) {
    return WatermarkParams(
      transferable: map['transferable'] as TransferableTypedData,
      mapTransferable: map['mapTransferable'] as TransferableTypedData?,
      timestamp: map['timestamp'] as DateTime,
      address: map['address'] as String? ?? '',
      weather: map['weather'] as String? ?? '',
      layoutType: map['layoutType'] as String? ?? 'modern',  // ← GANTI: fallback ke 'modern'
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

  // ============================================================
  // HELPER METHOD UNTUK MIGRASI (optional)
  // ============================================================
  /// Factory untuk migrasi dari format lama (layoutIndex) ke format baru
  factory WatermarkParams.fromMapLegacy(Map<String, dynamic> map) {
    // Jika masih ada layoutIndex, konversi ke layoutType
    final layoutIndex = map['layoutIndex'] as int?;
    String layoutType = 'modern';
    
    if (layoutIndex != null) {
      // Konversi index ke typeString
      switch (layoutIndex) {
        case 0:  layoutType = 'minimal'; break;
        case 1:  layoutType = 'dslr_corner'; break;
        case 2:  layoutType = 'gps_timestamp'; break;
        case 3:  layoutType = 'field_survey'; break;
        case 4:  layoutType = 'hud'; break;
        case 5:  layoutType = 'gps_card'; break;
        case 6:  layoutType = 'polaroid'; break;
        case 7:  layoutType = 'side_panel'; break;
        case 8:  layoutType = 'cinematic'; break;
        case 9:  layoutType = 'timemark_style'; break;
        case 10: layoutType = 'modern'; break;
        default: layoutType = 'modern';
      }
    }
    
    return WatermarkParams(
      transferable: map['transferable'] as TransferableTypedData,
      mapTransferable: map['mapTransferable'] as TransferableTypedData?,
      timestamp: map['timestamp'] as DateTime,
      address: map['address'] as String? ?? '',
      weather: map['weather'] as String? ?? '',
      layoutType: layoutType,  // ← hasil konversi dari index
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
