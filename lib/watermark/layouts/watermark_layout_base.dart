import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../../core/constants.dart';

abstract class WatermarkLayoutBase {
  String get name;
  String get defaultPosition => 'bottom';
  double get defaultOpacity => 0.85;
  bool get supportsMiniMap => true;
  bool get supportsBorder => true;

  Uint8List apply({
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
    Uint8List? mapBytes,
    bool showAddress = true,
    bool showCoordinates = true,
    double opacity = 0.85,
    bool showBorder = true,
    String fontSize = 'normal',
  });

  static int resolveYStart({
    required String watermarkPosition,
    required int imageHeight,
    required int contentHeight,
    int margin = 20,
  }) {
    switch (watermarkPosition.toLowerCase()) {
      case 'top':
        return margin;
      case 'bottom':
        return imageHeight - contentHeight - margin;
      case 'center':
        return (imageHeight - contentHeight) ~/ 2;
      default:
        return imageHeight - contentHeight - margin;
    }
  }

  static bool isAtTopEdge(int y, int imageHeight) => y < imageHeight / 2;

  static Uint8List encodeJpg(img.Image image, {int quality = 90}) {
    return img.encodeJpg(image, quality: quality);
  }
}
