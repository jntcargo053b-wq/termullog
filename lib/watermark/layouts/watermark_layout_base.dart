// lib/watermark/layouts/watermark_layout_base.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../../core/constants.dart';

abstract class WatermarkLayoutBase {
  String get name;

  img.Image apply({
    required img.Image src,
    required DateTime timestamp,
    required bool hasPosition,
    required double? lat,
    required double? lon,
    required double? acc,
    required String address,
    required String weather,
    required bool showWeather,
    required bool showAccuracy,
    required String watermarkPosition,
    required bool showMiniMap,
    required Uint8List? mapBytes,
    required bool showAddress,
    required bool showCoordinates,
    required double opacity,
    required bool showBorder,
    required String fontSize,
  });

  static Uint8List encodeJpg(img.Image image, {int quality = kJpegQuality}) {
    return Uint8List.fromList(img.encodeJpg(image, quality: quality));
  }
}
