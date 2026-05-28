import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../core/constants.dart';
import '../widgets/unified_watermark_painter.dart';

class WatermarkEngine {
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
    required double fontScale,
    required int imageQuality,
    double pixelRatio = 1.0,
  }) async {
    final ui.Image original = await _decodeImage(imageBytes);
    final int width = original.width;
    final int height = original.height;

    // Card width: ~38% of image width, clamped
    final double cardWidth = (width * 0.38).clamp(220.0, 420.0);

    final dummyPainter = UnifiedWatermarkPainter(
      timestamp: timestamp,
      hasPosition: lat != null && lon != null,
      lat: lat,
      lon: lon,
      acc: acc,
      address: address,
      weather: weather,
      showWeather: showWeather,
      showAccuracy: showAccuracy,
      showAddress: showAddress,
      showCoordinates: showCoordinates,
      opacity: opacity,
      showBorder: showBorder,
      fontSize: fontSize,
      layout: layout,
      fontScale: fontScale,
      cardWidth: cardWidth,
      isHighQuality: true,
      pixelRatio: pixelRatio,
    );
    final double cardHeight = dummyPainter.computeHeight();

    // Default position center-bottom (0.5, 0.85) – baca dari SettingsCache
    final double posX = 0.5;
    final double posY = 0.85;
    double left = (width * posX) - (cardWidth / 2);
    double top = (height * posY) - (cardHeight / 2);
    const double safeMargin = 16;
    left = left.clamp(safeMargin, width - cardWidth - safeMargin);
    top = top.clamp(safeMargin, height - cardHeight - safeMargin);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(original, Offset.zero, Paint());
    canvas.save();
    canvas.translate(left, top);

    final painter = UnifiedWatermarkPainter(
      timestamp: timestamp,
      hasPosition: lat != null && lon != null,
      lat: lat,
      lon: lon,
      acc: acc,
      address: address,
      weather: weather,
      showWeather: showWeather,
      showAccuracy: showAccuracy,
      showAddress: showAddress,
      showCoordinates: showCoordinates,
      opacity: opacity,
      showBorder: showBorder,
      fontSize: fontSize,
      layout: layout,
      fontScale: fontScale,
      cardWidth: cardWidth,
      isHighQuality: true,
      pixelRatio: pixelRatio,
    );
    painter.paint(canvas, Size(cardWidth, cardHeight));

    canvas.restore();
    final picture = recorder.endRecording();
    final ui.Image output = await picture.toImage(width, height);

    final byteData = await output.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) throw Exception('Failed to get image bytes');
    final img.Image jpegImg = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: byteData.buffer.asUint8List(),
      numChannels: 4,
    );
    final jpegBytes = img.encodeJpg(jpegImg, quality: imageQuality.clamp(50, 100));

    original.dispose();
    output.dispose();
    picture.dispose();

    return jpegBytes;
  }

  static Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromList(bytes, (image) => completer.complete(image));
    return completer.future;
  }
}
