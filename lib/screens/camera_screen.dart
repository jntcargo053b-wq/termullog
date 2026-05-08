import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path/path.dart' as path;

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

// ─────────────────────────────────────────────────────────────
// CONSTANTS & CONFIGURATION
// ─────────────────────────────────────────────────────────────

class CameraConstants {
  // GPS Configuration
  static const int gpsWatchdogIntervalSeconds = 15;
  static const int gpsStaleAfterSeconds = 25;
  static const double targetAccuracyMeters = 20.0;
  static const int maxGpsSamples = 5;
  static const int minSamplesRequired = 3;
  static const double outlierSpeedThresholdMs = 30.0;
  static const double maxValidAccuracyMeters = 80.0;
  static const double maxAcceptableAccuracyMeters = 80.0;
  static const int quickGpsTimeoutSeconds = 2;
  static const int warmupGpsTimeoutSeconds = 3;
  
  // GPS Polishing - Adaptive Timeout
  static const int polishTimeoutGoodAccuracy = 8;
  static const int polishTimeoutMediumAccuracy = 15;
  static const int polishTimeoutPoorAccuracy = 25;
  
  // GPS Accuracy thresholds
  static const double accuracyGood = 30.0;
  static const double accuracyMedium = 50.0;
  
  // Camera Configuration
  static const int photoQualityPercent = 78;
  static const int maxImageDimensionPx = 1600;
  static const Duration cameraTimeout = Duration(seconds: 5);
  static const Duration cameraReinitDelay = Duration(milliseconds: 300);
  
  // Kalman Filter
  static const double kalmanProcessNoise = 0.15;
  static const double kalmanInitialEstimateError = 1.0;
  static const double kalmanMinMeasurementNoise = 1.0;
  static const double kalmanMaxMeasurementNoise = 100.0;
  
  // UI & Layout
  static const double watermarkHeightRatio = 0.14;
  static const int watermarkMinHeight = 100;
  static const int watermarkMaxHeight = 180;
  static const int watermarkLineSpacing = 6;
  static const int watermarkMaxAddressLength = 42;
  
  // Performance
  static const Duration uiDebounceDelay = Duration(milliseconds: 100);
  static const int positionSampleLifespanSeconds = 15;
  static const int topSamplesForAveraging = 3;
  static const int maxErrorMessageLength = 50;
  
  // Temp File Cleanup
  static const Duration tempFileRetention = Duration(hours: 24);
  static const int addressCacheMaxSize = 20;
}

// ─────────────────────────────────────────────────────────────
// KALMAN FILTER
// ─────────────────────────────────────────────────────────────

class SimpleKalmanFilter {
  final double _processNoise;
  double _measurementNoise;
  double _errorCovariance;
  double? _stateEstimate;
  
  SimpleKalmanFilter({
    double q = CameraConstants.kalmanProcessNoise,
    double r = 10.0
  }) : _processNoise = q,
       _measurementNoise = r,
       _errorCovariance = CameraConstants.kalmanInitialEstimateError;
  
  double filter(double measurement, double measurementAccuracy) {
    _measurementNoise = measurementAccuracy.clamp(
      CameraConstants.kalmanMinMeasurementNoise,
      CameraConstants.kalmanMaxMeasurementNoise,
    );
    
    if (_stateEstimate == null) {
      _stateEstimate = measurement;
      return measurement;
    }
    
    _errorCovariance = _errorCovariance + _processNoise;
    final kalmanGain = _errorCovariance / (_errorCovariance + _measurementNoise);
    _stateEstimate = _stateEstimate! + kalmanGain * (measurement - _stateEstimate!);
    _errorCovariance = (1 - kalmanGain) * _errorCovariance;
    
    return _stateEstimate!;
  }
  
  void reset() {
    _errorCovariance = CameraConstants.kalmanInitialEstimateError;
    _stateEstimate = null;
  }
}

// ─────────────────────────────────────────────────────────────
// OPTIMIZED IMAGE PROCESSING
// ─────────────────────────────────────────────────────────────

class ImageProcessParams {
  final Uint8List imageBytes;
  final DateTime timestamp;
  final Position? position;
  final String address;
  final int quality;
  final int maxDimension;
  final String watermarkPosition;
  
