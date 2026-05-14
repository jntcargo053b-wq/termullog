// lib/watermark/watermark_params.dart
import 'dart:typed_data';
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

  // Getter untuk akses mudah
  Uint8List get imageBytes => transferable.materialize().asUint8List();
  Uint8List? get mapBytes => mapTransferable?.materialize().asUint8List();

  Map<String, dynamic> toMap() { ... } // sama seperti sebelumnya
  static WatermarkParams fromMap(Map<String, dynamic> map) { ... } // sama
}
