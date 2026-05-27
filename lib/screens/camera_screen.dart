// lib/screens/camera_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

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

  // GPS Filtering: riwayat posisi untuk moving average & outlier detection
  final List<Position> _positionHistory = [];
  static const int _maxHistorySize = 5;
  static const double _outlierThresholdMeters = 50.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettingsAndPosition();
  }

  Future<void> _loadSettingsAndPosition() async {
    await SettingsCache.preload();

    _showWeather = await SettingsCache.showWeather;
    _showAccuracy = await SettingsCache.showAccuracy;
    _showAddress = await SettingsCache.showAddress;
    _showCoordinates = await SettingsCache.showCoordinates;
    _opacity = await SettingsCache.opacity;
    _showBorder = await SettingsCache.showBorder;
    final fontSizeDouble = await SettingsCache.fontSize;
    _fontSize = fontSizeDouble <= 13 ? 'small' : fontSizeDouble >= 20 ? 'large' : 'normal';
    _currentLayout = await SettingsCache.layout;

    _watermarkPosition = await _loadWatermarkPosition();
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
    await _checkAndRequestHighAccuracyMode(); // Poin 2
    _initLocation();
    _startClock();
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
      setState(() => _isCameraReady = true);
      debugPrint('CAMERA READY');
    } catch (e) {
      debugPrint('INIT CAMERA ERROR: $e');
    }
  }

  // ==================== GPS ACCURACY IMPROVEMENTS ====================
  // Poin 2: Minta pengguna mengaktifkan mode akurasi tinggi
  Future<void> _checkAndRequestHighAccuracyMode() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      if (sdkInt >= 29) { // Android 10+
        final isLocationEnabled = await Geolocator.isLocationServiceEnabled();
        if (isLocationEnabled) {
          // Coba buka pengaturan lokasi untuk memastikan mode high accuracy
          // Tidak semua versi support, jadi kita hanya beri notifikasi
          final status = await Permission.location.request();
          if (!status.isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Izin lokasi diperlukan untuk akurasi GPS yang tinggi')),
              );
            }
          }
        }
      }
    }
  }

  // Poin 5: Filter GPS data (outlier detection & moving average)
  Position? _filterPosition(Position newPos) {
    // Outlier detection: jika tidak ada history, terima saja
    if (_positionHistory.isEmpty) {
      _positionHistory.add(newPos);
      return newPos;
    }

    final lastPos = _positionHistory.last;
    final distance = _calculateDistance(
      lastPos.latitude, lastPos.longitude,
      newPos.latitude, newPos.longitude,
    );

    // Jika loncat lebih dari threshold, anggap outlier dan abaikan
    if (distance > _outlierThresholdMeters) {
      debugPrint('GPS outlier detected: ${distance.toStringAsFixed(1)}m, ignored');
      return null;
    }

    // Moving average: simpan dan hitung rata-rata dari history
    _positionHistory.add(newPos);
    if (_positionHistory.length > _maxHistorySize) {
      _positionHistory.removeAt(0);
    }

    // Hitung rata-rata koordinat (moving average)
    double avgLat = 0.0, avgLon = 0.0, avgAcc = 0.0;
    for (final p in _positionHistory) {
      avgLat += p.latitude;
      avgLon += p.longitude;
      avgAcc += p.accuracy;
    }
    avgLat /= _positionHistory.length;
    avgLon /= _positionHistory.length;
    avgAcc /= _positionHistory.length;

    // Buat posisi baru dengan hasil filter
    final filteredPos = Position(
      latitude: avgLat,
      longitude: avgLon,
      accuracy: avgAcc,
      altitude: newPos.altitude,
      heading: newPos.heading,
      speed: newPos.speed,
      speedAccuracy: newPos.speedAccuracy,
      timestamp: newPos.timestamp,
      altitudeAccuracy: newPos.altitudeAccuracy,
      headingAccuracy: newPos.headingAccuracy,
    );
    return filteredPos;
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000; // meter
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
            sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  // ==================== LOCATION ====================
  Future<void> _initLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() {
          _address = 'GPS tidak aktif';
          _isLoadingLocation = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) setState(() {
          _address = 'Izin lokasi ditolak';
          _isLoadingLocation = false;
        });
        return;
      }

      // Poin 1: desiredAccuracy terbaik
      Position? firstPos;
      try {
        firstPos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation, // <-- Poin 1
          timeLimit: const Duration(seconds: 10),
        );
      } catch (e) {
        debugPrint('FIRST POSITION TIMEOUT: $e');
        firstPos = await Geolocator.getLastKnownPosition();
      }
      if (firstPos != null) {
        final filtered = _filterPosition(firstPos);
        if (filtered != null) await _updateLocationData(filtered);
      }
      if (mounted) setState(() => _isLoadingLocation = false);

      // Poin 3: force Android Location Manager sebagai fallback (jika FusedLocationProvider gagal)
      // Geolocator tidak mendukung force secara langsung, kita atur dengan mengubah settings
      // Namun kita bisa menggunakan parameter forceAndroidLocationManager di AndroidManifest? Tidak.
      // Alternatif: gunakan plugin lain? Atau kita hanya optimasi settings.
      // Yang bisa kita lakukan: setting intervalDuration yang wajar
      final locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5, // update setiap 5 meter
        intervalDuration: const Duration(seconds: 5), // <-- Poin 4: batasi interval
      );

      _positionSub = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen((pos) async {
        final filtered = _filterPosition(pos);
        if (filtered != null) await _updateLocationData(filtered);
      });
    } catch (e) {
      debugPrint('LOCATION ERROR: $e');
      if (mounted) setState(() {
        _address = 'Gagal memuat lokasi';
        _isLoadingLocation = false;
      });
    }
  }

  Future<void> _updateLocationData(Position pos) async {
    if (!mounted) return;
    setState(() => _currentPosition = pos);
    try {
      final result = await LocationWeatherService.fetchFromPosition(pos)
          .timeout(const Duration(seconds: 12));
      if (mounted) setState(() {
        _address = result.address;
        _weather = result.weather;
      });
    } catch (e) {
      debugPrint('ADDRESS/WEATHER ERROR: $e');
      setState(() => _address = '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}');
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

    if (_isLoadingLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tunggu hingga GPS mendapatkan lokasi...')),
      );
      return;
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      debugPrint('CAMERA NOT READY');
      return;
    }

    setState(() => _isCapturing = true);

    try {
      final XFile rawFile = await controller.takePicture().timeout(const Duration(seconds: 20));
      final rawBytes = await File(rawFile.path).readAsBytes();

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
        fontScale: _watermarkPosition.fontScale,
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
                onTap: _isLoadingLocation ? null : _takePhoto,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _isLoadingLocation ? Colors.grey : Colors.white,
                      width: 5,
                    ),
                    color: _isLoadingLocation ? Colors.grey.withOpacity(0.3) : Colors.white24,
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
