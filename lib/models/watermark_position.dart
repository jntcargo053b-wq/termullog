import 'package:flutter/material.dart';

@immutable
class WatermarkPosition {
  /// Posisi horizontal (0.0 - 1.0)
  final double x;

  /// Posisi vertical (0.0 - 1.0)
  final double y;

  /// Skala watermark
  final double scale;

  const WatermarkPosition({
    required this.x,
    required this.y,
    required this.scale,
  });

  /// Posisi default
  static const initial = WatermarkPosition(
    x: 0.5,
    y: 0.82,
    scale: 1.0,
  );

  /// Copy aman
  WatermarkPosition copyWith({
    double? x,
    double? y,
    double? scale,
  }) {
    return WatermarkPosition(
      x: (x ?? this.x).clamp(0.0, 1.0),
      y: (y ?? this.y).clamp(0.0, 1.0),
      scale: (scale ?? this.scale).clamp(0.6, 2.0),
    );
  }

  /// Simpan ke JSON
  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'scale': scale,
    };
  }

  /// Load dari JSON aman
  factory WatermarkPosition.fromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return initial;
    }

    return WatermarkPosition(
      x: (json['x'] ?? 0.5).toDouble(),
      y: (json['y'] ?? 0.82).toDouble(),
      scale: (json['scale'] ?? 1.0).toDouble(),
    );
  }

  /// Posisi pixel nyata
  Offset toOffset(
    Size screenSize,
  ) {
    return Offset(
      screenSize.width * x,
      screenSize.height * y,
    );
  }

  @override
  String toString() {
    return 'WatermarkPosition('
        'x: $x, '
        'y: $y, '
        'scale: $scale'
        ')';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WatermarkPosition &&
            runtimeType == other.runtimeType &&
            x == other.x &&
            y == other.y &&
            scale == other.scale;
  }

  @override
  int get hashCode {
    return Object.hash(
      x,
      y,
      scale,
    );
  }
}
