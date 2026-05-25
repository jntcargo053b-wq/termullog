// lib/screens/camera_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/watermark_position.dart';
import '../services/location_weather_service.dart';
import '../services/settings_cache.dart';
import '../watermark/watermark_engine.dart';
import '../widgets/draggable_watermark_overlay.dart';
import '../widgets/professional_watermark_painter.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isCameraReady = false;
  bool _isCapturing = false;
  bool _isLoadingLocation = true;

  Position? _currentPosition;
  String _address = 'Mencari lokasi...';
  String _weather = '';

  StreamSubscription<Position>? _positionSub;
  Timer? _clockTimer;
  DateTime _currentTimestamp = DateTime.now();

  // Settings watermark (akan dimuat dari cache)
  bool _showWeather = true;
  bool _showAccuracy = true;
  bool _showAddress = true;
  bool _showCoordinates = true;
  double _opacity = 0.82;
  bool _showBorder = true;
  String _fontSize = 'normal';

  // Posisi watermark custom
  late WatermarkPosition _watermarkPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettingsAndPosition();
  }

  Future<void> _loadSettingsAndPosition() async {
    await SettingsCache.preload();

    final layout = await SettingsCache.layout; // tidak dipakai, tapi tetap loading
    _showWeather = await SettingsCache.showWeather;
    _showAccuracy = await SettingsCache.showAccuracy;
    _showAddress = await SettingsCache.showAddress;
    _showCoordinates = await SettingsCache.showCoordinates;
    _opacity = await SettingsCache.opacity;
    _showBorder = await SettingsCache.showBorder;
    final fontSizeDouble = await SettingsCache.fontSize;
    _fontSize = fontSizeDouble <= 13
        ? 'small'
        : fontSizeDouble >= 20
            ? 'large'
            : 'normal';

    // Load posisi tersimpan
    _watermarkPosition = await _loadWatermarkPosition();

    // Mulai inisialisasi kamera & GPS setelah loading selesai
    _initialize();
  }

  Future<WatermarkPosition> _loadWatermarkPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString('watermark_position');
    if (jsonStr == null) return WatermarkPosition.initial;
    try {
      final Map<String, dynamic> json = Map<String, dynamic>.from(
        await Future.value(jsonDecode(jsonStr)),
      );
      return WatermarkPosition.fromJson(json);
    } catch (e) {
      return WatermarkPosition.initial;
    }
  }

  Future<void> _saveWatermarkPosition(WatermarkPosition pos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('watermark_position', jsonEncode(pos.toJson()));
  }

  Future<void> _initialize() async {
    await _initCamera();
    _initLocation(); // non-blocking
    _startClock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _positionSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      await controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      await _initCamera();
    }
  }

  // ==================== CAMERA ====================
  Future<void> _initCamera() async {
    try {
      if (widget.cameras.isEmpty) return;

      await _controller?.dispose();

      final controller = CameraController(
        widget.cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      _controller = controller;

      await controller.initialize().timeout(const Duration(seconds: 20));
      await controller.lockCaptureOrientation();

      if (!mounted) return;

      setState(() {
        _isCameraReady = true;
      });

      debugPrint('CAMERA READY');
    } catch (e, s) {
      debugPrint('INIT CAMERA ERROR: $e');
      debugPrint(s.toString());
    }
  }

  // ==================== LOCATION ====================
  Future<void> _initLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          setState(() {
            _address = 'GPS tidak aktif';
            _isLoadingLocation = false;
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _address = 'Izin lokasi ditolak';
            _isLoadingLocation = false;
          });
        }
        return;
      }

      Position? firstPos;
      try {
        firstPos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (e) {
        debugPrint('FIRST POSITION TIMEOUT: $e');
        firstPos = await Geolocator.getLastKnownPosition();
      }

      if (firstPos != null) {
        await _updateLocationData(firstPos);
      }

      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }

      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((pos) async {
        await _updateLocationData(pos);
      });
    } catch (e) {
      debugPrint('LOCATION ERROR: $e');
      if (mounted) {
        setState(() {
          _address = 'Gagal memuat lokasi';
          _isLoadingLocation = false;
        });
      }
    }
  }

  Future<void> _updateLocationData(Position pos) async {
    if (!mounted) return;

    setState(() {
      _currentPosition = pos;
    });

    try {
      final result = await LocationWeatherService.fetchFromPosition(pos)
          .timeout(const Duration(seconds: 12));
      if (mounted) {
        setState(() {
          _address = result.address;
          _weather = result.weather;
        });
      }
    } catch (e) {
      debugPrint('ADDRESS/WEATHER ERROR: $e');
      setState(() {
        _address = '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
      });
    }
  }

  // ==================== CLOCK ====================
  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _currentTimestamp = DateTime.now());
    });
  }

  // ==================== CAPTURE ====================
  Future<void> _takePhoto() async {
    if (_isCapturing) return;

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      debugPrint('CAMERA NOT READY');
      return;
    }

    setState(() => _isCapturing = true);

    try {
      final XFile file = await controller.takePicture().timeout(const Duration(seconds: 20));
      final imageBytes = await File(file.path).readAsBytes();
      final imageWidth = await _getImageWidth(imageBytes);

      // Render watermark dengan painter yang SAMA persis dengan preview
      final ui.Image watermarkedImage = await _applyWatermark(
        imageBytes: imageBytes,
        imageWidth: imageWidth,
      );

      // Simpan atau lanjutkan ke preview screen
      if (mounted) {
        // Kirim data ke halaman preview (atau simpan langsung)
        await Navigator.pushNamed(
          context,
          '/preview',
          arguments: {
            'imageBytes': await watermarkedImage.toByteData(format: ui.ImageByteFormat.png)?.buffer.asUint8List(),
            // tambahkan argumen lain jika perlu
          },
        );
      }
    } catch (e) {
      debugPrint('CAPTURE ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengambil foto: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  /// Dapatkan lebar gambar asli (untuk skala painter)
  Future<int> _getImageWidth(Uint8List imageBytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(imageBytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image.width;
  }

  /// Render watermark ke dalam gambar menggunakan painter yang sama
  Future<ui.Image> _applyWatermark({
    required Uint8List imageBytes,
    required int imageWidth,
  }) async {
    final ui.Image originalImage = await decodeImageFromList(imageBytes);
    final int width = originalImage.width;
    final int height = originalImage.height;

    // Ukuran card di hasil foto harus proporsional dengan lebar gambar
    // Lebar card di preview = 320 (virtual). Di hasil foto, kita ingin card memiliki lebar relatif sama
    // Misal lebar card hasil = width * (320 / layar_lebar) -> tapi kita bebas menentukan.
    // Cara sederhana: lebar card = 320 * (width / 1080) misal. Tapi lebih baik ukuran tetap 320?
    // Kita akan set cardWidth = 320 * (width / 1080) untuk proporsi. Atau tetap 320? Lebih baik proporsional.
    const double baseWidthReference = 1080.0;
    double cardWidth = 320.0 * (width / baseWidthReference);
    cardWidth = cardWidth.clamp(200.0, 500.0);

    // Hitung tinggi painter sesuai konten
    final dummyPainter = ProfessionalWatermarkPainter(
      timestamp: _currentTimestamp,
      hasPosition: _currentPosition != null,
      lat: _currentPosition?.latitude,
      lon: _currentPosition?.longitude,
      acc: _currentPosition?.accuracy,
      address: _address,
      weather: _weather,
      showWeather: _showWeather,
      showAccuracy: _showAccuracy,
      showAddress: _showAddress,
      showCoordinates: _showCoordinates,
      opacity: _opacity,
      showBorder: _showBorder,
      fontSize: _fontSize,
    );
    final double cardHeight = dummyPainter.computeHeightSync(Size(cardWidth, 0));

    // Posisi absolut pada gambar (berdasarkan persen)
    double left = width * _watermarkPosition.x;
    double top = height * _watermarkPosition.y;
    // Batasi agar card tidak keluar frame
    left = left.clamp(0.0, width - cardWidth);
    top = top.clamp(0.0, height - cardHeight);

    // Buat recorder dan canvas
    final recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    // Gambar original foto
    canvas.drawImage(originalImage, Offset.zero, Paint());
    // Simpan state, translasi ke posisi watermark, lalu gambar kartu
    canvas.save();
    canvas.translate(left, top);
    // Skala card (jika ada scaling dari user, sudah termasuk dalam _watermarkPosition.scale)
    canvas.scale(_watermarkPosition.scale);
    // Gambar background card (gradient, shadow, border) -> kita gambar manual atau pakai widget? Lebih mudah gambar manual.
    _drawWatermarkCard(canvas, Size(cardWidth, cardHeight), dummyPainter);
    canvas.restore();

    final picture = recorder.endRecording();
    final ui.Image outputImage = await picture.toImage(width, height);
    return outputImage;
  }

  /// Gambar background card dan painter di atasnya
  void _drawWatermarkCard(Canvas canvas, Size cardSize, ProfessionalWatermarkPainter painter) {
    final RRect rect = RRect.fromRectAndRadius(
      Offset.zero & cardSize,
      const Radius.circular(24),
    );
    // Gradient background
    final Paint bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xCC000000), Color(0xBF000000)],
      ).createShader(Offset.zero & cardSize);
    canvas.drawRRect(rect, bgPaint);
    // Border
    if (_showBorder) {
      final Paint borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withOpacity(0.15);
      canvas.drawRRect(rect, borderPaint);
    }
    // Shadow (manual)
    canvas.drawShadow(Path()..addRRect(rect), Colors.black, 18, true);
    // Gambar painter watermark
    painter.paint(canvas, cardSize);
  }

  // ==================== BUILD ====================
  @override
  Widget build(BuildContext context) {
    final isPreviewReady = _controller != null && _controller!.value.isInitialized;

    if (!_isCameraReady || !isPreviewReady) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),

          // Watermark overlay (draggable & scalable) hanya jika GPS sudah siap (atau bisa tampil walau belum)
          if (_currentPosition != null)
            DraggableWatermarkOverlay(
              previewSize: MediaQuery.of(context).size,
              timestamp: _currentTimestamp,
              hasPosition: true,
              lat: _currentPosition?.latitude,
              lon: _currentPosition?.longitude,
              acc: _currentPosition?.accuracy,
              address: _address,
              weather: _weather,
              showWeather: _showWeather,
              showAccuracy: _showAccuracy,
              showAddress: _showAddress,
              showCoordinates: _showCoordinates,
              opacity: _opacity,
              showBorder: _showBorder,
              fontSize: _fontSize,
              initialPosition: _watermarkPosition,
              onPositionChanged: (pos) {
                _watermarkPosition = pos;
                _saveWatermarkPosition(pos);
              },
            ),

          // Indikator loading GPS
          if (_isLoadingLocation)
            const Positioned(
              top: 50,
              left: 0,
              right: 0,
              child: Center(
                child: Chip(
                  backgroundColor: Colors.black87,
                  label: Text('Mengambil GPS...', style: TextStyle(color: Colors.white)),
                ),
              ),
            ),

          // Tombol capture
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _takePhoto,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 5),
                    color: Colors.white24,
                  ),
                  child: _isCapturing
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Helper untuk decode image dari bytes (jika belum ada di Flutter)
Future<ui.Image> decodeImageFromList(Uint8List bytes) async {
  final Completer<ui.Image> completer = Completer();
  ui.decodeImageFromList(bytes, (ui.Image image) {
    completer.complete(image);
  });
  return completer.future;
}
