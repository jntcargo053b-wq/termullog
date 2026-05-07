import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../core/camera_registry.dart';
import '../services/watermark_layout_service.dart';
import 'preview_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isTakingPhoto = false;
  String _locationText = 'Mendapatkan lokasi...';
  Position? _position;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _getLocation();
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

  Future<void> _getLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => _locationText = 'Izin lokasi ditolak');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _position = pos;
        _locationText =
            '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
      });
    } catch (e) {
      setState(() => _locationText = 'Lokasi tidak tersedia');
    }
  }

  Future<void> _ambilFoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isTakingPhoto) return;

    setState(() => _isTakingPhoto = true);

    try {
      final XFile file = await _controller!.takePicture();
      final Uint8List bytes = await file.readAsBytes();

      // Decode gambar
      img.Image? original = img.decodeImage(bytes);
      if (original == null) throw Exception('Gagal decode gambar');

      // Siapkan teks watermark
      final now = DateTime.now();
      final tanggal = DateFormat('dd MMM yyyy').format(now);
      final jam = DateFormat('HH:mm:ss').format(now);
      final lokasi = _position != null
          ? 'Lat: ${_position!.latitude.toStringAsFixed(6)}\nLon: ${_position!.longitude.toStringAsFixed(6)}'
          : 'Lokasi tidak tersedia';

      // Gambar watermark teks
      final watermarked = _addWatermark(original, tanggal, jam, lokasi);

      // Simpan file
      final dir = await getTemporaryDirectory();
      final outputPath =
          '${dir.path}/termullog_${now.millisecondsSinceEpoch}.jpg';
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(img.encodeJpg(watermarked, quality: 90));

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

  img.Image _addWatermark(
      img.Image src, String tanggal, String jam, String lokasi) {
    // Background strip watermark
    final stripHeight = 120;
    final isBottom = WatermarkLayoutService.position != 'top';

    final color = img.ColorRgba8(0, 0, 0, 180);
    final white = img.ColorRgba8(255, 255, 255, 255);
    final yellow = img.ColorRgba8(255, 200, 0, 255);

    final y0 = isBottom ? src.height - stripHeight : 0;
    final y1 = isBottom ? src.height : stripHeight;

    // Gambar strip semi-transparan
    for (int y = y0; y < y1; y++) {
      for (int x = 0; x < src.width; x++) {
        final orig = src.getPixel(x, y);
        final blended = img.ColorRgba8(
          ((orig.r * 0.3) + (0 * 0.7)).toInt(),
          ((orig.g * 0.3) + (0 * 0.7)).toInt(),
          ((orig.b * 0.3) + (0 * 0.7)).toInt(),
          255,
        );
        src.setPixel(x, y, blended);
      }
    }

    final font = img.arial24;
    final textY = isBottom ? src.height - stripHeight + 10 : 10;

    img.drawString(src, '📦 TermulLog', font: font,
        x: 16, y: textY, color: yellow);
    img.drawString(src, '$tanggal  $jam', font: font,
        x: 16, y: textY + 30, color: white);
    img.drawString(src, lokasi, font: font,
        x: 16, y: textY + 60, color: white);

    return src;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Preview kamera
          if (_isInitialized && _controller != null)
            SizedBox.expand(
              child: CameraPreview(_controller!),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),

          // Info lokasi atas
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.greenAccent, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _locationText,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
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
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // Tombol kembali
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 28),
                  ),

                  // Tombol shutter
                  GestureDetector(
                    onTap: _isTakingPhoto ? null : _ambilFoto,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        color: _isTakingPhoto
                            ? Colors.grey
                            : Colors.white.withOpacity(0.15),
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

                  // Placeholder kanan (simetri)
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
