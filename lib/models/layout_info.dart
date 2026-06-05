// lib/models/layout_info.dart
import 'package:flutter/material.dart';
import '../core/constants.dart';

class LayoutInfo {
  final WatermarkLayout layout;
  final String label;
  final String description;
  final IconData icon;
  final Color accentColor;

  const LayoutInfo({
    required this.layout,
    required this.label,
    required this.description,
    required this.icon,
    required this.accentColor,
  });
}

const List<LayoutInfo> kLayouts = [
  LayoutInfo(
    layout: WatermarkLayout.podCorporate,
    label: 'Corporate Report',
    description: 'Panel putih bersih, logo, data terstruktur. Ideal untuk laporan perusahaan.',
    icon: Icons.article_rounded,
    accentColor: Color(0xFF1565C0),
  ),
  LayoutInfo(
    layout: WatermarkLayout.podDarkField,
    label: 'Dark Field',
    description: 'Overlay gelap transparan, accent cyan. Cocok untuk dokumentasi lapangan.',
    icon: Icons.camera_alt_rounded,
    accentColor: Color(0xFF00B8D4),
  ),
  LayoutInfo(
    layout: WatermarkLayout.podGovern,
    label: 'Government',
    description: 'Strip biru tua formal, hash verifikasi. Untuk dokumen resmi/pemerintahan.',
    icon: Icons.verified_rounded,
    accentColor: Color(0xFF1A237E),
  ),
];
