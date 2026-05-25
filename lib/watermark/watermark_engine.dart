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
import 'layouts/layout_cinematic_v2.dart';
import 'layouts/layout_timemark_style.dart';
import 'layouts/layout_nama_baru.dart';

class WatermarkEngine {
  static final Map<WatermarkLayout, WatermarkLayoutBase> _layouts = {
    WatermarkLayout.minimal:        LayoutFilmStrip(),
    WatermarkLayout.dslrCorner:     LayoutDSLRCorner(),
    WatermarkLayout.cinematic:      LayoutCinematic(),
    WatermarkLayout.fieldSurvey:    LayoutFieldSurvey(),
    WatermarkLayout.hud:            LayoutHUD(),
    WatermarkLayout.gpsCard:        LayoutGpsCard(),
    WatermarkLayout.polaroid:       LayoutPolaroid(),
    WatermarkLayout.sidePanel:      LayoutSidePanel(),
    WatermarkLayout.cinematicV2:    LayoutCinematicV2(),
    WatermarkLayout.timeMarkStyle:  LayoutTimeMarkStyle(),
    WatermarkLayout.modern:         LayoutNamaBaru(),
  };

  /// SYNC version — untuk isolate (fallback)
  static Uint8List applyFromMap(Map<String, dynamic> params) {
    final wmParams = WatermarkParams.fromMap(params);
    final bytes = _getImageBytes(wmParams);
    final mapBytes = _getMapBytes(wmParams);
    final src = _decodeImage(bytes);
    if (src == null) return bytes ?? Uint8List(0);

    final layout = _getLayout(wmParams.layoutIndex);
    final quality = wmParams.imageQuality.clamp(50, 100);
    if (layout == null) return WatermarkLayoutBase.encodeJpg(_resizeIfNeeded(src), quality: quality);

    debugPrint('🔄 WatermarkEngine SYNC: apply layout [${layout.name}], quality=$quality');

    try {
      final result = layout.apply(
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
        showMiniMap: wmParams.showMiniMap,
        mapBytes: mapBytes,
        showAddress: wmParams.showAddress,
        showCoordinates: wmParams.showCoordinates,
        opacity: wmParams.opacity,
        showBorder: wmParams.showBorder,
        fontSize: wmParams.fontSize,
        mapSize: wmParams.mapSize,
        dateFormat: wmParams.dateFormat,
        timeFormat: wmParams.timeFormat,
        // fontScale tidak dikirim ke layout (tidak dibutuhkan di image library)
      );
      if (quality != 90) {
        try {
          final decoded = img.decodeJpg(result);
          if (decoded != null) return WatermarkLayoutBase.encodeJpg(decoded, quality: quality);
        } catch (_) {}
      }
      return result;
    } catch (e, stackTrace) {
      debugPrint('❌ WatermarkEngine SYNC error: $e');
      debugPrintStack(stackTrace: stackTrace);
      return WatermarkLayoutBase.encodeJpg(src, quality: quality);
    }
  }

  /// ASYNC version — untuk main thread (Flutter Canvas)
  static Future<Uint8List> applyFromMapAsync(Map<String, dynamic> params) async {
    final wmParams = WatermarkParams.fromMap(params);
    final bytes = _getImageBytes(wmParams);
    final mapBytes = _getMapBytes(wmParams);
    final src = _decodeImage(bytes);
    if (src == null) return bytes ?? Uint8List(0);

    final layout = _getLayout(wmParams.layoutIndex);
    final quality = wmParams.imageQuality.clamp(50, 100);
    if (layout == null) return WatermarkLayoutBase.encodeJpg(_resizeIfNeeded(src), quality: quality);

    debugPrint('🎨 WatermarkEngine ASYNC: apply layout [${layout.name}], quality=$quality');

    try {
      final result = await layout.applyAsync(
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
        showMiniMap: wmParams.showMiniMap,
        mapBytes: mapBytes,
        showAddress: wmParams.showAddress,
        showCoordinates: wmParams.showCoordinates,
        opacity: wmParams.opacity,
        showBorder: wmParams.showBorder,
        fontSize: wmParams.fontSize,
        mapSize: wmParams.mapSize,
        dateFormat: wmParams.dateFormat,
        timeFormat: wmParams.timeFormat,
        // fontScale tidak dikirim ke layout
      );
      if (quality != 90) {
        try {
          final decoded = img.decodeJpg(result);
          if (decoded != null) return WatermarkLayoutBase.encodeJpg(decoded, quality: quality);
        } catch (_) {}
      }
      return result;
    } catch (e, stackTrace) {
      debugPrint('❌ WatermarkEngine ASYNC error: $e');
      debugPrintStack(stackTrace: stackTrace);
      return applyFromMap(params);
    }
  }

