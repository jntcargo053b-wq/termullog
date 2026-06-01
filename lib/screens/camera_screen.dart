
// lib/screens/camera_screen.dart
// Final – GPS stabil dengan lock threshold adaptif, Kalman filter 4D, distanceFilter 3, akurasi high
// Resolusi kamera veryHigh, resize ke 1920px, watermark proporsional

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:geolocator/geolocator.dart';
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
  // Camera
  CameraController? _controller;
  bool _isCameraReady = false;
  bool _isCapturing = false;
  bool _isCameraInit = false;
  Completer<void>? _initCompleter;
  bool _torchOn = false;

  // GPS
  final GpsLockManager _gpsLock = GpsLockManager();
  final AddressResolver _addrResolver = AddressResolver();
  StreamSubscription<Position>? _posSub;
  bool _locationActive = false;

  Position? _displayPos;
  double? _currentAcc;
  double? _lastGeocodedAcc;
  bool _isFallback = false;
  String _gpsStatus = '🟡 Mencari GPS';
  double _gpsConfidence = 0.0;

  double? _displayLat;
  double? _displayLon;
  double? _displayAcc;

  // Address & Weather
  String _address = 'Mencari lokasi…';
  String _weather = '';
  bool _addrLoading = false;

  // Waktu
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  // Pengaturan
  bool _showWeather = true;
  bool _showAccuracy = true;
  bool _showAddress = true;
  bool _showCoordinates = true;
  double _opacity = 0.88;
  bool _showBorder = true;
  WatermarkLayout _layout = WatermarkLayout.timemarkClassic;

  // Filter outlier
  Position? _lastAcceptedRaw;
  static const double _maxAcceptableAccuracy = 15.0;
  static const double _maxJumpDistance = 200.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    await _checkGalleryPermission();
    await _initCamera();
    await _requestHighAccuracy();
    await _loadLastKnownPosition();
    await _initLocation();
    _startClock();
  }

  Future<void> _checkGalleryPermission() async {
    if (Platform.isAndroid) {
      final info = await _deviceAndroidVersion();
      if (info >= 33) {
        await Permission.photos.request();
      } else {
        await Permission.storage.request();
      }
    }
  }

  Future<int> _deviceAndroidVersion() async {
    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _initCamera() async {
    if (_isCameraInit) {
      await _initCompleter?.future;
      return;
    }
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
      if (!mounted) {
        await c.dispose();
        return;
      }
      _controller = c;
      if (mounted) setState(() => _isCameraReady = true);
    } catch (e) {
      debugPrint('Camera init error: $e');
    } finally {
      _isCameraInit = false;
      _initCompleter?.complete();
    }
  }

  Future<void> _requestHighAccuracy() async {
    try {
      await Geolocator.requestPermission();
    } catch (_) {}
  }

  Future<void> _loadLastKnownPosition() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null || !mounted) return;

      final addr = await _addrResolver.resolve(last);
      if (!mounted) return;
      setState(() {
        _displayPos = last;
        _displayLat = last.latitude;
        _displayLon = last.longitude;
        _displayAcc = last.accuracy;
        _currentAcc = last.accuracy;
        _gpsStatus = '🕐 Posisi Terakhir';
        if (addr.isNotEmpty) {
          _address = addr;
          _lastGeocodedAcc = last.accuracy;
        }
      });
    } catch (e) {
      debugPrint('LastKnownPosition error: $e');
    }
  }

  Future<void> _initLocation() async {
    if (_locationActive) return;
    _locationActive = true;
    try {
      // Warm-up
      Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      ).then((pos) {
        if (mounted) _onPosition(pos);
      }).catchError((_) {});

      // Stream GPS dengan setting produksi: high accuracy, distanceFilter 3 meter
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        ),
      ).listen(_onPosition, onError: (_) {});
    } catch (e) {
      debugPrint('Location stream error: $e');
    }
  }

  bool _isValidPosition(Position pos) {
    if (pos.accuracy > _maxAcceptableAccuracy) return false;
    if (_lastAcceptedRaw != null) {
      final distance = _haversineDistance(_lastAcceptedRaw!, pos);
      if (distance > _maxJumpDistance) return false;
    }
    return true;
  }

  double _haversineDistance(Position a, Position b) {
    const double R = 6371000;
    final lat1 = a.latitude * pi / 180;
    final lat2 = b.latitude * pi / 180;
    final deltaLat = (b.latitude - a.latitude) * pi / 180;
    final deltaLon = (b.longitude - a.longitude) * pi / 180;
    final aVal = sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2);
    final c = 2 * atan2(sqrt(aVal), sqrt(1 - aVal));
    return R * c;
  }

  void _onPosition(Position pos) {
    if (!mounted) return;

    if (!_isValidPosition(pos)) return;
    _lastAcceptedRaw = pos;

    final justLocked = _gpsLock.processSample(pos);
    final lockData = _gpsLock.lockData;

    setState(() {
      _currentAcc = pos.accuracy;
      _isFallback = lockData?.isFallbackLock ?? false;
      _gpsConfidence = lockData?.confidence ?? 0;
      _displayPos = lockData?.position ?? pos;

      if (_gpsLock.isLocked && lockData != null) {
        _displayLat = lockData.smoothedLatitude;
        _displayLon = lockData.smoothedLongitude;
        _displayAcc = lockData.accuracy;
      } else {
        _displayLat = pos.latitude;
        _displayLon = pos.longitude;
        _displayAcc = pos.accuracy;
      }

      _gpsStatus = _gpsLock.isLocked
          ? '🟢 Terkunci'
          : pos.accuracy <= 10
              ? '🔵 Akurat'
              : pos.accuracy <= 30
                  ? '🟡 Sedang'
                  : '🔴 Lemah';
    });

    if (justLocked && lockData != null) {
      _lastGeocodedAcc = null;
      LastKnownLocationCache.save(
        position: lockData.rawPosition,
        address: _address,
        weather: _weather,
      );
    }

    _maybeResolveAddress(pos);
    _maybeLoadWeather(pos);
  }

  int _geoReqId = 0;
  void _maybeResolveAddress(Position pos) {
    final accImproved = _lastGeocodedAcc != null &&
        (_lastGeocodedAcc! - pos.accuracy) >= 15.0;

    if (_addrLoading && !accImproved) return;
    if (_addrLoading) _geoReqId++;

    final id = ++_geoReqId;
    _addrLoading = true;
    _addrResolver.resolve(pos).then((addr) {
      if (!mounted || id != _geoReqId) return;
      setState(() {
        if (addr.isNotEmpty) {
          _address = addr;
          _lastGeocodedAcc = pos.accuracy;
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
    LocationWeatherService.fetchFromPosition(pos)
        .then((result) {
      if (mounted && result.weather.isNotEmpty) {
        setState(() => _weather = result.weather);
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
    if (mounted) setState(() {});
  }

  Future<void> _reloadSettings() async {
    SettingsCache.invalidate();
    await _loadSettings();
  }

  // Capture
  Future<void> _takePhoto() async {
    if (_isCapturing || _controller == null || !_controller!.value.isInitialized)
      return;
    if (_displayLat == null && (_currentAcc ?? 999) > 50.0) return;

    HapticFeedback.mediumImpact();
    setState(() => _isCapturing = true);

    try {
      final xFile = await _controller!.takePicture();
      final rawBytes = await File(xFile.path).readAsBytes();
      final captureTime = DateTime.now();
      final fontScale = await SettingsCache.getFontScale();
      final imageQuality = await SettingsCache.imageQuality;

      // Resize ke 1920px jika lebar >1920
      Uint8List finalBytes = rawBytes;
      img.Image? originalImg = img.decodeImage(rawBytes);
      if (originalImg != null) {
        const int targetWidth = 1920;
        if (originalImg.width > targetWidth) {
          final double ratio = originalImg.height / originalImg.width;
          final int targetHeight = (targetWidth * ratio).round();
          final resized = img.copyResize(originalImg, width: targetWidth, height: targetHeight);
          finalBytes = Uint8List.fromList(img.encodeJpg(resized, quality: imageQuality));
        } else {
          finalBytes = Uint8List.fromList(img.encodeJpg(originalImg, quality: imageQuality));
        }
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
      );

      final jpegBytes = await WatermarkEngine.process(params);

      final appDir = await getApplicationDocumentsDirectory();
      final histDir = Directory('${appDir.path}/history');
      await histDir.create(recursive: true);
      final ts = captureTime.millisecondsSinceEpoch;
      final outPath = '${histDir.path}/termullog_$ts.jpg';
      await File(outPath).writeAsBytes(jpegBytes);

      await GallerySaver.saveImage(outPath, albumName: 'TermulLog');

      try {
        await File(xFile.path).delete();
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Foto tersimpan ke Galeri'),
            backgroundColor: Color(0xFF1A2540),
            duration: Duration(seconds: 2),
          ),
        );
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
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
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

  Color _accColor(double? acc) {
    if (acc == null) return Colors.grey;
    if (acc <= 5) return const Color(0xFF3CB86A);
    if (acc <= 20) return const Color(0xFFFFB820);
    return const Color(0xFFE63946);
  }

  @override
  Widget build(BuildContext context) {
    final bool previewReady =
        _controller != null && _controller!.value.isInitialized;

    if (!_isCameraReady || !previewReady) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF1E90FF)),
              SizedBox(height: 16),
              Text('Menginisialisasi kamera…',
                  style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      );
    }

    final canCapture = !_isCapturing &&
        (_displayLat != null || (_currentAcc ?? 999) <= 50.0);

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
              color: _accColor(_currentAcc),
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
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          valueColor: AlwaysStoppedAnimation(Color(0xFFFF9500))),
                    ),
                    SizedBox(width: 6),
                    Text('Memperbarui…',
                        style: TextStyle(color: Color(0xFFFF9500), fontSize: 10)),
                  ],
                ),
              ),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 110,
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 8),
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
                        color: canCapture
                            ? const Color(0x33FFFFFF)
                            : Colors.grey.withOpacity(0.2),
                        border: Border.all(
                          color: canCapture ? Colors.white : Colors.grey,
                          width: 4,
                        ),
                      ),
                      child: _isCapturing
                          ? const Padding(
                              padding: EdgeInsets.all(18),
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 3),
                            )
                          : null,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.layers_outlined,
                        color: Colors.white54, size: 28),
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

