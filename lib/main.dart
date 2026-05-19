// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/camera_screen.dart';
import 'services/settings_service.dart';
import 'watermark/watermark_utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set orientation portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Load fonts
  await WatermarkFontManager.loadFonts();
  
  // Migrasi settings
  await SettingsService.migrateOldSettings();
  
  runApp(const TermulLogApp());
}

class TermulLogApp extends StatelessWidget {
  const TermulLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TermulLog',
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFF00B8D4),
        scaffoldBackgroundColor: const Color(0xFF0A0E1A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A1F2E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const CameraScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
