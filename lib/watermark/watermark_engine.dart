// lib/watermark/watermark_engine.dart
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../core/constants.dart';
import 'watermark_params.dart';
import 'layouts/watermark_layout_base.dart';
import 'layouts/layout_cinematic.dart';
import 'layouts/layout_hud.dart';
import 'layouts/layout_polaroid.dart';
import 'layouts/layout_documentary.dart';
import 'layouts/layout_leica.dart';
import 'layouts/layout_survey.dart';

class WatermarkEngine {
  static final Map<String, WatermarkLayoutBase> _layouts = {
    'cinematic': LayoutCinematic(),
    'hud': LayoutHUD(),
    'polaroid': LayoutPolaroid(),
    'documentary': LayoutDocumentary(),
    'leica': LayoutLeica(),
    'survey': LayoutSurvey(),
  };

  static Uint8List applyFromMap(Map<String, dynamic> params) {
    final wmParams = WatermarkParams.fromMap(params);
    final bytes = _getImageBytes(wmParams);
    final mapBytes = _getMapBytes(wmParams);
    final src = _decodeImage(bytes);
    
    if (src == null) return bytes ?? Uint8List(0);
    
    final layout = _getLayout(wmParams.layoutType);
    if (layout == null) {
      return WatermarkLayoutBase.encodeJpg(_resizeIfNeeded(src));
    }

    final String finalPosition = (wmParams.watermarkPosition.isEmpty || wmParams.watermarkPosition == 'default')
        ? layout.defaultPosition
        : wmParams.watermarkPosition;
    
    final double finalOpacity = (wmParams.opacity < 0)
        ? layout.defaultOpacity
        : wmParams.opacity;
    
    // FIX: wmParams fields are non-nullable bool — remove redundant ?? operators
    final bool finalShowWeather = wmParams.showWeather;
    final bool finalShowAccuracy = wmParams.showAccuracy;
    final bool finalShowAddress = wmParams.showAddress;
    final bool finalShowCoordinates = wmParams.showCoordinates;
    final bool finalShowBorder = layout.supportsBorder && wmParams.showBorder;
    final bool finalShowMiniMap = layout.supportsMiniMap && wmParams.showMiniMap;
    final String finalFontSize = (wmParams.fontSize.isEmpty || wmParams.fontSize == 'default')
        ? 'normal'
        : wmParams.fontSize;

    debugPrint('🎨 LAYOUT: ${wmParams.layoutType} -> POS: $finalPosition, OPACITY: $finalOpacity');

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
    
    final layout = _getLayout(wmParams.layoutType);
    if (layout == null) {
      return WatermarkLayoutBase.encodeJpg(_resizeIfNeeded(src));
    }

    final String finalPosition = (wmParams.watermarkPosition.isEmpty || wmParams.watermarkPosition == 'default')
        ? layout.defaultPosition
        : wmParams.watermarkPosition;
    
    final double finalOpacity = (wmParams.opacity < 0)
        ? layout.defaultOpacity
        : wmParams.opacity;
    
    // FIX: wmParams fields are non-nullable bool — remove redundant ?? operators
    final bool finalShowWeather = wmParams.showWeather;
    final bool finalShowAccuracy = wmParams.showAccuracy;
    final bool finalShowAddress = wmParams.showAddress;
    final bool finalShowCoordinates = wmParams.showCoordinates;
    final bool finalShowBorder = layout.supportsBorder && wmParams.showBorder;
    final bool finalShowMiniMap = layout.supportsMiniMap && wmParams.showMiniMap;
    final String finalFontSize = (wmParams.fontSize.isEmpty || wmParams.fontSize == 'default')
        ? 'normal'
        : wmParams.fontSize;

    debugPrint('🎨 LAYOUT: ${wmParams.layoutType} -> POS: $finalPosition, OPACITY: $finalOpacity');

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
      mapTransferable: mapBytes != null ? TransferableTypedData.fromList([mapBytes]) : null,
      timestamp: timestamp,
      address: address,
      weather: weather,
      layoutType: layoutType,
      // FIX: bool? params cannot be passed to required bool — apply defaults here
      showWeather: showWeather ?? true,
      showAccuracy: showAccuracy ?? true,
      showAddress: showAddress ?? true,
      showCoordinates: showCoordinates ?? true,
      opacity: opacity ?? -1,
      showBorder: showBorder ?? true,
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
      return null;
    }
  }
  
  static Uint8List? _getMapBytes(WatermarkParams p) {
    if (p.mapTransferable == null) return null;
    try {
      return p.mapTransferable!.materialize().asUint8List();
    } catch (e) {
      return null;
    }
  }
  
  static img.Image? _decodeImage(Uint8List? bytes) {
    if (bytes == null) return null;
    try {
      return WatermarkLayoutBase.decodeOrThrow(bytes);
    } catch (e) {
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
        // fallback ke original jika resize gagal
      }
    }
    return src;
  }
  
  static WatermarkLayoutBase? _getLayout(String layoutType) {
    String mappedType;
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
      return _layouts['cinematic'];
    }
    return layout;
  }
}
