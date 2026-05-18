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
  static final Map<int, WatermarkLayoutBase> _layouts = {
    0: LayoutFilmStrip(),
    1: LayoutDSLRCorner(),
    2: LayoutCinematic(),
    3: LayoutFieldSurvey(),
    4: LayoutHUD(),
    5: LayoutGpsCard(),
    6: LayoutPolaroid(),
    7: LayoutSidePanel(),
    8: LayoutCinematicV2(),
    9: LayoutTimeMarkStyle(),
    10: LayoutNamaBaru(),
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

    final layout = _layouts[wmParams.layoutIndex];
    if (layout == null) {
      debugPrint('WatermarkEngine: layout index ${wmParams.layoutIndex} tidak ditemukan');
      return WatermarkLayoutBase.encodeJpg(src);
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
