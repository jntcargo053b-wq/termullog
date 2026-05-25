import 'package:flutter/material.dart';

@immutable
class WatermarkPosition {
  final double x;
  final double y;
  final double scale;
  final double fontScale; // 🔥 Pisahkan scale card dan font

  const WatermarkPosition({
    required this.x,
    required this.y,
    required this.scale,
    this.fontScale = 1.0,
  });

  static const initial = WatermarkPosition(
    x: 0.5,
    y: 0.82,
    scale: 1.0,
    fontScale: 1.0,
  );

  WatermarkPosition copyWith({
    double? x,
    double? y,
    double? scale,
    double? fontScale,
  }) {
    return WatermarkPosition(
      x: (x ?? this.x).clamp(0.04, 0.96), // 🔥 Safe area clamp
      y: (y ?? this.y).clamp(0.04, 0.92),
      scale: (scale ?? this.scale).clamp(0.5, 2.5),
      fontScale: (fontScale ?? this.fontScale).clamp(0.7, 1.5),
    );
  }

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'scale': scale,
    'fontScale': fontScale,
  };

  factory WatermarkPosition.fromJson(Map<String, dynamic>? json) {
    if (json == null) return initial;
    return WatermarkPosition(
      x: (json['x'] ?? 0.5).toDouble(),
      y: (json['y'] ?? 0.82).toDouble(),
      scale: (json['scale'] ?? 1.0).toDouble(),
      fontScale: (json['fontScale'] ?? 1.0).toDouble(),
    );
  }

  Offset toOffset(Size screenSize) => Offset(screenSize.width * x, screenSize.height * y);
}
