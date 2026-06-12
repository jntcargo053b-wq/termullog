import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/camera_registry.dart';
import '../models/watermark_position.dart';
import '../services/pod_location_service.dart';
import '../services/settings_cache.dart';
import '../widgets/pod_gps_bar.dart';
import '../widgets/address_bar.dart';
import '../widgets/layout_picker_sheet.dart';
import '../widgets/draggable_watermark_overlay.dart';
import 'camera/camera_initializer.dart';
import 'camera/camera_settings_controller.dart';
import 'camera/photo_capture_controller.dart';
import 'camera/timestamp_stream.dart';

enum CaptureState {
  idle,
  waitingForGps,
  checking,
  capturing,
  succeeded,
  failed,
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  late final CameraInitializer _camera;
  late final CameraSettingsController _settings;
  late final PhotoCaptureController _capture;

  CaptureState _captureState = CaptureState.idle;
  bool _torchOn = false;
  bool _isMapLoading = false;
  WatermarkPosition _watermarkPos = WatermarkPosition.initial;
  Timer? _resetTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _camera = CameraInitializer(CameraRegistry.cameras);
    _settings = CameraSettingsController();
    _capture = const PhotoCaptureController();

    _loadWatermark();
    _settings.load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _loadWatermark() async {
    final pos = await SettingsCache.loadWatermarkPosition();
    if (mounted) setState(() => _watermarkPos = pos);
  }

  Future<void> _boot() async {
    if (!mounted) return;
    await Future.wait([
      CameraInitializer.requestGalleryPermission(),
      _initCamera(),
    ]);
    if (!mounted) return;
    unawaited(PodLocationService.instance.acquireForCapture());
  }

  Future<void> _initCamera() async {
    if (!mounted) return;
    try {
      await _camera.init(isMounted: () => mounted);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _takePhoto() async {
    if (_captureState != CaptureState.idle) return;

    final controller = _camera.controller;
    if (controller == null || !_camera.isReady) {
      _snack('Kamera belum siap', Colors.orange);
      return;
    }

    final gps = PodLocationService.instance.currentState;
    final gate = _capture.checkGpsGate(gps);

    switch (gate.gate) {
      case GpsGate.noPosition:
        _setCaptureState(CaptureState.waitingForGps);
        _snack('⏳ Menunggu posisi GPS…', Colors.orange);
        _scheduleReset(2);
        return;
      case GpsGate.blockedByAccuracy:
        _setCaptureState(CaptureState.failed);
        _snack(
          '❌ Akurasi GPS terlalu rendah (±${gate.accuracy.toStringAsFixed(0)}m > ${PhotoCaptureController.hardBlockAccuracy.toInt()}m)',
          Colors.red,
        );
        _scheduleReset(3);
        return;
      case GpsGate.needsConfirmation:
        _setCaptureState(CaptureState.checking);
        final proceed = await _confirmDialog(gps);
        if (proceed != true) {
          _setCaptureState(CaptureState.idle);
          return;
        }
        break;
      case GpsGate.ok:
        break;
    }

    HapticFeedback.mediumImpact();
    _setCaptureState(CaptureState.capturing);
    if (_settings.showMiniMap) setState(() => _isMapLoading = true);

    final result = await _capture.capture(
      controller: controller,
      gps: gps,
      settings: _settings.toCaptureSettings(),
    );

    if (mounted) setState(() => _isMapLoading = false);

    if (result.success) {
      _setCaptureState(CaptureState.succeeded);
      _snack(
        result.savedToGallery ? '✅ Foto tersimpan ke Galeri' : '✅ Foto tersimpan di internal',
        const Color(0xFF1A2540),
      );
      _scheduleReset(2);
    } else {
      _setCaptureState(CaptureState.failed);
      _snack('Gagal: ${result.errorMessage}', Colors.red);
      _scheduleReset(3);
    }

    PodLocationService.instance.releaseAfterCapture();
  }

  void _scheduleReset(int seconds) {
    _resetTimer?.cancel();
    _resetTimer = Timer(Duration(seconds: seconds), () {
      if (mounted &&
          (_captureState == CaptureState.waitingForGps ||
              _captureState == CaptureState.succeeded ||
              _captureState == CaptureState.failed)) {
        setState(() => _captureState = CaptureState.idle);
      }
      _resetTimer = null;
    });
  }

  void _cancelResetTimer() {
    _resetTimer?.cancel();
    _resetTimer = null;
  }

  void _setCaptureState(CaptureState state) {
    if (state == CaptureState.idle) _cancelResetTimer();
    if (mounted) setState(() => _captureState = state);
  }

  Future<bool?> _confirmDialog(PodLocationState gps) async {
    final acc = gps.accuracy ?? 0;
    final label = gps.confidence.label;
    final confidence = ((gps.lockResult?.confidenceScore ?? 0) * 100).toInt();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A0E1A),
        title: const Text('GPS Belum Stabil', style: TextStyle(color: Colors.white)),
        content: Text(
          'Status: $label\nAkurasi: ±${acc.toStringAsFixed(0)}m\nConfidence: $confidence%\n\nLanjutkan?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF9500)),
            child: const Text('Tetap Ambil'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: bg, duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _toggleTorch() async {
    if (_camera.controller == null || !_camera.isReady) {
      _snack('Kamera belum siap', Colors.orange);
      return;
    }
    final next = !_torchOn;
    try {
      await _camera.toggleTorch(next);
      if (mounted) setState(() => _torchOn = next);
    } catch (e) {
      _snack('Gagal mengubah lampu kilat', Colors.red);
    }
  }

  void _showLayoutPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0E1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => LayoutPickerSheet(
        current: _settings.layout,
        onSelect: (l) {
          _settings.setLayout(l);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      PodLocationService.instance.releaseAfterCapture();
      await _camera.dispose();
    } else if (state == AppLifecycleState.resumed) {
      await _initCamera();
      await _settings.reload();
      unawaited(PodLocationService.instance.acquireForCapture());
    }
  }

  @override
  void dispose() {
    _cancelResetTimer();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_camera.dispose());
    PodLocationService.instance.releaseAfterCapture();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _camera.controller;
    final previewReady = controller != null && controller.value.isInitialized && _camera.isReady;

    if (!previewReady) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Color(0xFF1E90FF)),
              const SizedBox(height: 16),
              const Text('Menginisialisasi kamera…', style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      );
    }

    final screenSize = MediaQuery.of(context).size;
    final canCapture = _captureState == CaptureState.idle;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(controller),
          _TimestampedOverlay(
            previewSize: screenSize,
            settings: _settings,
            initialPosition: _watermarkPos,
            gpsStream: PodLocationService.instance.stream,
            onPositionChanged: (pos) async {
              await SettingsCache.saveWatermarkPosition(pos);
              if (mounted) setState(() => _watermarkPos = pos);
            },
          ),
          if (_isMapLoading)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator(color: Color(0xFF1E90FF))),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: StreamBuilder<PodLocationState>(
              stream: PodLocationService.instance.stream,
              initialData: PodLocationService.instance.currentState,
              builder: (ctx, snapshot) {
                final gps = snapshot.data ?? PodLocationService.instance.currentState;
                return PodGpsBar(
                  confidence: gps.confidence,
                  accuracy: gps.accuracy,
                  lockProgress: gps.lockProgress,
                  fromCache: gps.fromCache,
                  addressLoading: gps.addressLoading,
                  isFallbackLock: gps.isFallbackLock,
                );
              },
            ),
          ),
          if (_settings.showAddress)
            Positioned(
              bottom: 130,
              left: 0,
              right: 0,
              child: StreamBuilder<PodLocationState>(
                stream: PodLocationService.instance.stream,
                initialData: PodLocationService.instance.currentState,
                builder: (ctx, snapshot) {
                  final gps = snapshot.data ?? PodLocationService.instance.currentState;
                  if (gps.address.isEmpty) return const SizedBox.shrink();
                  return AddressBar(
                    address: gps.address,
                    fromCache: gps.fromCache,
                    isLoading: gps.addressLoading,
                    isFastAddress: gps.isFastAddress,
                  );
                },
              ),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 110,
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8),
              color: const Color(0xCC000000),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off,
                        color: _torchOn ? const Color(0xFFFFD95A) : Colors.white54, size: 28),
                    onPressed: _captureState != CaptureState.idle ? null : _toggleTorch,
                  ),
                  GestureDetector(
                    onTap: _captureState != CaptureState.idle ? null : _takePhoto,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: _captureState != CaptureState.idle ? 64 : 72,
                      height: _captureState != CaptureState.idle ? 64 : 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _shutterColor(canCapture),
                        border: Border.all(color: _shutterBorderColor(canCapture), width: 4),
                      ),
                      child: _captureState != CaptureState.idle
                          ? const Padding(
                              padding: EdgeInsets.all(18),
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                          : null,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.layers_outlined, color: Colors.white54, size: 28),
                    onPressed: _captureState != CaptureState.idle ? null : _showLayoutPicker,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _shutterColor(bool canCapture) =>
      canCapture ? const Color(0x33FFFFFF) : Colors.grey.withOpacity(0.2);
  Color _shutterBorderColor(bool canCapture) =>
      canCapture ? Colors.white : Colors.white54;
}

