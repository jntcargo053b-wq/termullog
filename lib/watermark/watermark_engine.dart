// lib/watermark/watermark_engine.dart
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../core/constants.dart';
import 'watermark_params.dart';
import 'layout_registry.dart';  // ← import registry

class WatermarkEngine {
  static Uint8List applyFromMap(Map<String, dynamic> params) {
    final wmParams = WatermarkParams.fromMap(params);
    final transferable = wmParams.transferable;
    final bytes = transferable.materialize().asUint8List();

    Uint8List? mapBytes;
    if (wmParams.mapTransferable != null) {
      try {
        mapBytes = wmParams.mapTransferable!.materialize().asUint8List();
      } catch (e) {
        debugPrint('WatermarkEngine: gagal materialize mapBytes — $e');
        mapBytes = null;
      }
    }

    img.Image src;
    try {
      // Gunakan decoder dari registry (layout 0 memiliki static decodeOrThrow)
      src = LayoutRegistry.get(0)?.decodeOrThrow(bytes) ??
          (throw Exception('Decoder tidak tersedia'));
    } catch (e) {
      debugPrint('WatermarkEngine: gagal decode gambar — $e');
      return bytes; // kembalikan gambar asli tanpa watermark
    }

    if (src.width > kMaxOutputWidth || src.height > kMaxOutputWidth) {
      try {
        src = img.copyResize(src,
          width: src.width > src.height ? kMaxOutputWidth : null,
          height: src.height > src.width ? kMaxOutputWidth : null,
          interpolation: img.Interpolation.average);
      } catch (e) {
        debugPrint('WatermarkEngine: gagal resize — $e');
      }
    }

    final layout = LayoutRegistry.get(wmParams.layoutIndex);
    if (layout == null) {
      debugPrint('WatermarkEngine: layout index ${wmParams.layoutIndex} tidak ditemukan');
      return img.encodeJpg(src) as Uint8List;
    }

    debugPrint('WatermarkEngine: apply layout [${wmParams.layoutIndex}] ${layout.name}');

    try {
      final result = layout.apply(
        src: src,
        timestamp: wmParams.timestamp,
        hasPosition: wmParams.lat != null && wmParams.lon != null,
        lat: wmParams.lat,
        lon: wmParams.lon,
        acc: wmParams.acc,
        address: wmParams.address,
        weather: wmParams.weather,
        showWeather: wmParams.showWeather,
        showAccuracy: wmParams.showAccuracy,
        watermarkPosition: wmParams.watermarkPosition,
        showMiniMap: wmParams.showMiniMap,
        mapBytes: mapBytes,
      );

      return result;
    } catch (e, stackTrace) {
      debugPrint('WatermarkEngine: error saat apply layout — $e');
      debugPrintStack(stackTrace: stackTrace);
      return img.encodeJpg(src) as Uint8List;
    }
  }

  static WatermarkParams createParams({
    required Uint8List imageBytes,
    required DateTime timestamp,
    required int layoutIndex,
    String address = '',
    String weather = '',
    bool showWeather = true,
    bool showAccuracy = true,
    String watermarkPosition = 'bottom',
    bool showMiniMap = false,
    double? lat,
    double? lon,
    double? acc,
    Uint8List? mapBytes,
    String mapSize = 'medium',
    int mapZoomLevel = 16,
  }) {
    return WatermarkParams(
      transferable: TransferableTypedData.fromList([imageBytes]),
      mapTransferable: mapBytes != null 
          ? TransferableTypedData.fromList([mapBytes]) 
          : null,
      timestamp: timestamp,
      address: address,
      weather: weather,
      layoutIndex: layoutIndex,
      showWeather: showWeather,
      showAccuracy: showAccuracy,
      watermarkPosition: watermarkPosition,
      showMiniMap: showMiniMap,
      lat: lat,
      lon: lon,
      acc: acc,
      mapSize: mapSize,
      mapZoomLevel: mapZoomLevel,
    );
  }
}
