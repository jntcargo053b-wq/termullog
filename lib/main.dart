// lib/main.dart — POD Edition (Minimalis)
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/camera_registry.dart';
import 'services/settings_cache.dart';
import 'services/pod_address_resolver.dart';
import 'ui/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('id', null);

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Preload settings saja
  // Address cache akan di-load otomatis saat pertama kali dibutuhkan
  await SettingsCache.preload();

  try {
    CameraRegistry.cameras = await availableCameras();
    debugPrint('Cameras: ${CameraRegistry.cameras.length}');
  } catch (e) {
    debugPrint('Camera init error: $e');
    CameraRegistry.cameras = [];
  }

  runApp(const App());
}
