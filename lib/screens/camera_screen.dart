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
  Position? _bestPosition;
  bool _gpsReady = false;
  String _gpsText = '🔍 Searching GPS...';

  // ── GPS POLISH STATE ─────────────────────────────────────────────────────
  bool _isPolishing = false;        // sedang proses watermark GPS
  int _polishCountdown = 30;        // countdown timeout
  Timer? _countdownTimer;
  Completer<Position?>? _gpsCompleter;

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
    _countdownTimer?.cancel();
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
      setState(() => _gpsText = '❌ GPS tidak aktif');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() => _gpsText = '❌ Izin GPS ditolak');
      return;
    }

    _gpsStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    ).listen((Position pos) {
      // Selalu simpan posisi terbaik
      if (_bestPosition == null || pos.accuracy < _bestPosition!.accuracy) {
        _bestPosition = pos;
      }

      final acc = _bestPosition!.accuracy;

      setState(() {
        if (acc <= 10) {
          _gpsReady = true;
          _gpsText = '🟢 GPS Locked ±${acc.toStringAsFixed(1)}m';
        } else if (acc <= 30) {
          _gpsReady = false;
          _gpsText = '🟡 GPS ±${acc.toStringAsFixed(1)}m';
        } else {
          _gpsReady = false;
          _gpsText = '🔴 Sinyal lemah ±${acc.toStringAsFixed(1)}m';
        }
      });

      // Jika sedang menunggu GPS polish, resolve jika sudah cukup akurat
      if (_gpsCompleter != null &&
          !_gpsCompleter!.isCompleted &&
          acc <= 10) {
        _gpsCompleter!.complete(_bestPosition);
      }
    });
  }

  // ── AMBIL FOTO ───────────────────────────────────────────────────────────

  Future<void> _ambilFoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isTakingPhoto || _isPolishing) return;

    setState(() => _isTakingPhoto = true);

    try {
      // 1. Foto langsung — tidak tunggu GPS
      final XFile file = await _controller!.takePicture();
      final Uint8List bytes = await file.readAsBytes();
      final DateTime waktuFoto = DateTime.now();

      img.Image? original = img.decodeImage(bytes);
      if (original == null) throw Exception('Gagal decode gambar');

      setState(() {
        _isTakingPhoto = false;
        _isPolishing = true;
        _polishCountdown = 30;
      });

      // 2. Tunggu GPS terbaik (max 30 detik)
      final Position? finalPosition = await _waitForBestGps();

      // Gunakan posisi terbaik yang ada, apapun akurasinya
      final Position gpsResult = finalPosition ?? _bestPosition!;

      // 3. Tulis watermark dengan GPS final
      final watermarked = _addWatermark(original, waktuFoto, gpsResult);

      final dir = await getTemporaryDirectory();
      final outputPath =
          '${dir.path}/termullog_${waktuFoto.millisecondsSinceEpoch}.jpg';
      await File(outputPath)
          .writeAsBytes(img.encodeJpg(watermarked, quality: 90));

      if (!mounted) return;

      setState(() => _isPolishing = false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreviewScreen(imagePath: outputPath),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTakingPhoto = false;
          _isPolishing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e')),
        );
      }
    } finally {
      _countdownTimer?.cancel();
      _gpsCompleter = null;
    }
  }

  // ── TUNGGU GPS TERBAIK (MAX 30 DETIK) ───────────────────────────────────

  Future<Position?> _waitForBestGps() async {
    // Jika GPS sudah locked sebelum foto, langsung pakai
    if (_gpsReady && _bestPosition != null) return _bestPosition;

    // Jika sama sekali belum ada sinyal GPS
    if (_bestPosition == null) {
      // Tunggu sinyal pertama max 30 detik
      _gpsCompleter = Completer<Position?>();
      _startCountdown();
      return _gpsCompleter!.future;
    }

    // GPS ada tapi belum akurat — tunggu sampai locked atau timeout
    _gpsCompleter = Completer<Position?>();
    _startCountdown();
    return _gpsCompleter!.future;
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _polishCountdown = 30;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _polishCountdown--);

      if (_polishCountdown <= 0) {
        t.cancel();
        // Timeout — pakai posisi terbaik yang ada (bisa null)
        if (_gpsCompleter != null && !_gpsCompleter!.isCompleted) {
          _gpsCompleter!.complete(_bestPosition);
        }
      }
    });
  }

  // ── WATERMARK ────────────────────────────────────────────────────────────

  img.Image _addWatermark(img.Image src, DateTime now, Position pos) {
    final tanggal = DateFormat('dd MMM yyyy').format(now);
    final jam = DateFormat('HH:mm:ss').format(now);
    final lat = pos.latitude.toStringAsFixed(6);
    final lon = pos.longitude.toStringAsFixed(6);
    final acc = pos.accuracy.toStringAsFixed(1);

    final isBottom = WatermarkLayoutService.position != 'top';
    const stripHeight = 140;
    final y0 = isBottom ? src.height - stripHeight : 0;
    final y1 = isBottom ? src.height : stripHeight;

    // Strip gelap semi-transparan
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
                child: CircularProgressIndicator(color: Colors.white)),

          // GPS status bar atas
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.fromLTRB(16, 52, 16, 12),
              child: Row(
                children: [
                  Icon(
                    _gpsReady ? Icons.gps_fixed : Icons.gps_not_fixed,
                    color: _gpsReady ? Colors.greenAccent : Colors.amber,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _bestPosition != null
                          ? '${_bestPosition!.latitude.toStringAsFixed(5)}, '
                            '${_bestPosition!.longitude.toStringAsFixed(5)}'
                          : _gpsText,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12),
                    ),
                  ),
                  Text(
                    _gpsText,
                    style: TextStyle(
                      color: _gpsReady ? Colors.greenAccent : Colors.amber,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Overlay GPS Polish ─────────────────────────────────────────
          if (_isPolishing)
            Container(
              color: Colors.black.withOpacity(0.75),
              child: Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1B2A),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Countdown ring
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 80,
                            height: 80,
                            child: CircularProgressIndicator(
                              value: _polishCountdown / 30,
                              strokeWidth: 6,
                              backgroundColor: Colors.white12,
                              color: _gpsReady
                                  ? Colors.greenAccent
                                  : Colors.amber,
                            ),
                          ),
                          Text(
                            '$_polishCountdown',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _gpsReady
                            ? '✅ GPS Terkunci!\nMenyimpan foto...'
                            : '📡 Menyempurnakan GPS...\n$_gpsText',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _gpsReady
                            ? 'Koordinat berhasil dikunci'
                            : 'Foto sudah diambil.\nMenunggu GPS presisi atau timeout $_polishCountdown detik',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Tombol bawah
          if (!_isPolishing)
            Positioned(
              bottom: 0, left: 0, right: 0,
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
                          border:
                              Border.all(color: Colors.white, width: 4),
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
