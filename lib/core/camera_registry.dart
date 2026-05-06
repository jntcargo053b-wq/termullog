// ════════════════════════════════════════════════════════════════════════════
//  core/camera_registry.dart
//  Daftar kamera yang tersedia di perangkat (diinisialisasi saat startup)
// ════════════════════════════════════════════════════════════════════════════

import 'package:camera/camera.dart';

class CameraRegistry {
  CameraRegistry._();
  static List<CameraDescription> cameras = [];
}
