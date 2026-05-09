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
import '../services/settings_service.dart';
import '../core/constants.dart';

// ─────────────────────────────────────────────────────────────
// ENUM STATUS SAVE
// ─────────────────────────────────────────────────────────────

enum SaveStatus { idle, saving, saved, error }

// Konstanta lokal
const int _kMaxAddressLen = 50;

// ─────────────────────────────────────────────────────────────
// PREVIEW SCREEN
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

      // Ambil pengaturan dari SharedPreferences
      final layout = await SettingsService.getWatermarkLayout();
      final showWeather = await SettingsService.getShowWeather();
      final showAccuracy = await SettingsService.getShowAccuracy();
      final watermarkPosition = await SettingsService.getWatermarkPosition();

      final processedBytes = await _computeWatermark(
        bytes, timestamp, position, address, weather,
        layout, showWeather, showAccuracy, watermarkPosition,
      );

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
    WatermarkLayout layout,
    bool showWeather,
    bool showAccuracy,
    String watermarkPosition,
  ) async {
    return await compute(_applyWatermark, {
      'bytes': imageBytes,
      'timestamp': timestamp,
      'position': position,
      'address': address,
      'weather': weather,
      'layout': layout.index,
      'showWeather': showWeather,
      'showAccuracy': showAccuracy,
      'watermarkPosition': watermarkPosition,
    });
  }

  static Uint8List _applyWatermark(Map<String, dynamic> params) {
    final bytes = params['bytes'] as Uint8List;
    final timestamp = params['timestamp'] as DateTime;
    final position = params['position'] as Position?;
    final address = params['address'] as String;
    final weather = params['weather'] as String;
    final layoutIndex = params['layout'] as int;
    final showWeather = params['showWeather'] as bool;
    final showAccuracy = params['showAccuracy'] as bool;
    final watermarkPosition = params['watermarkPosition'] as String;

    final layout = WatermarkLayout.values[layoutIndex];

    img.Image? src = img.decodeImage(bytes);
    if (src == null) throw Exception('Gagal decode gambar');

    // Resize jika terlalu besar
    if (src.width > kMaxOutputWidth || src.height > kMaxOutputWidth) {
      src = img.copyResize(
        src,
        width: src.width > src.height ? kMaxOutputWidth : null,
        height: src.height > src.width ? kMaxOutputWidth : null,
        interpolation: img.Interpolation.average,
      );
    }

    // Panggil method sesuai layout yang dipilih
    switch (layout) {
      case WatermarkLayout.minimal:
        return _applyMinimalWatermark(src, timestamp, position, address, weather, showWeather, showAccuracy, watermarkPosition);
      case WatermarkLayout.modern:
        return _applyModernWatermark(src, timestamp, position, address, weather, showWeather, showAccuracy, watermarkPosition);
      case WatermarkLayout.elegant:
        return _applyElegantWatermark(src, timestamp, position, address, weather, showWeather, showAccuracy, watermarkPosition);
      case WatermarkLayout.professional:
        return _applyProfessionalWatermark(src, timestamp, position, address, weather, showWeather, showAccuracy, watermarkPosition);
    }
  }

  // ============================================================
  // LAYOUT 1: MINIMALIS
  // ============================================================
  static Uint8List _applyMinimalWatermark(
    img.Image src,
    DateTime timestamp,
    Position? position,
    String address,
    String weather,
    bool showWeather,
    bool showAccuracy,
    String watermarkPosition,
  ) {
    const int watermarkHeight = 100;
    const int leftPadding = 12;
    const int lineHeight = 20;
    
    final bool isTop = watermarkPosition == 'top';
    final int y0 = isTop ? 0 : src.height - watermarkHeight;
    if (y0 < 0) return Uint8List(0);
    
    // Background hitam transparan
    img.fillRect(
      src,
      x1: 0, y1: y0, x2: src.width - 1, y2: y0 + watermarkHeight,
      color: img.ColorRgba8(0, 0, 0, 180),
    );
    
    int currentY = y0 + 8;
    final int xText = leftPadding;
    final white = img.ColorRgba8(255, 255, 255, 255);
    final font = img.arial14;
    
    // Header
    img.drawString(src, 'TERMULOG', font: font, x: xText, y: currentY, color: white);
    currentY += lineHeight;
    
    // Waktu
    final timeStr = DateFormat('dd/MM/yy HH:mm:ss').format(timestamp);
    img.drawString(src, timeStr, font: font, x: xText, y: currentY, color: white);
    currentY += lineHeight;
    
    // Koordinat
    if (position != null) {
      final coordStr = '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      img.drawString(src, coordStr, font: font, x: xText, y: currentY, color: white);
      currentY += lineHeight;
      
      if (showAccuracy) {
        final accStr = '±${position.accuracy.toStringAsFixed(0)}m';
        img.drawString(src, accStr, font: font, x: xText, y: currentY, color: white);
      }
    }
    
    final jpegData = img.encodeJpg(src, quality: kJpegQuality);
    return Uint8List.fromList(jpegData);
  }

  // ============================================================
  // LAYOUT 2: MODERN
  // ============================================================
  static Uint8List _applyModernWatermark(
    img.Image src,
    DateTime timestamp,
    Position? position,
    String address,
    String weather,
    bool showWeather,
    bool showAccuracy,
    String watermarkPosition,
  ) {
    const int watermarkHeight = 130;
    const int leftPadding = 16;
    const int lineHeight = 22;
    
    final bool isTop = watermarkPosition == 'top';
    final int y0 = isTop ? 0 : src.height - watermarkHeight;
    if (y0 < 0) return Uint8List(0);
    
    // Background
    img.fillRect(
      src,
      x1: 0, y1: y0, x2: src.width - 1, y2: y0 + watermarkHeight,
      color: img.ColorRgba8(10, 10, 20, 210),
    );
    
    // Garis aksen di kiri (cyan)
    img.fillRect(
      src,
      x1: 0, y1: y0, x2: 6, y2: y0 + watermarkHeight,
      color: img.ColorRgba8(0, 200, 180, 255),
    );
    
    int currentY = y0 + 10;
    final int xText = leftPadding + 8;
    
    final white = img.ColorRgba8(255, 255, 255, 255);
    final cyan = img.ColorRgba8(0, 200, 180, 255);
    final grey = img.ColorRgba8(170, 170, 170, 255);
    final font = img.arial14;
    final fontSmall = img.arial14;
    
    // Header dengan icon
    img.drawString(src, '📍 TERMULOG', font: font, x: xText, y: currentY, color: cyan);
    currentY += lineHeight;
    
    // Waktu
    final timeStr = DateFormat('HH:mm:ss').format(timestamp);
    final dateStr = DateFormat('dd/MM/yyyy').format(timestamp);
    img.drawString(src, '$timeStr  •  $dateStr', font: fontSmall, x: xText, y: currentY, color: white);
    currentY += lineHeight - 2;
    
    currentY += 2;
    
    // Koordinat
    if (position != null) {
      final latStr = position.latitude.toStringAsFixed(5);
      final lonStr = position.longitude.toStringAsFixed(5);
      img.drawString(src, '🌐 $latStr°, $lonStr°', font: fontSmall, x: xText, y: currentY, color: white);
      currentY += lineHeight - 2;
      
      if (showAccuracy) {
        final accStr = '±${position.accuracy.toStringAsFixed(0)}m';
        final cyanColor = position.accuracy <= 10 ? cyan : grey;
        img.drawString(src, '🎯 Akurasi: $accStr', font: fontSmall, x: xText, y: currentY, color: cyanColor);
        currentY += lineHeight - 2;
      }
    }
    
    // Alamat singkat
    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      String shortAddr = address;
      if (shortAddr.length > 40) shortAddr = '${shortAddr.substring(0, 37)}...';
      img.drawString(src, '🏠 $shortAddr', font: fontSmall, x: xText, y: currentY, color: grey);
      currentY += lineHeight - 2;
    }
    
    // Cuaca
    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, '🌤️ $weather', font: fontSmall, x: xText, y: currentY, color: cyan);
    }
    
    final jpegData = img.encodeJpg(src, quality: kJpegQuality);
    return Uint8List.fromList(jpegData);
  }

  // ============================================================
  // LAYOUT 3: ELEGAN
  // ============================================================
  static Uint8List _applyElegantWatermark(
    img.Image src,
    DateTime timestamp,
    Position? position,
    String address,
    String weather,
    bool showWeather,
    bool showAccuracy,
    String watermarkPosition,
  ) {
    const int watermarkHeight = 140;
    const int leftPadding = 20;
    const int lineHeight = 24;
    
    final bool isTop = watermarkPosition == 'top';
    final int y0 = isTop ? 0 : src.height - watermarkHeight;
    if (y0 < 0) return Uint8List(0);
    
    // Background glass morphism
    img.fillRect(
      src,
      x1: 0, y1: y0, x2: src.width - 1, y2: y0 + watermarkHeight,
      color: img.ColorRgba8(20, 20, 35, 220),
    );
    
    // Border atas tipis
    img.drawLine(
      src,
      x1: 0, y1: y0, x2: src.width - 1, y2: y0,
      color: img.ColorRgba8(0, 200, 180, 150),
      thickness: 2,
    );
    
    int currentY = y0 + 16;
    final int xText = leftPadding;
    
    final white = img.ColorRgba8(255, 255, 255, 255);
    final cyan = img.ColorRgba8(0, 200, 180, 255);
    final gold = img.ColorRgba8(255, 180, 50, 255);
    final grey = img.ColorRgba8(160, 160, 170, 255);
    final font = img.arial14;
    final fontSmall = img.arial14;
    
    // Header
    img.drawString(src, 'TERMULOG', font: font, x: xText, y: currentY, color: gold);
    currentY += lineHeight;
    
    // Tanggal lengkap
    final dateStr = DateFormat('dd MMMM yyyy', 'id_ID').format(timestamp);
    final timeStr = DateFormat('HH:mm:ss').format(timestamp);
    img.drawString(src, dateStr, font: fontSmall, x: xText, y: currentY, color: white);
    currentY += lineHeight - 4;
    img.drawString(src, timeStr, font: fontSmall, x: xText, y: currentY, color: cyan);
    currentY += lineHeight;
    
    currentY += 4;
    
    // Koordinat
    if (position != null) {
      final latStr = position.latitude.toStringAsFixed(5);
      final lonStr = position.longitude.toStringAsFixed(5);
      img.drawString(src, '$latStr°', font: fontSmall, x: xText, y: currentY, color: white);
      currentY += lineHeight - 4;
      img.drawString(src, '$lonStr°', font: fontSmall, x: xText, y: currentY, color: white);
      currentY += lineHeight;
      
      if (showAccuracy) {
        final accStr = 'Akurasi ±${position.accuracy.toStringAsFixed(0)} meter';
        final accColor = position.accuracy <= 10 ? cyan : grey;
        img.drawString(src, accStr, font: fontSmall, x: xText, y: currentY, color: accColor);
      }
    }
    
    final jpegData = img.encodeJpg(src, quality: kJpegQuality);
    return Uint8List.fromList(jpegData);
  }

  // ============================================================
  // LAYOUT 4: PROFESIONAL
  // ============================================================
  static Uint8List _applyProfessionalWatermark(
    img.Image src,
    DateTime timestamp,
    Position? position,
    String address,
    String weather,
    bool showWeather,
    bool showAccuracy,
    String watermarkPosition,
  ) {
    const int watermarkHeight = 150;
    const int leftPadding = 16;
    const int lineHeight = 22;
    
    final bool isTop = watermarkPosition == 'top';
    final int y0 = isTop ? 0 : src.height - watermarkHeight;
    if (y0 < 0) return Uint8List(0);
    
    // Background
    img.fillRect(
      src,
      x1: 0, y1: y0, x2: src.width - 1, y2: y0 + watermarkHeight,
      color: img.ColorRgba8(0, 0, 0, 200),
    );
    
    // Header bar
    img.fillRect(
      src,
      x1: 0, y1: y0, x2: src.width - 1, y2: y0 + 28,
      color: img.ColorRgba8(0, 200, 180, 255),
    );
    
    int currentY = y0 + 8;
    final int xText = leftPadding;
    
    final white = img.ColorRgba8(255, 255, 255, 255);
    final cyan = img.ColorRgba8(0, 200, 180, 255);
    final darkText = img.ColorRgba8(0, 0, 0, 255);
    final grey = img.ColorRgba8(200, 200, 200, 255);
    final font = img.arial14;
    final fontSmall = img.arial14;
    
    // Header di bar cyan
    img.drawString(src, 'TERMULOG DOCUMENT', font: font, x: xText, y: currentY, color: darkText);
    
    currentY = y0 + 38;
    
    // Info waktu
    final dateStr = DateFormat('dd/MM/yyyy').format(timestamp);
    final timeStr = DateFormat('HH:mm:ss').format(timestamp);
    img.drawString(src, 'DATE : $dateStr', font: fontSmall, x: xText, y: currentY, color: white);
    currentY += lineHeight - 2;
    img.drawString(src, 'TIME : $timeStr', font: fontSmall, x: xText, y: currentY, color: white);
    currentY += lineHeight - 2;
    
    currentY += 2;
    
    // Koordinat
    if (position != null) {
      final latStr = position.latitude.toStringAsFixed(6);
      final lonStr = position.longitude.toStringAsFixed(6);
      img.drawString(src, 'LAT : $latStr', font: fontSmall, x: xText, y: currentY, color: grey);
      currentY += lineHeight - 2;
      img.drawString(src, 'LON : $lonStr', font: fontSmall, x: xText, y: currentY, color: grey);
      currentY += lineHeight - 2;
      
      if (showAccuracy) {
        img.drawString(src, 'ACCURACY : ±${position.accuracy.toStringAsFixed(0)}m', font: fontSmall, x: xText, y: currentY, color: cyan);
        currentY += lineHeight - 2;
      }
    }
    
    // Alamat
    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      String shortAddr = address;
      if (shortAddr.length > 45) shortAddr = '${shortAddr.substring(0, 42)}...';
      img.drawString(src, 'ADDR : $shortAddr', font: fontSmall, x: xText, y: currentY, color: grey);
    }
    
    final jpegData = img.encodeJpg(src, quality: kJpegQuality);
    return Uint8List.fromList(jpegData);
  }

  // ============================================================
  // SAVE & SHARE
  // ============================================================

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
      String errorMsg = e.toString();
      if (errorMsg.length > 50) errorMsg = errorMsg.substring(0, 50);
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
