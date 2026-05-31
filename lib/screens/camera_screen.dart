// lib/screens/camera_screen.dart
// FINAL v4 – Professional Timestamp Camera (Production Ready)
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
  int _gpsLockProgress = 0;
  Position? _displayPosition;
  double? _currentAccuracy;
  double _gpsConfidence = 0.0;
  double _gpsStability = 0.0;
  bool _isFallbackLock = false;
  String _gpsStatus = '🟡 Mencari GPS';

  // Address & Weather
  String _address = 'Mencari lokasi...';
  String _weather = '';
  bool _isAddressLoading = false;

  // Stream & Timers
  StreamSubscription<Position>? _positionSub;
  Timer? _clockTimer;
  DateTime _currentTimestamp = DateTime.now();
  bool _locationStreamActive = false;
  int _currentStreamIntervalMs = 2500; // start slow for searching
  bool _isRestartingStream = false;    // 🔒 restart lock

  // UI Settings
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

  // Geocode throttling
  DateTime _lastGeocodeTime = DateTime.now().subtract(const Duration(seconds: 10));
  Position? _lastGeocodePosition;
  int _geoRequestId = 0;

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

  String _buildGpsStatus() {
    if (!_gpsLockManager.isLocked) {
      if (_gpsStability > 0.15) {
        return '🟠 Menstabilkan GPS ${(_gpsStability * 100).toInt()}%';
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

  Future<void> _restartLocationStream() async {
    if (_isRestartingStream) return;
    _isRestartingStream = true;
    try {
      await _positionSub?.cancel();
      _positionSub = null;
      _locationStreamActive = false;
      await _initLocationStream();
    } finally {
      _isRestartingStream = false;
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

      final locationSettings = Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 0,
              intervalDuration: Duration(milliseconds: _currentStreamIntervalMs),
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

  Future<void> _updateStreamInterval() async {
    if (_isRestartingStream) return;
    final newInterval = _gpsLockManager.currentIntervalMs;
    if (newInterval != _currentStreamIntervalMs && _positionSub != null) {
      _currentStreamIntervalMs = newInterval;
      if (kDebugMode) {
        debugPrint('🔄 Restart GPS stream: ${_currentStreamIntervalMs}ms');
      }
      await _restartLocationStream();
    }
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
    // Adaptive hard unlock (hanya jika locked, tidak moving, dan drift > threshold dinamis)
    final lockData = _gpsLockManager.lockData;
    if (_gpsLockManager.isLocked && !_gpsLockManager.isMoving && lockData != null) {
      final driftDistance = Geolocator.distanceBetween(
        lockData.rawPosition.latitude,
        lockData.rawPosition.longitude,
        pos.latitude,
        pos.longitude,
      );
      final unlockThreshold = max(6.0, pos.accuracy * 0.6);
      if (driftDistance > unlockThreshold && pos.accuracy < 20.0) {
        if (kDebugMode) {
          debugPrint('🚨 HARD UNLOCK ${driftDistance.toStringAsFixed(1)}m > ${unlockThreshold.toStringAsFixed(1)}m (drift)');
        }
        _gpsLockManager.reset();
      }
    }

    final isNewLock = _gpsLockManager.processSample(pos);
    final lockDataAfter = _gpsLockManager.lockData;

    final displayPosition = lockDataAfter?.position ?? pos;
    final rawPosition = lockDataAfter?.rawPosition ?? pos;
    final acc = rawPosition.accuracy;
    final confidence = lockDataAfter?.confidence ?? 0.0;
    final stability = lockDataAfter?.stability ?? 0.0;
    final isFallback = lockDataAfter?.isFallbackLock ?? false;

    setState(() {
      _displayPosition = displayPosition;
      _currentAccuracy = acc;
      _gpsConfidence = confidence;
      _gpsStability = stability;
      _isFallbackLock = isFallback;
      _isGpsLocked = _gpsLockManager.isLocked;
      _gpsStatus = _buildGpsStatus();
    });

    if (_gpsLockManager.isLocked && _shouldGeocode(rawPosition)) {
      _addressResolver.onPositionUpdate(rawPosition, _fetchAddress);
    }

    if (isNewLock && lockDataAfter != null) {
      _addressResolver.forceRefresh(lockDataAfter.rawPosition, _fetchAddress);
      _lastGeocodePosition = lockDataAfter.rawPosition;
      _lastGeocodeTime = DateTime.now();
    }

    unawaited(_updateStreamInterval());

    if (kDebugMode) {
      debugPrint('📍 RAW: acc=${acc.toStringAsFixed(1)}m conf=${confidence.toStringAsFixed(2)} stability=${stability.toStringAsFixed(2)} locked=${_gpsLockManager.isLocked}');
    }
  }

  Future<void> _fetchAddress(Position pos) async {
    if (!mounted) return;
    final requestId = ++_geoRequestId;
    if (mounted) setState(() => _isAddressLoading = true);
    try {
      debugPrint('🌐 GEOCODE REQUEST #$requestId: lat=${pos.latitude}, lon=${pos.longitude}, acc=${pos.accuracy}m');
      final result = await LocationWeatherService.fetchFromPosition(pos)
          .timeout(const Duration(seconds: 12));
      if (requestId != _geoRequestId) return;
      if (!mounted) return;
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

    final capturePosition = _gpsLockManager.lockData?.position ?? _gpsLockManager.bestFix ?? _displayPosition;
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
      // Aman untuk device yang tidak support mode lock
      try { await controller.setExposureMode(ExposureMode.locked); } catch (_) {}
      try { await controller.setFocusMode(FocusMode.locked); } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 150));

      final XFile rawFile = await controller.takePicture().timeout(const Duration(seconds: 8));
      final rawBytes = await File(rawFile.path).readAsBytes();

      final captureAddress = (_address.isNotEmpty &&
              !_address.startsWith('Mencari') &&
              !_address.startsWith('GPS') &&
              !_address.startsWith('Izin') &&
              !_address.startsWith('Gagal'))
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
                          if (_gpsStability > 0)
                            LinearProgressIndicator(
                              value: _gpsStability,
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
