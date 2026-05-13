
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
  });

  /// Konversi ke Map untuk dikirim ke isolate
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'transferable': transferable,
      'timestamp': timestamp,
      'address': address,
      'weather': weather,
      'layout': layoutIndex,
      'showWeather': showWeather,
      'showAccuracy': showAccuracy,
      'watermarkPosition': watermarkPosition,
      'showMiniMap': showMiniMap,
    };
    
    if (mapTransferable != null) {
      map['mapTransferable'] = mapTransferable;
    }
    if (lat != null) map['posLat'] = lat;
    if (lon != null) map['posLon'] = lon;
    if (acc != null) map['posAcc'] = acc;
    
    return map;
  }

  /// Materialize bytes dari TransferableTypedData
  static WatermarkParams fromMap(Map<String, dynamic> map) {
    final transferable = map['transferable'] as TransferableTypedData;
    final bytes = transferable.materialize().asUint8List();
    
    final mapTransferable = map['mapTransferable'] as TransferableTypedData?;
    final mapBytes = mapTransferable?.materialize().asUint8List();

    // Buat params baru dengan bytes yang sudah di-materialize
    return WatermarkParams(
      transferable: TransferableTypedData.fromList([bytes]),
      mapTransferable: mapBytes != null 
          ? TransferableTypedData.fromList([mapBytes]) 
          : null,
      timestamp: map['timestamp'] as DateTime,
      address: map['address'] as String,
      weather: map['weather'] as String,
      layoutIndex: map['layout'] as int,
      showWeather: map['showWeather'] as bool,
      showAccuracy: map['showAccuracy'] as bool,
      watermarkPosition: map['watermarkPosition'] as String,
      showMiniMap: map['showMiniMap'] as bool? ?? false,
      lat: map['posLat'] as double?,
      lon: map['posLon'] as double?,
      acc: map['posAcc'] as double?,
    );
  }
}
