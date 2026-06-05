// lib/widgets/pod_gps_bar.dart
// ============================================================
// POD GPS BAR — Status bar GPS untuk Proof of Delivery
// ============================================================
// Menampilkan:
//   - Level confidence (ikon + label)
//   - Akurasi dalam meter
//   - Progress bar menuju lock (animated)
//   - Badge "LOCKED" saat excellent
//   - Badge "CACHE" jika data dari sesi sebelumnya
// ============================================================

import 'package:flutter/material.dart';
import '../services/pod_gps_engine.dart';

class PodGpsBar extends StatelessWidget {
  final PodConfidence confidence;
  final double? accuracy;
  final double lockProgress;
  final bool fromCache;
  final bool addressLoading;

  const PodGpsBar({
    super.key,
    required this.confidence,
    this.accuracy,
    this.lockProgress = 0.0,
    this.fromCache = false,
    this.addressLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = _color(confidence);
    final label = confidence.label;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ikon GPS dengan pulse saat searching
          _GpsIcon(confidence: confidence, color: color),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Label + badge
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  if (confidence == PodConfidence.excellent) ...[
                    const SizedBox(width: 5),
                    _Badge(label: 'LOCKED', color: const Color(0xFF3CB86A)),
                  ],
                  if (fromCache) ...[
                    const SizedBox(width: 5),
                    _Badge(label: 'CACHE', color: const Color(0xFFFF9500)),
                  ],
                  if (addressLoading) ...[
                    const SizedBox(width: 5),
                    const SizedBox(
                      width: 8,
                      height: 8,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation(Color(0xFFFF9500)),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              // Accuracy + progress bar
              if (accuracy != null)
                Text(
                  '±${accuracy!.toStringAsFixed(0)} m',
                  style: TextStyle(
                    color: color.withOpacity(0.75),
                    fontSize: 9,
                    height: 1.2,
                  ),
                ),
              if (confidence != PodConfidence.excellent &&
                  confidence != PodConfidence.searching) ...[
                const SizedBox(height: 3),
                _LockProgressBar(progress: lockProgress, color: color),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Color _color(PodConfidence c) {
    switch (c) {
      case PodConfidence.searching: return Colors.grey;
      case PodConfidence.poor:      return const Color(0xFFE63946);
      case PodConfidence.fair:      return const Color(0xFFFF9500);
      case PodConfidence.good:      return const Color(0xFFFFD700);
      case PodConfidence.excellent: return const Color(0xFF3CB86A);
    }
  }
}

// ── Animated GPS Icon ────────────────────────────────────
class _GpsIcon extends StatefulWidget {
  final PodConfidence confidence;
  final Color color;
  const _GpsIcon({required this.confidence, required this.color});

  @override
  State<_GpsIcon> createState() => _GpsIconState();
}

class _GpsIconState extends State<_GpsIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = Tween(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = widget.confidence == PodConfidence.searching ||
        widget.confidence == PodConfidence.poor;

    if (isSearching) {
      return FadeTransition(
        opacity: _pulse,
        child: Icon(Icons.gps_not_fixed, size: 13, color: widget.color),
      );
    }
    if (widget.confidence == PodConfidence.excellent) {
      return Icon(Icons.gps_fixed, size: 13, color: widget.color);
    }
    return Icon(Icons.gps_not_fixed, size: 13, color: widget.color);
  }
}

// ── Lock Progress Bar ────────────────────────────────────
class _LockProgressBar extends StatelessWidget {
  final double progress;
  final Color color;
  const _LockProgressBar({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          backgroundColor: Colors.white12,
          valueColor: AlwaysStoppedAnimation(color),
          minHeight: 3,
        ),
      ),
    );
  }
}

// ── Badge ─────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.6), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 7,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
