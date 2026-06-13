// lib/screens/preview_screen.dart
// FINAL PRODUCTION – folder history sinkron dengan HomeScreen & HistoryScreen
// Menyimpan ke ApplicationDocumentsDirectory/history (bukan termullog_history)
// Watermark processing, mini map, save ke galeri, share
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../services/location_weather_service.dart';
import '../services/settings_cache.dart';
import '../watermark/watermark_engine.dart';
import '../watermark/watermark_params.dart';

enum SaveStatus { idle, saving, saved, error }

class PreviewScreen extends StatefulWidget {
  final String? imagePath;
  final Uint8List? imageBytes;
  final DateTime? timestamp;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final String? address;
  final String? weather;

  const PreviewScreen({
    super.key,
    this.imagePath,
    this.imageBytes,
    this.timestamp,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.address,
    this.weather,
  }) : assert(imagePath != null || imageBytes != null,
            'Harus menyediakan imagePath atau imageBytes');

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen>
    with SingleTickerProviderStateMixin {
  String? _displayImagePath;
  bool _isProcessing = false;
  String? _errorMessage;
  SaveStatus _saveStatus = SaveStatus.idle;
  bool _isSharing = false;
  bool _isMiniMapLoading = false;
  String? _miniMapError;
  late AnimationController _checkAnimController;
  late Animation<double> _checkAnim;
  final TransformationController _transformController =
      TransformationController();
  Offset? _lastDoubleTapPos;
  final Random _rng = Random();
  final ValueNotifier<String> _processingStep =
      ValueNotifier<String>('Memuat gambar...');

  @override
  void initState() {
    super.initState();
    _checkAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _checkAnim = CurvedAnimation(
      parent: _checkAnimController,
      curve: Curves.elasticOut,
    );

    if (widget.imagePath != null) {
      _displayImagePath = widget.imagePath;
      if (widget.imageBytes != null || widget.timestamp != null) {
        _processImageAsync();
      }
    } else {
      _processImageAsync();
    }
  }

  @override
  void dispose() {
    _checkAnimController.dispose();
    _transformController.dispose();
    _processingStep.dispose();
    super.dispose();
  }

  String _uniqueFileName(DateTime ts) {
    final suffix = _rng.nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    return 'termullog_${ts.millisecondsSinceEpoch}_$suffix.jpg';
  }

  Future<Directory> _getHistoryDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final historyDir = Directory('${appDir.path}/history'); // sinkron dengan Home & History
    if (!await historyDir.exists()) {
      await historyDir.create(recursive: true);
    }
    return historyDir;
  }

