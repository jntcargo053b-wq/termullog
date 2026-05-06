// ════════════════════════════════════════════════════════════════════════════
//  TermulLog — main.dart
//  Entry point aplikasi
// ════════════════════════════════════════════════════════════════════════════

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'core/camera_registry.dart';
import 'services/watermark_layout_service.dart';
import 'ui/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init kamera global
  try {
    CameraRegistry.cameras = await availableCameras();
  } catch (e) {
    debugPrint('Camera initialization failed: $e');
  }

  // Load layout preference tersimpan
  await WatermarkLayoutService.load();

  runApp(const App());
}
