import 'dart:async';
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
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {

  // ── KAMERA ──────────────────────────────────────────────────────────────
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isTakingPhoto = false;

  // ── GPS ─────────────────────────────────────────────────────────────────
  StreamSubscription<Position>? _gpsStream;
  Position? _currentPosition;
  bool _gpsReady = false;
  String _gpsText = '🔍 Searching GPS...';

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initCamera();
    _startGpsTracking();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _gpsStream?.cancel();
    super.dispose();
  }

  // ── INIT KAMERA ──────────────────────────────────────────────────────────

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

  // ── GPS TRACKING ─────────────────────────────────────────────────────────

  Future<void> _startGpsTracking() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _gpsText = '❌ GPS Disabled');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() => _gpsText = '❌ GPS Permission Denied');
      return;
    }

    _gpsStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    ).listen((Position pos) {
      // Simpan posisi dengan akurasi terbaik
      if (_currentPosition == null ||
          pos.accuracy < _currentPosition!.accuracy) {
        _currentPosition = pos;
      }

      final acc = _currentPosition!.accuracy;

      setState(() {
        if (acc <= 10) {
          _gpsReady = true;
          _gpsText = '🟢 GPS Locked ±${acc.toStringAsFixed(1)}m';
        } else {
          _gpsReady = false;
          _gpsText = '🟡 Searching GPS... ±${acc.toStringAsFixed(1)}m';
        }
      });
    });
  }

  // ── AMBIL FOTO ───────────────────────────────────────────────────────────

  Future<void> _ambilFoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isTakingPhoto) return;
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tunggu GPS siap terlebih dahulu')),
      );
      return;
    }

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

  // ── WATERMARK ────────────────────────────────────────────────────────────

  img.Image _addWatermark(img.Image src, DateTime now) {
    final pos = _currentPosition!;
    final tanggal = DateFormat('dd MMM yyyy').format(now);
    final jam = DateFormat('HH:mm:ss').format(now);
    final lat = pos.latitude.toStringAsFixed(6);
    final lon = pos.longitude.toStringAsFixed(6);
    final acc = pos.accuracy.toStringAsFixed(1);

    final isBottom = WatermarkLayoutService.position != 'top';
    const stripHeight = 130;
    final y0 = isBottom ? src.height - stripHeight : 0;
    final y1 = isBottom ? src.height : stripHeight;

    // Strip semi-transparan
    for (int y = y0; y < y1; y++) {
      for (int x = 0; x < src.width; x++) {
        final orig = src.getPixel(x, y);
        src.setPixel(
          x, y,
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

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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

          // GPS status bar (atas)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.fromLTRB(16, 52, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _gpsText,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                    ),
                  ),
                  if (_currentPosition != null)
                    Text(
                      '${_currentPosition!.latitude.toStringAsFixed(5)}, '
                      '${_currentPosition!.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 11),
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
                  // Tombol kembali
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 28),
                  ),

                  // Shutter — aktif hanya jika GPS siap
                  GestureDetector(
                    onTap: (_gpsReady && !_isTakingPhoto)
                        ? _ambilFoto
                        : null,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _gpsReady
                              ? Colors.white
                              : Colors.white38,
                          width: 4,
                        ),
                        color: _gpsReady
                            ? Colors.white.withOpacity(0.15)
                            : Colors.white.withOpacity(0.05),
                      ),
                      child: _isTakingPhoto
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 3),
                            )
                          : Icon(
                              Icons.camera_alt,
                              color: _gpsReady
                                  ? Colors.white
                                  : Colors.white38,
                              size: 32,
                            ),
                    ),
                  ),

                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),

          // Label "Waiting GPS" di tengah jika belum siap
          if (!_gpsReady)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Menunggu GPS stabil...',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
