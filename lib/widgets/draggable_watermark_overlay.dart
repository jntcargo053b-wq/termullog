import 'package:flutter/material.dart';
import '../models/watermark_position.dart';
import 'professional_watermark_card.dart';
import 'professional_watermark_painter.dart';

class DraggableWatermarkOverlay extends StatefulWidget {
  final Size previewSize;
  final DateTime timestamp;
  final bool hasPosition;
  final double? lat;
  final double? lon;
  final double? acc;
  final String address;
  final String weather;
  final bool showWeather;
  final bool showAccuracy;
  final bool showAddress;
  final bool showCoordinates;
  final double opacity;
  final bool showBorder;
  final String fontSize;
  final WatermarkPosition initialPosition;
  final Function(WatermarkPosition)? onPositionChanged;

  const DraggableWatermarkOverlay({
    super.key,
    required this.previewSize,
    required this.timestamp,
    required this.hasPosition,
    this.lat,
    this.lon,
    this.acc,
    required this.address,
    required this.weather,
    required this.showWeather,
    required this.showAccuracy,
    required this.showAddress,
    required this.showCoordinates,
    required this.opacity,
    required this.showBorder,
    required this.fontSize,
    this.initialPosition = WatermarkPosition.initial,
    this.onPositionChanged,
  });

  @override
  State<DraggableWatermarkOverlay> createState() =>
      _DraggableWatermarkOverlayState();
}

class _DraggableWatermarkOverlayState extends State<DraggableWatermarkOverlay> {
  late WatermarkPosition _position;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
  }

  void _updatePosition(WatermarkPosition newPos) {
    setState(() {
      _position = newPos;
    });
    widget.onPositionChanged?.call(_position);
  }

  @override
  Widget build(BuildContext context) {
    // Hitung tinggi painter secara dinamis
    final double painterHeight = ProfessionalWatermarkPainter.computeHeight(
      hasPosition: widget.hasPosition,
      showCoordinates: widget.showCoordinates,
      showAccuracy: widget.showAccuracy,
      showAddress: widget.showAddress,
      address: widget.address,
      showWeather: widget.showWeather,
      weather: widget.weather,
      fontSize: widget.fontSize,
    );

    final cardWidth = 320.0; // lebar tetap card
    final cardHeight = painterHeight;

    final screenWidth = widget.previewSize.width;
    final screenHeight = widget.previewSize.height;

    // Batas agar card tidak keluar layar (dengan margin kecil)
    final maxLeft = screenWidth - cardWidth;
    final maxTop = screenHeight - cardHeight;
    double left = screenWidth * _position.x;
    double top = screenHeight * _position.y;
    left = left.clamp(0.0, maxLeft);
    top = top.clamp(0.0, maxTop);

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanUpdate: (details) {
          double newLeft = left + details.delta.dx;
          double newTop = top + details.delta.dy;
          newLeft = newLeft.clamp(0.0, maxLeft);
          newTop = newTop.clamp(0.0, maxTop);
          final newX = newLeft / screenWidth;
          final newY = newTop / screenHeight;
          _updatePosition(_position.copyWith(x: newX, y: newY));
        },
        onScaleUpdate: (details) {
          double newScale = _position.scale * details.scale;
          newScale = newScale.clamp(0.6, 2.0);
          _updatePosition(_position.copyWith(scale: newScale));
        },
        child: Transform.scale(
          scale: _position.scale,
          child: ProfessionalWatermarkCard(
            opacity: widget.opacity,
            showBorder: widget.showBorder,
            child: SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: CustomPaint(
                painter: ProfessionalWatermarkPainter(
                  timestamp: widget.timestamp,
                  hasPosition: widget.hasPosition,
                  lat: widget.lat,
                  lon: widget.lon,
                  acc: widget.acc,
                  address: widget.address,
                  weather: widget.weather,
                  showWeather: widget.showWeather,
                  showAccuracy: widget.showAccuracy,
                  showAddress: widget.showAddress,
                  showCoordinates: widget.showCoordinates,
                  opacity: widget.opacity,
                  showBorder: widget.showBorder,
                  fontSize: widget.fontSize,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
