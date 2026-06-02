// lib/screens/camera_screen.dart
// FINAL – Perbaikan sesuai saran TimeMark
// - _onPosition selalu mengisi display (lock, bestFix, atau raw)
// - _maxAcceptableAccuracy = 30.0 (tidak terlalu ketat)
// - _geocodeAccuracyThreshold = 30.0
// - _takePhoto tidak membatalkan foto jika koordinat sudah ada (hanya warning)
// - _bootGps pakai LocationAccuracy.medium dengan timeout 5 detik
// - AddressResolver._minAccuracy = 15.0 (di file terpisah)

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:image/image.dart' as img;

import '../core/constants.dart';
import '../services/gps_lock_manager.dart';
import '../services/address_resolver.dart';
import '../services/last_known_location_cache.dart';
import '../services/location_weather_service.dart';
import '../services/settings_cache.dart';
import '../watermark/watermark_engine.dart';
import '../watermark/watermark_params.dart';
import '../watermark/watermark_preview_painter.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  // ── Camera ──────────────────────────────────────────────────────────────
  CameraController? _controller;
  bool _isCameraReady = false;
  bool _isCapturing = false;
  bool _isCameraInit = false;
  Completer<void>? _initCompleter;
  bool _torchOn = false;

  // ── GPS ──────────────────────────────────────────────────────────────────
  final GpsLockManager _gpsLock = GpsLockManager();
  final AddressResolver _addrResolver = AddressResolver();
  StreamSubscription<Position>? _posSub;
  bool _locationActive = false;

  // ── Data display & watermark ─────────────────────────────────────────────
  double? _displayLat;
  double? _displayLon;
  double? _displayAcc;
  String _address = '';
  String _weather = '';
  bool _addrLoading = false;
  double? _lastGeocodedAcc;
  bool _isFromCache = false;

  // ── GPS status chip ───────────────────────────────────────────────────────
  String _gpsStatus = '📍 Lokasi Tersimpan';
  double _gpsConfidence = 0.0;
  bool _isFallback = false;

  // ── Clock ─────────────────────────────────────────────────────────────────
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  // ── Settings ──────────────────────────────────────────────────────────────
  bool _showWeather = true;
  bool _showAccuracy = true;
  bool _showAddress = true;
  bool _showCoordinates = true;
  double _opacity = 0.88;
  bool _showBorder = true;
  WatermarkLayout _layout = WatermarkLayout.timemarkClassic;
  bool _showMiniMap = false;
  String _fontSize = 'normal';
  String _dateFormat = 'dd/MM/yyyy';
  String _timeFormat = 'HH:mm:ss';
  int _mapZoomLevel = 15;

  // ── Threshold (kompromi: 30m untuk startup, tidak terlalu ketat) ───────────
  static const double _maxAcceptableAccuracy = 30.0;    // filter sample GPS
  static const double _geocodeAccuracyThreshold = 30.0; // trigger geocode
  static const double _maxOsLastKnownAccuracy = 15.0;
  static const double _cacheAccuracyThreshold = 30.0;
  static const Duration _maxOurCacheAge = Duration(hours: 12);
  static const double _maxJumpDistance = 200.0;

  // ── Outlier filter ────────────────────────────────────────────────────────
  Position? _lastAcceptedRaw;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _startupAddressWarmup();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _startupAddressWarmup() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted && last.accuracy <= _maxOsLastKnownAccuracy) {
        _maybeResolveAddress(last);
      }
    } catch (_) {}
  }

  Future<void> _boot() async {
    await Future.wait([
      _loadOurCache(),
      _bootGps(),
      _checkGalleryPermission(),
      _initCamera(),
    ]);
    _startClock();
  }

  Future<void> _bootGps() async {
    await _requestLocationPermission();

    // Layer 2a: OS Last Known
    _loadOsLastKnown();

    // Layer 2b: Fused Location (medium, timeout 5 detik)
    try {
      final fused = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 5));
      if (mounted && fused.accuracy <= 100.0) {
        _onPosition(fused);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Fused location error: $e');
    }

    // Layer 3: GPS stream akurasi tinggi
    await _initLocation();
  }

  Future<void> _loadOurCache() async {
    try {
      final cached = await LastKnownLocationCache.load();
      if (cached == null || !mounted) return;
      if (DateTime.now().difference(cached.cachedAt) > _maxOurCacheAge) return;
      if (cached.address.isEmpty) return;

      setState(() {
        _displayLat = cached.latitude;
        _displayLon = cached.longitude;
        _displayAcc = cached.accuracy;
        _address = cached.address;
        _lastGeocodedAcc = cached.accuracy;
        _weather = cached.weather;
        _gpsStatus = '📍 Lokasi Tersimpan';
        _isFromCache = true;
      });

      // Langsung geocode dari cache
      if (cached.accuracy <= _geocodeAccuracyThreshold) {
        _maybeResolveAddress(Position(
          latitude: cached.latitude,
          longitude: cached.longitude,
          accuracy: cached.accuracy,
          timestamp: DateTime.now(),
          altitude: 0, altitudeAccuracy: 0,
          heading: 0, headingAccuracy: 0,
          speed: 0, speedAccuracy: 0,
        ));
      }
    } catch (e) {
      debugPrint('OurCache error: $e');
    }
  }

  Future<void> _loadOsLastKnown() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null || !mounted) return;
      if (last.accuracy > _maxOsLastKnownAccuracy) return;
      final age = last.timestamp != null
          ? DateTime.now().difference(last.timestamp!)
          : Duration.zero;
      if (age > const Duration(minutes: 1)) return;

      setState(() {
        if (_displayLat != null && !_isFromCache) return;
        _displayLat = last.latitude;
        _displayLon = last.longitude;
        _displayAcc = last.accuracy;
        if (_address.isEmpty) _gpsStatus = '📡 Memperbarui lokasi...';
      });
      _maybeResolveAddress(last);
    } catch (_) {}
  }

  Future<void> _checkGalleryPermission() async {
    if (Platform.isAndroid) {
      final v = await _androidSdkVersion();
      if (v >= 33) await Permission.photos.request();
      else await Permission.storage.request();
    }
  }

  Future<int> _androidSdkVersion() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.version.sdkInt;
    } catch (_) { return 0; }
  }

  Future<void> _initCamera() async {
    if (_isCameraInit) { await _initCompleter?.future; return; }
    _isCameraInit = true;
    _initCompleter = Completer();
    try {
      if (widget.cameras.isEmpty) return;
      await _controller?.dispose();
      final c = CameraController(
        widget.cameras.first,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await c.initialize();
      if (!mounted) { await c.dispose(); return; }
      _controller = c;
      if (mounted) setState(() => _isCameraReady = true);
    } catch (e) {
      debugPrint('Camera init error: $e');
    } finally {
      _isCameraInit = false;
      _initCompleter?.complete();
    }
  }

  Future<void> _requestLocationPermission() async {
    try { await Geolocator.requestPermission(); } catch (_) {}
  }

  Future<void> _initLocation() async {
    if (_locationActive) return;
    _locationActive = true;
    try {
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 2,
        ),
      ).listen(_onPosition, onError: (_) {});
    } catch (e) {
      debugPrint('Location stream error: $e');
    }
  }

  bool _isValidPosition(Position pos) {
    if (pos.accuracy > _maxAcceptableAccuracy) return false;
    if (_lastAcceptedRaw != null) {
      final d = _haversineDistance2(
        _lastAcceptedRaw!.latitude, _lastAcceptedRaw!.longitude,
        pos.latitude, pos.longitude,
      );
      if (d > _maxJumpDistance && pos.accuracy > (_lastAcceptedRaw!.accuracy + 5)) {
        return false;
      }
    }
    return true;
  }

  // PERBAIKAN 1: _onPosition selalu mengisi display (lock, bestFix, atau raw)
  void _onPosition(Position pos) {
    if (!mounted) return;
    if (!_isValidPosition(pos)) return;
    _lastAcceptedRaw = pos;

    final justLocked = _gpsLock.processSample(pos);
    final lockData = _gpsLock.lockData;
    final isLocked = _gpsLock.isLocked;

    setState(() {
      _gpsConfidence = lockData?.confidence ?? 0;
      _isFallback = lockData?.isFallbackLock ?? false;
      _isFromCache = false;
      _gpsStatus = isLocked ? '🟢 Terkunci' : '📡 Memperbarui lokasi...';
    });

    // 🔥 SELALU ISI DISPLAY (jangan tunggu lock)
    final bestFix = _gpsLock.bestFix;
    if (isLocked && lockData != null) {
      _displayLat = lockData.smoothedLatitude;
      _displayLon = lockData.smoothedLongitude;
      _displayAcc = lockData.accuracy;
    } else if (bestFix != null) {
      _displayLat = bestFix.latitude;
      _displayLon = bestFix.longitude;
      _displayAcc = bestFix.accuracy;
    } else {
      // Fallback ke raw stream
      _displayLat = pos.latitude;
      _displayLon = pos.longitude;
      _displayAcc = pos.accuracy;
    }

    // Geocode tanpa menunggu lock (pakai bestFix atau pos)
    Position? geocodePos;
    if (isLocked && lockData != null) {
      geocodePos = _makePosition(
        source: pos,
        lat: lockData.smoothedLatitude,
        lon: lockData.smoothedLongitude,
        acc: lockData.accuracy,
      );
    } else if (bestFix != null && bestFix.accuracy <= _geocodeAccuracyThreshold) {
      geocodePos = bestFix;
    } else if (pos.accuracy <= _geocodeAccuracyThreshold) {
      geocodePos = pos;
    }

    if (geocodePos != null) {
      _maybeResolveAddress(geocodePos);
    }

    // Weather
    final sourcePos = (isLocked && lockData != null)
        ? _makePosition(
            source: pos,
            lat: lockData.smoothedLatitude,
            lon: lockData.smoothedLongitude,
            acc: lockData.accuracy,
          )
        : pos;
    _maybeLoadWeather(sourcePos);

    if (justLocked && lockData != null) {
      _lastGeocodedAcc = null;
      _addrResolver.forceRefresh();
      _maybeResolveAddress(geocodePos ?? sourcePos);
    }
  }

  Position _makePosition({
    required Position source,
    required double lat,
    required double lon,
    required double acc,
  }) {
    return Position(
      latitude: lat, longitude: lon,
      timestamp: DateTime.now(), accuracy: acc,
      altitude: source.altitude, altitudeAccuracy: source.altitudeAccuracy,
      heading: source.heading, headingAccuracy: source.headingAccuracy,
      speed: source.speed, speedAccuracy: source.speedAccuracy,
      floor: source.floor, isMocked: source.isMocked,
    );
  }

  int _geoReqId = 0;
  void _maybeResolveAddress(Position pos) {
    // PERBAIKAN 4: longgarkan threshold (30m)
    if (pos.accuracy > _geocodeAccuracyThreshold) return;

    final accImproved = _lastGeocodedAcc != null &&
        (_lastGeocodedAcc! - pos.accuracy) >= 5.0;
    if (_addrLoading && !accImproved) return;
    if (_addrLoading) _geoReqId++;

    final id = ++_geoReqId;
    _addrLoading = true;
    _addrResolver.resolve(pos).then((addr) {
      if (!mounted || id != _geoReqId) return;
      setState(() {
        if (addr.isNotEmpty) {
          final shouldUpdate = _lastGeocodedAcc == null || pos.accuracy <= _lastGeocodedAcc!;
          if (shouldUpdate) {
            _address = addr;
            _lastGeocodedAcc = pos.accuracy;
            _isFromCache = false;
            if (_displayLat != null && _displayLon != null && _displayAcc != null &&
                _displayAcc! <= _cacheAccuracyThreshold) {
              LastKnownLocationCache.save(
                position: Position(
                  latitude: _displayLat!,
                  longitude: _displayLon!,
                  accuracy: _displayAcc!,
                  timestamp: DateTime.now(),
                  altitude: 0, altitudeAccuracy: 0,
                  heading: 0, headingAccuracy: 0,
                  speed: 0, speedAccuracy: 0,
                ),
                address: addr,
                weather: _weather,
              );
            }
          }
        }
        _addrLoading = false;
      });
    }).catchError((_) {
      if (mounted) setState(() => _addrLoading = false);
    });
  }

  DateTime? _lastWeatherFetch;
  void _maybeLoadWeather(Position pos) {
    final now = DateTime.now();
    if (_lastWeatherFetch != null &&
        now.difference(_lastWeatherFetch!).inMinutes < 10) return;
    _lastWeatherFetch = now;
    LocationWeatherService.fetchFromPosition(pos).then((result) {
      if (mounted && result.weather.isNotEmpty) {
        setState(() => _weather = result.weather);
        if (_displayLat != null && _displayLon != null && _displayAcc != null &&
            _displayAcc! <= _cacheAccuracyThreshold) {
          LastKnownLocationCache.save(
            position: Position(
              latitude: _displayLat!,
              longitude: _displayLon!,
              accuracy: _displayAcc!,
              timestamp: DateTime.now(),
              altitude: 0, altitudeAccuracy: 0,
              heading: 0, headingAccuracy: 0,
              speed: 0, speedAccuracy: 0,
            ),
            address: _address,
            weather: result.weather,
          );
        }
      }
    }).catchError((_) {});
  }

  void _startClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  Future<void> _loadSettings() async {
    await SettingsCache.preload();
    _showWeather = await SettingsCache.showWeather;
    _showAccuracy = await SettingsCache.showAccuracy;
    _showAddress = await SettingsCache.showAddress;
    _showCoordinates = await SettingsCache.showCoordinates;
    _opacity = await SettingsCache.opacity;
    _showBorder = await SettingsCache.showBorder;
    _layout = await SettingsCache.layout;
    _showMiniMap = await SettingsCache.showMiniMap;
    _mapZoomLevel = await SettingsCache.mapZoomLevel;
    _dateFormat = await SettingsCache.dateFormat;
    _timeFormat = await SettingsCache.timeFormat;
    final fontSizeDouble = await SettingsCache.fontSize;
    _fontSize = fontSizeDouble <= 13 ? 'small' : fontSizeDouble >= 20 ? 'large' : 'normal';
    if (mounted) setState(() {});
  }

  Future<void> _reloadSettings() async {
    SettingsCache.invalidate();
    await _loadSettings();
  }

  // PERBAIKAN 6: _takePhoto tidak membatalkan jika koordinat sudah ada
  Future<void> _takePhoto() async {
    if (_isCapturing || _controller == null || !_controller!.value.isInitialized) return;

    final double acc = _displayAcc ?? 999.0;
    if (_displayLat == null || _displayLon == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('⏳ GPS belum siap, tunggu sebentar...'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ));
      }
      return;
    }

    // Warning jika akurasi >30, tapi tetap izinkan foto
    if (acc > 30.0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('⚠️ GPS ±${acc.toStringAsFixed(0)}m, hasil mungkin kurang akurat.'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ));
      }
    }

    HapticFeedback.mediumImpact();
    setState(() => _isCapturing = true);

    try {
      final xFile = await _controller!.takePicture();
      final rawBytes = await File(xFile.path).readAsBytes();
      final captureTime = DateTime.now();
      final fontScale = await SettingsCache.getFontScale();
      final imageQuality = await SettingsCache.imageQuality;

      Uint8List finalBytes = rawBytes;
      final originalImg = img.decodeImage(rawBytes);
      if (originalImg != null) {
        const int targetWidth = 1920;
        if (originalImg.width > targetWidth) {
          final ratio = originalImg.height / originalImg.width;
          final h = (targetWidth * ratio).round();
          final resized = img.copyResize(originalImg, width: targetWidth, height: h);
          finalBytes = Uint8List.fromList(img.encodeJpg(resized, quality: imageQuality));
        } else {
          finalBytes = Uint8List.fromList(img.encodeJpg(originalImg, quality: imageQuality));
        }
      }

      Uint8List? mapBytes;
      if (_showMiniMap && _displayLat != null && _displayLon != null) {
        mapBytes = await LocationWeatherService.fetchMapWithRetry(
          _displayLat!, _displayLon!,
        );
        if (mapBytes != null && mapBytes.isEmpty) mapBytes = null;
      }

      final params = WatermarkParams(
        imageBytes: finalBytes,
        timestamp: captureTime,
        address: _address,
        weather: _weather,
        layoutIndex: _layout.index,
        showWeather: _showWeather,
        showAccuracy: _showAccuracy,
        showAddress: _showAddress,
        showCoordinates: _showCoordinates,
        opacity: _opacity,
        showBorder: _showBorder,
        lat: _displayLat,
        lon: _displayLon,
        acc: _displayAcc,
        fontScale: fontScale,
        imageQuality: imageQuality,
        appName: 'TermulLog',
        showMiniMap: _showMiniMap,
        mapBytes: mapBytes,
        mapSize: 120,
        mapZoomLevel: _mapZoomLevel,
        fontSize: _fontSize,
        dateFormat: _dateFormat,
        timeFormat: _timeFormat,
      );

      final jpegBytes = await WatermarkEngine.process(params);

      final appDir = await getApplicationDocumentsDirectory();
      final histDir = Directory('${appDir.path}/history');
      await histDir.create(recursive: true);
      final ts = captureTime.millisecondsSinceEpoch;
      final outPath = '${histDir.path}/termullog_$ts.jpg';
      await File(outPath).writeAsBytes(jpegBytes);
      await GallerySaver.saveImage(outPath, albumName: 'TermulLog');

      try { await File(xFile.path).delete(); } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Foto tersimpan ke Galeri'),
          backgroundColor: Color(0xFF1A2540),
          duration: Duration(seconds: 2),
        ));
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _toggleTorch() async {
    try {
      _torchOn = !_torchOn;
      await _controller?.setFlashMode(_torchOn ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (_isCameraInit) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      await _controller?.dispose();
      if (mounted && _controller != null) {
        _controller = null;
        setState(() => _isCameraReady = false);
      }
      await _posSub?.cancel();
      _posSub = null;
      _locationActive = false;
    } else if (state == AppLifecycleState.resumed) {
      _addrResolver.reset();
      await _initCamera();
      await _initLocation();
      await _reloadSettings();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _posSub?.cancel();
    _controller?.dispose();
    _addrResolver.dispose();
    super.dispose();
  }

  double _haversineDistance2(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) *
            sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  Color _accColor(double? acc) {
    if (acc == null) return Colors.grey;
    if (acc <= 5) return const Color(0xFF3CB86A);
    if (acc <= 15) return const Color(0xFFFFB820);
    return const Color(0xFFE63946);
  }

  @override
  Widget build(BuildContext context) {
    final bool previewReady = _controller != null && _controller!.value.isInitialized;

    if (!_isCameraReady || !previewReady) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Color(0xFF1E90FF)),
              const SizedBox(height: 16),
              const Text('Menginisialisasi kamera…',
                  style: TextStyle(color: Colors.white54)),
              if (_address.isNotEmpty) ...[
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _address,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final canCapture = !_isCapturing && _displayLat != null && _displayLon != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),
          CustomPaint(
            painter: WatermarkPreviewPainter(
              timestamp: _now,
              hasPosition: _displayLat != null,
              lat: _displayLat,
              lon: _displayLon,
              acc: _displayAcc,
              address: _address,
              weather: _weather,
              showWeather: _showWeather,
              showAccuracy: _showAccuracy,
              showAddress: _showAddress,
              showCoordinates: _showCoordinates,
              opacity: _opacity,
              showBorder: _showBorder,
              layout: _layout,
            ),
          ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: _GpsChip(
              status: _gpsStatus,
              acc: _displayAcc,
              confidence: _gpsConfidence,
              isFallback: _isFallback,
              isFromCache: _isFromCache,
              color: _accColor(_displayAcc),
            ),
          ),

          if (_addrLoading)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 10, height: 10,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          valueColor: AlwaysStoppedAnimation(Color(0xFFFF9500))),
                    ),
                    SizedBox(width: 6),
                    Text('Alamat…',
                        style: TextStyle(color: Color(0xFFFF9500), fontSize: 10)),
                  ],
                ),
              ),
            ),

          if (_address.isNotEmpty && _showAddress)
            Positioned(
              bottom: 110,
              left: 0,
              right: 0,
              child: _AddressPreviewBar(
                address: _address,
                isFromCache: _isFromCache,
                isLoading: _addrLoading,
              ),
            ),

          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              height: 110,
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8),
              color: const Color(0xCC000000),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      _torchOn ? Icons.flash_on : Icons.flash_off,
                      color: _torchOn ? const Color(0xFFFFD95A) : Colors.white54,
                      size: 28,
                    ),
                    onPressed: _toggleTorch,
                  ),
                  GestureDetector(
                    onTap: canCapture ? _takePhoto : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: _isCapturing ? 64 : 72,
                      height: _isCapturing ? 64 : 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: canCapture ? const Color(0x33FFFFFF) : Colors.grey.withOpacity(0.2),
                        border: Border.all(
                          color: canCapture ? Colors.white : Colors.grey,
                          width: 4,
                        ),
                      ),
                      child: _isCapturing
                          ? const Padding(
                              padding: EdgeInsets.all(18),
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                            )
                          : null,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.layers_outlined, color: Colors.white54, size: 28),
                    onPressed: _showLayoutPicker,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLayoutPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0E1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _LayoutPickerSheet(
        current: _layout,
        onSelect: (l) {
          setState(() => _layout = l);
          SettingsCache.setLayout(l);
          Navigator.pop(context);
        },
      ),
    );
  }
}