  /// Helper method untuk memudahkan pemanggilan dari camera_screen
  static Future<Uint8List> process({
    required Uint8List imageBytes,
    required DateTime timestamp,
    required WatermarkLayout layout,
    required double? lat,
    required double? lon,
    required double? acc,
    required String address,
    required String weather,
    required bool showWeather,
    required bool showAccuracy,
    required bool showAddress,
    required bool showCoordinates,
    required double opacity,
    required bool showBorder,
    required String fontSize,
    required bool showMiniMap,
    required String mapSize,
    required int mapZoomLevel,
    required int imageQuality,
    required String dateFormat,
    required String timeFormat,
    required double fontScale,
    Uint8List? mapBytes,
  }) async {
    final params = createParams(
      imageBytes: imageBytes,
      timestamp: timestamp,
      layoutIndex: layout.index,
      address: address,
      weather: weather,
      showWeather: showWeather,
      showAccuracy: showAccuracy,
      showAddress: showAddress,
      showCoordinates: showCoordinates,
      opacity: opacity,
      showBorder: showBorder,
      fontSize: fontSize,
      showMiniMap: showMiniMap,
      lat: lat,
      lon: lon,
      acc: acc,
      mapBytes: mapBytes,
      mapSize: mapSize,
      mapZoomLevel: mapZoomLevel,
      imageQuality: imageQuality,
      dateFormat: dateFormat,
      timeFormat: timeFormat,
      fontScale: fontScale,
    );
    return await applyFromMapAsync(params.toMap());
  }

  static WatermarkParams createParams({
    required Uint8List imageBytes,
    required DateTime timestamp,
    required int layoutIndex,
    String address = '',
    String weather = '',
    bool showWeather = true,
    bool showAccuracy = true,
    bool showAddress = true,
    bool showCoordinates = true,
    double opacity = 0.85,
    bool showBorder = true,
    String fontSize = 'normal',
    bool showMiniMap = false,
    double? lat,
    double? lon,
    double? acc,
    Uint8List? mapBytes,
    String mapSize = 'medium',
    int imageQuality = 90,
    String dateFormat = 'dd MMM yyyy',
    String timeFormat = 'HH:mm:ss',
    int mapZoomLevel = 16,
    double fontScale = 1.0,
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
      showAddress: showAddress,
      showCoordinates: showCoordinates,
      opacity: opacity,
      showBorder: showBorder,
      fontSize: fontSize,
      showMiniMap: showMiniMap,
      lat: lat,
      lon: lon,
      acc: acc,
      mapSize: mapSize,
      mapZoomLevel: mapZoomLevel,
      imageQuality: imageQuality,
      dateFormat: dateFormat,
      timeFormat: timeFormat,
      fontScale: fontScale,
    );
  }

  static Uint8List? _getImageBytes(WatermarkParams p) {
    try {
      return p.transferable.materialize().asUint8List();
    } catch (e) {
      debugPrint('WatermarkEngine: gagal materialize image bytes — $e');
      return null;
    }
  }

  static Uint8List? _getMapBytes(WatermarkParams p) {
    if (p.mapTransferable == null) return null;
    try {
      return p.mapTransferable!.materialize().asUint8List();
    } catch (e) {
      debugPrint('WatermarkEngine: gagal materialize map bytes — $e');
      return null;
    }
  }

  static img.Image? _decodeImage(Uint8List? bytes) {
    if (bytes == null) return null;
    try {
      return WatermarkLayoutBase.decodeOrThrow(bytes);
    } catch (e) {
      debugPrint('WatermarkEngine: gagal decode gambar — $e');
      return null;
    }
  }

  static img.Image _resizeIfNeeded(img.Image src) {
    if (src.width > kMaxOutputWidth || src.height > kMaxOutputWidth) {
      try {
        return img.copyResize(src,
            width: src.width > src.height ? kMaxOutputWidth : null,
            height: src.height > src.width ? kMaxOutputWidth : null,
            interpolation: img.Interpolation.average);
      } catch (e) {
        debugPrint('WatermarkEngine: gagal resize — $e');
      }
    }
    return src;
  }

  static WatermarkLayoutBase? _getLayout(int index) {
    if (index < 0 || index >= WatermarkLayout.values.length) return null;
    return _layouts[WatermarkLayout.values[index]];
  }
}
