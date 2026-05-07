import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import '../core/camera_registry.dart';
import '../services/watermark_layout_service.dart';
import 'preview_screen.dart';

// ───────────────── GPS BAR WIDGET ─────────────────

class GpsBar extends StatelessWidget {
  final bool gpsReady;
  final String gpsText;
  final Position? bestPosition;
  
  const GpsBar({
    super.key,
    required this.gpsReady,
    required this.gpsText,
    this.bestPosition,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      padding: EdgeInsets.fromLTRB(12, MediaQuery.of(context).padding.top + 8, 12, 8),
      child: Row(
        children: [
          Icon(
            gpsReady ? Icons.gps_fixed : Icons.gps_not_fixed, 
            color: gpsReady ? Colors.greenAccent : Colors.amber,
            size: 14,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              bestPosition != null 
                ? '${bestPosition!.latitude.toStringAsFixed(4)}, ${bestPosition!.longitude.toStringAsFixed(4)}'
                : 'No GPS',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            gpsText,
            style: TextStyle(
              color: gpsReady ? Colors.greenAccent : Colors.amber,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────── MAIN CAMERA SCREEN ─────────────────

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => false;

  // ───────────────── CAMERA ─────────────────
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isTakingPhoto = false;
  bool _isCameraBusy = false;
  bool _isReinitializingCamera = false;
  bool _isResumingApp = false;
  
  bool _captureLocked = false;
  bool _acquireLock() {
    if (_captureLocked) return false;
    _captureLocked = true;
    return true;
  }
  void _releaseLock() {
    _captureLocked = false;
  }

  // ───────────────── GPS ─────────────────
  StreamSubscription<Position>? _gpsStream;
  Position? _bestPosition;
  bool _gpsReady = false;
  String _gpsText = '📍 Mencari GPS...';
  
  Timer? _gpsWatchdog;
  DateTime _lastGpsUpdate = DateTime.now();
  static const int _gpsUpdateIntervalMs = 3000;
  bool _isProcessingGps = false;
  int _gpsRestartCount = 0;
  
  final List<Position> _positionSamples = [];
  static const int _maxSamples = 5;
  static const double _targetAccuracy = 20.0;
  static const int _minSamplesRequired = 3;
  int _samplesCollected = 0;

  // ───────────────── GPS POLISH ─────────────────
  bool _isPolishing = false;
  int _polishCountdown = 25;
  Timer? _countdownTimer;
  Completer<void>? _gpsCompleter;
  bool _isWaitingForGps = false;

  // ───────────────── KALMAN ─────────────────
  final SimpleKalmanFilter _kalmanLat = SimpleKalmanFilter(q: 0.15, r: 10.0);
  final SimpleKalmanFilter _kalmanLon = SimpleKalmanFilter(q: 0.15, r: 10.0);
  bool _kalmanInitialized = false;

  // ───────────────── PERFORMANCE ─────────────────
  bool _isWarmingUp = true;
  int _photoQuality = 78;
  static const int _maxImageDimension = 1600;
  
  final Map<String, String> _addressCache = {};
  static const int _maxCacheSize = 20;
  
  Timer? _uiUpdateTimer;
  
  bool _isDisposed = false;

  // ───────────────── INIT ─────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    
    _initCamera();
    _startGpsTracking();
    _startGpsWatchdog();
  }

  @override
  void dispose() {
    _isDisposed = true;
    
    _uiUpdateTimer?.cancel();
    _countdownTimer?.cancel();
    _gpsWatchdog?.cancel();
    
    _gpsStream?.cancel().then((_) {
      _gpsStream = null;
    }).catchError((_) {});
    
    if (_gpsCompleter != null && !_gpsCompleter!.isCompleted) {
      _gpsCompleter!.complete();
    }
    
    _positionSamples.clear();
    _addressCache.clear();
    
    _disposeCamera();
    
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  Future<void> _disposeCamera() async {
    if (_controller != null) {
      try {
        await _controller?.dispose();
      } catch (e) {
        debugPrint('Dispose camera error: $e');
      } finally {
        _controller = null;
      }
    }
  }

  // ───────────────── APP LIFECYCLE ─────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (_isDisposed) return;
    
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _gpsStream?.pause();
      _gpsWatchdog?.cancel();
      await _disposeCamera();
      if (mounted) {
        setState(() {
          _controller = null;
          _isInitialized = false;
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_isResumingApp) return;
      _isResumingApp = true;
      
      _gpsStream?.resume();
      _startGpsWatchdog();
      
      await Future.delayed(const Duration(milliseconds: 300));
      await _initCamera();
      
      _isResumingApp = false;
    }
  }

  // ───────────────── CAMERA INIT ─────────────────

  Future<void> _initCamera() async {
    if (_isReinitializingCamera) return;
    if (_isDisposed) return;
    if (CameraRegistry.cameras.isEmpty) return;
    
    _isReinitializingCamera = true;
    
    try {
      if (_controller != null && _controller!.value.isInitialized) return;

      final camera = CameraRegistry.cameras.first;
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      _controller = controller;

      await controller.initialize();
      
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isWarmingUp = false;
        });
      }
    } catch (e) {
      debugPrint('Camera init error: $e');
      _controller = null;
    } finally {
      _isReinitializingCamera = false;
    }
  }

  // ───────────────── GPS WATCHDOG ─────────────────

  void _startGpsWatchdog() {
    _gpsWatchdog?.cancel();
    
    _gpsWatchdog = Timer.periodic(
      const Duration(seconds: 15),
      (_) async {
        if (_isDisposed) return;
        
        final last = DateTime.now().difference(_lastGpsUpdate);
        
        if (last.inSeconds > 25) {
          debugPrint('GPS Watchdog: Restarting GPS stream (${_gpsRestartCount + 1})');
          _gpsRestartCount++;
          await _gpsStream?.cancel();
          _startGpsTracking();
        }
      },
    );
  }

  // ───────────────── START GPS ─────────────────

  Future<void> _startGpsTracking() async {
    if (_isDisposed) return;
    
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _updateGpsText('❌ GPS tidak aktif');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _updateGpsText('❌ Izin GPS ditolak');
        return;
      }

      _warmupGps();

      final locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
        intervalDuration: const Duration(seconds: 3),
        forceLocationManager: false,
      );

      await _gpsStream?.cancel();
      
      _gpsStream = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        _onGpsData,
        onError: (error) {
          debugPrint('GPS Error: $error');
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('GPS Init Error: $e');
    }
  }
  
  void _warmupGps() async {
    try {
      final warmup = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 3));
      
      if (!_isDisposed && warmup != null) {
        _bestPosition = warmup;
        _positionSamples.add(warmup);
        _updateGpsText('🟡 GPS ±${warmup.accuracy.toStringAsFixed(0)}m');
      }
    } catch (_) {}
  }
  
  void _updateGpsText(String text) {
    if (_isDisposed) return;
    if (mounted) {
      setState(() {
        _gpsText = text;
      });
    }
  }

  void _onGpsData(Position pos) {
    if (_isDisposed) return;
    
    final timestamp = pos.timestamp ?? DateTime.now();
    final now = DateTime.now();
    
    if (now.difference(timestamp).inSeconds > 5) return;
    
    final elapsed = now.difference(_lastGpsUpdate).inMilliseconds;
    if (elapsed < _gpsUpdateIntervalMs) return;
    _lastGpsUpdate = now;
    
    if (_isProcessingGps) return;
    _isProcessingGps = true;
    
    try {
      if (pos.isMocked) return;
      
      if (_bestPosition != null && _isOutlier(pos, _bestPosition!)) return;
      
      _positionSamples.removeWhere((p) {
        final ts = p.timestamp ?? now;
        return now.difference(ts).inSeconds > 15;
      });
      _positionSamples.add(pos);
      
      while (_positionSamples.length > _maxSamples) {
        _positionSamples.removeAt(0);
      }
      
      _samplesCollected++;
      if (_samplesCollected < _minSamplesRequired) return;
      
      final averaged = _averageBestPositions();
      if (averaged == null) return;
      
      if (_bestPosition == null || averaged.accuracy < _bestPosition!.accuracy) {
        _bestPosition = averaged;
        
        if (_bestPosition!.accuracy < 25 && !_kalmanInitialized) {
          _kalmanLat.reset();
          _kalmanLon.reset();
          _kalmanInitialized = true;
        }
      }
      
      final acc = _bestPosition!.accuracy;
      final isReady = acc <= _targetAccuracy;
      
      _debounceUiUpdate(() {
        if (_isDisposed) return;
        setState(() {
          _gpsReady = isReady;
          if (isReady) {
            _gpsText = '🟢 GPS ${acc.toStringAsFixed(0)}m';
          } else if (acc <= 30) {
            _gpsText = '🟡 ${acc.toStringAsFixed(0)}m';
          } else {
            _gpsText = '🔴 ${acc.toStringAsFixed(0)}m';
          }
        });
      });
      
      if (_isWaitingForGps && _gpsCompleter != null && 
          !_gpsCompleter!.isCompleted && isReady) {
        _gpsCompleter!.complete();
        _isWaitingForGps = false;
      }
    } finally {
      _isProcessingGps = false;
    }
  }
  
  void _debounceUiUpdate(VoidCallback callback) {
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = Timer(const Duration(milliseconds: 100), callback);
  }

  bool _isOutlier(Position newPos, Position lastPos) {
    final newTs = newPos.timestamp ?? DateTime.now();
    final lastTs = lastPos.timestamp ?? DateTime.now();
    
    final distance = _calculateDistance(
      lastPos.latitude, lastPos.longitude,
      newPos.latitude, newPos.longitude,
    );
    
    final timeDiff = newTs.difference(lastTs).inSeconds.abs();
    if (timeDiff == 0) return false;
    final speed = distance / timeDiff;
    return speed > 30;
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
        sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  Position? _averageBestPositions() {
    if (_positionSamples.isEmpty) return _bestPosition;
    
    final validSamples = _positionSamples.where((p) => p.accuracy < 100).toList();
    if (validSamples.isEmpty) return _bestPosition;
    
    validSamples.sort((a, b) => a.latitude.compareTo(b.latitude));
    final medianLat = validSamples[validSamples.length ~/ 2].latitude;
    validSamples.sort((a, b) => a.longitude.compareTo(b.longitude));
    final medianLon = validSamples[validSamples.length ~/ 2].longitude;
    
    final sorted = List<Position>.from(validSamples)
      ..sort((a, b) => a.accuracy.compareTo(b.accuracy));
    
    final topN = sorted.take(3).toList();
    
    double totalWeight = 0;
    double weightedLat = 0;
    double weightedLon = 0;
    
    for (final p in topN) {
      final weight = 1.0 / (p.accuracy);
      totalWeight += weight;
      weightedLat += p.latitude * weight;
      weightedLon += p.longitude * weight;
    }
    
    double finalLat = weightedLat / totalWeight;
    double finalLon = weightedLon / totalWeight;
    
    finalLat = (finalLat + medianLat) / 2;
    finalLon = (finalLon + medianLon) / 2;
    
    if (_kalmanInitialized) {
      finalLat = _kalmanLat.filter(finalLat, topN.first.accuracy);
      finalLon = _kalmanLon.filter(finalLon, topN.first.accuracy);
    }
    
    final avgAccuracy = topN.map((p) => p.accuracy).reduce((a, b) => a + b) / topN.length;
    
    return Position(
      latitude: finalLat,
      longitude: finalLon,
      accuracy: avgAccuracy,
      altitude: topN.first.altitude,
      altitudeAccuracy: topN.first.altitudeAccuracy,
      heading: topN.first.heading,
      headingAccuracy: topN.first.headingAccuracy,
      speed: topN.first.speed,
      speedAccuracy: topN.first.speedAccuracy,
      timestamp: DateTime.now(),
    );
  }

  // ───────────────── TAKE PHOTO ─────────────────
  
  Future<void> _ambilFoto() async {
    if (!_acquireLock()) return;
    
    try {
      final ctrl = _controller;
      if (ctrl == null || !ctrl.value.isInitialized) return;
      if (_isTakingPhoto || _isPolishing || _isCameraBusy) return;
      if (ctrl.value.isTakingPicture) return;
      
      _isCameraBusy = true;
      if (mounted) setState(() => _isTakingPhoto = true);
      
      HapticFeedback.lightImpact();
      await _quickGpsRefresh();
      
      final XFile file = await ctrl.takePicture().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Camera timeout'),
      );
      
      final bytes = await File(file.path).readAsBytes();
      final DateTime waktuFoto = DateTime.now();
      
      if (mounted) {
        setState(() {
          _isTakingPhoto = false;
          _isPolishing = true;
          _polishCountdown = 25;
        });
      }
      
      await _waitForBestGps();
      
      final String alamat = _bestPosition != null
          ? await _getAddressCached(_bestPosition)
          : 'Lokasi tidak tersedia';
      
      final result = await compute(_processImageOptimized, ImageProcessParams(
        imageBytes: bytes,
        timestamp: waktuFoto,
        position: _bestPosition,
        address: alamat,
        quality: _photoQuality,
        maxDimension: _maxImageDimension,
      ));
      
      final dir = await getTemporaryDirectory();
      final outputPath = '${dir.path}/termullog_${waktuFoto.millisecondsSinceEpoch}.jpg';
      await File(outputPath).writeAsBytes(result.jpegData);
      
      if (!mounted || _isDisposed) return;
      
      setState(() => _isPolishing = false);
      
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreviewScreen(imagePath: outputPath),
        ),
      );
      
      if (mounted && _controller == null) {
        await _initCamera();
      }
    } on TimeoutException catch (e) {
      debugPrint('Timeout: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kamera sibuk, coba lagi'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted && !_isDisposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${e.toString().substring(0, 50)}')),
        );
      }
    } finally {
      _cleanupCapture();
    }
  }
  
  Future<void> _quickGpsRefresh() async {
    if (_bestPosition != null && _bestPosition!.accuracy <= 30) return;
    
    try {
      final fresh = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 2));
      if (!fresh.isMocked && fresh.accuracy < (_bestPosition?.accuracy ?? 999)) {
        _bestPosition = fresh;
      }
    } catch (_) {}
  }
  
  void _cleanupCapture() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    
    if (_gpsCompleter != null && !_gpsCompleter!.isCompleted) {
      _gpsCompleter!.complete();
    }
    _gpsCompleter = null;
    _isWaitingForGps = false;
    _isCameraBusy = false;
    
    if (mounted && !_isDisposed) {
      setState(() {
        _isTakingPhoto = false;
        _isPolishing = false;
      });
    }
    
    _releaseLock();
  }
  
  Future<void> _waitForBestGps() async {
    if (_isDisposed) return;
    
    if (_gpsReady && _bestPosition != null && 
        _bestPosition!.accuracy <= _targetAccuracy) {
      return;
    }
    
    if (_isWaitingForGps) return;
    
    _isWaitingForGps = true;
    _gpsCompleter = Completer<void>();
    _startCountdown();
    
    try {
      await _gpsCompleter!.future.timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          if (_gpsCompleter != null && !_gpsCompleter!.isCompleted) {
            _gpsCompleter!.complete();
          }
        },
      );
    } finally {
      _isWaitingForGps = false;
    }
  }
  
  void _startCountdown() {
    _countdownTimer?.cancel();
    _polishCountdown = 25;
    
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed || !mounted) {
        timer.cancel();
        return;
      }
      
      setState(() => _polishCountdown--);
      
      if (_polishCountdown <= 0) {
        timer.cancel();
        if (_gpsCompleter != null && !_gpsCompleter!.isCompleted) {
          _gpsCompleter!.complete();
        }
      }
    });
  }
  
  Future<String> _getAddressCached(Position? pos) async {
    if (pos == null) return 'Lokasi tidak tersedia';
    
    final cacheKey = '${pos.latitude.toStringAsFixed(3)},${pos.longitude.toStringAsFixed(3)}';
    
    if (_addressCache.containsKey(cacheKey)) {
      return _addressCache[cacheKey]!;
    }
    
    try {
      final placemarks = await placemarkFromCoordinates(
        pos.latitude, pos.longitude,
      ).timeout(const Duration(seconds: 5));
      
      String address;
      if (placemarks.isEmpty) {
        address = '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      } else {
        final p = placemarks.first;
        final parts = [p.street, p.locality].where((e) => e != null && e.trim().isNotEmpty).toList();
        address = parts.join(', ');
        if (address.isEmpty) address = '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      }
      
      if (_addressCache.length >= _maxCacheSize) {
        _addressCache.remove(_addressCache.keys.first);
      }
      _addressCache[cacheKey] = address;
      
      return address;
    } catch (_) {
      return '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
    }
  }

  // ───────────────── UI ─────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera preview
            if (_isInitialized && _controller != null && !_isWarmingUp)
              Center(
                child: ClipRect(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: CameraPreview(_controller!),
                  ),
                ),
              )
            else
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(strokeWidth: 2),
                    SizedBox(height: 16),
                    Text('Starting camera...', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            
            // GPS bar
            Positioned(
              top: 0, left: 0, right: 0,
              child: GpsBar(
                gpsReady: _gpsReady,
                gpsText: _gpsText,
                bestPosition: _bestPosition,
              ),
            ),
            
            // Polishing overlay
            if (_isPolishing)
              Container(
                color: Colors.black.withOpacity(0.85),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.greenAccent, strokeWidth: 2),
                      const SizedBox(height: 16),
                      Text(_gpsText, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      const SizedBox(height: 8),
                      Text('$_polishCountdown s', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            
            // Capture button
            if (!_isPolishing && !_isWarmingUp)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  color: Colors.black87,
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      ),
                      GestureDetector(
                        onTap: (_isTakingPhoto || _isPolishing) ? null : _ambilFoto,
                        child: Container(
                          width: 64, height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            color: Colors.white.withOpacity(0.15),
                          ),
                          child: _isTakingPhoto
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.camera_alt, color: Colors.white, size: 28),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ───────────────── OPTIMIZED IMAGE PROCESSING ─────────────────

class ImageProcessParams {
  final Uint8List imageBytes;
  final DateTime timestamp;
  final Position? position;
  final String address;
  final int quality;
  final int maxDimension;
  
  const ImageProcessParams({
    required this.imageBytes,
    required this.timestamp,
    this.position,
    required this.address,
    required this.quality,
    required this.maxDimension,
  });
}

class ProcessedImage {
  final Uint8List jpegData;
  const ProcessedImage({required this.jpegData});
}

ProcessedImage _processImageOptimized(ImageProcessParams params) {
  img.Image? src;
  
  try {
    src = img.decodeImage(params.imageBytes);
    if (src == null) throw Exception('Decode failed');
    
    if (src.width > params.maxDimension || src.height > params.maxDimension) {
      src = img.copyResize(
        src, 
        width: src.width > src.height ? params.maxDimension : null,
        height: src.height > src.width ? params.maxDimension : null,
        interpolation: img.Interpolation.average,
      );
    }
    
    src = _addWatermarkFast(src, params);
    
    final jpegData = img.encodeJpg(src, quality: params.quality);
    
    return ProcessedImage(jpegData: Uint8List.fromList(jpegData));
  } finally {
    src?.clear();
  }
}

// FIX: Perbaikan fillRect untuk package image versi 4.8.0
img.Image _addWatermarkFast(img.Image src, ImageProcessParams params) {
  final now = params.timestamp;
  final pos = params.position;
  final alamat = params.address;
  
  final tanggal = DateFormat('dd/MM/yy').format(now);
  final jam = DateFormat('HH:mm:ss').format(now);
  
  final gpsAvailable = pos != null;
  final lat = gpsAvailable ? pos.latitude.toStringAsFixed(5) : 'N/A';
  final lon = gpsAvailable ? pos.longitude.toStringAsFixed(5) : 'N/A';
  final acc = gpsAvailable ? '${pos.accuracy.toStringAsFixed(0)}m' : 'No GPS';
  
  final int stripHeight = (src.height * 0.14).toInt().clamp(100, 180);
  final isBottom = WatermarkLayoutService.position != 'top';
  final y0 = isBottom ? src.height - stripHeight : 0;
  
  if (y0 < 0) return src;
  
  // FIX: fillRect dengan parameter yang benar untuk image 4.8.0
  // Signature: fillRect(src, x, y, x2, y2, color)
  img.fillRect(
    src,
    0,  // x1
    y0, // y1
    src.width, // x2
    y0 + stripHeight, // y2
    img.ColorRgba8(0, 0, 0, 180),
  );
  
  final font = src.width > 1500 ? img.arial24 : img.arial14;
  final white = img.ColorRgba8(255, 255, 255, 255);
  final yellow = img.ColorRgba8(255, 200, 0, 255);
  final green = img.ColorRgba8(100, 220, 100, 255);
  
  final lineH = (stripHeight / 6).floor().clamp(14, 24);
  final y = y0 + 6;
  
  if (y + lineH * 5 <= src.height) {
    img.drawString(src, 'TermulLog', font: font, x: 10, y: y, color: yellow);
    img.drawString(src, '$tanggal  $jam', font: font, x: 10, y: y + lineH, color: white);
    img.drawString(src, '$lat, $lon', font: font, x: 10, y: y + lineH * 2, color: white);
    img.drawString(src, 'Acc: $acc', font: font, x: 10, y: y + lineH * 3, 
      color: gpsAvailable ? green : white);
    
    final shortAddr = alamat.length > 42 ? '${alamat.substring(0, 39)}...' : alamat;
    if (shortAddr.isNotEmpty && y + lineH * 4 < src.height) {
      img.drawString(src, shortAddr, font: font, x: 10, y: y + lineH * 4, color: white);
    }
  }
  
  return src;
}

// ───────────────── KALMAN FILTER ─────────────────

class SimpleKalmanFilter {
  final double _q;
  double _r;
  double _p;
  double? _x;
  
  SimpleKalmanFilter({double q = 0.15, double r = 10.0})
    : _q = q, _r = r, _p = 1.0;
  
  double filter(double measurement, double measurementAccuracy) {
    _r = measurementAccuracy.clamp(1.0, 100.0);
    
    if (_x == null) {
      _x = measurement;
      return measurement;
    }
    
    _p = _p + _q;
    final k = _p / (_p + _r);
    _x = _x! + k * (measurement - _x!);
    _p = (1 - k) * _p;
    
    return _x!;
  }
  
  void reset() {
    _p = 1.0;
    _x = null;
  }
}
