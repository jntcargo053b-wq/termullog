import 'package:flutter/material.dart';

class WatermarkPosition {
  final double x;      // 0..1 (persen dari lebar layar)
  final double y;      // 0..1 (persen dari tinggi layar)
  final double scale;  // faktor skala (0.6 – 2.0)

  const WatermarkPosition({
    required this.x,
    required this.y,
    required this.scale,
  });

  WatermarkPosition copyWith({
    double? x,
    double? y,
    double? scale,
  }) {
    return WatermarkPosition(
      x: x ?? this.x,
      y: y ?? this.y,
      scale: scale ?? this.scale,
    );
  }

  // Posisi default (bawah tengah, sedikit naik)
  static const initial = WatermarkPosition(
    x: 0.5,   // center horizontal
    y: 0.82,  // 82% dari atas
    scale: 1.0,
  );

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'scale': scale,
      };

  factory WatermarkPosition.fromJson(Map<String, dynamic> json) {
    return WatermarkPosition(
      x: json['x'] as double,
      y: json['y'] as double,
      scale: json['scale'] as double,
    );
  }
}
