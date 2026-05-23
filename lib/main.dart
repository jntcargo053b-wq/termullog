// ════════════════════════════════════════════════════════════════════════════
//  TermulLog — main.dart
//  Entry point aplikasi
// ════════════════════════════════════════════════════════════════════════════

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/camera_registry.dart';
import 'services/settings_cache.dart';
import 'ui/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inisialisasi locale untuk intl (wajib untuk DateFormat dengan locale 'id_ID')
  await initializeDateFormatting('id', null);

  // Set preferred orientations (portrait only)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Load pengaturan dari SharedPreferences (cache)
  await SettingsCache.preload();

  // Init kamera global
  try {
    CameraRegistry.cameras = await availableCameras();
    debugPrint('Camera initialized: ${CameraRegistry.cameras.length} cameras found');
  } catch (e) {
    debugPrint('Camera initialization failed: $e');
    CameraRegistry.cameras = [];
  }

  runApp(const App());
}
