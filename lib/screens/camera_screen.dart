// lib/screens/camera_screen.dart
// FINAL v9 – Production ready
// - Throttle setState (hanya ketika perubahan signifikan)
// - Freshness check untuk realtime capture (timestamp <5 detik)
// - Semua perbaikan sebelumnya dipertahankan
import 'dart:async';
import 'dart:io';

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
import '../services/address_resolver.dart';

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
  final AddressResolver _addressResolver = AddressResolver();
  bool _isGpsLocked = false;
  Position? _displayPosition;      // smoothed untuk overlay
  Position? _latestRealtimePosition; // realtime terbaru
  double? _currentAccuracy;
  double _gpsConfidence = 0.0;
  bool _isFallbackLock = false;
  double _gpsStability = 0.0;

  // Address & Weather
  String _address = 'Mencari lokasi...';
  String _weather = '';
  String _gpsStatus = '🟡 Mencari GPS';
  bool _isAddressLoading = false;

  StreamSubscription<Position>? _positionSub;
  Timer? _clockTimer;
  DateTime _currentTimestamp = DateTime.now();
  bool _locationStreamActive = false;
  int _lastGpsIntervalMs = 0;
  bool _isRestartingLocationStream = false;  // guard restart

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
  static const double _minAccuracyForCapture = 25.0;
  static const double _geocodeMinDistanceMeters = 15.0;
  static const int _geocodeMinIntervalSeconds = 10;

  DateTime _lastGeocodeTime = DateTime.now().subtract(const Duration(seconds: 10));
  Position? _lastGeocodePosition;
  int _geoRequestId = 0;

  Position? _lastDisplayPosition; // untuk smoothing

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettingsAndInit();
  }

  Future<void> _loadSettingsAndInit() async {
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

    await LocationWeatherService.loadPersistedCache();
    await _checkGalleryPermission();
    await _initCamera();
    await _checkAndRequestHighAccuracyMode();
    await _initLocationStream();
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
    _addressResolver.dispose();
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
      _addressResolver.reset();
      if (mounted) setState(() => _gpsStatus = '🟡 Mencari GPS');
      await _initCamera();
      await _initLocationStream();
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
      if (!mounted || _controller != controller) {
        await controller.dispose();
        _cameraInitCompleter?.complete();
        return;
      }
      await controller.lockCaptureOrientation();
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
            const SnackBar(content: Text('Izin akses foto diperlukan.')),
          );
        }
      } else {
        final status = await Permission.storage.request();
        if (!status.isGranted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Izin penyimpanan diperlukan.')),
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
              const SnackBar(content: Text('Izin lokasi diperlukan untuk akurasi GPS tinggi.')),
            );
          }
        }
      }
    }
  }

  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _currentTimestamp = DateTime.now());
    });
  }

  Future<void> _saveWatermarkPosition(WatermarkPosition pos) async {
    await SettingsCache.saveWatermarkPosition(pos);
  }

  String _buildGpsStatusText() {
    if (!_gpsLockManager.isLocked) {
      final progress = _gpsLockManager.stationaryProgress;
      if (progress > 0.15) {
        return '🟠 Menstabilkan GPS ${(progress * 100).toInt()}%';
      }
      return '🟡 Mencari GPS';
    }
    if (_gpsLockManager.isMoving) {
      return '🔵 Memperbarui Lokasi';
    }
    if (_gpsStability >= 0.80) {
      return '🟢 GPS Locked';
    }
    return '🟠 Menstabilkan GPS';
  }

  String _buildConfidenceText(double confidence) {
    if (confidence >= 0.95) return 'Excellent';
    if (confidence >= 0.85) return 'Good';
    if (confidence >= 0.70) return 'Fair';
    return 'Poor';
  }

  Color _getAccuracyColor(double acc, {bool isFallback = false}) {
    if (isFallback) return Colors.orange;
    if (acc <= 5) return Colors.green;
    if (acc <= 10) return Colors.lightGreen;
    if (acc <= 25) return Colors.orange;
    return Colors.red;
  }

  Position _smoothPosition(Position oldPos, Position newPos, double alpha) {
    return Position(
      latitude: oldPos.latitude + (newPos.latitude - oldPos.latitude) * alpha,
      longitude: oldPos.longitude + (newPos.longitude - oldPos.longitude) * alpha,
      timestamp: newPos.timestamp,
      accuracy: newPos.accuracy,
      altitude: newPos.altitude,
      altitudeAccuracy: newPos.altitudeAccuracy,
      heading: newPos.heading,
      headingAccuracy: newPos.headingAccuracy,
      speed: newPos.speed,
      speedAccuracy: newPos.speedAccuracy,
    );
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
          _gpsStatus = '⚠️ GPS tidak aktif';
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
          _gpsStatus = '⚠️ Izin ditolak';
        });
        _locationStreamActive = false;
        return;
      }

      final intervalMs = _gpsLockManager.currentIntervalMs;
      _lastGpsIntervalMs = intervalMs;

      final locationSettings = Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 0,
              intervalDuration: Duration(milliseconds: intervalMs),
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
        _onPositionSample,
        onError: (e) {
          if (kDebugMode) debugPrint('GPS STREAM ERROR: $e');
          _locationStreamActive = false;
          _positionSub?.cancel();
          _positionSub = null;
        },
        onDone: () {
          _locationStreamActive = false;
          _positionSub = null;
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('LOCATION INIT ERROR: $e');
      if (mounted) setState(() => _address = 'Gagal memuat lokasi');
      _locationStreamActive = false;
    }
  }

  void _restartStreamIfNeeded() {
    final newInterval = _gpsLockManager.currentIntervalMs;
    if (newInterval == _lastGpsIntervalMs) return;
    if (_positionSub == null) return;
    if (_isRestartingLocationStream) return;

    _lastGpsIntervalMs = newInterval;
    _isRestartingLocationStream = true;

    Future.microtask(() async {
      try {
        await _positionSub?.cancel();
        _positionSub = null;
        _locationStreamActive = false;
        await _initLocationStream();
      } finally {
        _isRestartingLocationStream = false;
      }
    });
  }

  bool _shouldGeocode(Position rawPos) {
    final now = DateTime.now();
    if (_lastGeocodePosition == null) {
      _lastGeocodePosition = rawPos;
      _lastGeocodeTime = now;
      return true;
    }
    final distance = Geolocator.distanceBetween(
      _lastGeocodePosition!.latitude, _lastGeocodePosition!.longitude,
      rawPos.latitude, rawPos.longitude,
    );
    if (distance >= _geocodeMinDistanceMeters) {
      _lastGeocodePosition = rawPos;
      _lastGeocodeTime = now;
      return true;
    }
    if (now.difference(_lastGeocodeTime).inSeconds >= _geocodeMinIntervalSeconds) {
      _lastGeocodePosition = rawPos;
      _lastGeocodeTime = now;
      return true;
    }
    return false;
  }

  void _onPositionSample(Position pos) {
    final isNewLock = _gpsLockManager.processSample(pos);
    final lockData = _gpsLockManager.lockData;

    _latestRealtimePosition = pos;

    // --- Overlay smoothing dengan validasi movedDistance ---
    final currentRaw = lockData?.position ?? pos;
    double movedDistance = 0.0;
    if (_lastDisplayPosition != null) {
      movedDistance = Geolocator.distanceBetween(
        _lastDisplayPosition!.latitude, _lastDisplayPosition!.longitude,
        currentRaw.latitude, currentRaw.longitude,
      );
    }
    final shouldSmooth = lockData != null &&
        _lastDisplayPosition != null &&
        !_gpsLockManager.isMoving &&
        movedDistance < 3.0;

    Position newDisplayPos;
    if (shouldSmooth) {
      const double alpha = 0.20;
      newDisplayPos = _smoothPosition(_lastDisplayPosition!, currentRaw, alpha);
    } else {
      newDisplayPos = currentRaw;
    }
    _lastDisplayPosition = newDisplayPos;

    final acc = pos.accuracy;
    final confidence = lockData?.confidence ?? 0.0;
    final stability = lockData?.stability ?? 0.0;
    final isFallback = lockData?.isFallbackLock ?? false;

    // --- Throttle setState: hanya jika perubahan signifikan ---
    final shouldRebuild =
        _displayPosition == null ||
        movedDistance > 0.5 ||
        (_currentAccuracy ?? 999) != acc.roundToDouble() ||
        _gpsConfidence != confidence ||
        _gpsStability != stability ||
        _isFallbackLock != isFallback ||
        _isGpsLocked != _gpsLockManager.isLocked;

    if (shouldRebuild && mounted) {
      setState(() {
        _displayPosition = newDisplayPos;
        _currentAccuracy = acc;
        _gpsConfidence = confidence;
        _gpsStability = stability;
        _isFallbackLock = isFallback;
        _isGpsLocked = _gpsLockManager.isLocked;
        _gpsStatus = _buildGpsStatusText();
      });
    } else {
      // tetap update nilai internal tanpa rebuild
      _displayPosition = newDisplayPos;
      _currentAccuracy = acc;
      _gpsConfidence = confidence;
      _gpsStability = stability;
      _isFallbackLock = isFallback;
      _isGpsLocked = _gpsLockManager.isLocked;
      _gpsStatus = _buildGpsStatusText();
    }

    // Geocode: tetap jalan selama locked atau akurasi masih baik
    final shouldGeocodeNow = (_gpsLockManager.isLocked || acc <= 25.0) && _shouldGeocode(pos);
    if (shouldGeocodeNow) {
      _addressResolver.onPositionUpdate(pos, _fetchAddress);
    }

    if (isNewLock && lockData != null) {
      _addressResolver.forceRefresh(pos, _fetchAddress);
      _lastGeocodePosition = pos;
      _lastGeocodeTime = DateTime.now();
    }

    _restartStreamIfNeeded();

    if (kDebugMode) {
      debugPrint('📍 REALTIME: acc=${acc.toStringAsFixed(1)}m locked=${_gpsLockManager.isLocked} moveDist=${movedDistance.toStringAsFixed(1)}m');
    }
  }

  Future<void> _fetchAddress(Position pos) async {
    final requestId = ++_geoRequestId;
    if (mounted) setState(() => _isAddressLoading = true);
    try {
      debugPrint('🌐 GEOCODE REQUEST #$requestId: lat=${pos.latitude}, lon=${pos.longitude}, acc=${pos.accuracy}m');
      final result = await LocationWeatherService.fetchFromPosition(pos)
          .timeout(const Duration(seconds: 15));
      if (requestId != _geoRequestId) return;
      if (!mounted) return;

      final latest = _latestRealtimePosition;
      if (latest != null) {
        final distance = Geolocator.distanceBetween(
          latest.latitude, latest.longitude,
          pos.latitude, pos.longitude,
        );
        if (distance > 40.0) {
          if (kDebugMode) debugPrint('🚫 Ignore stale geocode result (dist ${distance.toStringAsFixed(0)}m)');
          setState(() => _isAddressLoading = false);
          return;
        }
      }

      setState(() {
        _address = result.address;
        _weather = result.weather.isNotEmpty ? result.weather : '🌡️ --°C';
        _isAddressLoading = false;
      });
      debugPrint('📍 ADDRESS RESULT #$requestId: ${result.address}');
    } catch (e) {
      if (requestId != _geoRequestId) return;
      if (mounted) setState(() => _isAddressLoading = false);
      debugPrint('❌ Geocode error #$requestId: $e');
    }
  }

  Future<void> _takePhoto() async {
    if (_isCapturing) return;

    // Capture priority dengan freshness check realtime
    Position? capturePosition;
    final rawPos = _gpsLockManager.lockData?.rawPosition;
    final realtime = _latestRealtimePosition;
    int realtimeAge = 999;
    if (realtime?.timestamp != null) {
      realtimeAge = DateTime.now().difference(realtime!.timestamp!).inSeconds;
    }
    final freshRealtime = (realtime != null && realtimeAge < 5) ? realtime : null;

    capturePosition = rawPos ?? freshRealtime ?? _displayPosition ?? _gpsLockManager.bestFix;

    if (capturePosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Menunggu sinyal GPS...')),
      );
      return;
    }

    final bool isAccurate = capturePosition.accuracy <= _minAccuracyForCapture;
    final bool isStable = _gpsStability >= 0.62;
    final bool hasConfidence = _gpsConfidence >= 0.72;

    if (!isAccurate || !isStable || !hasConfidence) {
      final missing = <String>[];
      if (!isAccurate) missing.add('akurasi (${capturePosition.accuracy.toStringAsFixed(0)}m)');
      if (!isStable) missing.add('stabilitas');
      if (!hasConfidence) missing.add('confidence');
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('GPS Belum Siap'),
          content: Text('GPS belum stabil: ${missing.join(', ')}.\nTetap ambil foto?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tetap Ambil')),
          ],
        ),
      );
      if (shouldContinue != true) return;
    }

    await Future.delayed(const Duration(milliseconds: _antiShakeDelayMs));

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    setState(() => _isCapturing = true);

    try {
      try { await controller.setExposureMode(ExposureMode.locked); } catch (_) {}
      try { await controller.setFocusMode(FocusMode.locked); } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 150));

      final XFile rawFile = await controller.takePicture().timeout(const Duration(seconds: 8));
      final rawBytes = await File(rawFile.path).readAsBytes();

      // Fresh geocode untuk alamat foto
      String captureAddress = _address;
      try {
        final freshResult = await LocationWeatherService.fetchFromPosition(capturePosition)
            .timeout(const Duration(seconds: 3));
        if (freshResult.address.isNotEmpty) {
          captureAddress = freshResult.address;
          if (kDebugMode) debugPrint('📸 FRESH ADDRESS: $captureAddress');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Fresh geocode failed: $e, fallback to cached address');
      }

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

      try { await controller.setExposureMode(ExposureMode.auto); } catch (_) {}
      try { await controller.setFocusMode(FocusMode.auto); } catch (_) {}

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
      try { await _controller?.setExposureMode(ExposureMode.auto); } catch (_) {}
      try { await _controller?.setFocusMode(FocusMode.auto); } catch (_) {}
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

    final overlayPosition = _displayPosition;
    final canCapture = overlayPosition != null &&
        !_gpsLockManager.isMoving &&
        _gpsConfidence >= 0.62 &&
        (_currentAccuracy ?? 999) <= 35.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),

          if (overlayPosition != null)
            DraggableWatermarkOverlay(
              previewSize: MediaQuery.of(context).size,
              timestamp: _currentTimestamp,
              hasPosition: true,
              lat: overlayPosition.latitude,
              lon: overlayPosition.longitude,
              acc: _currentAccuracy ?? overlayPosition.accuracy,
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

          if (_isAddressLoading)
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
                    Text('Memperbarui alamat...', style: TextStyle(color: Colors.orange, fontSize: 10)),
                  ],
                ),
              ),
            ),

          if (!_isGpsLocked && overlayPosition == null)
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
                            _gpsStatus,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                          if (_gpsLockManager.stationaryProgress > 0)
                            LinearProgressIndicator(
                              value: _gpsLockManager.stationaryProgress,
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

          if (_currentAccuracy != null && overlayPosition != null)
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
                    Icon(Icons.gps_fixed, size: 12, color: _getAccuracyColor(_currentAccuracy!, isFallback: _isFallbackLock)),
                    const SizedBox(width: 4),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '±${_currentAccuracy!.toStringAsFixed(0)}m',
                          style: TextStyle(color: _getAccuracyColor(_currentAccuracy!, isFallback: _isFallbackLock), fontSize: 10),
                        ),
                        Text(
                          _gpsStatus,
                          style: TextStyle(color: _getAccuracyColor(_currentAccuracy!, isFallback: _isFallbackLock).withOpacity(0.8), fontSize: 8),
                        ),
                        if (_gpsConfidence > 0)
                          Text(
                            '🛰 ${_buildConfidenceText(_gpsConfidence)}${_isFallbackLock ? ' (fallback)' : ''}',
                            style: const TextStyle(color: Colors.white70, fontSize: 8),
                          ),
                      ],
                    ),
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
                onTap: canCapture ? _takePhoto : null,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: canCapture ? Colors.white : Colors.grey,
                      width: 5,
                    ),
                    color: canCapture ? Colors.white24 : Colors.grey.withOpacity(0.3),
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