  const ImageProcessParams({
    required this.imageBytes,
    required this.timestamp,
    this.position,
    required this.address,
    required this.quality,
    required this.maxDimension,
    required this.watermarkPosition,
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
  
  final int stripHeight = (src.height * CameraConstants.watermarkHeightRatio)
      .toInt()
      .clamp(CameraConstants.watermarkMinHeight, CameraConstants.watermarkMaxHeight);
  
  final isBottom = params.watermarkPosition != 'top';
  final y0 = isBottom ? src.height - stripHeight : 0;
  
  if (y0 < 0) return src;
  
  img.fillRect(
    src,
    x1: 0,
    y1: y0,
    x2: src.width - 1,
    y2: y0 + stripHeight - 1,
    color: img.ColorRgba8(0, 0, 0, 180),
  );
  
  final font = src.width > 1500 ? img.arial24 : img.arial14;
  final white = img.ColorRgba8(255, 255, 255, 255);
  final yellow = img.ColorRgba8(255, 200, 0, 255);
  final green = img.ColorRgba8(100, 220, 100, 255);
  
  final lineH = (stripHeight / 6).floor().clamp(14, 24);
  final y = y0 + CameraConstants.watermarkLineSpacing;
  
  if (y + lineH * 5 <= src.height) {
    img.drawString(src, 'TermulLog', font: font, x: 10, y: y, color: yellow);
    img.drawString(src, '$tanggal  $jam', font: font, x: 10, y: y + lineH, color: white);
    img.drawString(src, '$lat, $lon', font: font, x: 10, y: y + lineH * 2, color: white);
    img.drawString(src, 'Acc: $acc', font: font, x: 10, y: y + lineH * 3, 
      color: gpsAvailable ? green : white);
    
    final shortAddr = alamat.length > CameraConstants.watermarkMaxAddressLength 
        ? '${alamat.substring(0, CameraConstants.watermarkMaxAddressLength - 3)}...' 
        : alamat;
        
    if (shortAddr.isNotEmpty && y + lineH * 4 < src.height) {
      img.drawString(src, shortAddr, font: font, x: 10, y: y + lineH * 4, color: white);
    }
  }
  
  return src;
}

// ─────────────────────────────────────────────────────────────
// GPS BAR WIDGET
// ─────────────────────────────────────────────────────────────

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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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

// ─────────────────────────────────────────────────────────────
// MAIN CAMERA SCREEN
// ─────────────────────────────────────────────────────────────

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => false;

  // Camera
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isTakingPhoto = false;
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

  // GPS
  StreamSubscription<Position>? _gpsStream;
  Position? _bestPosition;
  bool _gpsReady = false;
  String _gpsText = '📍 Mencari GPS...';
  
  Timer? _gpsWatchdog;
  DateTime _lastGpsUpdate = DateTime.now();
  bool _isProcessingGps = false;
  int _gpsRestartCount = 0;
  
  final List<Position> _positionSamples = [];
  int _samplesCollected = 0;
  
  // GPS Polish
  bool _isPolishing = false;
  int _polishCountdown = CameraConstants.polishTimeoutPoorAccuracy;
  Timer? _countdownTimer;
  Completer<void>? _gpsCompleter;
  bool _isWaitingForGps = false;

  // Kalman
  final SimpleKalmanFilter _kalmanLat = SimpleKalmanFilter();
  final SimpleKalmanFilter _kalmanLon = SimpleKalmanFilter();
  bool _kalmanInitialized = false;

  // Performance
  bool _isWarmingUp = true;
  int _photoQuality = CameraConstants.photoQualityPercent;
  
  final Map<String, String> _addressCache = {};
  
  Timer? _uiUpdateTimer;
  
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    
    _initCamera();
    _startGpsTracking();
    _startGpsWatchdog();
    _cleanOldTempFiles();
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
  
  Future<void> _cleanOldTempFiles() async {
    try {
      final dir = await getTemporaryDirectory();
      final cutoff = DateTime.now().subtract(CameraConstants.tempFileRetention);
      
      final files = dir.listSync()
          .whereType<File>()
          .where((f) => path.basename(f.path).startsWith('termullog_'))
          .where((f) {
            try {
              return f.statSync().modified.isBefore(cutoff);
            } catch (_) {
              return false;
            }
          })
          .toList();
      
      for (final file in files) {
        try {
          await file.delete();
          debugPrint('Deleted old temp file: ${file.path}');
        } catch (e) {
          debugPrint('Failed to delete temp file: $e');
        }
      }
      
      if (files.isNotEmpty) {
        debugPrint('Cleaned up ${files.length} old temp files');
      }
    } catch (e) {
      debugPrint('Temp file cleanup error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _handleAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      _handleAppResumed();
    }
  }

  Future<void> _handleAppPaused() async {
    _gpsStream?.pause();
    _gpsWatchdog?.cancel();
    await _disposeCamera();
    if (mounted) {
      setState(() {
        _controller = null;
        _isInitialized = false;
      });
    }
  }

  Future<void> _handleAppResumed() async {
    if (_isResumingApp) return;
    _isResumingApp = true;
    
    if (mounted) {
      setState(() => _isWarmingUp = true);
    }
    
    _gpsStream?.resume();
    _startGpsWatchdog();
    
    await Future.delayed(CameraConstants.cameraReinitDelay);
    await _initCamera();
    
    _isResumingApp = false;
  }

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

  void _startGpsWatchdog() {
    _gpsWatchdog?.cancel();
    
    _gpsWatchdog = Timer.periodic(
      Duration(seconds: CameraConstants.gpsWatchdogIntervalSeconds),
      (_) async {
        if (_isDisposed) return;
        
        final last = DateTime.now().difference(_lastGpsUpdate);
        
        if (last.inSeconds > CameraConstants.gpsStaleAfterSeconds) {
          debugPrint('GPS Watchdog: Restarting GPS stream (${_gpsRestartCount + 1})');
          _gpsRestartCount++;
          await _gpsStream?.cancel();
          _startGpsTracking();
        }
      },
    );
  }

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
        distanceFilter: 5,
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
      ).timeout(Duration(seconds: CameraConstants.warmupGpsTimeoutSeconds));
      
      if (!_isDisposed && warmup != null) {
        if (warmup.accuracy <= CameraConstants.maxAcceptableAccuracyMeters && !warmup.isMocked) {
          _bestPosition = warmup;
          _positionSamples.add(warmup);
          _updateGpsText('🟡 GPS ±${warmup.accuracy.toStringAsFixed(0)}m');
        }
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
    
    _lastGpsUpdate = DateTime.now();
    
    final timestamp = pos.timestamp ?? DateTime.now();
    final now = DateTime.now();
    
    if (now.difference(timestamp).inSeconds > 5) return;
    
    if (pos.isMocked) return;
    if (pos.accuracy > CameraConstants.maxAcceptableAccuracyMeters) return;
    
    if (_isProcessingGps) return;
    _isProcessingGps = true;
    
    try {
      if (_bestPosition != null && _isOutlier(pos, _bestPosition!)) return;
      
      _positionSamples.removeWhere((p) {
        final ts = p.timestamp ?? now;
        return now.difference(ts).inSeconds > CameraConstants.positionSampleLifespanSeconds;
      });
      _positionSamples.add(pos);
      
      while (_positionSamples.length > CameraConstants.maxGpsSamples) {
        _positionSamples.removeAt(0);
      }
      
      _samplesCollected++;
      if (_samplesCollected < CameraConstants.minSamplesRequired) return;
      
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
      final isReady = acc <= CameraConstants.targetAccuracyMeters;
      
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
        final completer = _gpsCompleter;
        _isWaitingForGps = false;
        completer?.complete();
      }
    } finally {
      _isProcessingGps = false;
    }
  }
  
