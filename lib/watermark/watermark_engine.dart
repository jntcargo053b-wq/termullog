// lib/watermark/watermark_engine.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'watermark_params.dart';

class WatermarkEngine {
  /// Membuat parameter yang akan dikirim ke isolate
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

  /// Fungsi yang dijalankan di isolate
  static Future<Uint8List> applyFromMap(Map<String, dynamic> map) async {
    final params = WatermarkParams.fromMap(map);
    return await _applyWatermark(params);
  }

  static Future<Uint8List> _applyWatermark(WatermarkParams params) async {
    // 1. Decode gambar asli
    img.Image original = img.decodeImage(params.imageBytes)!;
    if (original.width == 0 || original.height == 0) {
      throw Exception('Gambar tidak valid');
    }

    // 2. Decode peta mini jika ada dan diaktifkan
    img.Image? miniMap;
    if (params.showMiniMap && params.mapBytes != null && params.mapBytes!.isNotEmpty) {
      miniMap = img.decodeImage(params.mapBytes!);
      debugPrint('✅ Mini map berhasil didecode: ${miniMap?.width}x${miniMap?.height}');
    } else {
      debugPrint('⚠️ Mini map tidak ditampilkan (showMiniMap=${params.showMiniMap}, mapBytes=${params.mapBytes != null})');
    }

    // 3. Buat gambar baru dengan ukuran yang mungkin disesuaikan (opsional: tambahkan border)
    img.Image output = img.copyResize(original, width: original.width, height: original.height);

    // 4. Gambar teks watermark (sesuai layout)
    _drawTextWatermark(output, params);

    // 5. Gambar peta mini jika ada
    if (miniMap != null) {
      _drawMiniMap(output, miniMap, params.watermarkPosition);
    }

    // 6. Encode ke JPEG (kualitas 90)
    return Uint8List.fromList(img.encodeJpg(output, quality: 90));
  }

  /// Fungsi untuk menggambar teks watermark (contoh sederhana)
  static void _drawTextWatermark(img.Image image, WatermarkParams params) {
    final font = img.arial_48; // pastikan font tersedia, atau pakai default
    final timestampStr = _formatTimestamp(params.timestamp);
    final locationStr = params.address.isNotEmpty ? params.address : 'Tidak ada lokasi';
    final weatherStr = params.showWeather && params.weather.isNotEmpty ? ' | ${params.weather}' : '';
    final accStr = params.showAccuracy && params.acc != null ? ' | ±${params.acc!.toStringAsFixed(0)}m' : '';

    String text = '$timestampStr | $locationStr$weatherStr$accStr';

    // Posisi berdasarkan watermarkPosition
    int x = 20, y = 20;
    switch (params.watermarkPosition.toLowerCase()) {
      case 'top-right':
        x = image.width - 20 - 300; // estimasi lebar teks
        y = 20;
        break;
      case 'bottom-left':
        x = 20;
        y = image.height - 50;
        break;
      case 'bottom-right':
        x = image.width - 20 - 300;
        y = image.height - 50;
        break;
      default: // top-left
        x = 20;
        y = 20;
    }

    img.drawString(image, text, font: font, x: x, y: y, color: img.ColorRgba8(255, 255, 255, 200));
  }

  /// Fungsi menggambar peta mini (resize dan posisi)
  static void _drawMiniMap(img.Image canvas, img.Image miniMap, String position) {
    // Ukuran peta: maksimal 150px lebar, pertahankan rasio
    int targetWidth = 150;
    int targetHeight = (miniMap.height * targetWidth / miniMap.width).toInt();
    if (targetHeight > 150) {
      targetHeight = 150;
      targetWidth = (miniMap.width * targetHeight / miniMap.height).toInt();
    }
    final resizedMap = img.copyResize(miniMap, width: targetWidth, height: targetHeight);

    // Tentukan posisi
    int x, y;
    switch (position.toLowerCase()) {
      case 'top-right':
        x = canvas.width - resizedMap.width - 15;
        y = 80;
        break;
      case 'bottom-left':
        x = 15;
        y = canvas.height - resizedMap.height - 80;
        break;
      case 'bottom-right':
        x = canvas.width - resizedMap.width - 15;
        y = canvas.height - resizedMap.height - 80;
        break;
      default: // top-left
        x = 15;
        y = 80;
    }

    // Gambar dengan border putih tipis
    img.drawRect(canvas, x - 2, y - 2, resizedMap.width + 4, resizedMap.height + 4, color: img.ColorRgba8(255, 255, 255, 200));
    img.compositeImage(canvas, resizedMap, destX: x, destY: y);
  }

  static String _formatTimestamp(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
