import 'dart:typed_data';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'watermark_params.dart';

// Import semua layout yang sudah Anda buat
import 'layouts/layout_film_strip.dart';
import 'layouts/layout_dslr_corner.dart';
import 'layouts/layout_cinematic.dart';
import 'layouts/layout_field_survey.dart';
import 'layouts/layout_hud.dart';

class WatermarkEngine {
  static WatermarkParams createParams({
    required Uint8List imageBytes,
    required DateTime timestamp,
    required int layoutIndex,
    required String address,
    required String weather,
    required bool showWeather,
    required bool showAccuracy,
    required String watermarkPosition,
    required bool showMiniMap,
    double? lat,
    double? lon,
    double? acc,
    Uint8List? mapBytes,
  }) {
    return WatermarkParams(
      transferable: TransferableTypedData.fromList([imageBytes]),
      mapTransferable:
          mapBytes != null
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
    );
  }

  static Future<Uint8List> applyFromMap(Map<String, dynamic> map) async {
    final params = WatermarkParams.fromMap(map);
    return await _applyWatermark(params);
  }

  static Future<Uint8List> _applyWatermark(WatermarkParams params) async {
    // 1. Decode image utama (hanya sekali)
    final img.Image? original = img.decodeImage(params.imageBytes);
    if (original == null) throw Exception('Failed to decode original image');

    // 2. Ambil mapBytes SEKALI (hindari multiple materialize)
    final Uint8List? mapBytes = params.mapBytes; // ← getter hanya dipanggil sekali
    img.Image? miniMap;
    if (params.showMiniMap && mapBytes != null && mapBytes.isNotEmpty) {
      miniMap = img.decodeImage(mapBytes);
      debugPrint(miniMap != null
          ? '✅ Mini map decoded: ${miniMap.width}x${miniMap.height}'
          : '⚠️ Failed to decode mini map');
    }

    // 3. Pilih layout berdasarkan layoutIndex
    late final img.Image Function(img.Image, WatermarkParams, img.Image?) layout;
    switch (params.layoutIndex) {
      case 0:
        layout = LayoutFilmStrip.apply;
        break;
      case 1:
        layout = LayoutDSLRCorner.apply;
        break;
      case 2:
        layout = LayoutCinematic.apply;
        break;
      case 3:
        layout = LayoutFieldSurvey.apply;
        break;
      case 4:
        layout = LayoutHUD.apply;
        break;
      default:
        layout = LayoutFilmStrip.apply; // fallback
    }

    // 4. Terapkan layout (fungsi layout akan menggambar teks & mini map)
    final img.Image output = layout(original, params, miniMap);

    return Uint8List.fromList(img.encodeJpg(output, quality: 90));
  }
}
