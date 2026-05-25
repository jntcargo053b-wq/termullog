// lib/widgets/professional_watermark_card.dart
import 'package:flutter/material.dart';

class ProfessionalWatermarkCard extends StatelessWidget {
  final Widget child;
  final double opacity;
  final bool showBorder;
  final VoidCallback? onTap;

  const ProfessionalWatermarkCard({
    super.key,
    required this.child,
    this.opacity = 0.82,
    this.showBorder = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
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
