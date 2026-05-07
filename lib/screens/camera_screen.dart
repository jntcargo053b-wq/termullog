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

import '../core/camera_registry.dart';
import '../services/watermark_layout_service.dart';
import 'preview_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {

  // ───────────────── CAMERA ─────────────────

  CameraController? _controller;
  bool _isInitialized = false;
  bool _isTakingPhoto = false;

  // ───────────────── GPS ─────────────────

  StreamSubscription<Position>? _gpsStream;
  Position? _bestPosition;
  bool _gpsReady = false;
  String _gpsText = '🔍 Searching GPS...';
  String _gpsError = '';

  // ───────────────── GPS PROCESSING ─────────────────

  final List<Position> _positionSamples = [];
  static const int _maxSamples = 10;
  static const double _targetAccuracy = 10.0;
  static const int _minSamplesRequired = 3;
  int _samplesCollected = 0;

  // ───────────────── GPS POLISH ─────────────────

  bool _isPolishing = false;
  int _polishCountdown = 45;
  Timer? _countdownTimer;
  Completer<void>? _gpsCompleter;

  // ───────────────── KALMAN ─────────────────

  final SimpleKalmanFilter _kalmanLat = SimpleKalmanFilter();
  final SimpleKalmanFilter _kalmanLon = SimpleKalmanFilter();
  bool _kalmanInitialized = false;

  // ───────────────── INIT ─────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _startGpsTracking();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    
    _gpsStream?.cancel();
    _gpsStream = null;
    
    _countdownTimer?.cancel();
    _countdownTimer = null;
    
    if (_gpsCompleter != null && !_gpsCompleter!.isCompleted) {
      _gpsCompleter!.complete();
    }
    _gpsCompleter = null;
    
    _positionSamples.clear();
    
    _controller?.dispose();
    _controller = null;
    
    super.dispose();
  }

  // ───────────────── APP LIFECYCLE ─────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      await controller.dispose();
      if (mounted) {
        setState(() {
          _controller = null;
          _isInitialized = false;
        });
      }
    }

    if (state == AppLifecycleState.resumed) {
      await _initCamera();
    }
  }

  // ───────────────── CAMERA INIT ─────────────────

  Future<void> _initCamera() async {
    if (CameraRegistry.cameras.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak ada kamera yang tersedia')),
        );
      }
      return;
    }

    final controller = CameraController(
      CameraRegistry.cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
    );

    _controller = controller;

    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error kamera: $e')),
        );
      }
    }
  }

  // ───────────────── START GPS ─────────────────

  Future<void> _startGpsTracking() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (mounted) setState(() => _gpsText = '❌ GPS tidak aktif');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _gpsText = '❌ Izin GPS ditolak');
        return;
      }

      // Warmup GPS
      try {
        final warmup = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
        ).timeout(const Duration(seconds: 5));

        _bestPosition = warmup;
        _positionSamples.add(warmup);
        _samplesCollected = 1;

        if (mounted) {
          setState(() {
            _gpsText = '🟡 GPS awal ±${warmup.accuracy.toStringAsFixed(0)}m';
          });
        }
      } catch (_) {}

      final LocationSettings locationSettings;

      if (Platform.isAndroid) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
          intervalDuration: const Duration(seconds: 1),
          forceLocationManager: false,
        );
      } else if (Platform.isIOS || Platform.isMacOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
          activityType: ActivityType.other,
          pauseLocationUpdatesAutomatically: false,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        );
      }

      _gpsStream = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position pos) {
          _onGpsData(pos);
        },
        onError: (error) {
          debugPrint('GPS Stream Error: $error');
          if (mounted) {
            setState(() {
              _gpsError = error.toString();
              _gpsText = '❌ Error GPS';
            });
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('GPS Init Error: $e');
      if (mounted) {
        setState(() {
          _gpsError = e.toString();
          _gpsText = '❌ Init GPS gagal';
        });
      }
    }
  }

  void _onGpsData(Position pos) {
    if (pos.isMocked) {
      debugPrint('⚠ Mock GPS detected');
      return;
    }

    final now = DateTime.now();
    final age = now.difference(pos.timestamp);

    if (age.inSeconds > 3) {
      debugPrint('⚠ Stale GPS skipped');
      return;
    }

    if (pos.timestamp.isAfter(now)) {
      debugPrint('⚠ Future timestamp skipped');
      return;
    }

    if (_bestPosition != null && _isOutlier(pos, _bestPosition!)) {
      debugPrint('⚠ Outlier skipped');
      return;
    }

    _positionSamples.removeWhere(
      (p) => DateTime.now().difference(p.timestamp).inSeconds > 8,
    );

    _positionSamples.add(pos);

    if (_positionSamples.length > _maxSamples) {
      _positionSamples.removeAt(0);
    }

    _samplesCollected++;

    if (_samplesCollected < _minSamplesRequired) {
      if (mounted) {
        setState(() {
          _gpsText =
              '🟡 Mengumpulkan sample ($_samplesCollected/$_minSamplesRequired)';
        });
      }
      return;
    }

    final averaged = _averageBestPositions();
    if (averaged == null) return;

    if (_bestPosition == null ||
        averaged.accuracy < _bestPosition!.accuracy) {
      _bestPosition = averaged;

      if (_bestPosition!.accuracy < 15 && !_kalmanInitialized) {
        _kalmanLat.reset();
        _kalmanLon.reset();
        _kalmanInitialized = true;
      }
    }

    final acc = _bestPosition!.accuracy;

    if (mounted) {
      setState(() {
        if (acc <= _targetAccuracy) {
          _gpsReady = true;
          _gpsText = '🟢 GPS Locked ±${acc.toStringAsFixed(1)}m';
        } else if (acc <= 20) {
          _gpsReady = false;
          _gpsText = '🟡 Refining ±${acc.toStringAsFixed(1)}m';
        } else {
          _gpsReady = false;
          _gpsText = '🔴 Weak GPS ±${acc.toStringAsFixed(1)}m';
        }
      });
    }

    if (_gpsCompleter != null &&
        !_gpsCompleter!.isCompleted &&
        acc <= _targetAccuracy) {
      _gpsCompleter!.complete();
    }
  }

  bool _isOutlier(Position newPos, Position lastPos) {
    final distance = _calculateDistance(
      lastPos.latitude,
      lastPos.longitude,
      newPos.latitude,
      newPos.longitude,
    );

    final timeDiff =
        newPos.timestamp.difference(lastPos.timestamp).inSeconds;

    if (timeDiff <= 0) return false;

    final speed = distance / timeDiff;
    return speed > 20;
  }

  double _calculateDistance(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return R * (2 * atan2(sqrt(a), sqrt(1 - a)));
  }

  Position? _averageBestPositions() {
    if (_positionSamples.isEmpty) return _bestPosition;

    final validSamples =
        _positionSamples.where((p) => p.accuracy < 100).toList();

    if (validSamples.isEmpty) return _bestPosition;

    final sorted = List<Position>.from(validSamples)
      ..sort((a, b) => a.accuracy.compareTo(b.accuracy));

    final topN = sorted.take(5).toList();

    double totalWeight = 0;
    double weightedLat = 0;
    double weightedLon = 0;

    for (final p in topN) {
      final weight = 1.0 / (p.accuracy * p.accuracy);
      totalWeight += weight;
      weightedLat += p.latitude * weight;
      weightedLon += p.longitude * weight;
    }

    double finalLat = weightedLat / totalWeight;
    double finalLon = weightedLon / totalWeight;

    if (_kalmanInitialized) {
      finalLat = _kalmanLat.filter(finalLat, topN.first.accuracy);
      finalLon = _kalmanLon.filter(finalLon, topN.first.accuracy);
    }

    final avgAccuracy =
        topN.map((p) => p.accuracy).reduce((a, b) => a + b) / topN.length;
    final estimatedAccuracy = avgAccuracy / sqrt(topN.length.toDouble());

    return Position(
      latitude: finalLat,
      longitude: finalLon,
      accuracy: estimatedAccuracy,
      altitude: topN.first.altitude,
      altitudeAccuracy: topN.first.altitudeAccuracy,
      heading: topN.first.heading,
      headingAccuracy: topN.first.headingAccuracy,
      speed: topN.first.speed,
      speedAccuracy: topN.first.speedAccuracy,
      timestamp: DateTime.now(),
    );
  }

  Future<void> _ambilFoto() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (_isTakingPhoto || _isPolishing) return;

    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always && 
        permission != LocationPermission.whileInUse) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Izin GPS diperlukan untuk watermark')),
        );
      }
      return;
    }

    setState(() => _isTakingPhoto = true);

    try {
      try {
        final fresh = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
        ).timeout(const Duration(seconds: 5));

        if (!fresh.isMocked) _bestPosition = fresh;
      } catch (_) {}

      final XFile file = await ctrl.takePicture();
      final Uint8List bytes = await file.readAsBytes();
      final DateTime waktuFoto = DateTime.now();

      final img.Image? original = await compute(_decodeImage, bytes);
      if (original == null) throw Exception('Decode gagal');

      setState(() {
        _isTakingPhoto = false;
        _isPolishing = true;
        _polishCountdown = 45;
      });

      await _waitForBestGps();

      final String alamat = _bestPosition != null
          ? await _getAddress(_bestPosition!)
          : 'Lokasi tidak tersedia';

      final WatermarkParams params = WatermarkParams(
        image: original,
        timestamp: waktuFoto,
        position: _bestPosition,
        address: alamat,
      );

      final img.Image watermarked = await compute(_addWatermarkAsync, params);

      final dir = await getTemporaryDirectory();
      final outputPath =
          '${dir.path}/termullog_${waktuFoto.millisecondsSinceEpoch}.jpg';

      final Uint8List jpegData = await compute(_encodeJpg, watermarked);

      await File(outputPath).writeAsBytes(jpegData);

      if (!mounted) return;

      setState(() => _isPolishing = false);

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PreviewScreen(imagePath: outputPath),
          ),
        );
      }
    } on CameraException catch (e) {
      debugPrint('Camera error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error kamera: ${e.code}')),
        );
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e')),
        );
      }
    } finally {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      if (_gpsCompleter != null && !_gpsCompleter!.isCompleted) {
        _gpsCompleter!.complete();
      }
      _gpsCompleter = null;
      if (mounted) {
        setState(() {
          _isTakingPhoto = false;
          _isPolishing = false;
        });
      }
    }
  }

  Future<void> _waitForBestGps() async {
    if (!mounted) return;
    
    if (_gpsReady &&
        _bestPosition != null &&
        _bestPosition!.accuracy <= _targetAccuracy) {
      return;
    }
    
    if (_gpsCompleter != null && !_gpsCompleter!.isCompleted) {
      _gpsCompleter!.complete();
      _gpsCompleter = null;
    }
    
    _gpsCompleter = Completer<void>();
    _startCountdown();

    await _gpsCompleter!.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        if (_gpsCompleter != null && !_gpsCompleter!.isCompleted) {
          _gpsCompleter!.complete();
        }
      },
    );
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _polishCountdown = 45;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
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

  Future<String> _getAddress(Position pos) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      ).timeout(const Duration(seconds: 10));

      if (placemarks.isEmpty) {
        return '${pos.latitude.toStringAsFixed(6)}, '
            '${pos.longitude.toStringAsFixed(6)}';
      }

      final p = placemarks.first;

      final parts = [
        p.street,
        p.subLocality,
        p.locality,
        p.administrativeArea,
      ].where((e) => e != null && e.trim().isNotEmpty).toList();

      final fullAddress = parts.join(', ');

      return fullAddress.length > 60
          ? '${fullAddress.substring(0, 57)}...'
          : fullAddress;
    } catch (_) {
      return '${pos.latitude.toStringAsFixed(6)}, '
          '${pos.longitude.toStringAsFixed(6)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_isInitialized && _controller != null)
            SizedBox.expand(child: CameraPreview(_controller!))
          else
            const Center(child: CircularProgressIndicator()),

          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.fromLTRB(16, 52, 16, 12),
              child: Row(
                children: [
                  Icon(
                    _gpsReady ? Icons.gps_fixed : Icons.gps_not_fixed,
                    color: _gpsReady ? Colors.greenAccent : Colors.amber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _bestPosition != null
                              ? '${_bestPosition!.latitude.toStringAsFixed(5)}, '
                                  '${_bestPosition!.longitude.toStringAsFixed(5)}'
                              : 'Belum ada GPS',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                        if (_bestPosition != null)
                          _buildGpsQualityIndicator(),
                      ],
                    ),
                  ),
                  Text(
                    _gpsText,
                    style: TextStyle(
                      color: _gpsReady ? Colors.greenAccent : Colors.amber,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_isPolishing)
            Container(
              color: Colors.black.withOpacity(0.75),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      color: Colors.greenAccent,
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _gpsText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Mengoptimalkan GPS... $_polishCountdown detik',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Foto akan diproses secara otomatis',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (!_isPolishing)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                color: Colors.black87,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                      ),
                    ),
                    GestureDetector(
                      onTap: _isTakingPhoto ? null : _ambilFoto,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 4,
                          ),
                          color: Colors.white.withOpacity(0.15),
                        ),
                        child: _isTakingPhoto
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              )
                            : const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 32,
                              ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGpsQualityIndicator() {
    if (_bestPosition == null) {
      return const SizedBox.shrink();
    }
    
    Color color;
    String label;
    
    if (_bestPosition!.accuracy <= 10) {
      color = Colors.green;
      label = 'Excellent';
    } else if (_bestPosition!.accuracy <= 20) {
      color = Colors.yellow;
      label = 'Good';
    } else if (_bestPosition!.accuracy <= 50) {
      color = Colors.orange;
      label = 'Fair';
    } else {
      color = Colors.red;
      label = 'Poor';
    }
    
    return Row(
      children: [
        Icon(Icons.gps_fixed, color: color, size: 12),
        const SizedBox(width: 4),
        Text(
          label, 
          style: TextStyle(color: color, fontSize: 10),
        ),
      ],
    );
  }
}

