// lib/screens/camera_screen.dart
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_weather_service.dart';
import '../services/settings_cache.dart';
import '../widgets/watermark_preview_overlay.dart';
import '../watermark/watermark_params.dart';
import '../watermark/watermark_engine.dart';

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
  DateTime _currentTimestamp = DateTime.now();

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
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) return;
    _controller = CameraController(widget.cameras[0], ResolutionPreset.max);
    await _controller!.initialize();
    if (!mounted) return;
    setState(() => _isCameraReady = true);
  }

  void _startLocationUpdates() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _isLoadingLocation = false);
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
        setState(() => _isLoadingLocation = false);
        return;
      }
    }
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 5),
    ).listen((Position pos) async {
      if (!mounted) return;
      setState(() {
        _currentPosition = pos;
        _isLoadingLocation = false;
      });
      try {
        final result = await LocationWeatherService.fetchFromPosition(pos);
        if (mounted) {
          setState(() {
            _address = result.address;
            _weather = result.weather;
          });
        }
      } catch (e) {
        debugPrint('Weather/address error: $e');
      }
    });
  }

  void _startTimestampUpdates() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) setState(() => _currentTimestamp = DateTime.now());
      return mounted;
    });
  }

  Future<void> _takePhoto() async {
    if (_isCapturing || _controller == null || !_controller!.value.isInitialized) return;
    setState(() => _isCapturing = true);
    try {
      final XFile file = await _controller!.takePicture();
      final bytes = await File(file.path).readAsBytes();
      // Baca setting terbaru
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
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/preview', arguments: params.toMap());
    } catch (e) {
      debugPrint('Photo capture error: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal mengambil foto')));
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: const Text('Kamera', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () async {
              await Navigator.pushNamed(context, '/settings');
              // Reload settings jika perlu
              setState(() {});
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          CameraPreview(_controller!),
          // Watermark overlay (live preview)
          if (!_isLoadingLocation)
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
          if (_isLoadingLocation)
            const Center(
              child: Chip(
                label: Text('Mendapatkan lokasi...'),
                backgroundColor: Colors.black54,
              ),
            ),
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
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
            ),
          ),
        ],
      ),
    );
  }
}