// GPS Chip Widget
class _GpsChip extends StatelessWidget {
  final String status;
  final double? acc;
  final double confidence;
  final bool isFallback;
  final Color color;

  const _GpsChip({
    required this.status,
    required this.acc,
    required this.confidence,
    required this.isFallback,
    required this.color,
  });

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
              Text(status,
                  style: TextStyle(color: color, fontSize: 10, height: 1.2)),
              if (acc != null)
                Text(
                  '± ${acc!.toStringAsFixed(0)} m${isFallback ? ' (fallback)' : ''}',
                  style: TextStyle(
                      color: color.withOpacity(0.8), fontSize: 9, height: 1.2),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// Layout Picker Bottom Sheet
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
        Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        const Text('Pilih Gaya Watermark',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ...WatermarkLayout.values.map((l) {
          final selected = l == current;
          return ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF1E90FF).withOpacity(0.2)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(8),
                border: selected
                    ? Border.all(color: const Color(0xFF1E90FF), width: 1.5)
                    : null,
              ),
              child: Icon(
                _iconFor(l),
                color: selected ? const Color(0xFF1E90FF) : Colors.white38,
                size: 18,
              ),
            ),
            title: Text(l.displayName,
                style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
            subtitle: Text(l.description,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () => onSelect(l),
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }

  IconData _iconFor(WatermarkLayout l) {
    switch (l) {
      case WatermarkLayout.timemarkClassic:
        return Icons.access_time;
      case WatermarkLayout.timemarkMinimal:
        return Icons.radio_button_checked;
      case WatermarkLayout.timemarkCard:
        return Icons.credit_card;
      case WatermarkLayout.timemarkHUD:
        return Icons.track_changes;
      case WatermarkLayout.timemarkFilm:
        return Icons.photo_camera_back;
    }
  }
}
