// lib/watermark/watermark_params.dart
import 'dart:typed_data';

/// Parameter lengkap untuk rendering watermark (dipakai di engine & isolate)
class WatermarkParams {
  final Uint8List imageBytes;
  final DateTime timestamp;
  final String address;
  final String weather;
  final int layoutIndex;       // WatermarkLayout.index
  final bool showWeather;
  final bool showAccuracy;
  final bool showAddress;
  final bool showCoordinates;
  final double opacity;
  final bool showBorder;
  final String fontSize;       // 'small' | 'normal' | 'large'
  final double? lat;
  final double? lon;
  final double? acc;
  final int imageQuality;
  final String dateFormat;
  final String timeFormat;
  final double fontScale;
  final String appName;         // nama aplikasi di watermark (default: 'TermulLog')

  const WatermarkParams({
    required this.imageBytes,
    required this.timestamp,
    required this.address,
    required this.weather,
    required this.layoutIndex,
    required this.showWeather,
    required this.showAccuracy,
    this.showAddress = true,
    this.showCoordinates = true,
    this.opacity = 0.88,
    this.showBorder = true,
    this.fontSize = 'normal',
    this.lat,
    this.lon,
    this.acc,
    this.imageQuality = 92,
    this.dateFormat = 'dd MMM yyyy',
    this.timeFormat = 'HH:mm:ss',
    this.fontScale = 1.0,
    this.appName = 'TermulLog',
  });
}