// ── Address Preview Bar ──────────────────────────────────────────────────────
class _AddressPreviewBar extends StatelessWidget {
  final String address;
  final bool isFromCache;
  final bool isLoading;
  const _AddressPreviewBar({required this.address, required this.isFromCache, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isFromCache ? const Color(0x40FF9500) : const Color(0x401E90FF),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isFromCache ? Icons.history_outlined : Icons.location_on_outlined,
            size: 13,
            color: isFromCache ? const Color(0xFFFF9500) : const Color(0xFF1E90FF),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              address,
              style: TextStyle(
                color: isFromCache ? const Color(0xFFCC9000) : Colors.white70,
                fontSize: 11,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isLoading) ...[
            const SizedBox(width: 6),
            const SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 1.2, valueColor: AlwaysStoppedAnimation(Color(0xFFFF9500)))),
          ],
        ],
      ),
    );
  }
}

// ── GPS Chip ─────────────────────────────────────────────────────────────────
class _GpsChip extends StatelessWidget {
  final String status;
  final double? acc;
  final double confidence;
  final bool isFallback;
  final bool isFromCache;
  final Color color;
  const _GpsChip({required this.status, required this.acc, required this.confidence, required this.isFallback, required this.isFromCache, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.gps_fixed, size: 11, color: color),
          const SizedBox(width: 5),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(status, style: TextStyle(color: color, fontSize: 10, height: 1.2)),
              if (acc != null)
                Text(
                  '± ${acc!.toStringAsFixed(0)} m${isFallback ? ' (fallback)' : ''}',
                  style: TextStyle(color: color.withOpacity(0.8), fontSize: 9, height: 1.2),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Layout Picker Sheet ───────────────────────────────────────────────────────
class _LayoutPickerSheet extends StatelessWidget {
  final WatermarkLayout current;
  final ValueChanged<WatermarkLayout> onSelect;
  const _LayoutPickerSheet({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        const Text('Pilih Gaya Watermark', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ...WatermarkLayout.values.map((l) {
          final selected = l == current;
          return ListTile(
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF1E90FF).withOpacity(0.2) : Colors.white10,
                borderRadius: BorderRadius.circular(8),
                border: selected ? Border.all(color: const Color(0xFF1E90FF), width: 1.5) : null,
              ),
              child: Icon(_iconFor(l), color: selected ? const Color(0xFF1E90FF) : Colors.white38, size: 18),
            ),
            title: Text(l.displayName, style: TextStyle(color: selected ? Colors.white : Colors.white70, fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
            subtitle: Text(l.description, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () => onSelect(l),
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }

  IconData _iconFor(WatermarkLayout l) {
    switch (l) {
      case WatermarkLayout.timemarkClassic: return Icons.access_time;
      case WatermarkLayout.timemarkMinimal: return Icons.radio_button_checked;
      case WatermarkLayout.timemarkCard: return Icons.credit_card;
      case WatermarkLayout.timemarkHUD: return Icons.track_changes;
      case WatermarkLayout.timemarkFilm: return Icons.photo_camera_back;
    }
  }
}