  Future<void> _processImageAsync() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _isMiniMapLoading = false;
      _miniMapError = null;
    });
    _processingStep.value = 'Memuat gambar...';

    try {
      // ── 1. LOAD IMAGE BYTES ───────────────────────────────────────
      final Uint8List bytes;
      if (widget.imageBytes != null) {
        bytes = widget.imageBytes!;
      } else if (widget.imagePath != null) {
        bytes = await File(widget.imagePath!).readAsBytes();
      } else {
        throw Exception('Tidak ada data gambar');
      }

      final timestamp = widget.timestamp ?? DateTime.now();
      final hasPosition = widget.latitude != null && widget.longitude != null;

      // ── 2. GET ADDRESS & WEATHER ──────────────────────────────────
      String address = widget.address ?? '';
      String weather = widget.weather ?? '';

      if (hasPosition && (address.isEmpty || weather.isEmpty)) {
        _processingStep.value = 'Mengambil alamat & cuaca...';
        try {
          final dummyPos = Position(
            latitude: widget.latitude!,
            longitude: widget.longitude!,
            accuracy: widget.accuracy ?? 0,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
            timestamp: DateTime.now(),
          );
          final result = await LocationWeatherService.fetchFromPosition(dummyPos)
              .timeout(const Duration(seconds: 10));
          if (address.isEmpty && result.address.isNotEmpty) {
            address = result.address;
          }
          if (weather.isEmpty && result.weather.isNotEmpty) {
            weather = result.weather;
          }
        } catch (_) {
          if (address.isEmpty) {
            address = 'GPS: ${widget.latitude!.toStringAsFixed(5)}, ${widget.longitude!.toStringAsFixed(5)}';
          }
        }
      } else if (address.isEmpty && !hasPosition) {
        address = 'Tidak ada lokasi';
      }

      // ── 3. LOAD SETTINGS ──────────────────────────────────────────
      _processingStep.value = 'Memuat pengaturan...';
      await SettingsCache.preload();

      final layout = await SettingsCache.layout;
      final showWeather = await SettingsCache.showWeather;
      final showAccuracy = await SettingsCache.showAccuracy;
      final showMiniMap = await SettingsCache.showMiniMap;
      final mapSize = await SettingsCache.mapSize;
      final mapZoomLevel = await SettingsCache.mapZoomLevel;
      final showAddress = await SettingsCache.showAddress;
      final showCoordinates = await SettingsCache.showCoordinates;
      final opacity = await SettingsCache.opacity;
      final showBorder = await SettingsCache.showBorder;
      final fontSizeDouble = await SettingsCache.fontSize;
      final imageQuality = await SettingsCache.imageQuality;
      final dateFormat = await SettingsCache.dateFormat;
      final timeFormat = await SettingsCache.timeFormat;
      final fontSizeStr = fontSizeDouble <= 13
          ? 'small'
          : fontSizeDouble >= 20
              ? 'large'
              : 'normal';

      // ── 4. FETCH MINI MAP ─────────────────────────────────────────
      Uint8List? mapBytes;
      if (showMiniMap && hasPosition) {
        _isMiniMapLoading = true;
        _processingStep.value = 'Mengunduh peta mini...';
        if (mounted) setState(() {});
        try {
          mapBytes = await LocationWeatherService.fetchMapWithRetry(
            widget.latitude!,
            widget.longitude!,
          ).timeout(const Duration(seconds: 8));
          if (mapBytes == null || mapBytes.isEmpty) {
            _miniMapError = 'Gagal mengunduh peta';
          } else {
            _miniMapError = null;
          }
        } catch (e) {
          mapBytes = null;
          _miniMapError = 'Gagal mengunduh peta';
        } finally {
          _isMiniMapLoading = false;
          if (mounted) setState(() {});
        }
      }

      // ── 5. CREATE WATERMARK PARAMS ────────────────────────────────
      _processingStep.value = 'Membuat watermark...';
      final appName = await SettingsCache.appName;
      final customLogoBytes = await SettingsCache.getCustomLogoBytes();
      final params = WatermarkParams(
        imageBytes: bytes,
        timestamp: timestamp,
        layoutIndex: layout.index,
        address: address,
        weather: weather,
        showWeather: showWeather,
        showAccuracy: showAccuracy,
        showMiniMap: showMiniMap,
        lat: widget.latitude,
        lon: widget.longitude,
        acc: widget.accuracy,
        mapBytes: mapBytes,
        mapSize: mapSize,
        mapZoomLevel: mapZoomLevel,
        showAddress: showAddress,
        showCoordinates: showCoordinates,
        opacity: opacity,
        showBorder: showBorder,
        fontSize: fontSizeStr,
        fontScale: fontSizeDouble <= 13 ? 0.85 : fontSizeDouble >= 20 ? 1.2 : 1.0,
        imageQuality: imageQuality,
        dateFormat: dateFormat,
        timeFormat: timeFormat,
        appName: appName,
        showLogo: true,
        logoType: customLogoBytes != null ? 'custom' : null,
        customLogoBytes: customLogoBytes,
      );

      // ── 6. PROCESS WATERMARK ──────────────────────────────────────
      final processedBytes = await WatermarkEngine.process(params);

      // ── 7. SAVE TO PERMANENT HISTORY ──────────────────────────────
      _processingStep.value = 'Menyimpan file...';
      final historyDir = await _getHistoryDirectory();
      final permanentFile = File('${historyDir.path}/${_uniqueFileName(timestamp)}');
      await permanentFile.writeAsBytes(processedBytes);

      if (mounted) {
        setState(() {
          _displayImagePath = permanentFile.path;
          _isProcessing = false;
        });
      }
    } catch (e, stackTrace) {
      final msg = e.toString();
      if (msg.toLowerCase().contains('cancel')) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }
      debugPrint('❌ PreviewScreen processing error: $e\n$stackTrace');
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: $msg';
          _isProcessing = false;
        });
      }
    }
  }

  // ── PERMISSION & SAVE ─────────────────────────────────────────────
  Future<bool> _requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    if (sdkInt >= 29) return true;
    final status = await Permission.storage.request();
    if (status.isPermanentlyDenied) openAppSettings();
    return status.isGranted;
  }

  Future<void> _saveToGallery() async {
    if (_saveStatus == SaveStatus.saving || _displayImagePath == null) return;

    if (Platform.isAndroid) {
      if (!await _requestStoragePermission()) {
        _showErrorSnackbar('Izin penyimpanan diperlukan');
        return;
      }
    } else if (Platform.isIOS) {
      final status = await Permission.photos.request();
      if (!status.isGranted) {
        _showErrorSnackbar('Izin akses foto diperlukan');
        return;
      }
    }

    setState(() => _saveStatus = SaveStatus.saving);

    try {
      final result = await GallerySaver.saveImage(
        _displayImagePath!,
        albumName: 'TermulLog',
      );
      if (!mounted) return;

      if (result == true) {
        setState(() => _saveStatus = SaveStatus.saved);
        _checkAnimController.forward(from: 0);
        HapticFeedback.mediumImpact();
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _saveStatus = SaveStatus.idle);
        });
      } else {
        _handleSaveError('Gagal menyimpan foto');
      }
    } catch (e) {
      final msg = e.toString();
      _handleSaveError(
          'Gagal menyimpan: ${msg.length > 60 ? '${msg.substring(0, 60)}…' : msg}');
    }
  }

  void _handleSaveError(String msg) {
    if (!mounted) return;
    setState(() => _saveStatus = SaveStatus.error);
    _showErrorSnackbar(msg);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saveStatus = SaveStatus.idle);
    });
  }

  Future<void> _sharePhoto() async {
    if (_isSharing || _displayImagePath == null) return;
    setState(() => _isSharing = true);

    try {
      final file = File(_displayImagePath!);
      if (!await file.exists()) throw Exception('File tidak ada');
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Foto dengan GPS dari TermulLog',
        subject: 'Foto GPS TermulLog',
      );
      HapticFeedback.lightImpact();
    } catch (e) {
      final msg = e.toString();
      _showErrorSnackbar(
          'Gagal membagikan: ${msg.length > 60 ? '${msg.substring(0, 60)}…' : msg}');
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  void _showErrorSnackbar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Preview Foto',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isProcessing) return _buildProcessingView();
    if (_errorMessage != null) return _buildErrorView();
    if (_displayImagePath == null) return _buildEmptyView();
    return _buildImageView();
  }

  Widget _buildProcessingView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 24),
            ValueListenableBuilder<String>(
              valueListenable: _processingStep,
              builder: (_, step, __) => Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      step,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (_isMiniMapLoading) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.withAlpha(76)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.amber.shade300,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Mengunduh peta mini...',
                              style: TextStyle(
                                color: Colors.amber.shade300,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_miniMapError != null && !_isMiniMapLoading) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Colors.orange.withAlpha(76)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 16, color: Colors.orange.shade300),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Peta: $_miniMapError\nMelanjutkan tanpa peta...',
                              style: TextStyle(
                                color: Colors.orange.shade300,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Terjadi kesalahan',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Kembali'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade800,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() => _errorMessage = null);
                    _processImageAsync();
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Coba Lagi'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_not_supported, color: Colors.white38, size: 64),
          SizedBox(height: 16),
          Text(
            'Tidak ada gambar',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildImageView() {
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onDoubleTapDown: (details) =>
                _lastDoubleTapPos = details.localPosition,
            onDoubleTap: () {
              final scale = _transformController.value.getMaxScaleOnAxis();
              if (scale > 1.0) {
                _transformController.value = Matrix4.identity();
              } else {
                final pos = _lastDoubleTapPos ?? Offset.zero;
                _transformController.value = Matrix4.identity()
                  ..translate(-pos.dx * (2.5 - 1), -pos.dy * (2.5 - 1))
                  ..scale(2.5);
              }
            },
            child: InteractiveViewer(
              transformationController: _transformController,
              minScale: 0.8,
              maxScale: 4.0,
              child: Center(
                child: Hero(
                  tag: 'preview_photo',
                  child: Image.file(
                    File(_displayImagePath!),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image,
                              color: Colors.white38, size: 64),
                          SizedBox(height: 12),
                          Text(
                            'Gagal memuat foto',
                            style: TextStyle(color: Colors.white38),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      color: Colors.grey.shade900,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('Foto Lagi'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _ActionButton(
            onPressed: _isSharing ? null : _sharePhoto,
            icon: _isSharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.share_outlined, size: 20),
            label: 'Bagikan',
            color: Colors.blue.shade600,
          ),
          const SizedBox(width: 10),
          _SaveButton(
            status: _saveStatus,
            checkAnim: _checkAnim,
            onPressed:
                _saveStatus == SaveStatus.saving ? null : _saveToGallery,
          ),
        ],
      ),
    );
  }
}

// Reusable widgets
class _ActionButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget icon;
  final String label;
  final Color color;

  const _ActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final SaveStatus status;
  final Animation<double> checkAnim;
  final VoidCallback? onPressed;

  const _SaveButton({
    required this.status,
    required this.checkAnim,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isSaved = status == SaveStatus.saved;
    final isError = status == SaveStatus.error;
    final isSaving = status == SaveStatus.saving;

    final bgColor = isError
        ? Colors.red.shade600
        : isSaved
            ? Colors.green.shade800
            : Colors.green.shade600;

    final icon = isSaving
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        : isSaved
            ? ScaleTransition(
                scale: checkAnim,
                child: const Icon(Icons.check_circle, size: 20),
              )
            : isError
                ? const Icon(Icons.error_outline, size: 20)
                : const Icon(Icons.save_alt, size: 20);

    final labelText = isSaving
        ? 'Menyimpan...'
        : isSaved
            ? 'Tersimpan!'
            : isError
                ? 'Gagal'
                : 'Simpan';

    return Expanded(
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: Text(labelText),
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}
