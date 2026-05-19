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
  // ============================================================
  // LAYOUT MAP - Menggunakan String key (typeString) untuk keamanan
  // ============================================================
  static final Map<String, WatermarkLayoutBase> _layouts = {
    'minimal':        LayoutFilmStrip(),
    'dslr_corner':    LayoutDSLRCorner(),
    'gps_timestamp':  LayoutCinematic(),      // GPS Timestamp pakai LayoutCinematic
    'field_survey':   LayoutFieldSurvey(),
    'hud':            LayoutHUD(),
    'gps_card':       LayoutGpsCard(),
    'polaroid':       LayoutPolaroid(),
    'side_panel':     LayoutSidePanel(),
    'cinematic':      LayoutCinematic(),
    'timemark_style': LayoutTimeMarkStyle(),
    'modern':         LayoutNamaBaru(),
  };

  // ============================================================
  // APPLY WATERMARK (SYNC)
  // ============================================================
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

    debugPrint('==========================');
    debugPrint('🎨 LAYOUT DIPAKAI: ${layout.name}');
    debugPrint('📝 LAYOUT TYPE: ${wmParams.layoutType}');
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
        showWeather: wmParams.showWeather,
        showAccuracy: wmParams.showAccuracy,
        watermarkPosition: wmParams.watermarkPosition,
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

  // ============================================================
  // APPLY WATERMARK (ASYNC)
  // ============================================================
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

    debugPrint('==========================');
    debugPrint('🎨 LAYOUT DIPAKAI: ${layout.name}');
    debugPrint('📝 LAYOUT TYPE: ${wmParams.layoutType}');
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
        showWeather: wmParams.showWeather,
        showAccuracy: wmParams.showAccuracy,
        watermarkPosition: wmParams.watermarkPosition,
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

  // ============================================================
  // CREATE PARAMS - Menerima layoutType String
  // ============================================================
  static WatermarkParams createParams({
    required Uint8List imageBytes,
    required DateTime timestamp,
    required String layoutType,  // ← String, BUKAN int!
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
      transferable: TransferableTypedData.fromList([imageBytes]),
      mapTransferable: mapBytes != null 
          ? TransferableTypedData.fromList([mapBytes]) 
          : null,
      timestamp: timestamp,
      address: address,
      weather: weather,
      layoutType: layoutType,  // ← String
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

  // ============================================================
  // HELPER METHODS
  // ============================================================
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
  
  // ============================================================
  // GET LAYOUT - Berdasarkan String typeString
  // ============================================================
  static WatermarkLayoutBase? _getLayout(String layoutType) {
    final layout = _layouts[layoutType];
    if (layout == null) {
      debugPrint('⚠️ Layout type not found: "$layoutType", using "modern" as fallback');
      return _layouts['modern'];
    }
    return layout;
  }
}

// ============================================================
// REFERENSI LAYOUT TYPE STRINGS
// ============================================================
/// Daftar lengkap layout type strings yang tersedia:
/// 
/// | typeString      | Layout Class        | Deskripsi
/// |-----------------|---------------------|----------------------------------
/// | 'minimal'       | LayoutFilmStrip()   | Film Strip dengan border biru
/// | 'dslr_corner'   | LayoutDSLRCorner()  | DSLR Corner style
/// | 'gps_timestamp' | LayoutCinematic()   | GPS Timestamp style
/// | 'field_survey'  | LayoutFieldSurvey() | Field Survey form style
/// | 'hud'           | LayoutHUD()         | HUD Modern style
/// | 'gps_card'      | LayoutGpsCard()     | GPS Card with map
/// | 'polaroid'      | LayoutPolaroid()    | Polaroid classic style
/// | 'side_panel'    | LayoutSidePanel()   | Side panel vertical
/// | 'cinematic'     | LayoutCinematic()   | Cinematic style
/// | 'timemark_style'| LayoutTimeMarkStyle()| TimeMark Camera style
/// | 'modern'        | LayoutNamaBaru()    | Modern Clean Card
