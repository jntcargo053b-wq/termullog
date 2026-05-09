import 'package:camera/camera.dart';

class CameraRegistry {
  static List<CameraDescription> cameras = [];
  
  static Future<void> initialize() async {
    cameras = await availableCameras();
  }
}
