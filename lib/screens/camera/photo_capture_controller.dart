import 'dart:io';
import 'package:camera/camera.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/pod_location_service.dart';
import '../../services/settings_cache.dart';
import '../../services/location_weather_service.dart';
import '../../watermark/watermark_engine.dart';
import '../../watermark/watermark_params.dart';
import 'image_processing.dart';
import 'camera_settings_controller.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class GpsGateResult {
  final GpsGate gate;
  final double accuracy;
  const GpsGateResult({required this.gate, required this.accuracy});
}

enum GpsGate { noPosition, blockedByAccuracy, needsConfirmation, ok }

class CaptureResult {
  final bool success;
  final bool savedToGallery;
  final String? savedPath;
  final String? errorMessage;
  const CaptureResult({
    required this.success,
    this.savedToGallery = false,
    this.savedPath,
    this.errorMessage,
  });
}

class PhotoCaptureController {
  static const double hardBlockAccuracy = 35.0;
  static const double warnAccuracy = 20.0;
  const PhotoCaptureController();

  GpsGateResult checkGpsGate(PodLocationState gps) {
    if (gps.lat == null || gps.lon == null) {
      return const GpsGateResult(gate: GpsGate.noPosition, accuracy: 0);
    }
    final acc = gps.accuracy ?? 999.0;
    if (acc > hardBlockAccuracy) {
      return GpsGateResult(gate: GpsGate.blockedByAccuracy, accuracy: acc);
    }
    if (!gps.confidence.canCapture || acc > warnAccuracy) {
      return GpsGateResult(gate: GpsGate.needsConfirmation, accuracy: acc);
    }
    return GpsGateResult(gate: GpsGate.ok, accuracy: acc);
  }

  Future<CaptureResult> capture({
    required CameraController controller,
    required PodLocationState gps,
    required CaptureSettings settings,
  }) async {
    // FIX: captureTime diambil SEBELUM await takePicture() agar timestamp
    // mencerminkan waktu shutter, bukan waktu selesai I/O.
    final captureTime = DateTime.now();

    XFile? xFile;
    try {
      xFile = await controller.takePicture();
      final rawBytes = await File(xFile.path).readAsBytes();
      final fontScale = await SettingsCache.getFontScale();
      final imageQuality = await SettingsCache.imageQuality;

      Uint8List finalBytes;
      try {
        finalBytes = await compute(resizeImageIsolate, ResizeParams(rawBytes, imageQuality));
      } catch (e) {
        finalBytes = await resizeImageSync(rawBytes, imageQuality);
      }

      Uint8List? mapBytes;
      if (settings.showMiniMap && gps.lat != null && gps.lon != null) {
        try {
          mapBytes = await LocationWeatherService.fetchMapWithRetry(
            gps.lat!, gps.lon!,
            width: 240, height: 240,
            zoom: settings.mapZoomLevel,
          );
        } catch (_) {}
      }

      final params = WatermarkParams(
        imageBytes: finalBytes,
        timestamp: captureTime,
        address: gps.address,
        weather: gps.weather,
        layoutIndex: settings.layout.index,
        showWeather: settings.showWeather,
        showAccuracy: settings.showAccuracy,
        showAddress: settings.showAddress,
        showCoordinates: settings.showCoordinates,
        opacity: settings.opacity,
        showBorder: settings.showBorder,
        lat: gps.lat,
        lon: gps.lon,
        acc: gps.accuracy,
        fontScale: fontScale,
        imageQuality: imageQuality,
        appName: settings.appName,
        showLogo: true,
        logoType: settings.customLogoBytes != null ? 'custom' : null,
        customLogoBytes: settings.customLogoBytes,
        showMiniMap: settings.showMiniMap,
        mapBytes: mapBytes,
        mapSize: 'medium',
        mapZoomLevel: settings.mapZoomLevel,
        fontSize: settings.fontSize,
        dateFormat: settings.dateFormat,
        timeFormat: settings.timeFormat,
      );

      final jpegBytes = await WatermarkEngine.process(params);
      final appDir = await getApplicationDocumentsDirectory();
      final histDir = Directory('${appDir.path}/history');
      await histDir.create(recursive: true);
      final outPath = '${histDir.path}/termullog_${captureTime.millisecondsSinceEpoch}.jpg';
      await File(outPath).writeAsBytes(jpegBytes);

      final saved = await GallerySaver.saveImage(outPath, albumName: 'TermulLog');

      // FIX: hapus temp file kamera setelah semua proses selesai sukses
      await File(xFile.path).delete();

      return CaptureResult(
        success: true,
        savedToGallery: saved == true,
        savedPath: outPath,
      );
    } catch (e) {
      // FIX: pastikan temp file kamera tetap dihapus meski proses gagal
      if (xFile != null) {
        try { await File(xFile.path).delete(); } catch (_) {}
      }
      return CaptureResult(
        success: false,
        errorMessage: e.toString().split('\n').first,
      );
    }
  }
}
