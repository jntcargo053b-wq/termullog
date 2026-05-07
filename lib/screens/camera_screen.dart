import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../core/camera_registry.dart';
import '../services/watermark_layout_service.dart';
import 'preview_screen.dart';

class CameraScreen extends StatefulWidget {
  final Position lockedPosition; // ← GPS sudah dikunci dari screen sebelumnya

  const CameraScreen({super.key, required this.lockedPosition});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isTakingPhoto = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    if (CameraRegistry.cameras.isEmpty) return;
    _controller = CameraController(
      CameraRegistry.cameras[0],
      ResolutionPreset.high,
      enableAudio: false,
    );
    try {
      await _controller!.initialize();
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _ambilFoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isTakingPhoto) return;

    setState(() => _isTakingPhoto = true);

    try {
      final XFile file = await _controller!.takePicture();
      final Uint8List bytes = await file.readAsBytes();

      img.Image? original = img.decodeImage(bytes);
      if (original == null) throw Exception('Gagal decode gambar');

      final now = DateTime.now();
      final watermarked = _addWatermark(original, now);

      final dir = await getTemporaryDirectory();
      final outputPath =
          '${dir.path}/termullog_${now.millisecondsSinceEpoch}.jpg';
      await File(outputPath)
          .writeAsBytes(img.encodeJpg(watermarked, quality: 90));

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreviewScreen(imagePath: outputPath),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengambil foto: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isTakingPhoto = false);
    }
  }

  img.Image _addWatermark(img.Image src, DateTime now) {
    final pos = widget.lockedPosition; // gunakan posisi yang sudah dikunci
    final tanggal = DateFormat('dd MMM yyyy').format(now);
    final jam = DateFormat('HH:mm:ss').format(now);
    final lat = pos.latitude.toStringAsFixed(6);
    final lon = pos.longitude.toStringAsFixed(6);
    final acc = pos.accuracy.toStringAsFixed(1);

    final isBottom = WatermarkLayoutService.position != 'top';
    const stripHeight = 140;
    final y0 = isBottom ? src.height - stripHeight : 0;
    final y1 = isBottom ? src.height : stripHeight;

    for (int y = y0; y < y1; y++) {
      for (int x = 0; x < src.width; x++) {
        final orig = src.getPixel(x, y);
        src.setPixel(x, y,
          img.ColorRgba8(
            (orig.r * 0.3).toInt(),
            (orig.g * 0.3).toInt(),
            (orig.b * 0.3).toInt(),
            255,
          ),
        );
      }
    }

    final font = img.arial24;
    final white = img.ColorRgba8(255, 255, 255, 255);
    final yellow = img.ColorRgba8(255, 200, 0, 255);
    final green = img.ColorRgba8(100, 220, 100, 255);
    final textY = isBottom ? src.height - stripHeight + 8 : 8;

    img.drawString(src, '📦 TermulLog',
        font: font, x: 16, y: textY, color: yellow);
    img.drawString(src, '$tanggal   $jam',
        font: font, x: 16, y: textY + 32, color: white);
    img.drawString(src, 'GPS: $lat, $lon',
        font: font, x: 16, y: textY + 64, color: white);
    img.drawString(src, 'Accuracy: ±${acc}m',
        font: font, x: 16, y: textY + 96, color: green);

    return src;
  }

  @override
  Widget build(BuildContext context) {
    final pos = widget.lockedPosition;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [

          // Kamera preview
          if (_isInitialized && _controller != null)
            SizedBox.expand(child: CameraPreview(_controller!))
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),

          // Info GPS terkunci (atas)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.fromLTRB(16, 52, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.gps_fixed,
                      color: Colors.greenAccent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${pos.latitude.toStringAsFixed(6)}, '
                      '${pos.longitude.toStringAsFixed(6)}  '
                      '±${pos.accuracy.toStringAsFixed(1)}m',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('🟢 Locked',
                        style: TextStyle(
                            color: Colors.greenAccent, fontSize: 11)),
                  ),
                ],
              ),
            ),
          ),

          // Tombol bawah
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black87,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 28),
                  ),
                  GestureDetector(
                    onTap: _isTakingPhoto ? null : _ambilFoto,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        color: Colors.white.withOpacity(0.15),
                      ),
                      child: _isTakingPhoto
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 3),
                            )
                          : const Icon(Icons.camera_alt,
                              color: Colors.white, size: 32),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
