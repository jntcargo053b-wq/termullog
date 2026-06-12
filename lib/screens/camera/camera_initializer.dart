import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class CameraInitializer {
  final List<CameraDescription> cameras;
  CameraController? _controller;
  bool _isReady = false;

  CameraInitializer(this.cameras);

  CameraController? get controller => _controller;
  bool get isReady => _isReady;

  static Future<void> requestGalleryPermission() async {
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      if (info.version.sdkInt >= 33) {
        await Permission.photos.request();
      } else {
        await Permission.storage.request();
      }
    }
  }

  Future<void> init({required bool Function() isMounted}) async {
    if (cameras.isEmpty) return;
    await dispose();
    final c = CameraController(
      cameras.first,
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await c.initialize();
    if (!isMounted()) {
      await c.dispose();
      return;
    }
    _controller = c;
    _isReady = true;
  }

  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
    _isReady = false;
  }

  Future<void> toggleTorch(bool torchOn) async {
    if (_controller == null) return;
    try {
      await _controller?.setFlashMode(torchOn ? FlashMode.torch : FlashMode.off);
    } catch (_) {}
  }
}
