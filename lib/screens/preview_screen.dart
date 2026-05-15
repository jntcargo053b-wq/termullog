// lib/screens/preview_screen.dart
import 'dart:io';
import 'dart:typed_data';
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
import 'package:async/async.dart';
import '../services/location_weather_service.dart';
import '../services/settings_cache.dart';
import '../core/constants.dart';
import '../watermark/watermark_params.dart';
import '../watermark/watermark_engine.dart';

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
  bool _isFileSaved = false;
  bool _isFileInUse = false;
  bool _isMiniMapLoading = false;
  String? _miniMapError;
  late AnimationController _checkAnimController;
  late Animation<double> _checkAnim;
  final TransformationController _transformController =
      TransformationController();
  Offset? _lastDoubleTapPos;
  final Random _rng = Random.secure();
  CancelableOperation<Uint8List>? _cancelableCompute;
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
    _cancelableCompute?.cancel();
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
    final historyDir = Directory('${appDir.path}/termullog_history');
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
      Uint8List bytes;
      if (widget.imageBytes != null) {
        bytes = widget.imageBytes!;
      } else if (widget.imagePath != null) {
        bytes = await File(widget.imagePath!).readAsBytes();
      } else {
        throw Exception('Tidak ada data gambar');
      }

      final timestamp = widget.timestamp ?? DateTime.now();
      final hasPosition = widget.latitude != null && widget.longitude != null;

      String address = widget.address ?? '';
      String weather = widget.weather ?? '';

      if (hasPosition && (address.isEmpty || weather.isEmpty)) {
        _processingStep.value = 'Mengambil alamat & cuaca...';
        try {
          final dummyPos = Position(
            latitude: widget.latitude!,
            longitude: widget.longitude!,
            accuracy: widget.accuracy ?? 0,
            altitude: 0, altitudeAccuracy: 0,
            heading: 0, headingAccuracy: 0,
            speed: 0, speedAccuracy: 0,
            timestamp: DateTime.now(),
          );
          final result = await LocationWeatherService.fetchFromPosition(dummyPos)
              .timeout(const Duration(seconds: 10));
          if (address.isEmpty && result.address.isNotEmpty) address = result.address;
          if (weather.isEmpty && result.weather.isNotEmpty) weather = result.weather;
        } catch (e) {
          if (address.isEmpty && hasPosition) {
            address = 'GPS: ${widget.latitude!.toStringAsFixed(5)}, ${widget.longitude!.toStringAsFixed(5)}';
          }
        }
      } else if (address.isEmpty && !hasPosition) {
        address = 'Tidak ada lokasi';
      }

      _processingStep.value = 'Memuat pengaturan...';
      await SettingsCache.preload();
      final layout = await SettingsCache.layout;
      final showWeather = await SettingsCache.showWeather;
      final showAccuracy = await SettingsCache.showAccuracy;
      final watermarkPosition = await SettingsCache.watermarkPosition;
      final showMiniMap = await SettingsCache.showMiniMap;
      final mapSize = await SettingsCache.mapSize;
      final mapZoomLevel = await SettingsCache.mapZoomLevel;

      Uint8List? mapBytes;
      if (showMiniMap && hasPosition) {
        _processingStep.value = 'Mengunduh peta mini...';
        setState(() => _isMiniMapLoading = true);
        try {
          mapBytes = await LocationWeatherService.fetchMapWithRetry(
            widget.latitude!, widget.longitude!,
          );
        } catch (_) {}
        setState(() => _isMiniMapLoading = false);
      }

      _processingStep.value = 'Membuat watermark...';
      final params = WatermarkEngine.createParams(
        imageBytes: bytes,
        timestamp: timestamp,
        layoutIndex: layout.index,
        address: address,
        weather: weather,
        showWeather: showWeather,
        showAccuracy: showAccuracy,
        watermarkPosition: watermarkPosition,
        showMiniMap: showMiniMap,
        lat: widget.latitude,
        lon: widget.longitude,
        acc: widget.accuracy,
        mapBytes: mapBytes,
        mapSize: mapSize,
        mapZoomLevel: mapZoomLevel,
      );

      _cancelableCompute = CancelableOperation.fromFuture(
        compute(WatermarkEngine.applyFromMap, params.toMap()),
      );
      final processedBytes = await _cancelableCompute!.value;

      _processingStep.value = 'Menyimpan file...';
      final historyDir = await _getHistoryDirectory();
      final fileName = _uniqueFileName(timestamp);
      final permanentFile = File('${historyDir.path}/$fileName');
      await permanentFile.writeAsBytes(processedBytes);

      if (mounted) {
        setState(() {
          _displayImagePath = permanentFile.path;
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: ${e.toString()}';
          _isProcessing = false;
        });
      }
    }
  }

  // ... SAVE, SHARE, UI methods (gunakan yang sudah ada dari file sebelumnya)
  // Saya sederhanakan untuk memastikan kompilasi berhasil
  
  Future<bool> _requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;
    if (sdkInt >= 29) return true;
    final status = await Permission.storage.request();
    return status.isGranted;
  }

  Future<void> _saveToGallery() async {
    if (_displayImagePath == null) return;
    await _requestStoragePermission();
    await GallerySaver.saveImage(_displayImagePath!, albumName: 'TermulLog');
  }

  Future<void> _sharePhoto() async {
    if (_displayImagePath == null) return;
    await Share.shareXFiles([XFile(_displayImagePath!)]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Preview Foto'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : _displayImagePath != null
              ? Image.file(File(_displayImagePath!), fit: BoxFit.contain)
              : const Center(child: Text('Tidak ada gambar', style: TextStyle(color: Colors.white))),
      bottomNavigationBar: _displayImagePath != null
          ? BottomAppBar(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(icon: const Icon(Icons.share), onPressed: _sharePhoto),
                  IconButton(icon: const Icon(Icons.save), onPressed: _saveToGallery),
                ],
              ),
            )
          : null,
    );
  }
}
