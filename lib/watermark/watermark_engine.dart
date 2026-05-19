// lib/watermark/watermark_engine.dart
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../core/constants.dart';
import 'watermark_params.dart';
import 'layouts/watermark_layout_base.dart';
import 'layouts/layout_film_strip.dart';
import 'layouts/layout_dslr_corner.dart';
import 'layouts/layout_cinematic.dart';
import 'layouts/layout_field_survey.dart';
import 'layouts/layout_hud.dart';
import 'layouts/layout_gps_card.dart';
import 'layouts/layout_polaroid.dart';
import 'layouts/layout_side_panel.dart';
import 'layouts/layout_timemark_style.dart';
import 'layouts/layout_nama_baru.dart';

class WatermarkEngine {
  // Layout MAP berdasarkan typeString
  static final Map<String, WatermarkLayoutBase> _layouts = {
    'minimal':        LayoutFilmStrip(),
    'dslr_corner':    LayoutDSLRCorner(),
    'gps_timestamp':  LayoutCinematic(),
    'field_survey':   LayoutFieldSurvey(),
    'hud':            LayoutHUD(),
    'gps_card':       LayoutGpsCard(),
    'polaroid':       LayoutPolaroid(),
    'side_panel':     LayoutSidePanel(),
    'cinematic':      LayoutCinematic(),
    'timemark_style': LayoutTimeMarkStyle(),
    'modern':         LayoutNamaBaru(),
  };

  static Uint8List applyFromMap(Map<String, dynamic> params) {
    final wmParams = WatermarkParams.fromMap(params);
    final bytes = _getImageBytes(wmParams);
    final mapBytes = _getMapBytes(wmParams);
    final src = _decodeImage(bytes);
    
    if (src == null) return bytes ?? Uint8List(0);
    
    // ✅ LAYOUT dipilih berdasarkan typeString, BUKAN position!
    final layout = _getLayout(wmParams.layoutType);
    if (layout == null) {
      return WatermarkLayoutBase.encodeJpg(_resizeIfNeeded(src));
    }

    debugPrint('==========================');
    debugPrint('🎨 LAYOUT: ${wmParams.layoutType}');
    debugPrint('📍 POSITION: ${wmParams.watermarkPosition}');
    debugPrint('==========================');

    try {
      // ✅ POSISI hanya menentukan letak, BUKAN jenis layout!
      return layout.apply(
        src: _resizeIfNeeded(src),
        timestamp: wmParams.timestamp,
        hasPosition: wmParams.lat != null && wmParams.lon != null,
        lat: wmParams.lat,
        lon: wmParams.lon,
        acc: wmParams.acc,
        address: wmParams.address,
        weather: wmParams.weather,
        showWeather: wmParams.showWeather,
        showAccuracy: wmParams.showAccuracy,
        watermarkPosition: wmParams.watermarkPosition,  // ← POSISI terpisah!
        showMiniMap: wmParams.showMiniMap,
        mapBytes: mapBytes,
        showAddress: wmParams.showAddress,
        showCoordinates: wmParams.showCoordinates,
        opacity: wmParams.opacity,
        showBorder: wmParams.showBorder,
        fontSize: wmParams.fontSize,
      );
    } catch (e, st) {
      debugPrint('❌ SYNC error: $e\n$st');
      return WatermarkLayoutBase.encodeJpg(src);
    }
  }

