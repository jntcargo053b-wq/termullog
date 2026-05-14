import 'dart:typed_data';
import 'dart:isolate';                  // ← tambahkan ini
import 'package:flutter/foundation.dart';

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
    required this.mapTransferable,
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

  Uint8List get imageBytes => transferable.materialize().asUint8List();
  Uint8List? get mapBytes => mapTransferable?.materialize().asUint8List();

  Map<String, dynamic> toMap() => {
    'transferable': transferable,
    'mapTransferable': mapTransferable,
    'timestamp': timestamp.toIso8601String(),
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
  };

  static WatermarkParams fromMap(Map<String, dynamic> map) {
    return WatermarkParams(
      transferable: map['transferable'] as TransferableTypedData,
      mapTransferable: map['mapTransferable'] as TransferableTypedData?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      address: map['address'] as String,
      weather: map['weather'] as String,
      layoutIndex: map['layoutIndex'] as int,
      showWeather: map['showWeather'] as bool,
      showAccuracy: map['showAccuracy'] as bool,
      watermarkPosition: map['watermarkPosition'] as String,
      showMiniMap: map['showMiniMap'] as bool,
      lat: map['lat'] as double?,
      lon: map['lon'] as double?,
      acc: map['acc'] as double?,
    );
  }
}
