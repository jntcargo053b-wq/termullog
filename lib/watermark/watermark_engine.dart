import 'dart:typed_data';
import 'dart:isolate';
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
    );
  }

  static Future<Uint8List> applyFromMap(Map<String, dynamic> map) async {
    final params = WatermarkParams.fromMap(map);
    return await _applyWatermark(params);
  }

  static Future<Uint8List> _applyWatermark(WatermarkParams params) async {
    final img.Image? original = img.decodeImage(params.imageBytes);
    if (original == null) throw Exception('Failed to decode original image');

    // Hanya SATU kali materialize mapBytes
    final Uint8List? mapBytes = params.mapBytes;
    img.Image? miniMap;
    if (params.showMiniMap && mapBytes != null && mapBytes.isNotEmpty) {
      miniMap = img.decodeImage(mapBytes);
      debugPrint(miniMap != null
          ? '✅ Mini map decoded: ${miniMap.width}x${miniMap.height}'
          : '⚠️ Failed to decode mini map');
    }

    final output = img.copyResize(original, width: original.width, height: original.height);

    _drawTextWatermark(output, params);
    if (miniMap != null) _drawMiniMap(output, miniMap, params.watermarkPosition);

    return Uint8List.fromList(img.encodeJpg(output, quality: 90));
  }

  static void _drawTextWatermark(img.Image image, WatermarkParams params) {
    final text = _buildText(params);
    final font = img.arial24;
    final int textWidth = (text.length * (font.base ~/ 2)).toInt();
    final int textHeight = font.lineHeight;

    int x, y;
    switch (params.layoutIndex) {
      case 0: // Film strip – bawah
        x = 16;
        y = image.height - textHeight - 16;
        break;
      case 1: // DSLR corner – ikuti preferensi posisi
        _setPositionByPreference(image.width, image.height, textWidth, textHeight,
            params.watermarkPosition, (v) => x = v, (v) => y = v);
        break;
      case 2: // Cinematic – tengah bawah
        x = (image.width - textWidth) ~/ 2;
        y = image.height - textHeight - 32;
        break;
      case 3: // Field survey – kanan atas
        x = image.width - textWidth - 16;
        y = 16;
        break;
      default: // HUD atau fallback – kanan bawah
        x = image.width - textWidth - 16;
        y = image.height - textHeight - 16;
    }

    x = x.clamp(4, image.width - textWidth - 4);
    y = y.clamp(4, image.height - textHeight - 4);

    img.fillRect(
      image,
      x1: x - 4,
      y1: y - 4,
      x2: x + textWidth + 4,
      y2: y + textHeight + 4,
      color: img.ColorRgba8(0, 0, 0, 180),
    );

    img.drawString(
      image,
      text,
      x: x,
      y: y,
      font: font,
      color: img.ColorRgba8(255, 255, 255, 255),
    );
  }

  static void _setPositionByPreference(int imgW, int imgH, int tw, int th,
      String pos, void Function(int) setX, void Function(int) setY) {
    switch (pos.toLowerCase()) {
      case 'top-right':
        setX(imgW - tw - 16);
        setY(16);
        break;
      case 'bottom-left':
        setX(16);
        setY(imgH - th - 16);
        break;
      case 'bottom-right':
        setX(imgW - tw - 16);
        setY(imgH - th - 16);
        break;
      default:
        setX(16);
        setY(16);
    }
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

    img.drawRect(
      canvas,
      x1: x - 2,
      y1: y - 2,
      x2: x + resized.width + 2,
      y2: y + resized.height + 2,
      color: img.ColorRgba8(255, 255, 255, 200),
    );

    img.compositeImage(canvas, resized, dstX: x, dstY: y);
  }

  static String _formatTimestamp(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