  static Future<Uint8List> applyFromMapAsync(Map<String, dynamic> params) async {
    final wmParams = WatermarkParams.fromMap(params);
    final bytes = _getImageBytes(wmParams);
    final mapBytes = _getMapBytes(wmParams);
    final src = _decodeImage(bytes);
    
    if (src == null) return bytes ?? Uint8List(0);
    
    // ✅ LAYOUT dipilih berdasarkan typeString, BUKAN position!
    final layout = _getLayout(wmParams.layoutType);
    if (layout == null) {
      return WatermarkLayoutBase.encodeJpg(_resizeIfNeeded(src));
    }

    debugPrint('==========================');
    debugPrint('🎨 LAYOUT: ${wmParams.layoutType}');
    debugPrint('📍 POSITION: ${wmParams.watermarkPosition}');
    debugPrint('==========================');

    try {
      // ✅ POSISI hanya menentukan letak, BUKAN jenis layout!
      return await layout.applyAsync(
        src: _resizeIfNeeded(src),
        timestamp: wmParams.timestamp,
        hasPosition: wmParams.lat != null && wmParams.lon != null,
        lat: wmParams.lat,
        lon: wmParams.lon,
        acc: wmParams.acc,
        address: wmParams.address,
        weather: wmParams.weather,
        showWeather: wmParams.showWeather,
        showAccuracy: wmParams.showAccuracy,
        watermarkPosition: wmParams.watermarkPosition,  // ← POSISI terpisah!
        showMiniMap: wmParams.showMiniMap,
        mapBytes: mapBytes,
        showAddress: wmParams.showAddress,
        showCoordinates: wmParams.showCoordinates,
        opacity: wmParams.opacity,
        showBorder: wmParams.showBorder,
        fontSize: wmParams.fontSize,
      );
    } catch (e, st) {
      debugPrint('❌ ASYNC error: $e\n$st');
      return applyFromMap(params);
    }
  }

  static WatermarkParams createParams({
    required Uint8List imageBytes,
    required DateTime timestamp,
    required String layoutType,  // ← String layout, BUKAN position!
    String address = '',
    String weather = '',
    bool showWeather = true,
    bool showAccuracy = true,
    bool showAddress = true,
    bool showCoordinates = true,
    double opacity = 0.85,
    bool showBorder = true,
    String fontSize = 'normal',
    String watermarkPosition = 'bottom',  // ← POSISI terpisah!
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
      layoutType: layoutType,  // ← layout dipilih user
      showWeather: showWeather,
      showAccuracy: showAccuracy,
      showAddress: showAddress,
      showCoordinates: showCoordinates,
      opacity: opacity,
      showBorder: showBorder,
      fontSize: fontSize,
      watermarkPosition: watermarkPosition,  // ← position terpisah!
      showMiniMap: showMiniMap,
      lat: lat,
      lon: lon,
      acc: acc,
      mapSize: mapSize,
      mapZoomLevel: mapZoomLevel,
    );
  }

  static Uint8List? _getImageBytes(WatermarkParams p) {
    try {
      return p.transferable.materialize().asUint8List();
    } catch (e) {
      debugPrint('❌ Failed to get image bytes: $e');
      return null;
    }
  }
  
  static Uint8List? _getMapBytes(WatermarkParams p) {
    if (p.mapTransferable == null) return null;
    try {
      return p.mapTransferable!.materialize().asUint8List();
    } catch (e) {
      debugPrint('❌ Failed to get map bytes: $e');
      return null;
    }
  }
  
  static img.Image? _decodeImage(Uint8List? bytes) {
    if (bytes == null) return null;
    try {
      return WatermarkLayoutBase.decodeOrThrow(bytes);
    } catch (e) {
      debugPrint('❌ Failed to decode image: $e');
      return null;
    }
  }
  
  static img.Image _resizeIfNeeded(img.Image src) {
    if (src.width > kMaxOutputWidth || src.height > kMaxOutputWidth) {
      try {
        return img.copyResize(
          src,
          width: src.width > src.height ? kMaxOutputWidth : null,
          height: src.height > src.width ? kMaxOutputWidth : null,
          interpolation: img.Interpolation.average,
        );
      } catch (e) {
        debugPrint('❌ Failed to resize image: $e');
      }
    }
    return src;
  }
  
  static WatermarkLayoutBase? _getLayout(String layoutType) {
    final layout = _layouts[layoutType];
    if (layout == null) {
      debugPrint('⚠️ Layout type not found: "$layoutType", using "modern" as fallback');
      return _layouts['modern'];
    }
    return layout;
  }
}
