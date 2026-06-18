// lib/widgets/draggable_watermark_overlay.dart
// Overlay watermark yang bisa di-drag di viewfinder kamera.
// Menggunakan WatermarkPreviewPainter sebagai renderer.

import 'dart:math';
import 'package:flutter/material.dart';
import '../models/watermark_position.dart';
import '../core/constants.dart';
import '../watermark/watermark_preview_painter.dart';

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
  final WatermarkLayout layout;
  final WatermarkPosition initialPosition;
  final Function(WatermarkPosition)? onPositionChanged;
  final bool showSnapGuides;

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
    required this.layout,
    required this.initialPosition,
    this.onPositionChanged,
    this.showSnapGuides = true,
  });

  @override
  State<DraggableWatermarkOverlay> createState() => _DraggableWatermarkOverlayState();
}

class _DraggableWatermarkOverlayState extends State<DraggableWatermarkOverlay>
    with SingleTickerProviderStateMixin {
  late WatermarkPosition _position;
  bool _isDragging = false;

  late AnimationController _snapAnimController;

  // Preset posisi
  final List<Map<String, dynamic>> _presets = [
    {'name': 'Bawah Kiri',   'icon': Icons.south_west, 'x': 0.02, 'y': 0.82, 'scale': 1.0},
    {'name': 'Bawah Kanan',  'icon': Icons.south_east, 'x': 0.50, 'y': 0.82, 'scale': 1.0},
    {'name': 'Bawah Tengah', 'icon': Icons.south,       'x': 0.25, 'y': 0.82, 'scale': 1.0},
    {'name': 'Atas Kiri',    'icon': Icons.north_west,  'x': 0.02, 'y': 0.02, 'scale': 1.0},
    {'name': 'Atas Kanan',   'icon': Icons.north_east,  'x': 0.50, 'y': 0.02, 'scale': 1.0},
  ];

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
    _snapAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
  }

  @override
  void dispose() {
    _snapAnimController.dispose();
    super.dispose();
  }

  void _updatePosition(WatermarkPosition pos, {bool animate = false}) {
    setState(() => _position = pos);
    if (animate) {
      _snapAnimController.forward(from: 0).then((_) => _snapAnimController.reverse());
    }
    widget.onPositionChanged?.call(pos);
  }

  WatermarkPosition _applySnap(WatermarkPosition pos, Size screenSize) {
    double newX = pos.x;
    double newY = pos.y;
    final double left = screenSize.width * pos.x;
    final double top = screenSize.height * pos.y;

    final double centerX = screenSize.width / 2;
    if ((left - centerX).abs() < 28) newX = (centerX / screenSize.width).clamp(0.04, 0.96);

    final double thirdY1 = screenSize.height * 0.33;
    final double thirdY2 = screenSize.height * 0.66;
    if ((top - thirdY1).abs() < 28) newY = (thirdY1 / screenSize.height).clamp(0.04, 0.92);
    else if ((top - thirdY2).abs() < 28) newY = (thirdY2 / screenSize.height).clamp(0.04, 0.92);

    return pos.copyWith(x: newX, y: newY);
  }

  @override
  Widget build(BuildContext context) {
    final double screenW = widget.previewSize.width;
    final double screenH = widget.previewSize.height;

    // Ukuran card preview – setengah lebar layar, tinggi proporsional
    final double cardW = (screenW * 0.52 * _position.scale).clamp(200.0, 400.0);
    final double cardH = cardW * 0.55; // proporsi landscape-friendly

    final double safeMargin = 12.0;
    double left = (screenW * _position.x).clamp(safeMargin, screenW - cardW - safeMargin);
    double top  = (screenH * _position.y).clamp(safeMargin, screenH - cardH - safeMargin);

    return Stack(
      children: [
        // Snap guides saat dragging
        if (_isDragging && widget.showSnapGuides)
          IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: SnapGuidePainter(
                  screenSize: widget.previewSize,
                  cardRect: Rect.fromLTWH(left, top, cardW, cardH),
                ),
              ),
            ),
          ),

        // Control buttons (preset & reset)
        Positioned(
          top: 60,
          right: 10,
          child: Column(
            children: [
              _controlBtn(Icons.grid_view, () => _showPresetDialog(context)),
              const SizedBox(height: 8),
              _controlBtn(Icons.center_focus_strong, () {
                final snapped = _applySnap(_position, widget.previewSize);
                _updatePosition(snapped, animate: true);
              }),
              const SizedBox(height: 8),
              _controlBtn(Icons.refresh, () =>
                  _updatePosition(WatermarkPosition.initial, animate: true)),
            ],
          ),
        ),

        // Card yang bisa di-drag
        Positioned(
          left: left,
          top: top,
          child: AnimatedBuilder(
            animation: _snapAnimController,
            builder: (context, child) {
              final s = 1.0 - (_snapAnimController.value * 0.04);
              return Transform.scale(scale: s, child: child);
            },
            child: GestureDetector(
              onPanStart: (_) => setState(() => _isDragging = true),
              onPanUpdate: (details) {
                double nx = ((left + details.delta.dx) / screenW).clamp(0.04, 0.96);
                double ny = ((top + details.delta.dy) / screenH).clamp(0.04, 0.92);
                _updatePosition(_position.copyWith(x: nx, y: ny));
              },
              onPanEnd: (_) {
                setState(() => _isDragging = false);
                final snapped = _applySnap(_position, widget.previewSize);
                if (snapped != _position) _updatePosition(snapped, animate: true);
              },
              onScaleUpdate: (details) {
                final ns = (_position.scale * details.scale).clamp(0.5, 2.5);
                final nf = (_position.fontScale * details.scale).clamp(0.7, 1.5);
                _updatePosition(_position.copyWith(scale: ns, fontScale: nf));
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: cardW,
                  height: cardH,
                  child: CustomPaint(
                    painter: WatermarkPreviewPainter(
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
                      layout: widget.layout,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _controlBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  void _showPresetDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          children: _presets.map((preset) => ListTile(
            leading: Icon(preset['icon'] as IconData, color: Colors.white70),
            title: Text(preset['name'] as String,
                style: const TextStyle(color: Colors.white)),
            onTap: () {
              _updatePosition(
                _position.copyWith(
                  x: preset['x'] as double,
                  y: preset['y'] as double,
                  scale: preset['scale'] as double,
                ),
                animate: true,
              );
              Navigator.pop(context);
            },
          )).toList(),
        ),
      ),
    );
  }
}

class SnapGuidePainter extends CustomPainter {
  final Size screenSize;
  final Rect cardRect;
  const SnapGuidePainter({required this.screenSize, required this.cardRect});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final cx = screenSize.width / 2;
    final cy = screenSize.height / 2;
    canvas.drawLine(Offset(0, cy), Offset(screenSize.width, cy), paint);
    canvas.drawLine(Offset(cx, 0), Offset(cx, screenSize.height), paint);

    paint.color = Colors.white.withOpacity(0.15);
    for (final frac in [1.0 / 3.0, 2.0 / 3.0]) {
      canvas.drawLine(Offset(0, screenSize.height * frac),
          Offset(screenSize.width, screenSize.height * frac), paint);
      canvas.drawLine(Offset(screenSize.width * frac, 0),
          Offset(screenSize.width * frac, screenSize.height), paint);
    }

    canvas.drawRect(
      cardRect,
      Paint()
        ..color = Colors.blueAccent.withOpacity(0.25)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(SnapGuidePainter old) =>
      old.screenSize != screenSize || old.cardRect != cardRect;
}
