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

enum SaveStatus { idle, saving, saved, error }

const int _kMaxAddressLen = 55; // Diperpanjang untuk font lebih besar

// Gunakan warna dari constants.dart
final _blue = kColorLightBlue;
final _blueDim = kColorDimBlue;
final _white = kColorWhite;
final _offWhite = kColorOffWhite;
final _grey = kColorDarkGrey;
final _dark = kColorVeryDarkBg;
final _darker = kColorBlackerBg;

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
          final result = await LocationWeatherService.fetchFromPosition(position)
              .timeout(const Duration(seconds: 8));
          address = result.address;
          weather = result.weather;
        } catch (e) {
          debugPrint('Geocoding/weather error: $e');
          address = 'GPS: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
        }
      } else {
        address = 'Tidak ada lokasi';
      }

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

    if (src.width > kMaxOutputWidth || src.height > kMaxOutputWidth) {
      src = img.copyResize(
        src,
        width: src.width > src.height ? kMaxOutputWidth : null,
        height: src.height > src.width ? kMaxOutputWidth : null,
        interpolation: img.Interpolation.average,
      );
    }

    switch (layout) {
      case WatermarkLayout.minimal:
        return _layoutFilmStrip(src, timestamp, position, address, weather, showWeather, showAccuracy, watermarkPosition);
      case WatermarkLayout.modern:
        return _layoutDSLRCorner(src, timestamp, position, address, weather, showWeather, showAccuracy, watermarkPosition);
      case WatermarkLayout.elegant:
        return _layoutCinematic(src, timestamp, position, address, weather, showWeather, showAccuracy, watermarkPosition);
      case WatermarkLayout.professional:
        return _layoutFieldSurvey(src, timestamp, position, address, weather, showWeather, showAccuracy, watermarkPosition);
      case WatermarkLayout.semiTransparent:
        return _layoutHUD(src, timestamp, position, address, weather, showWeather, showAccuracy, watermarkPosition);
    }
  }

  // ── LAYOUT 1: FILM STRIP (DIPERBESAR) ─────────────────────────
  static Uint8List _layoutFilmStrip(
    img.Image src, DateTime timestamp, Position? position,
    String address, String weather, bool showWeather, bool showAccuracy, String watermarkPosition,
  ) {
    const int stripH = 95;  // Diperbesar dari 72
    const int borderH = 4;  // Diperbesar dari 3
    const int padX = 24;    // Diperbesar dari 20
    const int lineH = 28;   // Diperbesar dari 22
    final bool isTop = watermarkPosition == 'top';
    final int y0 = isTop ? 0 : src.height - stripH;
    if (y0 < 0) return Uint8List(0);

    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: src.height - 1,
        color: img.ColorRgba8(0, 0, 8, 255));
    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + borderH,
        color: img.ColorRgba8(30, 144, 255, 255));
    img.fillRect(src, x1: 0, y1: src.height - borderH, x2: src.width - 1, y2: src.height - 1,
        color: img.ColorRgba8(30, 144, 255, 255));
    img.fillCircle(src, x: padX + 6, y: y0 + borderH + 18, radius: 7,
        color: img.ColorRgba8(220, 30, 30, 255));

    final font = img.arial24;  // Ganti ke arial24 dari arial14
    int cy = y0 + borderH + 10;

    img.drawString(src, '   ${DateFormat('yyyy-MM-dd').format(timestamp)}  ${DateFormat('HH:mm:ss').format(timestamp)}',
        font: font, x: padX, y: cy, color: _white);
    cy += lineH;

    if (position != null) {
      final acc = showAccuracy ? '  ±${position.accuracy.toStringAsFixed(0)}m' : '';
      img.drawString(src,
          '${position.latitude.toStringAsFixed(6)}  ${position.longitude.toStringAsFixed(6)}$acc',
          font: font, x: padX, y: cy, color: _blue);
      cy += lineH;
    }

    String line3 = '';
    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      line3 = address.length > _kMaxAddressLen ? '${address.substring(0, _kMaxAddressLen - 1)}…' : address;
    } else if (showWeather && weather.isNotEmpty) {
      line3 = weather;
    }
    if (line3.isNotEmpty) {
      img.drawString(src, line3, font: font, x: padX, y: cy, color: _grey);
    }

    return Uint8List.fromList(img.encodeJpg(src, quality: kJpegQuality));
  }

  // ── LAYOUT 2: DSLR CORNER (DIPERBESAR) ────────────────────────
  static Uint8List _layoutDSLRCorner(
    img.Image src, DateTime timestamp, Position? position,
    String address, String weather, bool showWeather, bool showAccuracy, String watermarkPosition,
  ) {
    const int padX = 18;
    const int padY = 16;
    const int lineH = 26;   // Diperbesar dari 19
    const int brkLen = 22;  // Diperbesar dari 16
    const int brkW = 4;     // Diperbesar dari 3

    int rows = 2;
    if (position != null) rows += 2;
    if (showAccuracy && position != null) rows += 1;
    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) rows += 1;
    if (showWeather && weather.isNotEmpty) rows += 1;

    final int boxH = padY * 2 + rows * lineH;
    final int boxW = (src.width * 0.55).toInt().clamp(300, src.width - 30);
    final bool isTop = watermarkPosition == 'top';
    final int x0 = 20;
    final int y0 = isTop ? 20 : src.height - boxH - 20;
    final int x1 = x0 + boxW;
    final int y1 = y0 + boxH;

    for (int y = y0; y <= y1; y++) {
      for (int x = x0; x <= x1; x++) {
        if (x < 0 || x >= src.width || y < 0 || y >= src.height) continue;
        final px = src.getPixel(x, y);
        src.setPixel(x, y, img.ColorRgba8(
          ((px.r * 15) ~/ 100), ((px.g * 15) ~/ 100), ((px.b * 15) ~/ 100), 255));
      }
    }

    final blueColor = img.ColorRgba8(30, 144, 255, 255);
    img.fillRect(src, x1: x0, y1: y0, x2: x0 + brkLen, y2: y0 + brkW, color: blueColor);
    img.fillRect(src, x1: x0, y1: y0, x2: x0 + brkW, y2: y0 + brkLen, color: blueColor);
    img.fillRect(src, x1: x1 - brkLen, y1: y0, x2: x1, y2: y0 + brkW, color: blueColor);
    img.fillRect(src, x1: x1 - brkW, y1: y0, x2: x1, y2: y0 + brkLen, color: blueColor);
    img.fillRect(src, x1: x0, y1: y1 - brkW, x2: x0 + brkLen, y2: y1, color: blueColor);
    img.fillRect(src, x1: x0, y1: y1 - brkLen, x2: x0 + brkW, y2: y1, color: blueColor);
    img.fillRect(src, x1: x1 - brkLen, y1: y1 - brkW, x2: x1, y2: y1, color: blueColor);
    img.fillRect(src, x1: x1 - brkW, y1: y1 - brkLen, x2: x1, y2: y1, color: blueColor);

    final font = img.arial24;  // Ganti ke arial24
    int cy = y0 + padY;
    final int xT = x0 + padX;

    img.drawString(src, DateFormat('dd  MMM  yyyy').format(timestamp), font: font, x: xT, y: cy, color: _blue);
    cy += lineH;
    img.drawString(src, DateFormat('HH : mm : ss').format(timestamp), font: font, x: xT, y: cy, color: _white);
    cy += lineH;

    if (position != null) {
      img.drawString(src, 'N ${position.latitude.toStringAsFixed(6)}', font: font, x: xT, y: cy, color: _offWhite);
      cy += lineH;
      img.drawString(src, 'E ${position.longitude.toStringAsFixed(6)}', font: font, x: xT, y: cy, color: _offWhite);
      cy += lineH;
      if (showAccuracy) {
        img.drawString(src, 'ACC  ±${position.accuracy.toStringAsFixed(0)} m', font: font, x: xT, y: cy, color: _grey);
        cy += lineH;
      }
    }

    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      String sh = address.length > 50 ? '${address.substring(0, 47)}…' : address;
      img.drawString(src, sh, font: font, x: xT, y: cy, color: _grey);
      cy += lineH;
    }

    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, weather, font: font, x: xT, y: cy, color: _blue);
    }

    return Uint8List.fromList(img.encodeJpg(src, quality: kJpegQuality));
  }

  // ── LAYOUT 3: CINEMATIC (DIPERBESAR) ──────────────────────────
  static Uint8List _layoutCinematic(
    img.Image src, DateTime timestamp, Position? position,
    String address, String weather, bool showWeather, bool showAccuracy, String watermarkPosition,
  ) {
    const int gradH = 180;  // Diperbesar dari 140
    const int padX = 36;    // Diperbesar dari 28
    const int lineH = 28;   // Diperbesar dari 22
    final bool isTop = watermarkPosition == 'top';
    final int gradY0 = isTop ? 0 : src.height - gradH;

    for (int y = gradY0; y < gradY0 + gradH; y++) {
      if (y < 0 || y >= src.height) continue;
      final t = isTop ? 1.0 - (y - gradY0) / gradH : (y - gradY0) / gradH;
      final alpha = (t * 200).toInt().clamp(0, 200);
      for (int x = 0; x < src.width; x++) {
        final px = src.getPixel(x, y);
        src.setPixel(x, y, img.ColorRgba8(
          ((px.r * (255 - alpha)) ~/ 255),
          ((px.g * (255 - alpha)) ~/ 255),
          ((px.b * (255 - alpha)) ~/ 255), 255));
      }
    }

    final int divY = isTop ? gradH - 40 : gradY0 + 36;
    img.fillRect(src, x1: padX, y1: divY, x2: src.width - padX, y2: divY + 2,
        color: img.ColorRgba8(30, 144, 255, 200));

    final font = img.arial24;
    int cy = isTop ? 16 : gradY0 + 12;

    img.drawString(src, DateFormat('HH : mm : ss').format(timestamp), font: font, x: padX, y: cy, color: _white);
    cy += lineH;
    img.drawString(src, DateFormat('dd  MMMM  yyyy').format(timestamp), font: font, x: padX, y: cy, color: _blue);
    cy += lineH + 8;

    if (position != null) {
      img.drawString(src,
          '${position.latitude.toStringAsFixed(5)}°N   ${position.longitude.toStringAsFixed(5)}°E',
          font: font, x: padX, y: cy, color: _offWhite);
      cy += lineH;
      if (showAccuracy) {
        img.drawString(src, 'ACCURACY  ±${position.accuracy.toStringAsFixed(0)} M',
            font: font, x: padX, y: cy, color: _grey);
        cy += lineH;
      }
    }

    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      String sh = address.length > _kMaxAddressLen ? '${address.substring(0, _kMaxAddressLen - 1)}…' : address;
      img.drawString(src, sh, font: font, x: padX, y: cy, color: _grey);
      cy += lineH;
    }

    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, weather, font: font, x: padX, y: cy, color: _blue);
    }

    return Uint8List.fromList(img.encodeJpg(src, quality: kJpegQuality));
  }

  // ── LAYOUT 4: FIELD SURVEY (DIPERBESAR) ───────────────────────
  static Uint8List _layoutFieldSurvey(
    img.Image src, DateTime timestamp, Position? position,
    String address, String weather, bool showWeather, bool showAccuracy, String watermarkPosition,
  ) {
    const int headerH = 32;   // Diperbesar dari 22
    const int rowH = 28;      // Diperbesar dari 20
    const int padX = 16;      // Diperbesar dari 12
    const int colVal = 130;   // Diperbesar dari 100

    final List<List<String>> rows = [
      ['DATE', DateFormat('yyyy-MM-dd').format(timestamp)],
      ['TIME', DateFormat('HH:mm:ss').format(timestamp)],
    ];
    if (position != null) {
      rows.add(['LAT', '${position.latitude.toStringAsFixed(6)}°']);
      rows.add(['LON', '${position.longitude.toStringAsFixed(6)}°']);
      if (showAccuracy) rows.add(['ACC', '±${position.accuracy.toStringAsFixed(0)} m']);
    }
    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      rows.add(['ADDR', address.length > 50 ? '${address.substring(0, 47)}…' : address]);
    }
    if (showWeather && weather.isNotEmpty) rows.add(['WX', weather]);

    final int totalH = headerH + rows.length * rowH + 8;
    final bool isTop = watermarkPosition == 'top';
    final int y0 = isTop ? 0 : src.height - totalH;
    if (y0 < 0) return Uint8List(0);

    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + headerH,
        color: img.ColorRgba8(30, 144, 255, 255));
    img.drawString(src, 'TERMULOG  GEOTAGGED PHOTO',
        font: img.arial24, x: padX, y: y0 + 8,
        color: img.ColorRgba8(0, 0, 0, 255));

    final font = img.arial24;
    int cy = y0 + headerH;
    for (int i = 0; i < rows.length; i++) {
      img.fillRect(src, x1: 0, y1: cy, x2: src.width - 1, y2: cy + rowH,
          color: i.isEven ? img.ColorRgba8(0, 0, 12, 220) : img.ColorRgba8(10, 10, 28, 220));
      img.drawString(src, rows[i][0], font: font, x: padX, y: cy + 6, color: _grey);
      img.drawString(src, rows[i][1], font: font, x: padX + colVal, y: cy + 6,
          color: i < 2 ? _white : _blue);
      cy += rowH;
    }

    img.fillRect(src, x1: 0, y1: cy, x2: src.width - 1, y2: cy + 3,
        color: img.ColorRgba8(30, 144, 255, 200));

    return Uint8List.fromList(img.encodeJpg(src, quality: kJpegQuality));
  }

  // ── LAYOUT 5: HUD (DIPERBESAR) ────────────────────────────────
  static Uint8List _layoutHUD(
    img.Image src, DateTime timestamp, Position? position,
    String address, String weather, bool showWeather, bool showAccuracy, String watermarkPosition,
  ) {
    const int padX = 36;    // Diperbesar dari 28
    const int padY = 20;    // Diperbesar dari 16
    const int lineH = 28;   // Diperbesar dari 20
    const int accentH = 6;  // Diperbesar dari 4

    int rows = 2;  // Header + timestamp
    if (position != null) rows += 1;
    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) rows += 1;
    if (showWeather && weather.isNotEmpty) rows += 1;

    final int panelH = padY * 2 + rows * lineH + (rows - 1) * 6 + accentH;
    final bool isTop = watermarkPosition == 'top';
    final int y0 = isTop ? 0 : src.height - panelH;
    if (y0 < 0) return Uint8List(0);

    final int yEnd = src.height - accentH;
    for (int y = y0; y < yEnd; y++) {
      final progress = (y - y0) / (yEnd - y0).clamp(1, double.infinity);
      final alpha = (140 + (progress * 80)).toInt().clamp(0, 220);
      for (int x = 0; x < src.width; x++) {
        final px = src.getPixel(x, y);
        src.setPixel(x, y, img.ColorRgba8(
          ((px.r * (255 - alpha)) ~/ 255),
          ((px.g * (255 - alpha)) ~/ 255),
          ((px.b * (255 - alpha)) ~/ 255), 255));
      }
    }

    img.fillRect(src, x1: 0, y1: src.height - accentH, x2: src.width - 1, y2: src.height - 1,
        color: img.ColorRgba8(30, 144, 255, 255));
    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + 2,
        color: img.ColorRgba8(30, 144, 255, 120));

    final font = img.arial24;
    int cy = y0 + padY;

    img.drawString(src,
        '${DateFormat('dd MMM yyyy').format(timestamp)}   ${DateFormat('HH:mm:ss').format(timestamp)}',
        font: font, x: padX, y: cy, color: _white);
    cy += lineH + 6;

    if (position != null) {
      final acc = showAccuracy ? '   ±${position.accuracy.toStringAsFixed(0)}m' : '';
      img.drawString(src,
          '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}$acc',
          font: font, x: padX, y: cy, color: img.ColorRgba8(30, 144, 255, 255));
      cy += lineH + 6;
    }

    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      String sh = address.length > _kMaxAddressLen ? '${address.substring(0, _kMaxAddressLen - 1)}…' : address;
      img.drawString(src, sh, font: font, x: padX, y: cy, color: _grey);
      cy += lineH + 6;
    }

    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, weather, font: font, x: padX, y: cy, color: _white);
    }

    return Uint8List.fromList(img.encodeJpg(src, quality: kJpegQuality));
  }

  // ── SAVE & SHARE ─────────────────────────────────────────────

  Future<void> _saveToGallery() async {
    if (_saveStatus == SaveStatus.saving || _displayImagePath == null) return;
    setState(() => _saveStatus = SaveStatus.saving);

    try {
      final bool? result = await GallerySaver.saveImage(
        _displayImagePath!, albumName: 'TermulLog');

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
        content: Row(children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(msg)),
        ]),
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
        title: const Text('Preview Foto',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
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
            Text('Mengambil alamat & cuaca',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
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
            Text('Terjadi kesalahan: $_errorMessage',
                style: const TextStyle(color: Colors.white70)),
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
      return const Center(
          child: Text('Tidak ada gambar', style: TextStyle(color: Colors.white70)));
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
                        Text('Gagal memuat foto',
                            style: TextStyle(color: Colors.white38)),
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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _ActionButton(
                onPressed: _isSharing ? null : _sharePhoto,
                icon: _isSharing
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : isSaved
                ? ScaleTransition(scale: checkAnim, child: const Icon(Icons.check_circle, size: 20))
                : isError
                    ? const Icon(Icons.error_outline, size: 20)
                    : const Icon(Icons.save_alt, size: 20),
        label: Text(isSaving ? 'Menyimpan...' : isSaved ? 'Tersimpan!' : isError ? 'Gagal' : 'Simpan'),
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
