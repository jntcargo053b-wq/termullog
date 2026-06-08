// lib/screens/camera_screen.dart
// ============================================================
// CAMERA SCREEN — POD (Proof of Delivery) Edition
// (dengan isolate aktif untuk resize gambar)
// ============================================================

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../core/constants.dart';
import '../services/pod_location_service.dart';
import '../services/settings_cache.dart';
import '../watermark/watermark_engine.dart';
import '../watermark/watermark_params.dart';
import '../watermark/watermark_preview_painter.dart';
import '../widgets/pod_gps_bar.dart';

// Parameter untuk isolate
class _ResizeParams {
  final Uint8List rawBytes;
  final int quality;
  _ResizeParams(this.rawBytes, this.quality);
}

// Fungsi isolate (top-level)
Future<Uint8List> _resizeImageIsolate(_ResizeParams params) async {
  final originalImg = img.decodeImage(params.rawBytes);
  if (originalImg == null) return params.rawBytes;
  
  const int targetWidth = 1920;
  if (originalImg.width <= targetWidth) {
    return Uint8List.fromList(img.encodeJpg(originalImg, quality: params.quality));
  }
  
  final ratio = originalImg.height / originalImg.width;
  final h = (targetWidth * ratio).round();
  final resized = img.copyResize(originalImg, width: targetWidth, height: h);
  return Uint8List.fromList(img.encodeJpg(resized, quality: params.quality));
}

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  // ── Camera ────────────────────────────────────────────────
  CameraController? _controller;
  bool _isCameraReady = false;
  bool _isCapturing = false;
  bool _isCameraInit = false;
  Completer<void>? _initCompleter;
  bool _torchOn = false;

  // ── GPS State ────────────────────────────────────────────
  PodLocationState _gps = const PodLocationState();
  StreamSubscription<PodLocationState>? _gpsSub;

  // ── Clock ────────────────────────────────────────────────
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  // ── Settings ─────────────────────────────────────────────
  bool _showWeather = true;
  bool _showAccuracy = true;
  bool _showAddress = true;
  bool _showCoordinates = true;
  double _opacity = 0.88;
  bool _showBorder = true;
  WatermarkLayout _layout = WatermarkLayout.podCorporate;
  bool _showMiniMap = false;
  String _fontSize = 'normal';
  String _appName = 'TermulLog';
  Uint8List? _customLogoBytes;
  ui.Image? _customLogoImage; // decoded for live preview
  String _dateFormat = 'dd/MM/yyyy';
  String _timeFormat = 'HH:mm:ss';
  int _mapZoomLevel = 15;

  // ── UI State ─────────────────────────────────────────────
  bool _isMapLoading = false;

  static const double _hardBlockAccuracy = 35.0;
  static const double _warnAccuracy = 20.0;

  // ═══════════════════════════════════════════════════════════
  // Lifecycle
  // ═══════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettingsAsync();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    await Future.wait([
      _checkGalleryPermission(),
      _initCamera(),
    ]);
    _startClock();
    _subscribeGps();
    // GPS sudah start dari main.dart
  }

  void _subscribeGps() {
    _gps = PodLocationService.instance.currentState;
    _gpsSub = PodLocationService.instance.stream.listen((state) {
      if (!mounted) return;
      setState(() => _gps = state);
    });
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
    } else if (state == AppLifecycleState.resumed) {
      await _initCamera();
      await _reloadSettings();
      await PodLocationService.instance.restart();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _gpsSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // Camera
  // ═══════════════════════════════════════════════════════════

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
      _initCompleter?.complete();
    } catch (e) {
      debugPrint('Camera init error: $e');
      _initCompleter?.completeError(e);
    } finally {
      _isCameraInit = false;
    }
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
    } catch (_) {
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Capture (dengan isolate aktif)
  // ═══════════════════════════════════════════════════════════

  Future<void> _takePhoto() async {
    if (_isCapturing || _controller == null || !_controller!.value.isInitialized) {
      _snack('Kamera belum siap', Colors.orange);
      return;
    }

    final gpsSnapshot = _gps;

    if (gpsSnapshot.lat == null || gpsSnapshot.lon == null) {
      _snack('⏳ Menunggu posisi GPS…', Colors.orange);
      return;
    }

    final acc = gpsSnapshot.accuracy ?? 999.0;

    if (acc > _hardBlockAccuracy) {
      _snack('❌ Akurasi GPS terlalu rendah (±${acc.toStringAsFixed(0)}m > ${_hardBlockAccuracy.toInt()}m). '
          'Tunggu sampai sinyal lebih baik.', Colors.red);
      return;
    }

    if (!gpsSnapshot.confidence.canCapture || acc > _warnAccuracy) {
      final label = gpsSnapshot.confidence.label;
      final confidencePercent = ((gpsSnapshot.lockResult?.confidenceScore ?? 0) * 100).toInt();
      
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0A0E1A),
          title: const Text('GPS Belum Stabil',
              style: TextStyle(color: Colors.white)),
          content: Text(
            'Status: $label\n'
            'Akurasi: ±${acc.toStringAsFixed(0)}m\n'
            'Confidence: $confidencePercent%\n\n'
            'Foto mungkin memiliki lokasi kurang akurat.\nLanjutkan?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal',
                  style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFF9500)),
              child: const Text('Tetap Ambil'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isCapturing = true);

    try {
      final xFile = await _controller!.takePicture();
      final rawBytes = await File(xFile.path).readAsBytes();
      final captureTime = DateTime.now();
      final fontScale = await SettingsCache.getFontScale();
      final imageQuality = await SettingsCache.imageQuality;

      // 🔄 RESIZE MENGGUNAKAN ISOLATE (aktif kembali)
      Uint8List finalBytes;
      try {
        finalBytes = await compute(_resizeImageIsolate, _ResizeParams(rawBytes, imageQuality));
      } catch (e) {
        debugPrint('Isolate resize gagal, fallback sync: $e');
        finalBytes = await _resizeImageSync(rawBytes, imageQuality);
      }

      // Mini map
      Uint8List? mapBytes;
      if (_showMiniMap && gpsSnapshot.lat != null && gpsSnapshot.lon != null) {
        if (mounted) setState(() => _isMapLoading = true);
        mapBytes = await _fetchMapBytes(gpsSnapshot.lat!, gpsSnapshot.lon!);
        if (mounted) setState(() => _isMapLoading = false);
      }

      final params = WatermarkParams(
        imageBytes: finalBytes,
        timestamp: captureTime,
        address: gpsSnapshot.address,
        weather: gpsSnapshot.weather,
        layoutIndex: _layout.index,
        showWeather: _showWeather,
        showAccuracy: _showAccuracy,
        showAddress: _showAddress,
        showCoordinates: _showCoordinates,
        opacity: _opacity,
        showBorder: _showBorder,
        lat: gpsSnapshot.lat,
        lon: gpsSnapshot.lon,
        acc: gpsSnapshot.accuracy,
        fontScale: fontScale,
        imageQuality: imageQuality,
        appName: _appName,
        showLogo: true,
        logoType: _customLogoBytes != null ? 'custom' : null,
        customLogoBytes: _customLogoBytes,
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

      final saved = await GallerySaver.saveImage(outPath, albumName: 'TermulLog');
      if (saved == true) {
        _snack('✅ Foto tersimpan ke Galeri', const Color(0xFF1A2540));
      } else {
        _snack('✅ Foto tersimpan di internal', const Color(0xFF1A2540));
      }

      await File(xFile.path).delete();
    } catch (e) {
      debugPrint('Capture error: $e');
      _snack('Gagal: ${e.toString().split('\n').first}', Colors.red);
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  // Resize sync (fallback)
  Future<Uint8List> _resizeImageSync(Uint8List rawBytes, int quality) async {
    final originalImg = img.decodeImage(rawBytes);
    if (originalImg == null) return rawBytes;
    const int targetWidth = 1920;
    if (originalImg.width <= targetWidth) {
      return Uint8List.fromList(img.encodeJpg(originalImg, quality: quality));
    }
    final ratio = originalImg.height / originalImg.width;
    final h = (targetWidth * ratio).round();
    final resized = img.copyResize(originalImg, width: targetWidth, height: h);
    return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  }

  Future<Uint8List?> _fetchMapBytes(double lat, double lon) async {
    try {
      final url = Uri.parse(
          'https://staticmap.openstreetmap.de/staticmap.php'
          '?center=$lat,$lon&zoom=$_mapZoomLevel&size=240x240&maptype=mapnik');
      final res = await http.get(
        url,
        headers: {
          'User-Agent': 'TermulLog-POD/3.0 (Android; +https://termullog.example.com)',
        },
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return res.bodyBytes;
    } catch (e) {
      debugPrint('Map fetch error: $e');
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════
  // Settings
  // ═══════════════════════════════════════════════════════════

  Future<void> _loadSettingsAsync() async {
    await SettingsCache.preload();
    await Future.wait([
      SettingsCache.showWeather.then((v) => _showWeather = v),
      SettingsCache.showAccuracy.then((v) => _showAccuracy = v),
      SettingsCache.showAddress.then((v) => _showAddress = v),
      SettingsCache.showCoordinates.then((v) => _showCoordinates = v),
      SettingsCache.opacity.then((v) => _opacity = v),
      SettingsCache.showBorder.then((v) => _showBorder = v),
      SettingsCache.layout.then((v) => _layout = v),
      SettingsCache.showMiniMap.then((v) => _showMiniMap = v),
      SettingsCache.mapZoomLevel.then((v) => _mapZoomLevel = v),
      SettingsCache.dateFormat.then((v) => _dateFormat = v),
      SettingsCache.timeFormat.then((v) => _timeFormat = v),
      SettingsCache.fontSize.then((v) =>
          _fontSize = v <= 13 ? 'small' : v >= 20 ? 'large' : 'normal'),
      SettingsCache.appName.then((v) => _appName = v),
      SettingsCache.getCustomLogoBytes().then((v) async {
        _customLogoBytes = v;
        if (v != null) {
          try {
            final codec = await ui.instantiateImageCodec(v);
            final frame = await codec.getNextFrame();
            _customLogoImage = frame.image;
          } catch (_) {
            _customLogoImage = null;
          }
        } else {
          _customLogoImage = null;
        }
      }),
    ]);
    if (mounted) setState(() {});
  }

  Future<void> _reloadSettings() async {
    SettingsCache.invalidate();
    await _loadSettingsAsync();
  }

  void _startClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  Future<void> _toggleTorch() async {
    try {
      _torchOn = !_torchOn;
      await _controller?.setFlashMode(_torchOn ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _snack(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: bg,
      duration: const Duration(seconds: 2),
    ));
  }

  // ═══════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════

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
              if (_gps.address.isNotEmpty) ...[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _gps.address,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),
          CustomPaint(
            painter: WatermarkPreviewPainter(
              timestamp: _now,
              hasPosition: _gps.lat != null,
              lat: _gps.lat,
              lon: _gps.lon,
              acc: _gps.accuracy,
              address: _gps.address,
              weather: _gps.weather,
              showWeather: _showWeather,
              showAccuracy: _showAccuracy,
              showAddress: _showAddress,
              showCoordinates: _showCoordinates,
              opacity: _opacity,
              showBorder: _showBorder,
              layout: _layout,
              appName: _appName,
              showLogo: true,
              logoType: _customLogoBytes != null ? 'custom' : null,
              customLogo: _customLogoImage,
              timeFormat: _timeFormat,
              fontScale: _fontSize == 'small' ? 0.8 : _fontSize == 'large' ? 1.2 : 1.0,
            ),
          ),
          if (_isMapLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFF1E90FF)),
              ),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: PodGpsBar(
              confidence: _gps.confidence,
              accuracy: _gps.accuracy,
              lockProgress: _gps.lockProgress,
              fromCache: _gps.fromCache,
              addressLoading: _gps.addressLoading,
              isFallbackLock: _gps.isFallbackLock,
            ),
          ),
          if (_gps.address.isNotEmpty && _showAddress)
            Positioned(
              bottom: 130,
              left: 0,
              right: 0,
              child: _AddressBar(
                address: _gps.address,
                fromCache: _gps.fromCache,
                isLoading: _gps.addressLoading,
                isFastAddress: _gps.isFastAddress,
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
                children: [
                  IconButton(
                    icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off,
                        color: _torchOn ? const Color(0xFFFFD95A) : Colors.white54, size: 28),
                    onPressed: _toggleTorch,
                  ),
                  GestureDetector(
                    onTap: _isCapturing ? null : _takePhoto,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: _isCapturing ? 64 : 72,
                      height: _isCapturing ? 64 : 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _shutterColor(),
                        border: Border.all(color: _shutterBorderColor(), width: 4),
                      ),
                      child: _isCapturing
                          ? const Padding(
                              padding: EdgeInsets.all(18),
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
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

  Color _shutterColor() {
    if (_isCapturing) return Colors.grey.withOpacity(0.2);
    if (_gps.confidence == PodConfidence.excellent) return const Color(0x22AAFFAA);
    return const Color(0x33FFFFFF);
  }

  Color _shutterBorderColor() {
    if (_isCapturing) return Colors.grey;
    if (_gps.confidence == PodConfidence.excellent) return const Color(0xFF3CB86A);
    if (_gps.confidence == PodConfidence.good) return Colors.white;
    return Colors.white54;
  }

  void _showLayoutPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0E1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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

// ==================== SUB-WIDGETS ====================

class _AddressBar extends StatelessWidget {
  final String address;
  final bool fromCache;
  final bool isLoading;
  final bool isFastAddress;

  const _AddressBar({
    required this.address,
    required this.fromCache,
    required this.isLoading,
    this.isFastAddress = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = fromCache
        ? const Color(0xFFCC9000)
        : (isFastAddress ? Colors.cyan.shade300 : Colors.white70);
    final borderColor = fromCache
        ? const Color(0x40FF9500)
        : (isFastAddress ? const Color(0x401E90FF) : const Color(0x401E90FF));
    final icon = fromCache
        ? Icons.history_outlined
        : (isFastAddress ? Icons.speed_outlined : Icons.location_on_outlined);
    final iconColor = fromCache
        ? const Color(0xFFFF9500)
        : (isFastAddress ? const Color(0xFF00BCD4) : const Color(0xFF1E90FF));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isFastAddress && !fromCache && !isLoading)
                  const Text('⏳ Memperbarui alamat akurat...',
                      style: TextStyle(color: Colors.cyan, fontSize: 9)),
                Text(address, style: TextStyle(color: color, fontSize: 11),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (isLoading) ...[
            const SizedBox(width: 6),
            const SizedBox(width: 8, height: 8,
                child: CircularProgressIndicator(strokeWidth: 1.2,
                    valueColor: AlwaysStoppedAnimation(Color(0xFFFF9500)))),
          ],
        ],
      ),
    );
  }
}

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
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        const Text('Pilih Gaya Watermark',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
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
              child: Icon(_iconFor(l),
                  color: selected ? const Color(0xFF1E90FF) : Colors.white38, size: 18),
            ),
            title: Text(l.displayName,
                style: TextStyle(color: selected ? Colors.white : Colors.white70, fontSize: 14,
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
      case WatermarkLayout.podCorporate: return Icons.article_rounded;
      case WatermarkLayout.podDarkField: return Icons.camera_alt_rounded;
      case WatermarkLayout.podGovern: return Icons.verified_rounded;
    }
  }
}
