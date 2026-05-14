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
    final img.Image? original = img.decodeImage(params.imageBytes);
    if (original == null) throw Exception('Failed to decode original image');

    img.Image? miniMap;
    if (params.showMiniMap && params.mapBytes != null && params.mapBytes!.isNotEmpty) {
      miniMap = img.decodeImage(params.mapBytes!);
      if (miniMap == null) debugPrint('⚠️ Failed to decode mini map');
    }

    // Work on a copy
    final output = img.copyResize(original, width: original.width, height: original.height);

    _drawTextWatermark(output, params);
    if (miniMap != null) _drawMiniMap(output, miniMap, params.watermarkPosition);

    return Uint8List.fromList(img.encodeJpg(output, quality: 90));
  }

  static void _drawTextWatermark(img.Image image, WatermarkParams params) {
    final text = _buildText(params);
    const fontSize = 20;
    final font = img.arial_24; // available in image 4.x

    // Measure text size
    final textWidth = img.getStringWidth(font, text);
    final textHeight = fontSize + 6; // approximate

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
      default:
        x = 16;
        y = 16;
    }

    // Draw background rectangle
    img.drawRect(image, x - 4, y - 4, x + textWidth + 4, y + textHeight + 4,
        fillColor: img.ColorRgba8(0, 0, 0, 180));

    // Draw text (using named parameters)
    img.drawString(image, text, x: x, y: y, font: font, color: img.ColorRgba8(255, 255, 255, 255));
  }

  static String _buildText(WatermarkParams params) {
    final timestampStr = _formatTimestamp(params.timestamp);
    final locationStr = params.address.isNotEmpty ? params.address : 'No location';
    final weatherStr = params.showWeather && params.weather.isNotEmpty ? ' | ${params.weather}' : '';
    final accStr = params.showAccuracy && params.acc != null ? ' | ±${params.acc!.toStringAsFixed(0)}m' : '';
    return '$timestampStr | $locationStr$weatherStr$accStr';
  }

  static void _drawMiniMap(img.Image canvas, img.Image miniMap, String position) {
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
      default:
        x = 16;
        y = 80;
    }

    // Draw white border (fillColor makes it a filled rectangle, but we use it as outline by drawing a smaller inner rect)
    img.drawRect(canvas, x - 2, y - 2, x + resized.width + 2, y + resized.height + 2,
        fillColor: img.ColorRgba8(255, 255, 255, 200));
    // Composite the map over it
    img.compositeImage(canvas, resized, dx: x, dy: y);
  }

  static String _formatTimestamp(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
