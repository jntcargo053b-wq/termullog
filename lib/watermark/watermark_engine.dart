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
    
    // ✅ LAYOUT dipilih berdasarkan typeString
    final layout = _getLayout(wmParams.layoutType);
    if (layout == null) {
      return WatermarkLayoutBase.encodeJpg(_resizeIfNeeded(src));
    }

    // 🎨 PERSONALITY LAYOUT - gunakan default dari layout jika user tidak menentukan
    final String finalPosition;
    final double finalOpacity;
    final bool finalShowWeather;
    final bool finalShowAccuracy;
    final bool finalShowAddress;
    final bool finalShowCoordinates;
    final bool finalShowBorder;
    final String finalFontSize;
    final bool finalShowMiniMap;

    // POSISI: gunakan personality layout jika user tidak menentukan atau 'default'
    if (wmParams.watermarkPosition.isEmpty || 
        wmParams.watermarkPosition == 'default') {
      finalPosition = layout.defaultPosition;
      debugPrint('🎨 Using LAYOUT personality position: $finalPosition');
    } else {
      finalPosition = wmParams.watermarkPosition;
      debugPrint('🎨 Using USER override position: $finalPosition');
    }

    // OPACITY: gunakan personality layout jika user tidak override
    if (wmParams.opacity < 0) {
      finalOpacity = layout.defaultOpacity;
      debugPrint('🎨 Using LAYOUT personality opacity: $finalOpacity');
    } else {
      finalOpacity = wmParams.opacity;
      debugPrint('🎨 Using USER override opacity: $finalOpacity');
    }

    // SHOW WEATHER: personality atau user?
    finalShowWeather = wmParams.showWeather ?? layout.defaultShowWeather;
    
    // SHOW ACCURACY: personality atau user?
    finalShowAccuracy = wmParams.showAccuracy ?? layout.defaultShowAccuracy;
    
    // SHOW ADDRESS: personality atau user?
    finalShowAddress = wmParams.showAddress ?? layout.defaultShowAddress;
    
    // SHOW COORDINATES: personality atau user?
    finalShowCoordinates = wmParams.showCoordinates ?? layout.defaultShowCoordinates;
    
    // SHOW BORDER: layout bisa tidak mendukung border
    finalShowBorder = layout.supportsBorder && (wmParams.showBorder ?? true);
    
    // FONT SIZE: personality atau user?
    finalFontSize = wmParams.fontSize.isEmpty || wmParams.fontSize == 'default' 
        ? layout.defaultFontSize 
        : wmParams.fontSize;
    
    // SHOW MINI MAP: layout bisa tidak mendukung mini map
    finalShowMiniMap = layout.supportsMiniMap && (wmParams.showMiniMap ?? false);

    debugPrint('==========================');
    debugPrint('🎨 LAYOUT: ${wmParams.layoutType}');
    debugPrint('📍 POSITION: $finalPosition (personality: ${layout.defaultPosition})');
    debugPrint('🎨 OPACITY: $finalOpacity (personality: ${layout.defaultOpacity})');
    debugPrint('🖼️  SHOW WEATHER: $finalShowWeather');
    debugPrint('🎯 SHOW ACCURACY: $finalShowAccuracy');
    debugPrint('📍 SHOW ADDRESS: $finalShowAddress');
    debugPrint('🗺️  SHOW COORDINATES: $finalShowCoordinates');
    debugPrint('📏 FONT SIZE: $finalFontSize');
    debugPrint('🗺️  MINI MAP: $finalShowMiniMap');
    debugPrint('==========================');

    try {
      return layout.apply(
        src: _resizeIfNeeded(src),
        timestamp: wmParams.timestamp,
        hasPosition: wmParams.lat != null && wmParams.lon != null,
        lat: wmParams.lat,
        lon: wmParams.lon,
        acc: wmParams.acc,
        address: wmParams.address,
        weather: wmParams.weather,
        showWeather: finalShowWeather,
        showAccuracy: finalShowAccuracy,
        watermarkPosition: finalPosition,
        showMiniMap: finalShowMiniMap,
        mapBytes: mapBytes,
        showAddress: finalShowAddress,
        showCoordinates: finalShowCoordinates,
        opacity: finalOpacity,
        showBorder: finalShowBorder,
        fontSize: finalFontSize,
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
    
    // ✅ LAYOUT dipilih berdasarkan typeString
    final layout = _getLayout(wmParams.layoutType);
    if (layout == null) {
      return WatermarkLayoutBase.encodeJpg(_resizeIfNeeded(src));
    }

    // 🎨 PERSONALITY LAYOUT - gunakan default dari layout jika user tidak menentukan
    final String finalPosition;
    final double finalOpacity;
    final bool finalShowWeather;
    final bool finalShowAccuracy;
    final bool finalShowAddress;
    final bool finalShowCoordinates;
    final bool finalShowBorder;
    final String finalFontSize;
    final bool finalShowMiniMap;

    // POSISI: gunakan personality layout jika user tidak menentukan atau 'default'
    if (wmParams.watermarkPosition.isEmpty || 
        wmParams.watermarkPosition == 'default') {
      finalPosition = layout.defaultPosition;
    } else {
      finalPosition = wmParams.watermarkPosition;
    }

    // OPACITY: gunakan personality layout jika user tidak override
    if (wmParams.opacity < 0) {
      finalOpacity = layout.defaultOpacity;
    } else {
      finalOpacity = wmParams.opacity;
    }

    // SHOW WEATHER: personality atau user?
    finalShowWeather = wmParams.showWeather ?? layout.defaultShowWeather;
    
    // SHOW ACCURACY: personality atau user?
    finalShowAccuracy = wmParams.showAccuracy ?? layout.defaultShowAccuracy;
    
    // SHOW ADDRESS: personality atau user?
    finalShowAddress = wmParams.showAddress ?? layout.defaultShowAddress;
    
    // SHOW COORDINATES: personality atau user?
    finalShowCoordinates = wmParams.showCoordinates ?? layout.defaultShowCoordinates;
    
    // SHOW BORDER: layout bisa tidak mendukung border
    finalShowBorder = layout.supportsBorder && (wmParams.showBorder ?? true);
    
    // FONT SIZE: personality atau user?
    finalFontSize = wmParams.fontSize.isEmpty || wmParams.fontSize == 'default' 
        ? layout.defaultFontSize 
        : wmParams.fontSize;
    
    // SHOW MINI MAP: layout bisa tidak mendukung mini map
    finalShowMiniMap = layout.supportsMiniMap && (wmParams.showMiniMap ?? false);

    debugPrint('==========================');
    debugPrint('🎨 LAYOUT: ${wmParams.layoutType}');
    debugPrint('📍 POSITION: $finalPosition (personality: ${layout.defaultPosition})');
    debugPrint('🎨 OPACITY: $finalOpacity (personality: ${layout.defaultOpacity})');
    debugPrint('==========================');

    try {
      return await layout.applyAsync(
        src: _resizeIfNeeded(src),
        timestamp: wmParams.timestamp,
        hasPosition: wmParams.lat != null && wmParams.lon != null,
        lat: wmParams.lat,
        lon: wmParams.lon,
        acc: wmParams.acc,
        address: wmParams.address,
        weather: wmParams.weather,
        showWeather: finalShowWeather,
        showAccuracy: finalShowAccuracy,
        watermarkPosition: finalPosition,
        showMiniMap: finalShowMiniMap,
        mapBytes: mapBytes,
        showAddress: finalShowAddress,
        showCoordinates: finalShowCoordinates,
        opacity: finalOpacity,
        showBorder: finalShowBorder,
        fontSize: finalFontSize,
      );
    } catch (e, st) {
      debugPrint('❌ ASYNC error: $e\n$st');
      return applyFromMap(params);
    }
  }

  static WatermarkParams createParams({
    required Uint8List imageBytes,
    required DateTime timestamp,
    required String layoutType,
    String address = '',
    String weather = '',
    bool? showWeather,  // ← nullable, akan pakai personality jika null
    bool? showAccuracy, // ← nullable
    bool? showAddress,  // ← nullable
    bool? showCoordinates, // ← nullable
    double? opacity,    // ← nullable, -1 artinya pakai personality
    bool? showBorder,
    String? fontSize,
    String? watermarkPosition,  // ← nullable, 'default' artinya pakai personality
    bool? showMiniMap,
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
      layoutType: layoutType,
      showWeather: showWeather,
      showAccuracy: showAccuracy,
      showAddress: showAddress,
      showCoordinates: showCoordinates,
      opacity: opacity ?? -1,  // -1 = use personality
      showBorder: showBorder,
      fontSize: fontSize ?? 'default',  // 'default' = use personality
      watermarkPosition: watermarkPosition ?? 'default',  // 'default' = use personality
      showMiniMap: showMiniMap ?? false,
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
