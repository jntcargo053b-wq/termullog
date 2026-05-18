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
import 'layouts/layout_nama_baru.dart'; // Modern Clean Card

class WatermarkEngine {
  // ⚠️ Map dengan KEY enum — TIDAK lagi pakai index integer
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
    WatermarkLayout.modern:         LayoutNamaBaru(), // Modern Clean Card
  };

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
      src = WatermarkLayoutBase.decodeOrThrow(bytes);
    } catch (e) {
      debugPrint('WatermarkEngine: gagal decode gambar — $e');
      return bytes;
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

    // Cari layout berdasarkan index (dari enum)
    final layoutEnum = WatermarkLayout.values[wmParams.layoutIndex];
    final layout = _layouts[layoutEnum];
    
    if (layout == null) {
      debugPrint('WatermarkEngine: layout ${layoutEnum.name} tidak ditemukan');
      return WatermarkLayoutBase.encodeJpg(src);
    }

    debugPrint('WatermarkEngine: apply layout [${layoutEnum.name}] ${layout.name}');

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
        showAddress: wmParams.showAddress,
        showCoordinates: wmParams.showCoordinates,
        opacity: wmParams.opacity,
        showBorder: wmParams.showBorder,
        fontSize: wmParams.fontSize,
      );
      return result;
    } catch (e, stackTrace) {
      debugPrint('WatermarkEngine: error saat apply layout — $e');
      debugPrintStack(stackTrace: stackTrace);
      return WatermarkLayoutBase.encodeJpg(src);
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
      layoutIndex: layoutIndex,
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
