// lib/screens/camera_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:path_provider/path_provider.dart';

import '../models/watermark_position.dart';
import '../services/location_weather_service.dart';
import '../services/settings_cache.dart';
import '../watermark/watermark_engine.dart';
import '../core/constants.dart';
import '../widgets/draggable_watermark_overlay.dart';

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

  // Watermark settings
  bool _showWeather = true;
  bool _showAccuracy = true;
  bool _showAddress = true;
  bool _showCoordinates = true;
  double _opacity = 0.82;
  bool _showBorder = true;
  String _fontSize = 'normal';
  WatermarkLayout _currentLayout = WatermarkLayout.modern;

  // Watermark position (custom)
  WatermarkPosition _watermarkPosition = WatermarkPosition.initial;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettingsAndPosition();
  }

  Future<void> _loadSettingsAndPosition() async {
    await SettingsCache.preload();

    // Load all settings
    _showWeather = await SettingsCache.showWeather;
    _showAccuracy = await SettingsCache.showAccuracy;
    _showAddress = await SettingsCache.showAddress;
    _showCoordinates = await SettingsCache.showCoordinates;
    _opacity = await SettingsCache.opacity;
    _showBorder = await SettingsCache.showBorder;
    final fontSizeDouble = await SettingsCache.fontSize;
    _fontSize = fontSizeDouble <= 13 ? 'small' : fontSizeDouble >= 20 ? 'large' : 'normal';
    _currentLayout = await SettingsCache.layout;

    // Load saved position
    _watermarkPosition = await _loadWatermarkPosition();

    // Start initialization
    _initialize();
  }

  Future<WatermarkPosition> _loadWatermarkPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString('watermark_position');
    if (jsonStr == null) return WatermarkPosition.initial;
    try {
      final Map<String, dynamic> json = jsonDecode(jsonStr);
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
    } catch (e) {
      debugPrint('INIT CAMERA ERROR: $e');
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
      final XFile rawFile = await controller.takePicture().timeout(const Duration(seconds: 20));
      final rawBytes = await File(rawFile.path).readAsBytes();

      // Apply watermark using WatermarkEngine
      final finalBytes = await WatermarkEngine.process(
        imageBytes: rawBytes,
        timestamp: _currentTimestamp,
        layout: _currentLayout,
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
        showMiniMap: false,
        mapSize: 'medium',
        mapZoomLevel: 16,
        imageQuality: 90,
        dateFormat: 'dd MMM yyyy',
        timeFormat: 'HH:mm:ss',
      );

      final dir = await getTemporaryDirectory();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(finalBytes);

      await GallerySaver.saveImage(file.path, albumName: 'Timestamp Camera');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto berhasil disimpan ke Galeri')),
      );
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
              layout: _currentLayout,
              initialPosition: _watermarkPosition,
              onPositionChanged: (pos) {
                _watermarkPosition = pos;
                _saveWatermarkPosition(pos);
              },
            ),

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
