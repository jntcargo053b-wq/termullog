// lib/screens/camera_screen.dart
// FINAL VERSION dengan:
// - Cache geocoding & weather
// - Last known location
// - Force refresh alamat ketika akurasi membaik ≥5m
// - Adaptive Kalman filter (di GpsLockManager)
// - Nominatim sebagai prioritas utama geocoding
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
  bool _isGpsLocked = false;
  int _gpsLockProgress = 0;
  Position? _currentPosition;   // hybrid untuk watermark (sudah Kalman)
  double? _currentAccuracy;
  double _gpsConfidence = 0.0;

  // Address (dengan cache)
  String _address = 'Mencari lokasi...';
  String _weather = '';
  String _gpsStatus = 'Searching GPS...';
  bool _isAddressLoading = false;

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
  static const double _minAccuracyForCapture = 25.0;

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

    // Load persisted address cache dari shared preferences
    await LocationWeatherService.loadPersistedCache();

    // Tampilkan last known location (jika ada) sebagai sementara
    await _loadLastKnownAndCache();

    await _checkGalleryPermission();
    await _initCamera();
    await _checkAndRequestHighAccuracyMode();
    await _initLocationWithFirstFix();
    _startClock();
  }

  Future<void> _loadLastKnownAndCache() async {
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted) {
        setState(() {
          _currentPosition = lastKnown;
          _currentAccuracy = lastKnown.accuracy;
          _gpsStatus = _buildGpsStatus(lastKnown.accuracy, 0.0);
          // Gunakan address dari cache jika ada (tidak perlu geocode ulang)
          // Cache sudah dimuat sebelumnya, tapi kita bisa tampilkan address terakhir jika ada
        });
        if (kDebugMode) {
          debugPrint('Last known location: ${lastKnown.latitude}, ${lastKnown.longitude} acc=${lastKnown.accuracy}m');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Last known location error: $e');
    }
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
      if (mounted) setState(() => _gpsStatus = 'Searching GPS...');
      await _initCamera();
      await _initLocationWithFirstFix();
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

  String _buildGpsStatus(double acc, double confidence) {
    if (acc <= 8) return 'GPS Ready';
    if (acc <= 15) return 'GPS Stabilizing';
    if (acc <= 25) return 'GPS Improving';
    return 'GPS Searching';
  }

  String _buildConfidenceText(double confidence) {
    if (confidence >= 0.95) return 'Excellent';
    if (confidence >= 0.85) return 'Good';
    if (confidence >= 0.70) return 'Fair';
    return 'Poor';
  }

  Color _getAccuracyColor(double acc) {
    if (acc <= 5) return Colors.green;
    if (acc <= 10) return Colors.lightGreen;
    if (acc <= 20) return Colors.orange;
    return Colors.red;
  }

  Future<void> _initLocationWithFirstFix() async {
    // Ambil posisi awal (first fix) sebelum stream
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() {
          _address = 'GPS tidak aktif';
          _gpsStatus = 'GPS tidak aktif';
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
          _gpsStatus = 'Izin ditolak';
        });
        return;
      }

      final firstFix = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      ).timeout(const Duration(seconds: 10));
      if (mounted) {
        _onPositionSample(firstFix);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('First fix error: $e');
    }
    // Setelah itu mulai stream
    _initLocationStream();
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
          _gpsStatus = 'GPS tidak aktif';
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
          _gpsStatus = 'Izin ditolak';
        });
        _locationStreamActive = false;
        return;
      }

      final locationSettings = Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 0,
              intervalDuration: const Duration(milliseconds: 300),
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

  // ==================== GPS SAMPLE PROCESSING ====================
  // Menggunakan raw position untuk geocoding, hybrid (Kalman) untuk watermark.
  void _onPositionSample(Position pos) {
    final isNewLock = _gpsLockManager.processSample(pos);
    final lockData = _gpsLockManager.lockData;
    final progress = _gpsLockManager.stationaryProgress;

    // displayPosition sudah melewati Kalman filter (hybrid)
    final displayPosition = lockData?.position ?? pos;
    // raw untuk geocoding (belum difilter)
    final geocodePosition = lockData?.rawPosition ?? pos;
    final acc = geocodePosition.accuracy;
    final confidence = lockData?.confidence ?? 0.0;

    setState(() {
      _currentPosition = displayPosition;
      _isGpsLocked = _gpsLockManager.isLocked;
      _gpsLockProgress = (progress * 100).toInt();
      _currentAccuracy = acc;
      _gpsConfidence = confidence;
      _gpsStatus = _buildGpsStatus(acc, confidence);
    });

    // Geocoding menggunakan raw position, dengan threshold akurasi ≤ 50m
    if (acc <= 50.0) {
      _addressResolver.onPositionUpdate(geocodePosition, _fetchAddress);
    }

    // Jika baru lock, paksa refresh alamat
    if (isNewLock && lockData != null) {
      _addressResolver.forceRefresh(lockData.rawPosition, _fetchAddress);
    }

    if (kDebugMode) {
      debugPrint('📍 GPS: rawAcc=${acc.toStringAsFixed(1)}m conf=${confidence.toStringAsFixed(2)} locked=$_isGpsLocked');
    }
  }

  // AddressResolver akan memanggil method ini dengan posisi raw terbaru
  Future<void> _fetchAddress(Position pos) async {
    if (mounted) setState(() => _isAddressLoading = true);
    try {
      debugPrint('🌐 Geocoding RAW: lat=${pos.latitude}, lon=${pos.longitude}, acc=${pos.accuracy}m');
      final result = await LocationWeatherService.fetchFromPosition(pos)
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() {
        _address = result.address;
        _weather = result.weather;
        _isAddressLoading = false;
      });
      debugPrint('📍 ADDRESS: ${result.address}');
    } catch (e) {
      debugPrint('❌ Geocode error: $e');
      if (mounted) setState(() => _isAddressLoading = false);
    }
  }

  Future<void> _takePhoto() async {
    if (_isCapturing) return;

    // Gunakan best fix jika ada, fallback ke raw position atau hybrid
    final capturePosition = _gpsLockManager.bestFix ?? _gpsLockManager.lockData?.rawPosition ?? _currentPosition;
    if (capturePosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Menunggu sinyal GPS...')),
      );
      return;
    }

    if (capturePosition.accuracy > _minAccuracyForCapture) {
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Akurasi GPS Rendah'),
          content: Text('Akurasi GPS saat ini ${capturePosition.accuracy.toStringAsFixed(0)}m.\nTetap ambil foto?'),
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
      await controller.setExposureMode(ExposureMode.locked);
      await controller.setFocusMode(FocusMode.locked);

      final XFile rawFile = await controller.takePicture().timeout(const Duration(seconds: 8));
      final rawBytes = await File(rawFile.path).readAsBytes();

      // Pilih address untuk watermark (jika belum dapat, gunakan koordinat)
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
      try {
        await controller.setExposureMode(ExposureMode.auto);
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {}
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

    final displayPosition = _gpsLockManager.lockData?.position ?? _currentPosition;

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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '±${_currentAccuracy!.toStringAsFixed(0)}m',
                          style: TextStyle(color: _getAccuracyColor(_currentAccuracy!), fontSize: 10),
                        ),
                        Text(
                          _gpsStatus,
                          style: TextStyle(color: _getAccuracyColor(_currentAccuracy!).withOpacity(0.8), fontSize: 8),
                        ),
                        if (_gpsConfidence > 0)
                          Text(
                            '🛰 ${_buildConfidenceText(_gpsConfidence)}',
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
                onTap: (displayPosition != null) ? _takePhoto : null,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: (displayPosition != null) ? Colors.white : Colors.grey,
                      width: 5,
                    ),
                    color: (displayPosition != null) ? Colors.white24 : Colors.grey.withOpacity(0.3),
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
