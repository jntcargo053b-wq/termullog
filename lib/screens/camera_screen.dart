// lib/screens/camera_screen.dart
// FINAL PRODUCTION VERSION
// - GPS akurasi tinggi dengan GpsLockManager (weighted average, outlier rejection)
// - Menggunakan FusedLocationProvider (forceLocationManager: false)
// - Filter akurasi sebelum capture (>15m peringatan)
// - Optimalisasi setState dengan distance threshold
// - Stable lifecycle & race condition handling

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
  double? _currentAccuracy;

  Position? _lastGeocodedPosition;
  bool _isAddressLoading = false;
  static const double _geocodeDistanceThreshold = 25.0;
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
      _initLocation();
      final pos = _currentPosition ?? _bestPosition;
      if (pos != null) unawaited(_fetchAddressAndWeather(pos, forceRefresh: true));
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

  // ==================== PERMISSIONS ====================
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
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) setState(() {
          _address = 'Izin lokasi ditolak';
          _isLoadingLocation = false;
        });
        _locationStreamActive = false;
        return;
      }

      // Step 1: Last known position (hanya jika akurasi <= 50m)
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && lastKnown.accuracy <= 50 && mounted) {
        setState(() {
          _currentPosition = lastKnown;
          _isLoadingLocation = false;
          _currentAccuracy = lastKnown.accuracy;
        });
        _gpsLockManager.processSample(lastKnown, null);
        unawaited(_fetchAddressAndWeather(lastKnown, forceRefresh: true));
      }

      // Step 2: Get current position (loop hingga akurasi <= 15m)
      Position? accuratePos;
      int attempts = 0;
      while (attempts < 3 && (accuratePos == null || accuratePos.accuracy > 15)) {
        try {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.bestForNavigation,
            timeLimit: const Duration(seconds: 5),
          );
          if (accuratePos == null || pos.accuracy < accuratePos.accuracy) accuratePos = pos;
          if (accuratePos.accuracy <= 10) break;
          await Future.delayed(const Duration(milliseconds: 800));
        } catch (e) { break; }
        attempts++;
      }
      if (accuratePos != null && mounted) {
        setState(() {
          _currentPosition = accuratePos;
          _isLoadingLocation = false;
          _currentAccuracy = accuratePos.accuracy;
        });
        _gpsLockManager.processSample(accuratePos, null);
        unawaited(_fetchAddressAndWeather(accuratePos, forceRefresh: true));
      }

      // Step 3: Continuous stream (FusedLocationProvider, forceLocationManager: false)
      LocationSettings locationSettings;
      if (Platform.isAndroid) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 2,
          intervalDuration: const Duration(seconds: 1),
          forceLocationManager: false, // 🔥 lebih akurat di HP modern
        );
      } else if (Platform.isIOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 2,
          pauseLocationUpdatesAutomatically: false,
          activityType: ActivityType.fitness,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 2,
        );
      }

      _positionSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        (pos) {
          if (!mounted) return;

          // Tolak akurasi > 50m
          if (pos.accuracy > 50) return;

          // Throttle setState: update jika bergerak >= 0.5m atau akurasi meningkat signifikan
          final old = _currentPosition;
          final moved = old == null
              ? 999.0
              : Geolocator.distanceBetween(old.latitude, old.longitude, pos.latitude, pos.longitude);
          final accuracyImproved = old == null || pos.accuracy < old.accuracy - 2;

          if (moved >= 0.5 || accuracyImproved) {
            setState(() {
              _currentPosition = pos;
              _isLoadingLocation = false;
              _currentAccuracy = pos.accuracy;
            });
          }

          unawaited(_fetchAddressAndWeather(pos));

          final justLocked = _gpsLockManager.processSample(pos, _currentPosition);
          if (justLocked) {
            final lockData = _gpsLockManager.lockData;
            if (lockData != null) {
              if (mounted) setState(() {
                _bestPosition = lockData.position;
                _isGpsLocked = true;
                _currentAccuracy = lockData.accuracy;
              });
              unawaited(_fetchAddressAndWeather(lockData.position, forceRefresh: true)
                  .then((_) => _gpsLockManager.updateLockAddress(_address, _weather)));
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
        },
        onError: (e) {
          if (kDebugMode) debugPrint('GPS STREAM ERROR: $e');
          _locationStreamActive = false;
        },
        onDone: () {
          _locationStreamActive = false;
        },
      );
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

    // Filter akurasi: peringatan jika > 15 meter
    if (capturePosition.accuracy > 15) {
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

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    setState(() => _isCapturing = true);

    try {
      final XFile rawFile = await controller.takePicture().timeout(const Duration(seconds: 8));
      final rawBytes = await File(rawFile.path).readAsBytes();

      final captureAddress = (_address.isNotEmpty &&
              _address != 'Mencari lokasi...' &&
              _address != 'GPS tidak aktif' &&
              _address != 'Izin lokasi ditolak' &&
              _address != 'Gagal memuat lokasi')
          ? _address
          : '${capturePosition.latitude.toStringAsFixed(6)}, ${capturePosition.longitude.toStringAsFixed(6)}';

      final finalBytes = await WatermarkEngine.process(
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

      final success = await GallerySaver.saveImage(file.path, albumName: 'Timestamp Camera');
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

  Color _getAccuracyColor(double? acc) {
    if (acc == null) return Colors.white70;
    if (acc <= 5) return Colors.green;
    if (acc <= 10) return Colors.lightGreen;
    if (acc <= 20) return Colors.orange;
    return Colors.red;
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
          // Indikator loading GPS
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
          // Indikator akurasi (jika ada posisi)
          if (_currentAccuracy != null && _currentPosition != null)
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
                    Icon(Icons.gps_fixed, size: 12, color: _getAccuracyColor(_currentAccuracy)),
                    const SizedBox(width: 4),
                    Text(
                      '±${_currentAccuracy!.toStringAsFixed(0)}m',
                      style: TextStyle(color: _getAccuracyColor(_currentAccuracy), fontSize: 10),
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
          // Tombol capture
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
}
