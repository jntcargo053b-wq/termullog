// ════════════════════════════════════════════════════════════════════════════
//  TermulLog — main.dart
//  Entry point aplikasi
// ════════════════════════════════════════════════════════════════════════════

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/camera_registry.dart';
import 'services/watermark_layout_service.dart';
import 'ui/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations (portrait only)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Init kamera global
  try {
    CameraRegistry.cameras = await availableCameras();
    debugPrint('Camera initialized: ${CameraRegistry.cameras.length} cameras found');
  } catch (e) {
    debugPrint('Camera initialization failed: $e');
    // Inisialisasi dengan list kosong agar tidak crash
    CameraRegistry.cameras = [];
  }

  // Load layout preference tersimpan
  await WatermarkLayoutService.load();

  runApp(const App());
}
