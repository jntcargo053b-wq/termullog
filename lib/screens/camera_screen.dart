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
import '../services/location_weather_service.dart';
import 'preview_screen_enhanced.dart';
import 'settings_screen.dart';

// ============================================================
// Constants
// ============================================================
class CameraConstants {
  static const int gpsWatchdogIntervalSeconds = 15;
  static const int gpsStaleAfterSeconds = 25;
  static const double accuracyTarget = 10.0;
  static const double accuracyGood = 15.0;
  static const double accuracyMedium = 25.0;
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
  static const int polishTimeoutGoodAccuracy = 3;
  static const int polishTimeoutMediumAccuracy = 7;
  static const int polishTimeoutPoorAccuracy = 15;
  static const Duration cameraTimeout = Duration(seconds: 5);
  static const Duration cameraReinitDelay = Duration(milliseconds: 300);
  static const Duration uiDebounceDelay = Duration(milliseconds: 100);
  static const int maxErrorMessageLength = 50;
  static const Duration tempFileRetention = Duration(hours: 24);
  static const int lowAccuracyCheckDelaySeconds = 5;
  static const double lowAccuracyThreshold = 30.0;
  static const int preWarmDelayMs = 800;
  static const double accuracyMax = 80.0;
  static const int addressCacheMaxSize = 20;
}

// ============================================================
// GPS Bar Widget (alamat real-time)
// ============================================================
class GpsBar extends StatelessWidget {
  final bool gpsReady;
  final String gpsText;
  final Position? bestPosition;
  final String address;

