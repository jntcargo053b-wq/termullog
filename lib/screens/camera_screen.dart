import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/location_weather_service.dart';
import '../services/settings_cache.dart';
import '../watermark/watermark_engine.dart';
import '../widgets/watermark_preview_overlay.dart';

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
  String _address = 'Mencari alamat...';
  String _weather = '';

  StreamSubscription<Position>? _positionSub;
  Timer? _clockTimer;
  DateTime _currentTimestamp = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
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

      // dispose controller lama untuk menghindari double instance
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
      // Cek layanan GPS
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          setState(() {
            _address = 'GPS tidak aktif';
            _isLoadingLocation = false;
          });
        }
        return;
      }

      // Cek izin
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _address = 'Izin lokasi ditolak';
            _isLoadingLocation = false;
          });
        }
        return;
      }

      // Ambil lokasi awal dengan timeout fallback
      Position? firstPos;
      try {
        firstPos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (e) {
        debugPrint('FIRST POSITION TIMEOUT: $e');
        // fallback ke last known position
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

      // Stream realtime dengan akurasi high (lebih ringan)
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
      _address = '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
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

      await SettingsCache.preload();

      final layout = await SettingsCache.layout;
      final showWeather = await SettingsCache.showWeather;
      final showAccuracy = await SettingsCache.showAccuracy;
      final showAddress = await SettingsCache.showAddress;
      final showCoordinates = await SettingsCache.showCoordinates;
      final opacity = await SettingsCache.opacity;
      final showBorder = await SettingsCache.showBorder;
      final fontSizeDouble = await SettingsCache.fontSize;
      final showMiniMap = await SettingsCache.showMiniMap;
      final mapSize = await SettingsCache.mapSize;
      final mapZoomLevel = await SettingsCache.mapZoomLevel;

      final fontSize = fontSizeDouble <= 13 ? 'small' : fontSizeDouble >= 20 ? 'large' : 'normal';

      final params = WatermarkEngine.createParams(
        imageBytes: imageBytes,
        timestamp: _currentTimestamp,
        layoutIndex: layout.index,
        address: _address,
        weather: _weather,
        showWeather: showWeather,
        showAccuracy: showAccuracy,
        showAddress: showAddress,
        showCoordinates: showCoordinates,
        opacity: opacity,
        showBorder: showBorder,
        fontSize: fontSize,
        showMiniMap: showMiniMap,
        lat: _currentPosition?.latitude,
        lon: _currentPosition?.longitude,
        acc: _currentPosition?.accuracy,
        mapSize: mapSize,
        mapZoomLevel: mapZoomLevel,
      );

      if (mounted) {
        // Gunakan pushNamed, BUKAN pushReplacementNamed
        await Navigator.pushNamed(
          context,
          '/preview',
          arguments: params.toMap(),
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

  // ==================== BUILD ====================
  @override
  Widget build(BuildContext context) {
    // Safety check sebelum menampilkan preview
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
          // Camera preview dengan safety
          CameraPreview(_controller!),

          // Live watermark preview (hanya jika ada posisi)
          if (_currentPosition != null)
            WatermarkPreviewOverlay(
              previewSize: MediaQuery.of(context).size,
              timestamp: _currentTimestamp,
              hasPosition: true,
              lat: _currentPosition?.latitude,
              lon: _currentPosition?.longitude,
              acc: _currentPosition?.accuracy,
              address: _address,
              weather: _weather,
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