  void _debounceUiUpdate(VoidCallback callback) {
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = Timer(CameraConstants.uiDebounceDelay, callback);
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
    return speed > CameraConstants.outlierSpeedThresholdMs;
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
    final validSamples = _positionSamples
        .where((p) => p.accuracy < CameraConstants.maxValidAccuracyMeters)
        .toList();
        
    if (validSamples.length < CameraConstants.minSamplesRequired) {
      return _bestPosition;
    }
    
    final sorted = List<Position>.from(validSamples)
      ..sort((a, b) => a.accuracy.compareTo(b.accuracy));
    
    final medianIdx = sorted.length ~/ 2;
    final medianPos = sorted[medianIdx];
    
    final topN = sorted.take(CameraConstants.topSamplesForAveraging).toList();
    
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
    
    finalLat = (finalLat + medianPos.latitude) / 2;
    finalLon = (finalLon + medianPos.longitude) / 2;
    
    if (_kalmanInitialized) {
      finalLat = _kalmanLat.filter(finalLat, topN.first.accuracy);
      finalLon = _kalmanLon.filter(finalLon, topN.first.accuracy);
    }
    
    final avgAccuracy = topN.map((p) => p.accuracy).reduce((a, b) => a + b) / topN.length;
    
    return Position(
      latitude: finalLat,
      longitude: finalLon,
      accuracy: avgAccuracy,
      altitude: medianPos.altitude,
      altitudeAccuracy: medianPos.altitudeAccuracy,
      heading: medianPos.heading,
      headingAccuracy: medianPos.headingAccuracy,
      speed: medianPos.speed,
      speedAccuracy: medianPos.speedAccuracy,
      timestamp: DateTime.now(),
    );
  }

  int _adaptivePolishTimeout() {
    if (_bestPosition == null) {
      return CameraConstants.polishTimeoutPoorAccuracy;
    }
    
    final acc = _bestPosition!.accuracy;
    
    if (acc <= CameraConstants.accuracyGood) {
      return CameraConstants.polishTimeoutGoodAccuracy;
    }
    
    if (acc <= CameraConstants.accuracyMedium) {
      return CameraConstants.polishTimeoutMediumAccuracy;
    }
    
    return CameraConstants.polishTimeoutPoorAccuracy;
  }

