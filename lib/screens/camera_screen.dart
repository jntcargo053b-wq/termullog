import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isCameraReady = false;
  bool _isTorchOn = false;
  bool _isCapturing = false;

  final MobileScannerController _scannerController = MobileScannerController(
    formats: [BarcodeFormat.qrCode, BarcodeFormat.code128, BarcodeFormat.ean13],
    detectionSpeed: DetectionSpeed.normal,
  );

  String _lastScannedCode = '';
  String _photoPath = '';
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadHistory();
    _initCamera();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.camera.request();
    await Permission.storage.request();
  }

  Future<int> _androidSdkVersion() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.version.sdkInt;
    } catch (_) {
      return 0; // perbaikan: catch block dengan body
    }
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) return;
    try {
      _controller = CameraController(
        widget.cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _controller!.initialize();
      if (mounted) {
        setState(() => _isCameraReady = true);
      }
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() => _isCapturing = true);
    try {
      final XFile file = await _controller!.takePicture();
      final String path = file.path;

      // Simpan ke galeri (Android 10+ butuh izin khusus)
      if (Platform.isAndroid) {
        final int version = await _androidSdkVersion();
        if (version >= 29) {
          // Scoped storage: simpan di Pictures
          final dir = await getExternalStorageDirectories(type: StorageDirectory.pictures);
          if (dir != null) {
            final newPath = '${dir.first.path}/scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
            await File(file.path).copy(newPath);
            setState(() => _photoPath = newPath);
          } else {
            setState(() => _photoPath = path);
          }
        } else {
          setState(() => _photoPath = path);
        }
      } else {
        setState(() => _photoPath = path);
      }

      // Tambahkan ke history
      _addToHistory(_lastScannedCode, _photoPath);
    } catch (e) {
      debugPrint('Gagal ambil foto: $e');
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    final String code = capture.barcodes.first.rawValue ?? '';
    if (code.isNotEmpty && code != _lastScannedCode) {
      setState(() => _lastScannedCode = code);
      // Optional: langsung ambil foto jika setting auto-capture
      // _takePicture();
    }
  }

  Future<void> _sharePhoto() async {
    if (_photoPath.isEmpty) return;
    await Share.shareXFiles([XFile(_photoPath)], text: 'Hasil scan: $_lastScannedCode');
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? stored = prefs.getStringList('scan_history');
    if (stored != null) setState(() => _history = stored);
  }

  Future<void> _addToHistory(String code, String path) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> newHistory = [DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()), code, path, ..._history];
    if (newHistory.length > 50) newHistory.removeRange(50, newHistory.length);
    setState(() => _history = newHistory);
    await prefs.setStringList('scan_history', newHistory);
  }

  void _toggleTorch() async {
    if (_controller == null) return;
    _isTorchOn = !_isTorchOn;
    await _controller!.setFlashMode(_isTorchOn ? FlashMode.torch : FlashMode.off);
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scannerController.start();
    } else if (state == AppLifecycleState.paused) {
      _scannerController.stop();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _scannerController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TERMULScan'),
        actions: [
          IconButton(
            icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off),
            onPressed: _toggleTorch,
          ),
          IconButton(
            icon: const Icon(Icons.camera_alt),
            onPressed: _photoPath.isEmpty ? null : _sharePhoto,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Kamera untuk scanner
                MobileScanner(
                  controller: _scannerController,
                  onDetect: _onBarcodeDetected,
                ),
                // Overlay kotak scan
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.red, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  margin: const EdgeInsets.all(40),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black87,
            child: Column(
              children: [
                Text(
                  _lastScannedCode.isEmpty ? 'Belum ada scan' : _lastScannedCode,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Gap(12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isCameraReady && _lastScannedCode.isNotEmpty && !_isCapturing
                          ? _takePicture
                          : null,
                      icon: const Icon(Icons.camera),
                      label: Text(_isCapturing ? 'Mengambil...' : 'Ambil Foto'),
                    ),
                    const Gap(16),
                    ElevatedButton.icon(
                      onPressed: _photoPath.isEmpty ? null : () async {
                        await Share.shareXFiles([XFile(_photoPath)], text: _lastScannedCode);
                      },
                      icon: const Icon(Icons.share),
                      label: const Text('Bagikan'),
                    ),
                  ],
                ),
                if (_photoPath.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Foto tersimpan: ${_photoPath.split('/').last}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: _history.isEmpty
                ? const Center(child: Text('Belum ada riwayat'))
                : ListView.builder(
                    itemCount: _history.length ~/ 3,
                    itemBuilder: (ctx, i) {
                      final idx = i * 3;
                      return ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(_history[idx]),
                        subtitle: Text(_history[idx + 1]),
                        trailing: IconButton(
                          icon: const Icon(Icons.share),
                          onPressed: () => Share.shareXFiles([XFile(_history[idx + 2])], text: _history[idx + 1]),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
