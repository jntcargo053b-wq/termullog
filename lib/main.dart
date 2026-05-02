// ════════════════════════════════════════════════════════════════════════════
//  TermulLog — main.dart
// ════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';

// ─── Global cameras list ─────────────────────────────────────────────────────
List<CameraDescription> _cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { _cameras = await availableCameras(); } catch (_) {}
  await WatermarkLayout.load();
  runApp(const App());
}

// ════════════════════════════════════════════════════════════════════════════
//  CONSTANTS
// ════════════════════════════════════════════════════════════════════════════

const int kMaxOutputWidth = 1280;
const int kJpegQuality    = 85;
const int kSigMaxWidth    = 500;

// ════════════════════════════════════════════════════════════════════════════
//  LAYOUT REGISTRY
// ════════════════════════════════════════════════════════════════════════════

class LayoutInfo {
  final String id, label, description;
  final IconData icon;
  final Color accentColor;
  const LayoutInfo({
    required this.id, required this.label, required this.description,
    required this.icon, required this.accentColor,
  });
}

const List<LayoutInfo> kLayouts = [
  LayoutInfo(id: 'layout1', label: 'Professional Report',
    description: 'Strip navy di bawah foto, kotak info abu-abu, tanda tangan kiri.',
    icon: Icons.article_outlined, accentColor: Color(0xFF1B4F72)),
  LayoutInfo(id: 'layout2', label: 'Compact Field',
    description: 'Strip hijau, info ringkas, cocok untuk laporan cepat di lapangan.',
    icon: Icons.assignment_turned_in_outlined, accentColor: Color(0xFF27AE60)),
  LayoutInfo(id: 'layout3', label: 'Dark Minimal',
    description: 'Latar gelap elegan, teks putih, garis aksen emas. Kesan premium.',
    icon: Icons.dark_mode_outlined, accentColor: Color(0xFF212121)),
  LayoutInfo(id: 'layout4', label: 'Split Side-by-Side',
    description: 'Panel kiri: foto. Panel kanan: info & tanda tangan dua kolom ungu.',
    icon: Icons.view_column_outlined, accentColor: Color(0xFF6C3483)),
];

// ════════════════════════════════════════════════════════════════════════════
//  WATERMARK ENGINE
// ════════════════════════════════════════════════════════════════════════════

Uint8List _processWatermark(Map<String, dynamic> p) {
  img.Image base = img.decodeImage(p['imageBytes'] as Uint8List)!;
  if (base.width > kMaxOutputWidth)
    base = img.copyResize(base, width: kMaxOutputWidth, interpolation: img.Interpolation.linear);

  final sigBytes = p['sigBytes'] as Uint8List?;
  img.Image? sig;
  if (sigBytes != null && sigBytes.isNotEmpty) {
    sig = img.decodeImage(sigBytes);
    if (sig != null && sig.width > 
