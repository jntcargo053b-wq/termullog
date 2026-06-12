import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class CameraInitializerException implements Exception {
  final String message;
  final Object? cause;
  const CameraInitializerException(this.message, {this.cause});
  @override
  String toString() => 'CameraInitializerException: $message'
      '${cause != null ? " ($cause)" : ""}';
}

class CameraInitializer {
  final List<CameraDescription> cameras;
  CameraController? _controller;
  bool _isReady = false;
  String? _lastError;

  CameraInitializer(this.cameras);

  CameraController? get controller => _controller;
  bool get isReady => _isReady;
  String? get lastError => _lastError;

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
    if (cameras.isEmpty) {
      _lastError = 'Tidak ada kamera yang tersedia';
      throw const CameraInitializerException('Tidak ada kamera yang tersedia');
    }

    await dispose();

    // FIX: pilih resolusi berdasarkan ketersediaan device.
    // veryHigh bisa OOM di device 2–3 GB RAM — coba high sebagai fallback.
    CameraController? c;
    CameraException? lastCameraError;

    for (final preset in [ResolutionPreset.veryHigh, ResolutionPreset.high]) {
      try {
        c = CameraController(
          cameras.first,
          preset,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );
        await c.initialize();
        break; // sukses, keluar dari loop
      } on CameraException catch (e) {
        lastCameraError = e;
        await c?.dispose();
        c = null;
        if (preset == ResolutionPreset.high) rethrow; // sudah coba semua
      }
    }

    // FIX: controller di-dispose jika widget sudah unmount setelah await
    if (!isMounted()) {
      await c?.dispose();
      return;
    }

    if (c == null) {
      _lastError = lastCameraError?.description ?? 'Gagal inisialisasi kamera';
      throw CameraInitializerException(
        _lastError!,
        cause: lastCameraError,
      );
    }

    _controller = c;
    _isReady = true;
    _lastError = null;
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