// ───────────────── BACKGROUND PROCESSING ─────────────────

class WatermarkParams {
  final img.Image image;
  final DateTime timestamp;
  final Position? position;
  final String address;

  WatermarkParams({
    required this.image,
    required this.timestamp,
    this.position,
    required this.address,
  });
}

img.Image? _decodeImage(Uint8List bytes) {
  return img.decodeImage(bytes);
}

Uint8List _encodeJpg(img.Image image) {
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

img.Image _addWatermarkAsync(WatermarkParams params) {
  final src = params.image;
  final now = params.timestamp;
  final pos = params.position;
  final alamat = params.address;

  final tanggal = DateFormat('dd MMM yyyy').format(now);
  final jam = DateFormat('HH:mm:ss').format(now);

  final gpsAvailable = pos != null;

  final lat = gpsAvailable
      ? pos.latitude.toStringAsFixed(6)
      : 'N/A';
  final lon = gpsAvailable
      ? pos.longitude.toStringAsFixed(6)
      : 'N/A';
  final acc = gpsAvailable
      ? '±${pos.accuracy.toStringAsFixed(1)}m'
      : 'GPS Unavailable';

  const stripHeight = 210;

  final isBottom = WatermarkLayoutService.position != 'top';
  final y0 = isBottom ? src.height - stripHeight : 0;

  img.fillRect(
    src,
    x1: 0,
    y1: y0,
    x2: src.width,
    y2: y0 + stripHeight,
    color: img.ColorRgba8(0, 0, 0, 170),
  );

  final font = img.arial24;
  final white = img.ColorRgba8(255, 255, 255, 255);
  final yellow = img.ColorRgba8(255, 200, 0, 255);
  final green = img.ColorRgba8(100, 220, 100, 255);
  final red = img.ColorRgba8(255, 80, 80, 255);

  final textY = y0 + 10;

  img.drawString(src, 'TermulLog',
      font: font, x: 16, y: textY, color: yellow);

  img.drawString(src, '$tanggal   $jam',
      font: font, x: 16, y: textY + 32, color: white);

  img.drawString(src, 'GPS: $lat, $lon',
      font: font, x: 16, y: textY + 64, color: white);

  img.drawString(src, 'Accuracy: $acc',
      font: font, x: 16, y: textY + 96, color: gpsAvailable ? green : red);

  img.drawString(src, alamat,
      font: font, x: 16, y: textY + 128, color: white);

  return src;
}

// ───────────────── KALMAN FILTER ─────────────────

class SimpleKalmanFilter {
  final double _q = 0.05;
  double _r = 10.0;
  double _p = 1.0;
  double? _x;

  double filter(double measurement, double measurementAccuracy) {
    _r = measurementAccuracy;

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
