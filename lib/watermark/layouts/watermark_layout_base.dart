// lib/watermark/layouts/watermark_layout_base.dart
import 'package:image/image.dart' as img;
import '../../core/constants.dart';
import '../watermark_utils.dart';

abstract class WatermarkLayoutBase {
  String get name;
  
  // Default values yang baik
  int get padding => 14;
  int get borderRadius => 12;
  img.Color get accentColor => kColorCyan;
  img.Color get backgroundColor => kColorDarkBg;
  double get opacity => 0.85;
  bool get hasShadow => true;
  bool get hasBorder => true;

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

  // Helper method untuk encode ke JPEG
  static Uint8List encodeJpg(img.Image image, {int quality = kJpegQuality}) {
    return img.encodeJpg(image, quality: quality);
  }

  // Helper method untuk decode
  static img.Image decodeOrThrow(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Failed to decode image');
    return image;
  }

  // Helper untuk mendapatkan font size
  double getFontSizeValue(String fontSize) {
    switch (fontSize) {
      case 'small': return 12;
      case 'large': return 18;
      default: return 14;
    }
  }

  // Helper untuk menentukan posisi Y
  int getYPosition(int imageHeight, int watermarkHeight, String position, int margin) {
    return position == 'bottom'
        ? imageHeight - watermarkHeight - margin
        : margin;
  }
  
  // Async version (override jika perlu)
  Future<img.Image> applyAsync({
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
  }) async {
    return apply(
      src: src,
      timestamp: timestamp,
      hasPosition: hasPosition,
      lat: lat,
      lon: lon,
      acc: acc,
      address: address,
      weather: weather,
      showWeather: showWeather,
      showAccuracy: showAccuracy,
      watermarkPosition: watermarkPosition,
      showMiniMap: showMiniMap,
      mapBytes: mapBytes,
      showAddress: showAddress,
      showCoordinates: showCoordinates,
      opacity: opacity,
      showBorder: showBorder,
      fontSize: fontSize,
    );
  }
}