  const GpsBar({
    super.key,
    required this.gpsReady,
    required this.gpsText,
    this.bestPosition,
    this.address = '',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                      ? '${bestPosition!.latitude.toStringAsFixed(5)}, ${bestPosition!.longitude.toStringAsFixed(5)}'
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
          if (address.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                address,
                style: const TextStyle(color: Colors.white54, fontSize: 10),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// CameraScreen (StatefulWidget)
// ============================================================
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  // Camera
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isTakingPhoto = false;
  bool _isReinitializingCamera = false;
  bool _isResumingApp = false;
  bool _captureLocked = false;
  String? _cameraError;

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
  bool _isWarmingUp = true;
  Timer? _uiUpdateTimer;
  bool _isDisposed = false;

  // Address real-time & cache
  final Map<String, String> _addressCache = {};
  String _currentAddress = '';
  Timer? _addressFetchTimer;

  // Prefetch untuk keperluan preview (cached address & weather)
  String? _cachedAddress;
  String? _cachedWeather;
  DateTime? _lastFetchTime;

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
    _addressFetchTimer?.cancel();
    _isDisposed = true;
    _uiUpdateTimer?.cancel();
    _countdownTimer?.cancel();
    _gpsWatchdog?.cancel();
    _gpsStream?.cancel().then((_) => _gpsStream = null).catchError((_) {});
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

  // ============================================================
  // Helper Methods
  // ============================================================

  void _showCameraErrorDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Kamera Error'),
        content: const Text(
            'Tidak dapat mengakses kamera. Pastikan:\n\n1. Izin kamera sudah diberikan\n2. Tidak ada aplikasi lain yang menggunakan kamera\n3. Restart aplikasi'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openAppSettings();
            },
            child: const Text('Buka Setting'),
          ),
        ],
      ),
    );
  }

  Future<void> _preWarmGps() async {
    try {
      await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best)
          .timeout(const Duration(seconds: 3));
      await Future.delayed(const Duration(milliseconds: CameraConstants.preWarmDelayMs));
      await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best)
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<void> _showBatteryOptimizationDialog() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('battery_opt_dialog_shown') == true) return;
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    await prefs.setBool('battery_opt_dialog_shown', true);
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Optimalkan Akurasi GPS'),
        content: const Text(
          'Matikan battery optimization untuk aplikasi ini, '
          'izinkan lokasi "Selalu", dan aktifkan High Accuracy Mode.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Nanti'),
          ),
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
          }).toList();
      int deletedCount = 0;
      for (final f in files) {
        try {
          await f.delete();
          deletedCount++;
        } catch (_) {}
      }
      if (deletedCount > 0) debugPrint('Cleaned up $deletedCount old temp files');
    } catch (e) {
      debugPrint('Temp file cleanup error: $e');
    }
  }

  void _updateGpsText(String text) {
    if (mounted) setState(() => _gpsText = text);
  }

  // ============================================================
  // GPS Tracking
  // ============================================================

  Future<void> _startGpsTracking() async {
    if (_isDisposed) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _isLocationServiceDisabled = true);
        _updateGpsText('❌ GPS tidak aktif');
        return;
      } else {
        if (mounted) setState(() => _isLocationServiceDisabled = false);
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _updateGpsText('❌ Izin GPS ditolak');
        return;
      }

      // Reset sample counter ketika restart
      _samplesCollected = 0;
      _positionSamples.clear();

      _warmupGps();
      _checkLowAccuracyAndNotify();

      final settings = AndroidSettings(
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
      _gpsStream = Geolocator.getPositionStream(locationSettings: settings).listen(
        _onGpsData,
        onError: (e) => debugPrint('GPS Error: $e'),
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('GPS Init Error: $e');
    }
  }

  // _warmupGps TIDAK LANGSUNG SET _bestPosition
  void _warmupGps() async {
    try {
      final warmup = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best)
          .timeout(Duration(seconds: CameraConstants.warmupGpsTimeoutSeconds));
      if (!_isDisposed && warmup.accuracy <= CameraConstants.accuracyMax && !warmup.isMocked) {
        _positionSamples.add(warmup);
        _samplesCollected++;
        _updateGpsText('🟡 GPS ±${warmup.accuracy.toStringAsFixed(0)}m');
      }
    } catch (_) {}
  }

  void _startGpsWatchdog() {
    _gpsWatchdog?.cancel();
    _gpsWatchdog = Timer.periodic(
        Duration(seconds: CameraConstants.gpsWatchdogIntervalSeconds), (_) async {
      if (_isDisposed) return;
      if (DateTime.now().difference(_lastGpsUpdate).inSeconds > CameraConstants.gpsStaleAfterSeconds) {
        _gpsRestartCount++;
        await _gpsStream?.cancel();
        _startGpsTracking();
      }
    });
  }

  // Ambil alamat real-time (debounced, dengan cache)
  Future<void> _fetchAddressForCurrentPosition() async {
    if (_bestPosition == null) return;
    final pos = _bestPosition!;

    final cacheKey = '${pos.latitude.toStringAsFixed(3)},${pos.longitude.toStringAsFixed(3)}';
    if (_addressCache.containsKey(cacheKey)) {
      if (_currentAddress != _addressCache[cacheKey]!) {
        setState(() => _currentAddress = _addressCache[cacheKey]!);
      }
      return;
    }

    _addressFetchTimer?.cancel();
    _addressFetchTimer = Timer(const Duration(milliseconds: 800), () async {
      try {
        final result = await LocationWeatherService.fetchFromPosition(pos);
        final addr = result.address;
        if (mounted && addr.isNotEmpty && !addr.startsWith('GPS:')) {
          setState(() => _currentAddress = addr);
          if (_addressCache.length >= CameraConstants.addressCacheMaxSize) {
            _addressCache.remove(_addressCache.keys.first);
          }
          _addressCache[cacheKey] = addr;
        } else {
          if (mounted) setState(() => _currentAddress = '');
        }
      } catch (e) {
        debugPrint('Real-time address error: $e');
        if (mounted) setState(() => _currentAddress = '');
      }
    });
  }

  void _onGpsData(Position pos) {
    if (_isDisposed) return;
    _lastGpsUpdate = DateTime.now();

    final timestamp = pos.timestamp;
    if (timestamp == null) return;
    final now = DateTime.now();
    if (now.difference(timestamp).inSeconds > 5) return;
    if (pos.isMocked) return;
    if (pos.accuracy > CameraConstants.maxAcceptedAccuracyForSample) return;
    if (pos.speed > CameraConstants.maxHorizontalSpeedMs) return;

    if (_bestPosition != null) {
      final dist = _calculateDistance(
        _bestPosition!.latitude, _bestPosition!.longitude,
        pos.latitude, pos.longitude,
      );
      if (dist < CameraConstants.minDistanceChange && pos.accuracy > _bestPosition!.accuracy) return;
    }

    try {
      if (_bestPosition != null && _isOutlier(pos, _bestPosition!)) return;

      final now2 = DateTime.now();
      _positionSamples.removeWhere((p) =>
          now2.difference(p.timestamp ?? now2).inSeconds > CameraConstants.positionSampleLifespanSeconds);
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
        // Setelah _bestPosition berubah, ambil alamat realtime
        _fetchAddressForCurrentPosition();
      }

      final acc = _bestPosition!.accuracy;
      final isReady = acc <= CameraConstants.accuracyTarget;

      _debounceUiUpdate(() {
        if (mounted) setState(() {
          _gpsReady = isReady;
          _gpsText = isReady
              ? '🟢 GPS ±${acc.toStringAsFixed(0)}m'
              : '🟡 ±${acc.toStringAsFixed(0)}m';
        });
      });

      if (_isWaitingForGps && _gpsCompleter != null && !_gpsCompleter!.isCompleted && isReady) {
        final c = _gpsCompleter;
        _isWaitingForGps = false;
        c?.complete();
      }

      // Simpan ke cache untuk preview (address sudah di-fetch oleh _fetchAddressForCurrentPosition)
      if (pos.accuracy <= 20 && _currentAddress.isNotEmpty) {
        _cachedAddress = _currentAddress;
        _lastFetchTime = DateTime.now();
        // Weather bisa di-fetch sesekali, tetapi tidak wajib untuk preview
      }
    } catch (e) {
      debugPrint('GPS data error: $e');
    }
  }

  void _debounceUiUpdate(VoidCallback fn) {
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = Timer(CameraConstants.uiDebounceDelay, fn);
  }

  bool _isOutlier(Position newPos, Position lastPos) {
    final distance = _calculateDistance(
      lastPos.latitude, lastPos.longitude,
      newPos.latitude, newPos.longitude,
    );
    final timeDiff = (newPos.timestamp ?? DateTime.now())
        .difference(lastPos.timestamp ?? DateTime.now())
        .inSeconds
        .abs();
    if (timeDiff == 0) return false;
    final speed = distance / timeDiff;
    return speed > CameraConstants.outlierSpeedThresholdMs;
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  Position? _averageBestPositions() {
    final valid = _positionSamples
        .where((p) => p.accuracy <= CameraConstants.maxAcceptedAccuracyForSample)
        .toList();
    if (valid.length < CameraConstants.minSamplesRequired) return _bestPosition;

    final sorted = List<Position>.from(valid)..sort((a, b) => a.accuracy.compareTo(b.accuracy));
    final medianPos = sorted[sorted.length ~/ 2];
    final topN = sorted.take(CameraConstants.topSamplesForAveraging).toList();

    double tw = 0, wlat = 0, wlon = 0;
    for (final p in topN) {
      final w = 1.0 / p.accuracy;
      tw += w;
      wlat += p.latitude * w;
      wlon += p.longitude * w;
    }
    double lat = wlat / tw;
    double lon = wlon / tw;
    lat = (lat + medianPos.latitude) / 2;
    lon = (lon + medianPos.longitude) / 2;

    final accs = topN.map((e) => e.accuracy).toList()..sort();
    final medAcc = accs[accs.length ~/ 2];

    return Position(
      latitude: lat,
      longitude: lon,
      accuracy: medAcc,
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
      if (!fresh.isMocked &&
          fresh.accuracy <= CameraConstants.minAcceptableAccuracy &&
          fresh.accuracy < (_bestPosition?.accuracy ?? 999)) {
        _bestPosition = fresh;
      }
    } catch (_) {}
  }

  void _checkLowAccuracyAndNotify() {
    if (_hasShownLowAccuracyDialog) return;
    Future.delayed(Duration(seconds: CameraConstants.lowAccuracyCheckDelaySeconds), () {
      if (_isDisposed || !mounted) return;
      if (_bestPosition != null &&
          _bestPosition!.accuracy > CameraConstants.lowAccuracyThreshold &&
          !_hasShownLowAccuracyDialog) {
        _hasShownLowAccuracyDialog = true;
        _showAccuracyDialogIfNeeded();
      }
    });
  }

  Future<void> _showAccuracyDialogIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('gps_dialog_shown') == true) return;
    if (!mounted) return;
    await prefs.setBool('gps_dialog_shown', true);
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tingkatkan Akurasi GPS'),
        content: const Text('Aktifkan High Accuracy Mode di pengaturan lokasi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
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

  // ============================================================
  // Camera & Capture
  // ============================================================

  Future<void> _initCamera() async {
    if (_isReinitializingCamera || _isDisposed) return;
    if (CameraRegistry.cameras.isEmpty) {
      _cameraError = 'Tidak ada kamera yang tersedia';
      _showCameraErrorDialog();
      return;
    }

    _isReinitializingCamera = true;
    try {
      if (_controller != null && _controller!.value.isInitialized) return;
      final camera = CameraRegistry.cameras.first;
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _controller = controller;
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
      _cameraError = null;
      if (mounted) setState(() {
        _isInitialized = true;
        _isWarmingUp = false;
      });
    } catch (e) {
      debugPrint('Camera init error: $e');
      _cameraError = e.toString();
      _controller = null;
      if (mounted) {
        _showCameraErrorDialog();
        setState(() => _isWarmingUp = false);
      }
    } finally {
      _isReinitializingCamera = false;
    }
  }

  Future<void> _disposeCamera() async {
    try {
      await _controller?.dispose();
    } catch (e) {
      debugPrint('Dispose camera error: $e');
    }
    _controller = null;
  }

  Future<void> _handleAppPaused() async {
    _gpsStream?.pause();
    _gpsWatchdog?.cancel();
    await _disposeCamera();
    if (mounted) setState(() {
      _controller = null;
      _isInitialized = false;
    });
  }

  Future<void> _handleAppResumed() async {
    if (_isResumingApp) return;
    _isResumingApp = true;
    if (mounted) setState(() => _isWarmingUp = true);
    _gpsStream?.resume();
    _startGpsWatchdog();
    await Future.delayed(CameraConstants.cameraReinitDelay);
    try {
      await _initCamera();
    } catch (e) {
      debugPrint('Resume camera error: $e');
      if (mounted) setState(() => _isWarmingUp = false);
    }
    _isResumingApp = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _handleAppPaused();
    else if (state == AppLifecycleState.resumed) _handleAppResumed();
  }

  Future<void> _waitForBestGps() async {
    if (_isDisposed) return;
    if (_gpsReady && _bestPosition != null && _bestPosition!.accuracy <= CameraConstants.accuracyTarget) return;
    if (_isWaitingForGps) return;
    _isWaitingForGps = true;
    _gpsCompleter = Completer<void>();
    _startCountdown();
    final timeout = _adaptivePolishTimeout();
    try {
      await _gpsCompleter!.future.timeout(Duration(seconds: timeout), onTimeout: () {
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
      if (_isDisposed || !mounted) {
        timer.cancel();
        return;
      }
      setState(() => _polishCountdown--);
      if (_polishCountdown <= 0) {
        timer.cancel();
        if (_gpsCompleter != null && !_gpsCompleter!.isCompleted) _gpsCompleter!.complete();
      }
    });
  }

  // Cache sederhana untuk alamat (fallback)
  Future<String> _getAddressCached(Position? pos) async {
    if (pos == null) return 'Lokasi tidak tersedia';
    final cacheKey = '${pos.latitude.toStringAsFixed(3)},${pos.longitude.toStringAsFixed(3)}';
    if (_addressCache.containsKey(cacheKey)) return _addressCache[cacheKey]!;

    try {
      final result = await LocationWeatherService.fetchFromPosition(pos);
      final address = result.address;
      if (_addressCache.length >= CameraConstants.addressCacheMaxSize) {
        _addressCache.remove(_addressCache.keys.first);
      }
      _addressCache[cacheKey] = address;
      return address;
    } catch (_) {
      return '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
    }
  }

  Future<void> _ambilFoto() async {
    if (!_acquireLock()) return;
    try {
      final ctrl = _controller;
      if (ctrl == null || !ctrl.value.isInitialized) {
        _showCameraErrorDialog();
        return;
      }
      if (_isTakingPhoto || _isPolishing) return;
      if (ctrl.value.isTakingPicture) return;

      // Tampilkan overlay polishing SEBELUM capture
      if (mounted) setState(() {
        _isTakingPhoto = true;
        _isPolishing = true;
      });
      HapticFeedback.lightImpact();

      // Mulai countdown (akan di-update oleh _startCountdown)
      _startCountdown();

      XFile? capturedFile;
      await Future.wait([
        _quickGpsRefresh(),
        ctrl.takePicture().timeout(CameraConstants.cameraTimeout).then((f) => capturedFile = f),
      ]);
      if (capturedFile == null) throw Exception('Gagal mengambil foto');
      final bytes = await File(capturedFile!.path).readAsBytes();
      final waktuFoto = DateTime.now();

      // Tunggu GPS dengan adaptive timeout (tanpa override 2 detik)
      await _waitForBestGps();

      // Gunakan alamat yang sudah di-fetch realtime (atau cached)
      String alamat;
      if (_currentAddress.isNotEmpty) {
        alamat = _currentAddress;
      } else if (_cachedAddress != null &&
          _lastFetchTime != null &&
          DateTime.now().difference(_lastFetchTime!) < const Duration(minutes: 5)) {
        alamat = _cachedAddress!;
      } else {
        alamat = await _getAddressCached(_bestPosition);
      }

      final cuaca = _cachedWeather ?? '';

      if (mounted) {
        setState(() {
          _isTakingPhoto = false;
          // _isPolishing tetap true sampai preview selesai
        });
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PreviewScreen(
              imageBytes: bytes,
              timestamp: waktuFoto,
              position: _bestPosition,
              address: alamat,
              weather: cuaca,
            ),
          ),
        );
      }
      if (mounted) setState(() => _isPolishing = false);
      if (mounted && _controller == null) await _initCamera();
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        final msg = e.toString();
        final short = msg.length <= CameraConstants.maxErrorMessageLength
            ? msg
            : '${msg.substring(0, CameraConstants.maxErrorMessageLength)}...';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $short')));
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
    if (mounted && !_isDisposed) {
      setState(() {
        _isTakingPhoto = false;
        _isPolishing = false;
      });
    }
    _releaseLock();
  }

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera preview
            if (_cameraError != null)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Error Kamera: $_cameraError',
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => _initCamera(),
                      child: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              )
            else if (_isInitialized && _controller != null && !_isWarmingUp)
              Container(
                width: double.infinity,
                height: double.infinity,
                color: Colors.black,
                child: CameraPreview(_controller!),
              )
            else
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(strokeWidth: 2),
                    SizedBox(height: 16),
                    Text(
                      'Starting camera...',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),

            // Banner GPS non-aktif
            if (_isLocationServiceDisabled)
              Positioned(
                top: 40,
                left: 16,
                right: 16,
                child: Material(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.red.shade800,
                  child: InkWell(
                    onTap: () => Geolocator.openLocationSettings(),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.location_off, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Lokasi tidak aktif — Ketuk untuk mengaktifkan',
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                          Icon(Icons.chevron_right, color: Colors.white, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // GPS Bar (dengan alamat realtime)
            Positioned(
              top: _isLocationServiceDisabled ? 90 : 0,
              left: 0,
              right: 0,
              child: GpsBar(
                gpsReady: _gpsReady,
                gpsText: _gpsText,
                bestPosition: _bestPosition,
                address: _currentAddress,
              ),
            ),

            // Settings Button
            Positioned(
              top: _isLocationServiceDisabled ? 90 : 0,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.settings, color: Colors.white70, size: 22),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
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
                            ? 'Akurasi: ±${_bestPosition!.accuracy.toStringAsFixed(0)}m'
                            : _gpsText,
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$_polishCountdown s',
                        style: const TextStyle(color: Colors.white60),
                      ),
                    ],
                  ),
                ),
              ),

            // Capture button
            if (!_isPolishing && !_isWarmingUp && _cameraError == null)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
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
                          width: 64,
                          height: 64,
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
