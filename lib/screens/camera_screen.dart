// lib/screens/camera_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  // Camera
  CameraController? _controller;
  bool _isCameraReady = false;
  bool _isCapturing = false;
  bool _isCameraInitializing = false;
  Completer<void>? _cameraInitCompleter;

  // GPS
  final GpsLockManager _gpsLockManager = GpsLockManager();
  bool _isGpsLocked = false;
  int _gpsLockProgress = 0;
  Position? _currentPosition;      // live preview (hybrid)
  Position? _bestPosition;         // locked position (hybrid)
  String _address = 'Mencari lokasi...';
  String _weather = '';
  double? _currentAccuracy;
  String _gpsQuality = 'Searching';
  double _gpsConfidence = 0.0;

  // Geocoding throttling (distance + time)
  double? _lastGeocodeLat;
  double? _lastGeocodeLon;
  static const double _addressRefreshDistance = 15.0; // meters
  static const int _geocodeTimeThresholdSeconds = 8;
  bool _isAddressLoading = false;
  DateTime? _lastGeocodeTime;

  StreamSubscription<Position>? _positionSub;
  Timer? _clockTimer;
  DateTime _currentTimestamp = DateTime.now();
  bool _locationStreamActive = false;

  // Watermark settings
  bool _showWeather = true;
  bool _showAccuracy = true;
  bool _showAddress = true;
  bool _showCoordinates = true;
  double _opacity = 0.82;
  bool _showBorder = true;
  String _fontSize = 'normal';
  WatermarkLayout _currentLayout = WatermarkLayout.modern;
  WatermarkPosition _watermarkPosition = WatermarkPosition.initial;

  static const int _antiShakeDelayMs = 200;

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
    await _checkGalleryPermission();
    await _initCamera();
    await _checkAndRequestHighAccuracyMode();
    _initLocationStream();
    _startClock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _positionSub?.cancel();
    _positionSub = null;
    _controller?.dispose();
    _controller = null;
    _locationStreamActive = false;
    _isCameraInitializing = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (_isCameraInitializing) return;
    if (state == AppLifecycleState.inactive) {
      final controller = _controller;
      if (controller != null && controller.value.isInitialized) {
        await controller.dispose();
        if (_controller == controller) _controller = null;
      }
      if (mounted) setState(() => _isCameraReady = false);
      await _positionSub?.cancel();
      _positionSub = null;
      _locationStreamActive = false;
    } else if (state == AppLifecycleState.resumed) {
      await _initCamera();
      _initLocationStream();
      final rawPos = _gpsLockManager.rawPosition;
      if (rawPos != null) unawaited(_fetchAddressAndWeather(rawPos, forceRefresh: true));
    }
  }

  Future<void> _initCamera() async {
    if (_isCameraInitializing) {
      await _cameraInitCompleter?.future;
      return;
    }
    _isCameraInitializing = true;
    _cameraInitCompleter = Completer<void>();
    try {
      if (widget.cameras.isEmpty) {
        _cameraInitCompleter?.complete();
        return;
      }
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
      if (!mounted) {
        _cameraInitCompleter?.complete();
        return;
      }
      setState(() => _isCameraReady = true);
      _cameraInitCompleter!.complete();
    } catch (e) {
      if (kDebugMode) debugPrint('INIT CAMERA ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kamera gagal diinisialisasi: $e')),
        );
      }
      _cameraInitCompleter?.completeError(e);
    } finally {
      _isCameraInitializing = false;
    }
  }

  Future<void> _checkGalleryPermission() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        final status = await Permission.photos.request();
        if (!status.isGranted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Izin akses foto diperlukan untuk menyimpan gambar.')),
          );
        }
      } else {
        final status = await Permission.storage.request();
        if (!status.isGranted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Izin penyimpanan diperlukan untuk menyimpan gambar.')),
          );
        }
      }
    }
  }

  Future<void> _checkAndRequestHighAccuracyMode() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 29) {
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

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) * sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  Future<void> _fetchAddressAndWeather(Position pos, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      if (_isAddressLoading) return;
      // Distance threshold
      if (_lastGeocodeLat != null && _lastGeocodeLon != null) {
        final distance = _haversine(
          _lastGeocodeLat!, _lastGeocodeLon!,
          pos.latitude, pos.longitude,
        );
        if (distance < _addressRefreshDistance) {
          return;
        }
      }
      // Time threshold
      if (_lastGeocodeTime != null &&
          DateTime.now().difference(_lastGeocodeTime!).inSeconds < _geocodeTimeThresholdSeconds) {
        return;
      }
    }
    if (mounted) setState(() => _isAddressLoading = true);
    _lastGeocodeTime = DateTime.now();
    try {
      final result = await LocationWeatherService.fetchFromPosition(pos).timeout(const Duration(seconds: 12));
      if (mounted) {
        setState(() {
          _address = result.address;
          _weather = result.weather;
          _isAddressLoading = false;
        });
        _lastGeocodeLat = pos.latitude;
        _lastGeocodeLon = pos.longitude;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('GEOCODE ERROR: $e');
      if (mounted) {
        setState(() {
          _address = '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
          _isAddressLoading = false;
        });
      }
    }
  }

  Future<void> _initLocationStream() async {
    if (_locationStreamActive) return;
    _locationStreamActive = true;

    await _positionSub?.cancel();
    _positionSub = null;

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() {
          _address = 'GPS tidak aktif';
          _isGpsLocked = false;
        });
        _locationStreamActive = false;
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) setState(() {
          _address = 'Izin lokasi ditolak';
          _isGpsLocked = false;
        });
        _locationStreamActive = false;
        return;
      }

      // Best possible location settings
      final locationSettings = Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 0,
              intervalDuration: const Duration(milliseconds: 700),
              forceLocationManager: false,
            )
          : (Platform.isIOS
              ? AppleSettings(
                  accuracy: LocationAccuracy.bestForNavigation,
                  distanceFilter: 0,
                  pauseLocationUpdatesAutomatically: false,
                  activityType: ActivityType.fitness,
                )
              : const LocationSettings(
                  accuracy: LocationAccuracy.bestForNavigation,
                  distanceFilter: 0,
                ));

      _positionSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        (pos) async {
          if (!mounted) return;

          final justLocked = _gpsLockManager.processSample(pos);
          final lockData = _gpsLockManager.lockData;
          final progress = _gpsLockManager.stationaryProgress;

          setState(() {
            _currentPosition = lockData?.position ?? pos;
            _isGpsLocked = _gpsLockManager.isLocked;
            _gpsLockProgress = progress;
            if (lockData != null) {
              _bestPosition = lockData.position;
              _currentAccuracy = lockData.accuracy;
              _gpsQuality = lockData.quality;
              _gpsConfidence = lockData.confidence;
            } else {
              _currentAccuracy = pos.accuracy;
            }
          });

          // 🔥 Geocode using latest raw position (distance throttled)
          final rawPos = _gpsLockManager.rawPosition;
          if (rawPos != null) {
            await _fetchAddressAndWeather(rawPos);
          }

          // Force refresh geocode when lock is achieved or upgraded
          if (justLocked && lockData != null && rawPos != null) {
            await _fetchAddressAndWeather(rawPos, forceRefresh: true);
            _gpsLockManager.updateLockAddress(_address, _weather);
          }
        },
        onError: (e) {
          if (kDebugMode) debugPrint('GPS STREAM ERROR: $e');
          _locationStreamActive = false;
        },
        onDone: () => _locationStreamActive = false,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('LOCATION ERROR: $e');
      if (mounted) setState(() => _address = 'Gagal memuat lokasi');
      _locationStreamActive = false;
    }
  }

  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _currentTimestamp = DateTime.now());
    });
  }

  Future<void> _takePhoto() async {
    if (_isCapturing) return;
    final capturePosition = _bestPosition ?? _currentPosition;
    if (capturePosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Menunggu sinyal GPS...')),
      );
      return;
    }

    await Future.delayed(Duration(milliseconds: _antiShakeDelayMs));

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    setState(() => _isCapturing = true);

    try {
      await controller.setExposureMode(ExposureMode.locked);
      await controller.setFocusMode(FocusMode.locked);

      final XFile rawFile = await controller.takePicture().timeout(const Duration(seconds: 8));
      final rawBytes = await File(rawFile.path).readAsBytes();

      final captureAddress = (_address.isNotEmpty &&
              _address != 'Mencari lokasi...' &&
              _address != 'GPS tidak aktif' &&
              _address != 'Izin lokasi ditolak' &&
              _address != 'Gagal memuat lokasi')
          ? _address
          : '${capturePosition.latitude.toStringAsFixed(6)}, ${capturePosition.longitude.toStringAsFixed(6)}';

      final watermarkBytes = await WatermarkEngine.process(
        imageBytes: rawBytes,
        timestamp: _currentTimestamp,
        layout: _currentLayout,
        lat: capturePosition.latitude,
        lon: capturePosition.longitude,
        acc: capturePosition.accuracy,
        address: captureAddress,
        weather: _weather.isNotEmpty ? _weather : '',
        showWeather: _showWeather,
        showAccuracy: _showAccuracy,
        showAddress: _showAddress,
        showCoordinates: _showCoordinates,
        opacity: _opacity,
        showBorder: _showBorder,
        fontSize: _fontSize,
        fontScale: _watermarkPosition.fontScale,
        imageQuality: 90,
      ).timeout(const Duration(seconds: 15));

      final dir = await getTemporaryDirectory();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(watermarkBytes);
      final success = await GallerySaver.saveImage(file.path, albumName: 'Timestamp Camera');
      if (success != true) throw Exception('Gagal menyimpan foto ke galeri');
      await file.delete();

      await controller.setExposureMode(ExposureMode.auto);
      await controller.setFocusMode(FocusMode.auto);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto berhasil disimpan ke Galeri')),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('CAPTURE ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengambil foto: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

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
          if (!_isGpsLocked && displayPosition == null)
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
                            _gpsLockProgress > 0
                                ? 'Mengunci posisi... $_gpsLockProgress%'
                                : 'Mencari sinyal GPS...',
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
          if (_currentAccuracy != null && displayPosition != null)
            Positioned(
              top: 50,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.gps_fixed, size: 12, color: _getAccuracyColor(_currentAccuracy!)),
                    const SizedBox(width: 4),
                    Text(
                      '±${_currentAccuracy!.toStringAsFixed(0)}m',
                      style: TextStyle(color: _getAccuracyColor(_currentAccuracy!), fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          if (_isGpsLocked && _isAddressLoading)
            Positioned(
              top: 50,
              left: 16,
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
                onTap: (_currentPosition != null || _bestPosition != null) ? _takePhoto : null,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: (_currentPosition != null || _bestPosition != null) ? Colors.white : Colors.grey,
                      width: 5,
                    ),
                    color: (_currentPosition != null || _bestPosition != null) ? Colors.white24 : Colors.grey.withOpacity(0.3),
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

  Color _getAccuracyColor(double acc) {
    if (acc <= 5) return Colors.green;
    if (acc <= 10) return Colors.lightGreen;
    if (acc <= 20) return Colors.orange;
    return Colors.red;
  }
}
