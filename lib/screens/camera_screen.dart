// lib/screens/camera_screen.dart
// GPS FIX: faster lock + resume fix + remove throttle
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

  bool _isCameraInitializing = false;
  Completer<void>? _cameraInitCompleter;

  final GpsLockManager _gpsLockManager = GpsLockManager();
  bool _isGpsLocked = false;
  int _gpsLockProgress = 0;
  Position? _currentPosition;
  Position? _bestPosition;
  String _address = 'Mencari lokasi...';
  String _weather = '';

  Position? _lastGeocodedPosition;
  bool _isAddressLoading = false;
  static const double _geocodeDistanceThreshold = 25.0;
  // FIX 1: turunkan dari 8 → 5 agar alamat lebih cepat refresh
  static const int _geocodeTimeThresholdSeconds = 5;

  StreamSubscription<Position>? _positionSub;
  Timer? _clockTimer;
  DateTime _currentTimestamp = DateTime.now();
  DateTime? _lastGeocodeTime;

  bool _showWeather = true;
  bool _showAccuracy = true;
  bool _showAddress = true;
  bool _showCoordinates = true;
  double _opacity = 0.82;
  bool _showBorder = true;
  String _fontSize = 'normal';
  WatermarkLayout _currentLayout = WatermarkLayout.modern;
  WatermarkPosition _watermarkPosition = WatermarkPosition.initial;

  // FIX 2: hapus _isLocationInitialized — pakai flag berbeda yang bisa di-reset
  bool _locationStreamActive = false;

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
    _initLocation();
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
    final controller = _controller;
    if (state == AppLifecycleState.inactive) {
      if (controller != null && controller.value.isInitialized) {
        await controller.dispose();
        if (_controller == controller) _controller = null;
      }
      if (mounted) setState(() => _isCameraReady = false);

      // FIX 3: matikan stream saat inactive agar bisa restart bersih
      await _positionSub?.cancel();
      _positionSub = null;
      _locationStreamActive = false;

    } else if (state == AppLifecycleState.resumed) {
      await _initCamera();
      // FIX 3: restart stream GPS saat resume
      _initLocation();
      final pos = _currentPosition ?? _bestPosition;
      if (pos != null) await _fetchAddressAndWeather(pos, forceRefresh: true);
    }
  }

  // ==================== CAMERA ====================
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
      if (!mounted) { _cameraInitCompleter?.complete(); return; }
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

  // ==================== GALLERY PERMISSION ====================
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

  // ==================== HIGH ACCURACY MODE ====================
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
      if (timeSinceLast < _geocodeTimeThresholdSeconds &&
          distanceMoved < _geocodeDistanceThreshold) {
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

  // ==================== GPS LOCATION STREAM ====================
  Future<void> _initLocation() async {
    // FIX 4: gunakan _locationStreamActive bukan _isLocationInitialized
    if (_locationStreamActive) return;
    _locationStreamActive = true;

    await _positionSub?.cancel();
    _positionSub = null;

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() {
          _address = 'GPS tidak aktif';
          _isLoadingLocation = false;
        });
        _locationStreamActive = false;
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() {
          _address = 'Izin lokasi ditolak';
          _isLoadingLocation = false;
        });
        _locationStreamActive = false;
        return;
      }

      // FIX 5: last known position dulu (instan, 0ms)
      Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted) {
        setState(() {
          _currentPosition = lastKnown;
          _isLoadingLocation = false;
        });
        _gpsLockManager.processSample(lastKnown, null);
        unawaited(_fetchAddressAndWeather(lastKnown, forceRefresh: true));
      }

      // FIX 6: getCurrentPosition untuk fix akurat SEBELUM stream mulai
      // Ini memberi posisi valid dalam ~1–2 detik tanpa tunggu stream
      try {
        final currentPos = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            // timeLimit tidak ada di semua versi, pakai timeout di luar
          ),
        ).timeout(const Duration(seconds: 8));
        if (mounted) {
          setState(() {
            _currentPosition = currentPos;
            _isLoadingLocation = false;
          });
          _gpsLockManager.processSample(currentPos, null);
          unawaited(_fetchAddressAndWeather(currentPos, forceRefresh: true));
        }
      } catch (e) {
        if (kDebugMode) debugPrint('getCurrentPosition timeout/error: $e');
        // tidak fatal — stream akan terus berjalan
      }

      // Platform settings
      // FIX 7: distanceFilter: 0 agar dapat update meski diam
      LocationSettings locationSettings;
      if (Platform.isAndroid) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,         // <-- FIX: was 5, sekarang 0
          intervalDuration: const Duration(seconds: 1), // <-- FIX: was 2s
          forceLocationManager: false,
        );
      } else if (Platform.isIOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,         // <-- FIX: was 5
          pauseLocationUpdatesAutomatically: false,
          activityType: ActivityType.fitness,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        );
      }

      _positionSub = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen((pos) async {
        // FIX 8: hapus throttle 1.5m — selalu update agar koordinat segar
        if (mounted) setState(() {
          _currentPosition = pos;
          _isLoadingLocation = false;
        });

        unawaited(_fetchAddressAndWeather(pos));

        final justLocked = _gpsLockManager.processSample(pos, null);
        if (justLocked) {
          final lockData = _gpsLockManager.lockData;
          if (lockData != null) {
            if (mounted) setState(() {
              _bestPosition = lockData.position;
              _isGpsLocked = true;
            });
            unawaited(_fetchAddressAndWeather(lockData.position, forceRefresh: true));
            _gpsLockManager.updateLockAddress(_address, _weather);
          }
        } else {
          final progress = _gpsLockManager.stationaryProgress;
          if (_gpsLockManager.state != GpsLockState.locked) {
            if (mounted) setState(() {
              _gpsLockProgress = progress;
              _isGpsLocked = false;
            });
          } else {
            final lockData = _gpsLockManager.lockData;
            if (lockData != null && _bestPosition != lockData.position) {
              if (mounted) setState(() => _bestPosition = lockData.position);
            }
          }
        }
        if (_isGpsLocked && mounted) setState(() => _isLoadingLocation = false);
      }, onError: (e) {
        // FIX 9: tangani error stream agar tidak silent fail
        if (kDebugMode) debugPrint('GPS STREAM ERROR: $e');
        _locationStreamActive = false;
      });

    } catch (e) {
      if (kDebugMode) debugPrint('LOCATION ERROR: $e');
      if (mounted) setState(() {
        _address = 'Gagal memuat lokasi';
        _isLoadingLocation = false;
      });
      _locationStreamActive = false;
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

    final Position? capturePosition = _bestPosition ?? _currentPosition;
    if (capturePosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Menunggu sinyal GPS...')),
      );
      return;
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    setState(() => _isCapturing = true);

    try {
      final XFile rawFile = await controller.takePicture()
          .timeout(const Duration(seconds: 8));
      final rawBytes = await File(rawFile.path).readAsBytes();

      final captureAddress = (_address.isNotEmpty &&
              _address != 'Mencari lokasi...' &&
              _address != 'GPS tidak aktif' &&
              _address != 'Izin lokasi ditolak')
          ? _address
          : '${capturePosition.latitude.toStringAsFixed(6)}, '
            '${capturePosition.longitude.toStringAsFixed(6)}';
      final captureWeather = _weather.isNotEmpty ? _weather : '';

      final finalBytes = await WatermarkEngine.process(
        imageBytes: rawBytes,
        timestamp: _currentTimestamp,
        layout: _currentLayout,
        lat: capturePosition.latitude,
        lon: capturePosition.longitude,
        acc: capturePosition.accuracy,
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
      ).timeout(const Duration(seconds: 15));

      final dir = await getTemporaryDirectory();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(finalBytes);

      final success = await GallerySaver.saveImage(
          file.path, albumName: 'Timestamp Camera');
      if (success != true) throw Exception('Gagal menyimpan foto ke galeri');

      try { await file.delete(); } catch (_) {}

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

  // ==================== BUILD ====================
  @override
  Widget build(BuildContext context) {
    final isPreviewReady =
        _controller != null && _controller!.value.isInitialized;
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
          if (_isLoadingLocation && !_isGpsLocked && _currentPosition == null)
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
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.cyan),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _gpsLockManager.state == GpsLockState.searching
                                ? 'Mencari sinyal GPS...'
                                : 'Mengunci posisi... $_gpsLockProgress%',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                          if (_gpsLockProgress > 0)
                            LinearProgressIndicator(
                              value: _gpsLockProgress / 100,
                              backgroundColor: Colors.grey[800],
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.cyan),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.orange),
                      ),
                    ),
                    SizedBox(width: 6),
                    Text('Memperbarui alamat',
                        style: TextStyle(color: Colors.orange, fontSize: 10)),
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
                onTap: (_currentPosition != null || _bestPosition != null)
                    ? _takePhoto
                    : null,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: (_currentPosition != null || _bestPosition != null)
                          ? Colors.white
                          : Colors.grey,
                      width: 5,
                    ),
                    color: (_currentPosition != null || _bestPosition != null)
                        ? Colors.white24
                        : Colors.grey.withOpacity(0.3),
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
