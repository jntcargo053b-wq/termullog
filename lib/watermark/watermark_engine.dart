// lib/watermark/watermark_engine.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../core/constants.dart';
import 'watermark_params.dart';
import 'layouts/watermark_layout_base.dart';
import 'layouts/layout_simple.dart';

class WatermarkEngine {
  static final Map<String, WatermarkLayoutBase> _layouts = {
    'minimal':     LayoutSimple(),
    'dslr_corner': LayoutSimple(),
    'cinematic':   LayoutSimple(),
    'hud':         LayoutSimple(),
    'polaroid':    LayoutSimple(),
    'modern':      LayoutSimple(),
  };

  static Uint8List applyFromMap(Map<String, dynamic> params) {
    final wmParams = WatermarkParams.fromMap(params);
    
    // Ambil bytes dari transferable
    Uint8List? bytes;
    if (wmParams.transferable is Uint8List) {
      bytes = wmParams.transferable as Uint8List;
    } else if (wmParams.transferable != null) {
      // Coba konversi jika perlu
      try {
        bytes = wmParams.transferable as Uint8List;
      } catch (e) {
        debugPrint('❌ Failed to get bytes: $e');
      }
    }
    
    if (bytes == null) return Uint8List(0);
    
    final src = img.decodeImage(bytes);
    if (src == null) return bytes;
    
    final layout = _layouts[wmParams.layoutType] ?? _layouts['modern']!;
    
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
      mapBytes: null,
      showAddress: wmParams.showAddress,
      showCoordinates: wmParams.showCoordinates,
      opacity: wmParams.opacity,
      showBorder: wmParams.showBorder,
      fontSize: wmParams.fontSize,
    );
    
    return WatermarkLayoutBase.encodeJpg(result);
  }

  static Future<Uint8List> applyFromMapAsync(Map<String, dynamic> params) async {
    return applyFromMap(params);
  }

  static WatermarkParams createParams({
    required Uint8List imageBytes,
    required DateTime timestamp,
    required String layoutType,
    String address = '',
    String weather = '',
    bool showWeather = true,
    bool showAccuracy = true,
    bool showAddress = true,
    bool showCoordinates = true,
    double opacity = 0.85,
    bool showBorder = true,
    String fontSize = 'normal',
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
      transferable: imageBytes,
      mapTransferable: null,
      timestamp: timestamp,
      address: address,
      weather: weather,
      layoutType: layoutType,
      showWeather: showWeather,
      showAccuracy: showAccuracy,
      showAddress: showAddress,
      showCoordinates: showCoordinates,
      opacity: opacity,
      showBorder: showBorder,
      fontSize: fontSize,
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
