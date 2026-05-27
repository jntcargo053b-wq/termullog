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
import '../services/gps_lock_manager.dart';

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

  // GPS data
  final GpsLockManager _gpsLockManager = GpsLockManager();
  bool _isGpsLocked = false;
  int _gpsLockProgress = 0;
  Position? _currentPosition;   // live preview
  Position? _bestPosition;      // final capture after lock
  String _address = 'Mencari lokasi...';
  String _weather = '';

  // Address freshness tracking
  Position? _lastGeocodedPosition;
  bool _isAddressLoading = false;
  static const double _geocodeDistanceThreshold = 25.0;
  static const int _geocodeTimeThresholdSeconds = 8;

  StreamSubscription<Position>? _positionSub;
  Timer? _clockTimer;
  DateTime _currentTimestamp = DateTime.now();
  DateTime? _lastGeocodeTime;

  // Watermark settings
  bool _showWeather = true;
  bool _showAccuracy = true;
  bool _showAddress = true;
  bool _showCoordinates = true;
  double _opacity = 0.82;
  bool _showBorder = true;
  String _fontSize = 'normal';
  WatermarkLayout _currentLayout = WatermarkLayout.modern;

  // Watermark position
  WatermarkPosition _watermarkPosition = WatermarkPosition.initial;

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

    _watermarkPosition = await SettingsCache.loadWatermarkPosition();
    _initialize();
  }

  Future<void> _saveWatermarkPosition(WatermarkPosition pos) async {
    await SettingsCache.saveWatermarkPosition(pos);
  }

  Future<void> _initialize() async {
    await _initCamera();
    await _checkAndRequestHighAccuracyMode();
    _initLocation();
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
      final pos = _currentPosition ?? _bestPosition;
      if (pos != null) {
        await _fetchAddressAndWeather(pos, forceRefresh: true);
      }
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
      setState(() => _isCameraReady = true);
      debugPrint('CAMERA READY');
    } catch (e) {
      debugPrint('INIT CAMERA ERROR: $e');
    }
  }

  // ==================== HIGH ACCURACY MODE ====================
  Future<void> _checkAndRequestHighAccuracyMode() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      if (sdkInt >= 29) {
        final isLocationEnabled = await Geolocator.isLocationServiceEnabled();
        if (isLocationEnabled) {
          final status = await Permission.location.request();
          if (!status.isGranted && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Izin lokasi diperlukan untuk akurasi GPS yang tinggi')),
            );
          }
        }
      }
    }
  }

  // ==================== SMART GEOCODING ====================
  Future<void> _fetchAddressAndWeather(Position pos, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      if (_isAddressLoading) return;

      final now = DateTime.now();
      final timeSinceLast = _lastGeocodeTime != null
          ? now.difference(_lastGeocodeTime!).inSeconds
          : _geocodeTimeThresholdSeconds + 1;

      final distanceMoved = _lastGeocodedPosition != null
          ? Geolocator.distanceBetween(
              _lastGeocodedPosition!.latitude,
              _lastGeocodedPosition!.longitude,
              pos.latitude,
              pos.longitude,
            )
          : double.infinity;

      if (timeSinceLast < _geocodeTimeThresholdSeconds && distanceMoved < _geocodeDistanceThreshold) {
        debugPrint('📍 SKIP geocode: time=${timeSinceLast}s, moved=${distanceMoved.toStringAsFixed(1)}m');
        return;
      }
    }

    if (mounted) setState(() => _isAddressLoading = true);
    _lastGeocodeTime = DateTime.now();

    try {
      final result = await LocationWeatherService.fetchFromPosition(pos)
          .timeout(const Duration(seconds: 12));
      if (mounted) {
        setState(() {
          _address = result.address;
          _weather = result.weather;
          _lastGeocodedPosition = pos;
          _isAddressLoading = false;
        });
        debugPrint('📍 GEOCODE OK: ${_address.substring(0, _address.length.clamp(0, 50))}');
      }
    } catch (e) {
      debugPrint('📍 GEOCODE ERROR: $e');
      if (mounted) {
        setState(() {
          _address = '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
          _isAddressLoading = false;
        });
      }
    }
  }

  // ==================== GPS LOCATION STREAM ====================
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

      // Posisi pertama (cepat)
      Position? firstPos;
      try {
        firstPos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (e) {
        debugPrint('FIRST POSITION TIMEOUT: $e');
        firstPos = await Geolocator.getLastKnownPosition();
      }

      if (firstPos != null) {
        if (mounted) setState(() => _currentPosition = firstPos);
        _gpsLockManager.processSample(firstPos, null);
        await _fetchAddressAndWeather(firstPos, forceRefresh: true);
      }
      if (mounted) setState(() => _isLoadingLocation = false);

      // Konfigurasi stream GPS
      LocationSettings locationSettings;
      if (Platform.isAndroid) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
          intervalDuration: const Duration(seconds: 5),
          forceLocationManager: true,
        );
      } else if (Platform.isIOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
          pauseLocationUpdatesAutomatically: false,
          activityType: ActivityType.fitness,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
        );
      }

      Position? lastSample;
      _positionSub = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen((pos) async {
        if (mounted) setState(() => _currentPosition = pos);
        await _fetchAddressAndWeather(pos);

        final justLocked = _gpsLockManager.processSample(pos, lastSample);
        lastSample = pos;

        if (justLocked) {
          final lockData = _gpsLockManager.lockData;
          if (lockData != null) {
            if (mounted) setState(() {
              _bestPosition = lockData.position;
              _isGpsLocked = true;
            });
            await _fetchAddressAndWeather(lockData.position, forceRefresh: true);
            _gpsLockManager.updateLockAddress(_address, _weather);
          }
        } else {
          final progress = _gpsLockManager.stationaryProgress;
          if (_gpsLockManager.state != GpsLockState.locked) {
            if (mounted) setState(() {
              _gpsLockProgress = progress;
              _isGpsLocked = false;
              _isLoadingLocation = true;
            });
          } else {
            final lockData = _gpsLockManager.lockData;
            if (lockData != null && _bestPosition != lockData.position) {
              if (mounted) setState(() => _bestPosition = lockData.position);
            }
          }
        }

        if (_isGpsLocked && mounted) setState(() => _isLoadingLocation = false);
      });
    } catch (e) {
      debugPrint('LOCATION ERROR: $e');
      if (mounted) setState(() {
        _address = 'Gagal memuat lokasi';
        _isLoadingLocation = false;
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

    if (!_isGpsLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masih mengunci GPS, tunggu sebentar...')),
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

      final lockData = _gpsLockManager.lockData;
      if (lockData == null) throw Exception('GPS lock data hilang');

      final captureAddress = (_address.isNotEmpty && _address != 'Mencari lokasi...')
          ? _address
          : lockData.address;
      final captureWeather = _weather.isNotEmpty ? _weather : lockData.weather;

      final finalBytes = await WatermarkEngine.process(
        imageBytes: rawBytes,
        timestamp: _currentTimestamp,
        layout: _currentLayout,
        lat: lockData.position.latitude,
        lon: lockData.position.longitude,
        acc: lockData.position.accuracy,
        address: captureAddress,
        weather: captureWeather,
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

    final displayPosition = _currentPosition ?? _bestPosition;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),

          if (displayPosition != null)
            DraggableWatermarkOverlay(
              previewSize: MediaQuery.of(context).size,
              timestamp: _currentTimestamp,
              hasPosition: true,
              lat: displayPosition.latitude,
              lon: displayPosition.longitude,
              acc: displayPosition.accuracy,
              address: _isAddressLoading ? 'Memperbarui alamat...' : _address,
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

          if (_isLoadingLocation && !_isGpsLocked)
            Positioned(
              top: 50,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.cyan))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _gpsLockManager.state == GpsLockState.searching
                                ? 'Mencari sinyal GPS...'
                                : 'Mengunci posisi... $_gpsLockProgress%',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                          if (_gpsLockProgress > 0)
                            LinearProgressIndicator(
                              value: _gpsLockProgress / 100,
                              backgroundColor: Colors.grey[800],
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.cyan),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_isGpsLocked && _isAddressLoading)
            Positioned(
              top: 50,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.orange))),
                    SizedBox(width: 6),
                    Text('Memperbarui alamat', style: TextStyle(color: Colors.orange, fontSize: 10)),
                  ],
                ),
              ),
            ),

          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isGpsLocked ? _takePhoto : null,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _isGpsLocked ? Colors.white : Colors.grey, width: 5),
                    color: _isGpsLocked ? Colors.white24 : Colors.grey.withOpacity(0.3),
                  ),
                  child: _isCapturing
                      ? const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Colors.white))
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