class _TimestampedOverlay extends StatefulWidget {
  final Size previewSize;
  final CameraSettingsController settings;
  final WatermarkPosition initialPosition;
  final Stream<PodLocationState> gpsStream;
  final Function(WatermarkPosition) onPositionChanged;

  const _TimestampedOverlay({
    required this.previewSize,
    required this.settings,
    required this.initialPosition,
    required this.gpsStream,
    required this.onPositionChanged,
  });

  @override
  State<_TimestampedOverlay> createState() => _TimestampedOverlayState();
}

class _TimestampedOverlayState extends State<_TimestampedOverlay> {
  DateTime _now = DateTime.now();
  StreamSubscription<DateTime>? _timeSub;

  @override
  void initState() {
    super.initState();
    _timeSub = TimestampStream().stream.listen((time) {
      if (mounted) setState(() => _now = time);
    });
  }

  @override
  void dispose() {
    _timeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PodLocationState>(
      stream: widget.gpsStream,
      initialData: PodLocationService.instance.currentState,
      builder: (ctx, snapshot) {
        final gps = snapshot.data ?? const PodLocationState();
        return DraggableWatermarkOverlay(
          previewSize: widget.previewSize,
          timestamp: _now,
          hasPosition: gps.lat != null,
          lat: gps.lat,
          lon: gps.lon,
          acc: gps.accuracy,
          address: gps.address,
          weather: gps.weather,
          showWeather: widget.settings.showWeather,
          showAccuracy: widget.settings.showAccuracy,
          showAddress: widget.settings.showAddress,
          showCoordinates: widget.settings.showCoordinates,
          opacity: widget.settings.opacity,
          showBorder: widget.settings.showBorder,
          fontSize: widget.settings.fontSize,
          layout: widget.settings.layout,
          initialPosition: widget.initialPosition,
          onPositionChanged: widget.onPositionChanged,
          showSnapGuides: true,
        );
      },
    );
  }
}
