import 'dart:math';
import 'package:flutter/material.dart';
import '../models/watermark_position.dart';
import '../core/constants.dart';
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
    this.initialPosition = WatermarkPosition.initial,
    this.onPositionChanged,
    this.showSnapGuides = true,
  });

  @override
  State<DraggableWatermarkOverlay> createState() => _DraggableWatermarkOverlayState();
}

class _DraggableWatermarkOverlayState extends State<DraggableWatermarkOverlay> with SingleTickerProviderStateMixin {
  late WatermarkPosition _position;
  late AnimationController _snapAnimationController;
  bool _isDragging = false;

  static const List<Map<String, dynamic>> _presets = [
    {'name': 'Bawah Kiri', 'icon': Icons.crop_7_5, 'x': 0.04, 'y': 0.82, 'scale': 1.0},
    {'name': 'Bawah Tengah', 'icon': Icons.crop_5_4, 'x': 0.5, 'y': 0.82, 'scale': 1.0},
    {'name': 'Bawah Kanan', 'icon': Icons.crop_7_5, 'x': 0.96, 'y': 0.82, 'scale': 1.0},
    {'name': 'Atas Kiri', 'icon': Icons.crop_7_5, 'x': 0.04, 'y': 0.08, 'scale': 0.9},
    {'name': 'Atas Kanan', 'icon': Icons.crop_7_5, 'x': 0.96, 'y': 0.08, 'scale': 0.9},
    {'name': 'Cinematic', 'icon': Icons.movie, 'x': 0.5, 'y': 0.88, 'scale': 1.2},
  ];

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
    _snapAnimationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  }

  @override
  void dispose() {
    _snapAnimationController.dispose();
    super.dispose();
  }

  void _updatePosition(WatermarkPosition newPos, {bool animate = false}) {
    if (animate) _snapAnimationController.forward(from: 0.0);
    setState(() => _position = newPos);
    widget.onPositionChanged?.call(_position);
  }

  WatermarkPosition _applySnap(WatermarkPosition pos, Size screenSize, Size cardSize) {
    final screenW = screenSize.width;
    final screenH = screenSize.height;
    final cardW = cardSize.width * pos.scale;
    final cardH = cardSize.height * pos.scale;
    double newX = pos.x;
    double newY = pos.y;
    double left = screenW * pos.x;
    double top = screenH * pos.y;

    final centerX = (screenW - cardW) / 2;
    if ((left - centerX).abs() < 25) newX = (centerX / screenW).clamp(0.04, 0.96);

    final thirdTop = screenH * 0.33;
    final thirdBottom = screenH * 0.66;
    if ((top - thirdTop).abs() < 25) newY = (thirdTop / screenH).clamp(0.04, 0.92);
    else if ((top - thirdBottom).abs() < 25) newY = (thirdBottom / screenH).clamp(0.04, 0.92);

    return pos.copyWith(x: newX, y: newY);
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = widget.previewSize.width > widget.previewSize.height;
    final dummyPainter = ProfessionalWatermarkPainter(
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
      layout: widget.layout,
      fontScale: _position.fontScale,
    );
    
    final double painterHeight = dummyPainter.computeHeightSync(Size(320, 400), isLandscape: isLandscape);
    final double baseCardWidth = isLandscape ? 340 : 320;
    final double cardWidth = (baseCardWidth * _position.scale).clamp(220, 480);
    final double cardHeight = painterHeight * _position.scale;
    
    final screenWidth = widget.previewSize.width;
    final screenHeight = widget.previewSize.height;
    final safeLeft = screenWidth * 0.04;
    final safeRight = screenWidth * 0.96 - cardWidth;
    final safeTop = screenHeight * 0.04;
    final safeBottom = screenHeight * 0.92 - cardHeight;
    
    double left = screenWidth * _position.x;
    double top = screenHeight * _position.y;
    left = left.clamp(safeLeft, safeRight);
    top = top.clamp(safeTop, safeBottom);

    return Stack(
      children: [
        if (_isDragging && widget.showSnapGuides)
          IgnorePointer(
            child: CustomPaint(
              painter: SnapGuidePainter(screenSize: widget.previewSize, cardRect: Rect.fromLTWH(left, top, cardWidth, cardHeight)),
            ),
          ),
        
        // Tombol preset (kanan atas)
        Positioned(
          top: 60,
          right: 10,
          child: Column(
            children: [
              _buildPresetButton(Icons.grid_view, () => _showPresetDialog(context)),
              const SizedBox(height: 8),
              _buildPresetButton(Icons.center_focus_strong, () {
                final snapped = _applySnap(_position, widget.previewSize, Size(cardWidth, cardHeight));
                _updatePosition(snapped, animate: true);
              }),
              const SizedBox(height: 8),
              _buildPresetButton(Icons.refresh, () => _updatePosition(WatermarkPosition.initial, animate: true)),
            ],
          ),
        ),
        
        Positioned(
          left: left,
          top: top,
          child: AnimatedBuilder(
            animation: _snapAnimationController,
            builder: (context, child) {
              final animationValue = _snapAnimationController.value;
              final animatedScale = 1.0 - (animationValue * 0.04);
              return Transform.scale(
                scale: animatedScale,
                child: GestureDetector(
                  onPanStart: (_) => setState(() => _isDragging = true),
                  onPanUpdate: (details) {
                    double newLeft = (left + details.delta.dx).clamp(safeLeft, safeRight);
                    double newTop = (top + details.delta.dy).clamp(safeTop, safeBottom);
                    _updatePosition(_position.copyWith(x: newLeft / screenWidth, y: newTop / screenHeight));
                  },
                  onPanEnd: (_) {
                    setState(() => _isDragging = false);
                    final snapped = _applySnap(_position, widget.previewSize, Size(cardWidth, cardHeight));
                    if (snapped != _position) _updatePosition(snapped, animate: true);
                  },
                  onScaleUpdate: (details) {
                    double newScale = (_position.scale * details.scale).clamp(0.5, 2.5);
                    double newFontScale = (_position.fontScale * details.scale).clamp(0.7, 1.5);
                    _updatePosition(_position.copyWith(scale: newScale, fontScale: newFontScale));
                  },
                  child: ProfessionalWatermarkCard(
                    position: _position,
                    screenSize: widget.previewSize,
                    isLandscape: isLandscape,
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
                          layout: widget.layout,
                          fontScale: _position.fontScale,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPresetButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(padding: const EdgeInsets.all(10), child: Icon(icon, color: Colors.white, size: 22)),
      ),
    );
  }

  void _showPresetDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          children: _presets.map((preset) => ListTile(
            leading: Icon(preset['icon'], color: Colors.white70),
            title: Text(preset['name'], style: const TextStyle(color: Colors.white)),
            onTap: () {
              _updatePosition(_position.copyWith(x: preset['x'], y: preset['y'], scale: preset['scale']), animate: true);
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
  SnapGuidePainter({required this.screenSize, required this.cardRect});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.4)..strokeWidth = 1.5..style = PaintingStyle.stroke;
    final centerY = screenSize.height / 2;
    final centerX = screenSize.width / 2;
    canvas.drawLine(Offset(0, centerY), Offset(screenSize.width, centerY), paint);
    canvas.drawLine(Offset(centerX, 0), Offset(centerX, screenSize.height), paint);
    paint.color = Colors.white.withOpacity(0.2);
    final thirdX1 = screenSize.width / 3, thirdX2 = screenSize.width * 2 / 3;
    final thirdY1 = screenSize.height / 3, thirdY2 = screenSize.height * 2 / 3;
    canvas.drawLine(Offset(thirdX1, 0), Offset(thirdX1, screenSize.height), paint);
    canvas.drawLine(Offset(thirdX2, 0), Offset(thirdX2, screenSize.height), paint);
    canvas.drawLine(Offset(0, thirdY1), Offset(screenSize.width, thirdY1), paint);
    canvas.drawLine(Offset(0, thirdY2), Offset(screenSize.width, thirdY2), paint);
    final highlightPaint = Paint()..color = Colors.blueAccent.withOpacity(0.3)..style = PaintingStyle.fill;
    canvas.drawRect(cardRect, highlightPaint);
  }

  @override
  bool shouldRepaint(SnapGuidePainter oldDelegate) => true;
}
