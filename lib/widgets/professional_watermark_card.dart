import 'package:flutter/material.dart';
import '../models/watermark_position.dart';

class ProfessionalWatermarkCard extends StatelessWidget {
  final Widget child;
  final double opacity;
  final bool showBorder;
  final VoidCallback? onTap;
  final WatermarkPosition position;
  final Size screenSize;
  final bool isLandscape;

  const ProfessionalWatermarkCard({
    super.key,
    required this.child,
    required this.position,
    required this.screenSize,
    required this.isLandscape,
    this.opacity = 0.82,
    this.showBorder = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 🔥 Dynamic width based on orientation
    double baseWidth = isLandscape ? 340 : 320;
    double dynamicWidth = (baseWidth * position.scale).clamp(220, 480);
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: dynamicWidth,
        padding: EdgeInsets.symmetric(
          horizontal: 16 * (isLandscape ? 0.8 : 1.0),
          vertical: 14 * (isLandscape ? 0.8 : 1.0),
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(isLandscape ? 20 : 24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.black.withOpacity(opacity),
              Colors.black.withOpacity(opacity - 0.08),
            ],
          ),
          border: showBorder
              ? Border.all(color: Colors.white.withOpacity(0.15), width: 1.2)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}
