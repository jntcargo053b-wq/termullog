import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as path;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/camera_registry.dart';
import 'preview_screen_enhanced.dart'; // Pastikan file ini sudah didefinisikan

// ─────────────────────────────────────────────────────────────
// CONSTANTS & CONFIGURATION (hanya yang diperlukan)
// ─────────────────────────────────────────────────────────────

class CameraConstants {
  // GPS Configuration
  static const int gpsWatchdogIntervalSeconds = 15;
  static const int gpsStaleAfterSeconds = 25;
  
  // Accuracy thresholds
  static const double accuracyExcellent = 5.0;
  static const double accuracyTarget = 10.0;
  static const double accuracyGood = 15.0;
  static const double accuracyMedium = 25.0;
  static const double accuracyPoor = 40.0;
  static const double accuracyMax = 80.0;
  
  // GPS sampling
  static const double maxAcceptedAccuracyForSample = 30.0;
  static const double minAcceptableAccuracy = 25.0;
  static const double minDistanceChange = 2.0;
  
  static const int maxGpsSamples = 10;
  static const int minSamplesRequired = 3;
  static const int topSamplesForAveraging = 5;
  static const int positionSampleLifespanSeconds = 20;
  
  static const double outlierSpeedThresholdMs = 30.0;
  static const double maxHorizontalSpeedMs = 50.0;
  static const int quickGpsTimeoutSeconds = 2;
  static const int warmupGpsTimeoutSeconds = 3;
  
  // GPS Polishing
  static const int polishTimeoutGoodAccuracy = 3;
  static const int polishTimeoutMediumAccuracy = 7;
  static const int polishTimeoutPoorAccuracy = 15;
  
  // Camera
  static const Duration cameraTimeout = Duration(seconds: 5);
  static const Duration cameraReinitDelay = Duration(milliseconds: 300);
  
  // Performance
  static const Duration uiDebounceDelay = Duration(milliseconds: 100);
  static const int maxErrorMessageLength = 50;
  
  // Temp file
  static const Duration tempFileRetention = Duration(hours: 24);
  
  // GPS Health Check
  static const int lowAccuracyCheckDelaySeconds = 5;
  static const double lowAccuracyThreshold = 30.0;
  
  // Pre-warm
  static const int preWarmDelayMs = 800;
}

// ─────────────────────────────────────────────────────────────
// KALMAN FILTER (DINONAKTIFKAN)
// ─────────────────────────────────────────────────────────────

class SimpleKalmanFilter {
  final double _processNoise;
  double _measurementNoise;
  double _errorCovariance;
  double? _stateEstimate;
  
  SimpleKalmanFilter({double q = 0.12, double r = 8.0})
      : _processNoise = q,
        _measurementNoise = r,
        _errorCovariance = 1.0;
  
  double filter(double measurement, double measurementAccuracy) => measurement;
  void reset() {
    _errorCovariance = 1.0;
    _stateEstimate = null;
  }
}

// ─────────────────────────────────────────────────────────────
// GPS BAR WIDGET
// ─────────────────────────────────────────────────────────────

class GpsBar extends StatelessWidget {
  final bool gpsReady;
  final String gpsText;
  final Position? bestPosition;
  
