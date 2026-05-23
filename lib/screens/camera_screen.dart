// lib/screens/camera_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import '../services/location_weather_service.dart';
import '../services/settings_cache.dart';
import '../widgets/watermark_preview_overlay.dart';
import '../watermark/watermark_engine.dart';
import '../watermark/watermark_params.dart';

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

  // GPS & location
  Position? _currentPosition;
  String _address = '';
  String _weather = '';
  bool _isLoadingLocation = true;
  StreamSubscription<Position>? _positionStream;
  Timer? _weatherUpdateTimer;

  // Preview overlay updates
  DateTime _currentTimestamp = DateTime.now();
  Timer? _timestampTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _startLocationUpdates();
    _startTimestampUpdates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStream?.cancel();
    _weatherUpdateTimer?.cancel();
    _timestampTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startCamera();
    } else if (state == AppLifecycleState.paused) {
      _controller?.stopImageStream();
    }
  }

  // ==========================================================================
  // INIT CAMERA
  // ==========================================================================
  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) return;
    _controller = CameraController(
      widget.cameras[0],
      ResolutionPreset.max,
      enableAudio: false,
    );
    await _controller!.initialize();
    if (!mounted) return;
    setState(() {
      _isCameraReady = true;
    });
    _startCamera();
  }

  void _startCamera() {
    if (_controller != null && _controller!.value.isInitialized) {
      _controller!.startImageStream((CameraImage image) {});
    }
  }

  // ==========================================================================
  // LOCATION & WEATHER (real time)
  // ==========================================================================
  void _startLocationUpdates() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5, // update setiap 5 meter
      ),
    ).listen((Position pos) async {
      if (!mounted) return;
      setState(() {
        _currentPosition = pos;
        _isLoadingLocation = false;
      });
      await _updateAddressAndWeather(pos);
    });
  }

  Future<void> _updateAddressAndWeather(Position pos) async {
    try {
      final result = await LocationWeatherService.fetchFromPosition(pos);
      if (mounted) {
        setState(() {
          _address = result.address;
          _weather = result.weather;
        });
      }
    } catch (e) {
      debugPrint('Error fetching address/weather: $e');
    }
  }

  void _startTimestampUpdates() {
    _timestampTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTimestamp = DateTime.now();
        });
      }
    });
  }

  // ==========================================================================
  // CAPTURE PHOTO
  // ==========================================================================
  Future<void> _takePhoto() async {
    if (_isCapturing || _controller == null || !_controller!.value.isInitialized) return;
    setState(() => _isCapturing = true);

    try {
      final XFile xFile = await _controller!.takePicture();
      final File imageFile = File(xFile.path);

      // Baca semua pengaturan dari cache (fresh)
      await SettingsCache.preload();
      final layout = await SettingsCache.layout;
      final showWeather = await SettingsCache.showWeather;
      final showAccuracy = await SettingsCache.showAccuracy;
      final showAddress = await SettingsCache.showAddress;
      final showCoordinates = await SettingsCache.showCoordinates;
      final opacity = await SettingsCache.opacity;
      final showBorder = await SettingsCache.showBorder;
      final fontSizeDouble = await SettingsCache.fontSize;
      final fontSizeStr = fontSizeDouble <= 13 ? 'small' : fontSizeDouble >= 20 ? 'large' : 'normal';
      final showMiniMap = await SettingsCache.showMiniMap;
      final mapSize = await SettingsCache.mapSize;
      final mapZoomLevel = await SettingsCache.mapZoomLevel;

      // Siapkan parameter watermark
      final bytes = await imageFile.readAsBytes();
      final params = WatermarkEngine.createParams(
        imageBytes: bytes,
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
        fontSize: fontSizeStr,
        showMiniMap: showMiniMap,
        lat: _currentPosition?.latitude,
        lon: _currentPosition?.longitude,
        acc: _currentPosition?.accuracy,
        mapSize: mapSize,
        mapZoomLevel: mapZoomLevel,
        // Map bytes diambil di PreviewScreen nanti, bisa dilewatkan null dulu
      );

      // Navigasi ke PreviewScreen dengan parameter
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/preview',
        arguments: {
          'imageBytes': params.transferable.materialize().asUint8List(),
          'timestamp': _currentTimestamp,
          'latitude': _currentPosition?.latitude,
          'longitude': _currentPosition?.longitude,
          'accuracy': _currentPosition?.accuracy,
          'address': _address,
          'weather': _weather,
          'params': params.toMap(), // kirim juga params untuk processing
        },
      );
    } catch (e) {
      debugPrint('Error taking photo: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal mengambil foto')),
      );
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  // ==========================================================================
  // BUILD UI
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    if (!_isCameraReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview
          CameraPreview(_controller!),
          
          // Watermark overlay (live preview)
          if (_currentPosition != null || !_isLoadingLocation)
            WatermarkPreviewOverlay(
              previewSize: MediaQuery.of(context).size,
              timestamp: _currentTimestamp,
              hasPosition: _currentPosition != null,
              lat: _currentPosition?.latitude,
              lon: _currentPosition?.longitude,
              acc: _currentPosition?.accuracy,
              address: _address,
              weather: _weather,
            ),
          
          // Loading indicator saat GPS masih mencari
          if (_isLoadingLocation)
            const Positioned(
              top: 50,
              left: 0,
              right: 0,
              child: Center(
                child: Chip(
                  label: Text('Mendapatkan lokasi...'),
                  backgroundColor: Colors.black54,
                ),
              ),
            ),
          
          // Tombol ambil foto dan switch kamera
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Tombol switch kamera (opsional)
                IconButton(
                  icon: const Icon(Icons.switch_camera, color: Colors.white),
                  onPressed: _switchCamera,
                ),
                
                // Tombol capture
                GestureDetector(
                  onTap: _takePhoto,
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade800, width: 4),
                    ),
                    child: _isCapturing
                        ? const Center(child: CircularProgressIndicator())
                        : null,
                  ),
                ),
                
                // Spacer untuk simetri
                const SizedBox(width: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _switchCamera() async {
    if (_controller == null) return;
    final lensDirection = _controller!.description.lensDirection;
    final newCamera = widget.cameras.firstWhere(
      (cam) => cam.lensDirection != lensDirection,
      orElse: () => widget.cameras.first,
    );
    await _controller!.dispose();
    _controller = CameraController(newCamera, ResolutionPreset.max, enableAudio: false);
    await _controller!.initialize();
    if (mounted) {
      setState(() {});
      _startCamera();
    }
  }
}