  Future<void> _quickGpsRefresh() async {
    if (_bestPosition != null && _bestPosition!.accuracy <= 30) return;
    
    try {
      final fresh = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(Duration(seconds: CameraConstants.quickGpsTimeoutSeconds));
      
      if (!fresh.isMocked && 
          fresh.accuracy <= CameraConstants.maxAcceptableAccuracyMeters &&
          fresh.accuracy < (_bestPosition?.accuracy ?? 999)) {
        _bestPosition = fresh;
      }
    } catch (_) {}
  }
  
  Future<void> _ambilFoto() async {
    if (!_acquireLock()) return;
    
    try {
      final ctrl = _controller;
      if (ctrl == null || !ctrl.value.isInitialized) return;
      if (_isTakingPhoto || _isPolishing) return;
      if (ctrl.value.isTakingPicture) return;
      
      if (mounted) setState(() => _isTakingPhoto = true);
      
      HapticFeedback.lightImpact();
      
      XFile? capturedFile;
      await Future.wait([
        _quickGpsRefresh(),
        ctrl.takePicture()
            .timeout(CameraConstants.cameraTimeout)
            .then((file) => capturedFile = file)
      ]);
      
      if (capturedFile == null) {
        throw Exception('Failed to capture photo');
      }
      
      final XFile file = capturedFile!;
      final bytes = await File(file.path).readAsBytes();
      final DateTime waktuFoto = DateTime.now();
      
      if (mounted) {
        setState(() {
          _isTakingPhoto = false;
          _isPolishing = true;
          _polishCountdown = _adaptivePolishTimeout();
        });
      }
      
      await _waitForBestGps();
      
      if (!mounted || _isDisposed) return;
      
      final String alamat = _bestPosition != null
          ? await _getAddressCached(_bestPosition)
          : 'Lokasi tidak tersedia';
      
      final result = await compute(_processImageOptimized, ImageProcessParams(
        imageBytes: bytes,
        timestamp: waktuFoto,
        position: _bestPosition,
        address: alamat,
        quality: _photoQuality,
        maxDimension: CameraConstants.maxImageDimensionPx,
        watermarkPosition: WatermarkLayoutService.position,
      ));
      
      if (!mounted || _isDisposed) return;
      
      final dir = await getTemporaryDirectory();
      final outputPath = '${dir.path}/termullog_${waktuFoto.millisecondsSinceEpoch}.jpg';
      await File(outputPath).writeAsBytes(result.jpegData);
      
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
        final msg = e.toString();
        final shortMsg = msg.length <= CameraConstants.maxErrorMessageLength 
            ? msg 
            : '${msg.substring(0, CameraConstants.maxErrorMessageLength)}...';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $shortMsg')),
        );
      }
    } finally {
      _cleanupCapture();
    }
  }
  
  void _cleanupCapture() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    
    if (_gpsCompleter != null && !_gpsCompleter!.isCompleted) {
      _gpsCompleter!.complete();
    }
    _gpsCompleter = null;
    _isWaitingForGps = false;
    
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
        _bestPosition!.accuracy <= CameraConstants.targetAccuracyMeters) {
      return;
    }
    
    if (_isWaitingForGps) return;
    
    _isWaitingForGps = true;
    _gpsCompleter = Completer<void>();
    _startCountdown();
    
    final timeoutSeconds = _adaptivePolishTimeout();
    
    try {
      await _gpsCompleter!.future.timeout(
        Duration(seconds: timeoutSeconds),
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
    _polishCountdown = _adaptivePolishTimeout();
    
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
      
      if (_addressCache.length >= CameraConstants.addressCacheMaxSize) {
        _addressCache.remove(_addressCache.keys.first);
      }
      _addressCache[cacheKey] = address;
      
      return address;
    } catch (_) {
      return '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
    }
  }

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
                      Text(
                        _bestPosition != null 
                          ? 'Akurasi: ${_bestPosition!.accuracy.toStringAsFixed(0)}m dari target ${CameraConstants.targetAccuracyMeters.toStringAsFixed(0)}m'
                          : _gpsText,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 200,
                        child: LinearProgressIndicator(
                          value: _bestPosition != null 
                            ? (1 - (_bestPosition!.accuracy / 100)).clamp(0.0, 1.0)
                            : null,
                          backgroundColor: Colors.white24,
                          color: Colors.greenAccent,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '$_polishCountdown s',
                        style: const TextStyle(color: Colors.white60, fontSize: 11),
                      ),
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