  const GpsBar({super.key, required this.gpsReady, required this.gpsText, this.bestPosition});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Icon(gpsReady ? Icons.gps_fixed : Icons.gps_not_fixed,
              color: gpsReady ? Colors.greenAccent : Colors.amber, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              bestPosition != null
                  ? '${bestPosition!.latitude.toStringAsFixed(5)}, ${bestPosition!.longitude.toStringAsFixed(5)}'
                  : 'No GPS',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(gpsText, style: TextStyle(color: gpsReady ? Colors.greenAccent : Colors.amber, fontSize: 10)),
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
  void _releaseLock() => _captureLocked = false;

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
  
  bool _isPolishing = false;
  int _polishCountdown = CameraConstants.polishTimeoutPoorAccuracy;
  Timer? _countdownTimer;
  Completer<void>? _gpsCompleter;
  bool _isWaitingForGps = false;

  bool _isLocationServiceDisabled = false;
  bool _hasShownLowAccuracyDialog = false;

  final SimpleKalmanFilter _kalmanLat = SimpleKalmanFilter();
  final SimpleKalmanFilter _kalmanLon = SimpleKalmanFilter();
  bool _kalmanInitialized = false;

  bool _isWarmingUp = true;
  Timer? _uiUpdateTimer;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    
    _initCamera();
    _preWarmGps();
    _startGpsTracking();
    _startGpsWatchdog();
    _cleanOldTempFiles();
    _showBatteryOptimizationDialog();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _uiUpdateTimer?.cancel();
    _countdownTimer?.cancel();
    _gpsWatchdog?.cancel();
    _gpsStream?.cancel().then((_) => _gpsStream = null).catchError((_) {});
    if (_gpsCompleter != null && !_gpsCompleter!.isCompleted) _gpsCompleter!.complete();
    _positionSamples.clear();
    _disposeCamera();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _preWarmGps() async {
    try {
      debugPrint('Pre-warming GPS...');
      await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best).timeout(const Duration(seconds: 3));
      await Future.delayed(const Duration(milliseconds: CameraConstants.preWarmDelayMs));
      await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best).timeout(const Duration(seconds: 3));
      debugPrint('GPS pre-warm complete');
    } catch (e) {
      debugPrint('Pre-warm GPS error: $e');
    }
  }

  Future<void> _showBatteryOptimizationDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyShown = prefs.getBool('battery_opt_dialog_shown') ?? false;
    if (alreadyShown) return;
    await Future.delayed(const Duration(seconds: 3));
    if (mounted && !alreadyShown) {
      await prefs.setBool('battery_opt_dialog_shown', true);
      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => AlertDialog(
          title: const Text('Optimalkan Akurasi GPS'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Untuk akurasi GPS maksimal:'),
              SizedBox(height: 12),
              Text('• Matikan battery optimization untuk aplikasi ini'),
              Text('• Izinkan akses lokasi "Selalu"'),
              Text('• Aktifkan High Accuracy Mode'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Nanti')),
            ElevatedButton(
              onPressed: () async {
                await Geolocator.openAppSettings();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Buka Setting'),
            ),
          ],
        ),
      );
    }
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
            try { return f.statSync().modified.isBefore(cutoff); } catch (_) { return false; }
          }).toList();
      for (final file in files) { try { await file.delete(); } catch (_) {} }
      if (files.isNotEmpty) debugPrint('Cleaned ${files.length} temp files');
    } catch (e) { debugPrint('Temp file cleanup error: $e'); }
  }

  void _checkLowAccuracyAndNotify() {
    if (_hasShownLowAccuracyDialog) return;
    Future.delayed(const Duration(seconds: CameraConstants.lowAccuracyCheckDelaySeconds), () {
      if (_isDisposed || !mounted) return;
      if (_bestPosition != null && _bestPosition!.accuracy > CameraConstants.lowAccuracyThreshold && !_hasShownLowAccuracyDialog) {
        _hasShownLowAccuracyDialog = true;
        _showAccuracyDialogIfNeeded();
      }
    });
  }

  Future<void> _showAccuracyDialogIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyShown = prefs.getBool('gps_dialog_shown') ?? false;
    if (alreadyShown || !mounted) return;
    await prefs.setBool('gps_dialog_shown', true);
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        title: const Text('Tingkatkan Akurasi GPS'),
        content: const Text('Aktifkan High Accuracy Mode di pengaturan lokasi untuk hasil terbaik.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup')),
          ElevatedButton(
            onPressed: () async {
              await Geolocator.openLocationSettings();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Buka Setting'),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed) return;
    if (state == AppLifecycleState.paused) _handleAppPaused();
    else if (state == AppLifecycleState.resumed) _handleAppResumed();
  }

  Future<void> _handleAppPaused() async {
    _gpsStream?.pause();
    _gpsWatchdog?.cancel();
    await _disposeCamera();
    if (mounted) setState(() { _controller = null; _isInitialized = false; });
  }

  Future<void> _handleAppResumed() async {
    if (_isResumingApp) return;
    _isResumingApp = true;
    if (mounted) setState(() => _isWarmingUp = true);
    _gpsStream?.resume();
    _startGpsWatchdog();
    await Future.delayed(CameraConstants.cameraReinitDelay);
    await _initCamera();
    _isResumingApp = false;
  }

  Future<void> _initCamera() async {
    if (_isReinitializingCamera || _isDisposed) return;
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
      if (mounted) setState(() { _isInitialized = true; _isWarmingUp = false; });
    } catch (e) {
      debugPrint('Camera init error: $e');
      _controller = null;
    } finally {
      _isReinitializingCamera = false;
    }
  }

  void _startGpsWatchdog() {
    _gpsWatchdog?.cancel();
    _gpsWatchdog = Timer.periodic(Duration(seconds: CameraConstants.gpsWatchdogIntervalSeconds), (_) async {
      if (_isDisposed) return;
      final last = DateTime.now().difference(_lastGpsUpdate);
      if (last.inSeconds > CameraConstants.gpsStaleAfterSeconds) {
        debugPrint('GPS Watchdog: Restarting GPS stream (${_gpsRestartCount + 1})');
        _gpsRestartCount++;
        await _gpsStream?.cancel();
        _startGpsTracking();
      }
    });
  }

  Future<void> _startGpsTracking() async {
    if (_isDisposed) return;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _isLocationServiceDisabled = true);
        _updateGpsText('❌ GPS tidak aktif');
        return;
      } else {
        if (mounted) setState(() => _isLocationServiceDisabled = false);
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _updateGpsText('❌ Izin GPS ditolak');
        return;
      }

      _warmupGps();
      _checkLowAccuracyAndNotify();

      final locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(milliseconds: 700),
        forceLocationManager: false,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'GPS aktif',
          notificationText: 'Mengoptimalkan akurasi lokasi',
          enableWakeLock: true,
        ),
      );

      await _gpsStream?.cancel();
      _gpsStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        _onGpsData,
        onError: (error) => debugPrint('GPS Error: $error'),
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('GPS Init Error: $e');
    }
  }

  void _warmupGps() async {
    try {
      final warmup = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best)
          .timeout(Duration(seconds: CameraConstants.warmupGpsTimeoutSeconds));
      if (!_isDisposed && warmup != null && warmup.accuracy <= CameraConstants.accuracyMax && !warmup.isMocked) {
        if (warmup.accuracy <= CameraConstants.minAcceptableAccuracy) {
          _bestPosition = warmup;
          _positionSamples.add(warmup);
          _updateGpsText('🟡 GPS ±${warmup.accuracy.toStringAsFixed(0)}m');
        }
      }
    } catch (_) {}
  }

  void _updateGpsText(String text) {
    if (_isDisposed) return;
    if (mounted) setState(() => _gpsText = text);
  }

  void _onGpsData(Position pos) {
    if (_isDisposed) return;
    _lastGpsUpdate = DateTime.now();
    final timestamp = pos.timestamp ?? DateTime.now();
    final now = DateTime.now();
    if (now.difference(timestamp).inSeconds > 5) return;
    if (pos.isMocked) return;
    if (pos.accuracy > CameraConstants.maxAcceptedAccuracyForSample) return;
    if (pos.speed > CameraConstants.maxHorizontalSpeedMs) return;
    
    if (_bestPosition != null) {
      final dist = _calculateDistance(_bestPosition!.latitude, _bestPosition!.longitude, pos.latitude, pos.longitude);
      if (dist < CameraConstants.minDistanceChange && pos.accuracy > _bestPosition!.accuracy) return;
    }
    
    if (_isProcessingGps) return;
    _isProcessingGps = true;
    try {
      if (_bestPosition != null && _isOutlier(pos, _bestPosition!)) return;
      
      _positionSamples.removeWhere((p) {
        final ts = p.timestamp ?? now;
        return now.difference(ts).inSeconds > CameraConstants.positionSampleLifespanSeconds;
      });
      _positionSamples.add(pos);
      while (_positionSamples.length > CameraConstants.maxGpsSamples) _positionSamples.removeAt(0);
      
      _samplesCollected++;
      if (_samplesCollected < CameraConstants.minSamplesRequired) return;
      
      final averaged = _averageBestPositions();
      if (averaged == null) return;
      
      if (_bestPosition == null || averaged.accuracy < _bestPosition!.accuracy) _bestPosition = averaged;
      
      final acc = _bestPosition!.accuracy;
      final isReady = acc <= CameraConstants.accuracyTarget;
      
      _debounceUiUpdate(() {
        if (_isDisposed) return;
        setState(() {
          _gpsReady = isReady;
          if (acc <= CameraConstants.accuracyExcellent) {
            _gpsText = '🟢 GPS Sangat Akurat ±${acc.toStringAsFixed(0)}m ✨';
          } else if (acc <= CameraConstants.accuracyTarget) {
            _gpsText = '🟢 GPS ±${acc.toStringAsFixed(0)}m';
          } else if (acc <= CameraConstants.accuracyGood) {
            _gpsText = '🟡 GPS ±${acc.toStringAsFixed(0)}m';
          } else if (acc <= CameraConstants.accuracyMedium) {
            _gpsText = '🟠 ±${acc.toStringAsFixed(0)}m';
          } else {
            _gpsText = '🔴 ±${acc.toStringAsFixed(0)}m';
          }
        });
      });
      
      if (_isWaitingForGps && _gpsCompleter != null && !_gpsCompleter!.isCompleted && isReady) {
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
    final distance = _calculateDistance(lastPos.latitude, lastPos.longitude, newPos.latitude, newPos.longitude);
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
    final validSamples = _positionSamples.where((p) => p.accuracy <= CameraConstants.maxAcceptedAccuracyForSample).toList();
    if (validSamples.length < CameraConstants.minSamplesRequired) return _bestPosition;
    
    final sorted = List<Position>.from(validSamples)..sort((a, b) => a.accuracy.compareTo(b.accuracy));
    final medianPos = sorted[sorted.length ~/ 2];
    final topN = sorted.take(CameraConstants.topSamplesForAveraging).toList();
    
    double totalWeight = 0, weightedLat = 0, weightedLon = 0;
    for (final p in topN) {
      final weight = 1.0 / p.accuracy;
      totalWeight += weight;
      weightedLat += p.latitude * weight;
      weightedLon += p.longitude * weight;
    }
    double finalLat = weightedLat / totalWeight;
    double finalLon = weightedLon / totalWeight;
    finalLat = (finalLat + medianPos.latitude) / 2;
    finalLon = (finalLon + medianPos.longitude) / 2;
    
    final accuracies = topN.map((e) => e.accuracy).toList()..sort();
    final medianAccuracy = accuracies[accuracies.length ~/ 2];
    
    return Position(
      latitude: finalLat,
      longitude: finalLon,
      accuracy: medianAccuracy,
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
    if (_bestPosition == null) return CameraConstants.polishTimeoutPoorAccuracy;
    final acc = _bestPosition!.accuracy;
    if (acc <= CameraConstants.accuracyGood) return CameraConstants.polishTimeoutGoodAccuracy;
    if (acc <= CameraConstants.accuracyMedium) return CameraConstants.polishTimeoutMediumAccuracy;
    return CameraConstants.polishTimeoutPoorAccuracy;
  }

  Future<void> _quickGpsRefresh() async {
    if (_bestPosition != null && _bestPosition!.accuracy <= CameraConstants.accuracyGood) return;
    try {
      final fresh = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best)
          .timeout(Duration(seconds: CameraConstants.quickGpsTimeoutSeconds));
      if (!fresh.isMocked && fresh.accuracy <= CameraConstants.minAcceptableAccuracy &&
          fresh.accuracy < (_bestPosition?.accuracy ?? 999)) {
        _bestPosition = fresh;
      }
    } catch (_) {}
  }

  // ====================== PERUBAHAN UTAMA ======================
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
        ctrl.takePicture().timeout(CameraConstants.cameraTimeout).then((f) => capturedFile = f),
      ]);
      if (capturedFile == null) throw Exception('Failed to capture photo');
      final bytes = await File(capturedFile!.path).readAsBytes();
      final waktuFoto = DateTime.now();
      
      // Tunggu GPS maksimal 2 detik agar tidak terasa lama
      await _waitForBestGps().timeout(const Duration(seconds: 2), onTimeout: () {});
      
      if (mounted) {
        setState(() {
          _isTakingPhoto = false;
          _isPolishing = true;
        });
      }
      
      // Langsung navigasi ke PreviewScreen dengan data mentah
      if (!mounted || _isDisposed) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreviewScreen(
            imageBytes: bytes,
            timestamp: waktuFoto,
            position: _bestPosition,
          ),
        ),
      );
      
      if (mounted) setState(() => _isPolishing = false);
      if (mounted && _controller == null) await _initCamera();
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) {
        final msg = e.toString();
        final shortMsg = msg.length <= CameraConstants.maxErrorMessageLength ? msg : '${msg.substring(0, CameraConstants.maxErrorMessageLength)}...';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $shortMsg')));
      }
    } finally {
      _cleanupCapture();
    }
  }

  void _cleanupCapture() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (_gpsCompleter != null && !_gpsCompleter!.isCompleted) _gpsCompleter!.complete();
    _gpsCompleter = null;
    _isWaitingForGps = false;
    if (mounted && !_isDisposed) setState(() { _isTakingPhoto = false; _isPolishing = false; });
    _releaseLock();
  }

  Future<void> _waitForBestGps() async {
    if (_isDisposed) return;
    if (_gpsReady && _bestPosition != null && _bestPosition!.accuracy <= CameraConstants.accuracyTarget) return;
    if (_isWaitingForGps) return;
    _isWaitingForGps = true;
    _gpsCompleter = Completer<void>();
    _startCountdown();
    final timeoutSeconds = _adaptivePolishTimeout();
    try {
      await _gpsCompleter!.future.timeout(Duration(seconds: timeoutSeconds), onTimeout: () {
        if (_gpsCompleter != null && !_gpsCompleter!.isCompleted) _gpsCompleter!.complete();
      });
    } finally {
      _isWaitingForGps = false;
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _polishCountdown = _adaptivePolishTimeout();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed || !mounted) { timer.cancel(); return; }
      setState(() => _polishCountdown--);
      if (_polishCountdown <= 0) {
        timer.cancel();
        if (_gpsCompleter != null && !_gpsCompleter!.isCompleted) _gpsCompleter!.complete();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
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
            if (_isLocationServiceDisabled)
              Positioned(
                top: 40, left: 16, right: 16,
                child: Material(
                  elevation: 2,
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.red.shade800,
                  child: InkWell(
                    onTap: () => Geolocator.openLocationSettings(),
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.location_off, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Expanded(child: Text('Lokasi tidak aktif — Ketuk untuk mengaktifkan', style: TextStyle(color: Colors.white, fontSize: 12))),
                          Icon(Icons.chevron_right, color: Colors.white, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: _isLocationServiceDisabled ? 90 : 0,
              left: 0, right: 0,
              child: GpsBar(gpsReady: _gpsReady, gpsText: _gpsText, bestPosition: _bestPosition),
            ),
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
                            ? 'Akurasi: ±${_bestPosition!.accuracy.toStringAsFixed(0)}m'
                            : _gpsText,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      Text('$_polishCountdown s', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            if (!_isPolishing && !_isWarmingUp)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  color: Colors.black87,
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white, size: 28)),
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
                              ? const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
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
