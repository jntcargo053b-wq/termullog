// lib/watermark/watermark_engine.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'watermark_params.dart';

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
      mapTransferable: mapBytes != null ? TransferableTypedData.fromList([mapBytes]) : null,
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
    // Decode original image
    img.Image? original = img.decodeImage(params.imageBytes);
    if (original == null) throw Exception('Gagal decode gambar asli');

    // Decode mini map if needed
    img.Image? miniMap;
    if (params.showMiniMap && params.mapBytes != null && params.mapBytes!.isNotEmpty) {
      miniMap = img.decodeImage(params.mapBytes!);
      if (miniMap != null) {
        debugPrint('✅ Mini map decoded: ${miniMap.width}x${miniMap.height}');
      } else {
        debugPrint('⚠️ Gagal decode mini map');
      }
    }

    // Resize original to reasonable size (optional)
    img.Image output = img.copyResize(original, width: original.width, height: original.height);

    // Draw text watermark
    _drawTextWatermark(output, params);

    // Draw mini map if available
    if (miniMap != null) {
      _drawMiniMap(output, miniMap, params.watermarkPosition);
    }

    // Encode to JPEG
    return Uint8List.fromList(img.encodeJpg(output, quality: 90));
  }

  static void _drawTextWatermark(img.Image image, WatermarkParams params) {
    final timestampStr = _formatTimestamp(params.timestamp);
    final locationStr = params.address.isNotEmpty ? params.address : 'Tidak ada lokasi';
    final weatherStr = params.showWeather && params.weather.isNotEmpty ? ' | ${params.weather}' : '';
    final accStr = params.showAccuracy && params.acc != null ? ' | ±${params.acc!.toStringAsFixed(0)}m' : '';
    final text = '$timestampStr | $locationStr$weatherStr$accStr';

    // Estimate text width (rough approximation)
    int textWidth = text.length * 12; // ~12px per karakter
    int textHeight = 20;

    int x, y;
    switch (params.watermarkPosition.toLowerCase()) {
      case 'top-right':
        x = image.width - textWidth - 16;
        y = 16;
        break;
      case 'bottom-left':
        x = 16;
        y = image.height - textHeight - 16;
        break;
      case 'bottom-right':
        x = image.width - textWidth - 16;
        y = image.height - textHeight - 16;
        break;
      default: // top-left
        x = 16;
        y = 16;
    }

    // Draw background rectangle for readability
    img.drawRect(image,
        x1: x - 4, y1: y - 4, x2: x + textWidth + 4, y2: y + textHeight + 4,
        fillColor: img.ColorRgba8(0, 0, 0, 180));

    // Draw text (using default font)
    img.drawString(image, text,
        x: x, y: y,
        color: img.ColorRgba8(255, 255, 255, 255));
  }

  static void _drawMiniMap(img.Image canvas, img.Image miniMap, String position) {
    // Resize mini map to max 150px width, maintain aspect ratio
    int targetWidth = 150;
    int targetHeight = (miniMap.height * targetWidth / miniMap.width).toInt();
    if (targetHeight > 150) {
      targetHeight = 150;
      targetWidth = (miniMap.width * targetHeight / miniMap.height).toInt();
    }
    final resized = img.copyResize(miniMap, width: targetWidth, height: targetHeight);

    int x, y;
    switch (position.toLowerCase()) {
      case 'top-right':
        x = canvas.width - resized.width - 16;
        y = 80;
        break;
      case 'bottom-left':
        x = 16;
        y = canvas.height - resized.height - 80;
        break;
      case 'bottom-right':
        x = canvas.width - resized.width - 16;
        y = canvas.height - resized.height - 80;
        break;
      default: // top-left
        x = 16;
        y = 80;
    }

    // Draw white border
    img.drawRect(canvas,
        x1: x - 2, y1: y - 2, x2: x + resized.width + 2, y2: y + resized.height + 2,
        fillColor: img.ColorRgba8(255, 255, 255, 200));

    // Composite image
    img.compositeImage(canvas, resized, x, y);
  }

  static String _formatTimestamp(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
