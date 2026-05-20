// lib/watermark/watermark_engine.dart
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../core/constants.dart';
import 'watermark_params.dart';
import 'layouts/watermark_layout_base.dart';

// IMPORT LAYOUT BARU (6 layout saja)
import 'layouts/layout_cinematic.dart';
import 'layouts/layout_hud.dart';
import 'layouts/layout_polaroid.dart';
import 'layouts/layout_documentary.dart';
import 'layouts/layout_leica.dart';
import 'layouts/layout_survey.dart';

class WatermarkEngine {
  // Layout MAP berdasarkan typeString - HANYA 6 LAYOUT BARU
  static final Map<String, WatermarkLayoutBase> _layouts = {
    'cinematic':    LayoutCinematic(),
    'hud':          LayoutHUD(),
    'polaroid':     LayoutPolaroid(),
    'documentary':  LayoutDocumentary(),
    'leica':        LayoutLeica(),
    'survey':       LayoutSurvey(),
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

    // SHOW WEATHER: default true jika tidak ditentukan
    finalShowWeather = wmParams.showWeather ?? true;
    
    // SHOW ACCURACY: default true jika tidak ditentukan
    finalShowAccuracy = wmParams.showAccuracy ?? true;
    
    // SHOW ADDRESS: default true jika tidak ditentukan
    finalShowAddress = wmParams.showAddress ?? true;
    
    // SHOW COORDINATES: default true jika tidak ditentukan
    finalShowCoordinates = wmParams.showCoordinates ?? true;
    
    // SHOW BORDER: layout bisa tidak mendukung border
    finalShowBorder = layout.supportsBorder && (wmParams.showBorder ?? true);
    
    // FONT SIZE: default 'normal'
    finalFontSize = wmParams.fontSize.isEmpty || wmParams.fontSize == 'default' 
        ? 'normal' 
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

    // SHOW WEATHER: default true jika tidak ditentukan
    finalShowWeather = wmParams.showWeather ?? true;
    
    // SHOW ACCURACY: default true jika tidak ditentukan
    finalShowAccuracy = wmParams.showAccuracy ?? true;
    
    // SHOW ADDRESS: default true jika tidak ditentukan
    finalShowAddress = wmParams.showAddress ?? true;
    
    // SHOW COORDINATES: default true jika tidak ditentukan
    finalShowCoordinates = wmParams.showCoordinates ?? true;
    
    // SHOW BORDER: layout bisa tidak mendukung border
    finalShowBorder = layout.supportsBorder && (wmParams.showBorder ?? true);
    
    // FONT SIZE: default 'normal'
    finalFontSize = wmParams.fontSize.isEmpty || wmParams.fontSize == 'default' 
        ? 'normal' 
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
    bool? showWeather,
    bool? showAccuracy,
    bool? showAddress,
    bool? showCoordinates,
    double? opacity,
    bool? showBorder,
    String? fontSize,
    String? watermarkPosition,
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
      opacity: opacity ?? -1,
      showBorder: showBorder,
      fontSize: fontSize ?? 'default',
      watermarkPosition: watermarkPosition ?? 'default',
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
    // Migrasi layout lama ke baru
    String mappedType = layoutType;
    switch (layoutType) {
      case 'minimal':
      case 'timeMarkStyle':
        mappedType = 'documentary';
        break;
      case 'dslr_corner':
        mappedType = 'leica';
        break;
      case 'gps_timestamp':
      case 'side_panel':
      case 'modern':
      case 'gps_card':
        mappedType = 'cinematic';
        break;
      case 'field_survey':
        mappedType = 'survey';
        break;
      default:
        mappedType = layoutType;
    }
    
    final layout = _layouts[mappedType];
    if (layout == null) {
      debugPrint('⚠️ Layout type not found: "$layoutType" -> mapped to "$mappedType", using "cinematic" as fallback');
      return _layouts['cinematic'];
    }
    return layout;
  }
}
