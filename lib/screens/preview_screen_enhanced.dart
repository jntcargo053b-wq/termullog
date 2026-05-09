import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import '../services/location_weather_service.dart';
import '../core/constants.dart';

// ─────────────────────────────────────────────────────────────
// ENUM STATUS SAVE
// ─────────────────────────────────────────────────────────────

enum SaveStatus { idle, saving, saved, error }

// Konstanta lokal untuk memastikan tidak error
const int _kMaxAddressLen = 44;
const int _kMaxErrorLen = 50;

// ─────────────────────────────────────────────────────────────
// PREVIEW SCREEN (dengan proses watermark & geocoding async)
// ─────────────────────────────────────────────────────────────

class PreviewScreen extends StatefulWidget {
  final String? imagePath;
  final Uint8List? imageBytes;
  final DateTime? timestamp;
  final Position? position;

  const PreviewScreen({
    super.key,
    this.imagePath,
    this.imageBytes,
    this.timestamp,
    this.position,
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
  late AnimationController _checkAnimController;
  late Animation<double> _checkAnim;
  final TransformationController _transformController = TransformationController();

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
    } else {
      _processImageAsync();
    }
  }

  @override
  void dispose() {
    _checkAnimController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  Future<void> _processImageAsync() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final bytes = widget.imageBytes!;
      final timestamp = widget.timestamp!;
      final position = widget.position;

      String address = '';
      String weather = '';
      if (position != null) {
        try {
          final result = await LocationWeatherService.fetchFromPosition(position).timeout(
            const Duration(seconds: 8),
          );
          address = result.address;
          weather = result.weather;
        } catch (e) {
          debugPrint('Geocoding/weather error: $e');
          address = 'GPS: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
        }
      } else {
        address = 'Tidak ada lokasi';
      }

      final processedBytes = await _computeWatermark(bytes, timestamp, position, address, weather);

      final dir = await getTemporaryDirectory();
      final fileName = 'termullog_${timestamp.millisecondsSinceEpoch}_temp.jpg';
      final tempFile = File('${dir.path}/$fileName');
      await tempFile.writeAsBytes(processedBytes);

      if (mounted) {
        setState(() {
          _displayImagePath = tempFile.path;
          _isProcessing = false;
        });
      }
    } catch (e) {
      debugPrint('Processing error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isProcessing = false;
        });
      }
    }
  }

  Future<Uint8List> _computeWatermark(
    Uint8List imageBytes,
    DateTime timestamp,
    Position? position,
    String address,
    String weather,
  ) async {
    return await compute(_applyWatermark, {
      'bytes': imageBytes,
      'timestamp': timestamp,
      'position': position,
      'address': address,
      'weather': weather,
    });
  }

  static Uint8List _applyWatermark(Map<String, dynamic> params) {
    final bytes = params['bytes'] as Uint8List;
    final timestamp = params['timestamp'] as DateTime;
    final position = params['position'] as Position?;
    final address = params['address'] as String;
    final weather = params['weather'] as String;

    img.Image? src = img.decodeImage(bytes);
    if (src == null) throw Exception('Gagal decode gambar');

    const maxDim = 1600;
    if (src.width > maxDim || src.height > maxDim) {
      src = img.copyResize(
        src,
        width: src.width > src.height ? maxDim : null,
        height: src.height > src.width ? maxDim : null,
        interpolation: img.Interpolation.average,
      );
    }

    const stripHeightRatio = 0.20;
    const minStripHeight = 120;
    const maxStripHeight = 220;
    const lineDivider = 6.5;
    const minLineHeight = 14;
    const maxLineHeight = 26;
    const startOffset = 8;
    const xPad = 10;

    final int stripHeight = (src.height * stripHeightRatio)
        .toInt()
        .clamp(minStripHeight, maxStripHeight);

    final y0 = src.height - stripHeight;
    if (y0 < 0) return Uint8List(0);

    img.fillRect(
      src,
      x1: 0, y1: y0, x2: src.width - 1, y2: y0 + stripHeight - 1,
      color: img.ColorRgba8(0, 0, 0, 190),
    );

    final font = src.width > 1500 ? img.arial24 : img.arial14;
    final white = img.ColorRgba8(255, 255, 255, 255);
    final yellow = img.ColorRgba8(255, 200, 0, 255);
    final green = img.ColorRgba8(100, 220, 100, 255);
    final grey = img.ColorRgba8(180, 180, 180, 255);

    final lineH = (stripHeight / lineDivider)
        .floor()
        .clamp(minLineHeight, maxLineHeight);
    final y = y0 + startOffset;

    if (y + lineH * 5 <= src.height) {
      img.drawString(src, 'TermulLog', font: font, x: xPad, y: y, color: yellow);
      final dateStr = DateFormat('dd/MM/yy').format(timestamp);
      final timeStr = DateFormat('HH:mm:ss').format(timestamp);
      img.drawString(src, '$dateStr  $timeStr', font: font, x: xPad, y: y + lineH, color: white);
      final latStr = position != null ? position.latitude.toStringAsFixed(6) : 'N/A';
      final lonStr = position != null ? position.longitude.toStringAsFixed(6) : 'N/A';
      img.drawString(src, '$latStr, $lonStr', font: font, x: xPad, y: y + lineH * 2, color: white);
      final accStr = position != null ? '±${position.accuracy.toStringAsFixed(0)}m' : 'No GPS';
      img.drawString(src, 'Akurasi: $accStr', font: font, x: xPad, y: y + lineH * 3,
          color: position != null ? green : white);
      String shortAddr = address;
      // FIX: Gunakan konstanta lokal _kMaxAddressLen
      if (shortAddr.length > _kMaxAddressLen) {
        shortAddr = '${shortAddr.substring(0, _kMaxAddressLen - 3)}...';
      }
      if (shortAddr.isNotEmpty) {
        img.drawString(src, shortAddr, font: font, x: xPad, y: y + lineH * 4, color: white);
      }
      if (weather.isNotEmpty && y + lineH * 5 < src.height) {
        img.drawString(src, 'Cuaca: $weather', font: font, x: xPad, y: y + lineH * 5, color: grey);
      }
    }

    final jpegData = img.encodeJpg(src, quality: 85);
    return Uint8List.fromList(jpegData);
  }

  Future<void> _saveToGallery() async {
    if (_saveStatus == SaveStatus.saving || _displayImagePath == null) return;
    setState(() => _saveStatus = SaveStatus.saving);

    try {
      final bool? result = await GallerySaver.saveImage(
        _displayImagePath!,
        albumName: 'TermulLog',
      );

      if (!mounted) return;

      if (result == true) {
        // Hapus temp file setelah tersimpan ke galeri
        try { await File(_displayImagePath!).delete(); } catch (_) {}
        setState(() => _saveStatus = SaveStatus.saved);
        _checkAnimController.forward(from: 0);
        HapticFeedback.mediumImpact();
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _saveStatus = SaveStatus.idle);
        });
      } else {
        setState(() => _saveStatus = SaveStatus.error);
        _showErrorSnackbar('Gagal menyimpan foto ke galeri');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _saveStatus = SaveStatus.idle);
        });
      }
    } catch (e) {
      setState(() => _saveStatus = SaveStatus.error);
      // FIX: Gunakan konstanta lokal _kMaxErrorLen
      String errorMsg = e.toString();
      if (errorMsg.length > _kMaxErrorLen) {
        errorMsg = errorMsg.substring(0, _kMaxErrorLen);
      }
      _showErrorSnackbar('Gagal menyimpan: $errorMsg');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _saveStatus = SaveStatus.idle);
      });
    }
  }

  Future<void> _sharePhoto() async {
    if (_isSharing || _displayImagePath == null) return;
    setState(() => _isSharing = true);

    try {
      final file = File(_displayImagePath!);
      if (!file.existsSync()) throw Exception('File tidak ada');
      await Share.shareXFiles(
        [XFile(_displayImagePath!)],
        text: 'Foto dengan GPS dari TermulLog',
        subject: 'Foto GPS TermulLog',
      );
      HapticFeedback.lightImpact();
    } catch (e) {
      _showErrorSnackbar('Gagal membagikan foto');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Preview Foto', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
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
    if (_isProcessing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Memproses foto...', style: TextStyle(color: Colors.white70)),
            SizedBox(height: 8),
            Text('Mengambil alamat & cuaca', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text('Terjadi kesalahan: $_errorMessage', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white24),
              child: const Text('Kembali'),
            ),
          ],
        ),
      );
    }

    if (_displayImagePath == null) {
      return const Center(child: Text('Tidak ada gambar', style: TextStyle(color: Colors.white70)));
    }

    return Column(
      children: [
        Expanded(
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
                        Icon(Icons.broken_image, color: Colors.white38, size: 64),
                        SizedBox(height: 12),
                        Text('Gagal memuat foto', style: TextStyle(color: Colors.white38)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Container(
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _ActionButton(
                onPressed: _isSharing ? null : _sharePhoto,
                icon: _isSharing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.share_outlined, size: 20),
                label: 'Bagikan',
                color: Colors.blue.shade600,
              ),
              const SizedBox(width: 10),
              _SaveButton(
                status: _saveStatus,
                checkAnim: _checkAnim,
                onPressed: _saveStatus == SaveStatus.saving ? null : _saveToGallery,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

    Color bgColor = Colors.green.shade600;
    if (isError) bgColor = Colors.red.shade600;
    if (isSaved) bgColor = Colors.green.shade800;

    return Expanded(
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: isSaving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : isSaved
                ? ScaleTransition(scale: checkAnim, child: const Icon(Icons.check_circle, size: 20))
                : isError
                    ? const Icon(Icons.error_outline, size: 20)
                    : const Icon(Icons.save_alt, size: 20),
        label: Text(
          isSaving ? 'Menyimpan...' : isSaved ? 'Tersimpan!' : isError ? 'Gagal' : 'Simpan',
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
      ),
    );
  }
}
