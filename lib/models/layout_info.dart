// ════════════════════════════════════════════════════════════════════════════
//  models/layout_info.dart
//  Deskripsi setiap layout watermark yang tersedia
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class LayoutInfo {
  final String id;
  final String label;
  final String description;
  final IconData icon;
  final Color accentColor;

  const LayoutInfo({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.accentColor,
  });
}

const List<LayoutInfo> kLayouts = [
  LayoutInfo(
    id: 'layout1',
    label: 'Professional Report',
    description:
        'Overlay navy transparan di bawah foto. Info lengkap: teknisi, ID, waktu, lokasi, cuaca + TTD.',
    icon: Icons.article_outlined,
    accentColor: Color(0xFF1B4F72),
  ),
  LayoutInfo(
    id: 'layout2',
    label: 'Compact Field',
    description:
        'Card pojok kanan atas. Info ringkas: nama, ID, waktu, lokasi. Cocok laporan cepat.',
    icon: Icons.assignment_turned_in_outlined,
    accentColor: Color(0xFF00897B),
  ),
  LayoutInfo(
    id: 'layout3',
    label: 'Dark Minimal',
    description:
        'Overlay gelap transparan + aksen cyan. Teks putih & cyan. Kesan premium modern.',
    icon: Icons.dark_mode_outlined,
    accentColor: Color(0xFF00B894),
  ),
  LayoutInfo(
    id: 'layout4',
    label: 'Vertical Sidebar',
    description:
        'Sidebar kiri dengan logo, teknisi, ID, waktu, lokasi & TTD. Ideal untuk foto portrait.',
    icon: Icons.layers_outlined,
    accentColor: Color(0xFF7B1FA2),
  ),
];
