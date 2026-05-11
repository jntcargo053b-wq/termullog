import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:math';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import '../services/location_weather_service.dart';
import '../services/settings_cache.dart';
import '../core/constants.dart';

// ─────────────────────────────────────────────────────────────
// ENUM STATUS SAVE
// ─────────────────────────────────────────────────────────────

enum SaveStatus { idle, saving, saved, error }

// konstanta lokal
const int _kMaxAddressLen = 55;

// warna dari constants.dart
final _blue = kColorLightBlue;
final _blueDim = kColorDimBlue;
final _white = kColorWhite;
final _offWhite = kColorOffWhite;
final _grey = kColorDarkGrey;
final _dark = kColorVeryDarkBg;
final _darker = kColorBlackerBg;

// ─────────────────────────────────────────────────────────────
// PREVIEW SCREEN
// ─────────────────────────────────────────────────────────────

class PreviewScreen extends StatefulWidget {
  final String? imagePath;
  final Uint8List? imageBytes;
  final DateTime? timestamp;
  final Position? position;
  final String? address;
  final String? weather;

  const PreviewScreen({
    super.key,
    this.imagePath,
    this.imageBytes,
    this.timestamp,
    this.position,
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
  late AnimationController _checkAnimController;
  late Animation<double> _checkAnim;
  final TransformationController _transformController = TransformationController();
  Offset? _lastDoubleTapPos;
  final Random _rng = Random.secure();

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
    final pathToDelete = _displayImagePath;
    final shouldDelete = !_isFileSaved && !_isProcessing && !_isFileInUse;
    _checkAnimController.dispose();
    _transformController.dispose();
    super.dispose();
    if (pathToDelete != null && shouldDelete) {
      Future.microtask(() async {
        try {
          final f = File(pathToDelete);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      });
    }
  }

  String _uniqueTempName(DateTime ts) {
    final suffix = _rng.nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    return 'termullog_${ts.millisecondsSinceEpoch}_$suffix.jpg';
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

      String address = widget.address ?? '';
      String weather = widget.weather ?? '';

      if (address.isEmpty && position != null) {
        try {
          final result = await LocationWeatherService.fetchFromPosition(position)
              .timeout(const Duration(seconds: 10));
          address = result.address;
          weather = result.weather;
        } catch (e) {
          debugPrint('Geocoding/weather error: $e');
          address = 'GPS: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
        }
      } else if (address.isEmpty && position == null) {
        address = 'Tidak ada lokasi';
      }

      final layout = await SettingsCache.layout;
      final showWeather = await SettingsCache.showWeather;
      final showAccuracy = await SettingsCache.showAccuracy;
      final watermarkPosition = await SettingsCache.watermarkPosition;
      final showMiniMap = await SettingsCache.showMiniMap;

      Uint8List? mapBytes;
      if (showMiniMap && position != null && layout == WatermarkLayout.professional) {
        try {
          mapBytes = await LocationWeatherService.fetchMapWithRetry(
            position.latitude,
            position.longitude,
          );
          if (mapBytes != null) debugPrint('Mini map fetched');
          else debugPrint('Mini map fetch failed');
        } catch (e) {
          debugPrint('Mini map fetch error: $e');
        }
      }

      final processedBytes = await _computeWatermark(
        bytes, timestamp, position, address, weather,
        layout, showWeather, showAccuracy, watermarkPosition, showMiniMap, mapBytes,
      );

      final dir = await getTemporaryDirectory();
      final fileName = _uniqueTempName(timestamp);
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
    bool showMiniMap,
    Uint8List? mapBytes,
  ) async {
    final transferable = TransferableTypedData.fromList([imageBytes]);
    final params = {
      'transferable': transferable,
      'timestamp': timestamp,
      'position': position,
      'address': address,
      'weather': weather,
      'layout': layout.index,
      'showWeather': showWeather,
      'showAccuracy': showAccuracy,
      'watermarkPosition': watermarkPosition,
      'showMiniMap': showMiniMap,
      'mapBytes': mapBytes,
    };
    return await compute(_applyWatermarkTransfer, params);
  }

  static Uint8List _applyWatermarkTransfer(Map<String, dynamic> params) {
    final transferable = params['transferable'] as TransferableTypedData;
    final bytes = transferable.materialize().asUint8List();
    final newParams = Map<String, dynamic>.from(params);
    newParams['bytes'] = bytes;
    newParams.remove('transferable');
    return _applyWatermark(newParams);
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
    final showMiniMap = params['showMiniMap'] as bool? ?? false;
    final mapBytes = params['mapBytes'] as Uint8List?;

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

    Uint8List result;
    switch (layout) {
      case WatermarkLayout.minimal:
        result = _layoutFilmStrip(src, timestamp, position, address, weather, showWeather, showAccuracy, watermarkPosition);
        break;
      case WatermarkLayout.modern:
        result = _layoutDSLRCorner(src, timestamp, position, address, weather, showWeather, showAccuracy, watermarkPosition);
        break;
      case WatermarkLayout.elegant:
        result = _layoutCinematic(src, timestamp, position, address, weather, showWeather, showAccuracy, watermarkPosition);
        break;
      case WatermarkLayout.professional:
        _drawFieldSurveyOnSrc(src, timestamp, position, address, weather, showWeather, showAccuracy, watermarkPosition);
        if (showMiniMap && mapBytes != null && position != null) {
          _addMiniMapTopRight(src, mapBytes);
        }
        result = Uint8List.fromList(img.encodeJpg(src, quality: kJpegQuality));
        break;
      case WatermarkLayout.semiTransparent:
        result = _layoutHUD(src, timestamp, position, address, weather, showWeather, showAccuracy, watermarkPosition);
        break;
    }
    return result;
  }

  // ── LAYOUT 1: FILM STRIP ─────────────────────────────────────
  static Uint8List _layoutFilmStrip(
    img.Image src, DateTime timestamp, Position? position,
    String address, String weather, bool showWeather, bool showAccuracy, String watermarkPosition,
  ) {
    const int stripH = 95;
    const int borderH = 4;
    const int padX = 24;
    const int lineH = 28;
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

    final font = img.arial24;
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

  // ── LAYOUT 2: DSLR CORNER ────────────────────────────────────
  static Uint8List _layoutDSLRCorner(
    img.Image src, DateTime timestamp, Position? position,
    String address, String weather, bool showWeather, bool showAccuracy, String watermarkPosition,
  ) {
    const int padX = 18;
    const int padY = 16;
    const int lineH = 26;
    const int brkLen = 22;
    const int brkW = 4;

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

    final font = img.arial24;
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

  // ── LAYOUT 3: CINEMATIC ──────────────────────────────────────
  static Uint8List _layoutCinematic(
    img.Image src, DateTime timestamp, Position? position,
    String address, String weather, bool showWeather, bool showAccuracy, String watermarkPosition,
  ) {
    const int gradH = 180;
    const int padX = 36;
    const int lineH = 28;
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

  // ── LAYOUT 4: FIELD SURVEY (modifikasi langsung src) ─────────
  static void _drawFieldSurveyOnSrc(
    img.Image src, DateTime timestamp, Position? position,
    String address, String weather, bool showWeather, bool showAccuracy, String watermarkPosition,
  ) {
    const int headerH = 32;
    const int rowH = 28;
    const int padX = 16;
    const int colVal = 130;

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

    final int totalRows = rows.length;
    final int totalH = headerH + totalRows * rowH + 12;
    final bool isTop = watermarkPosition == 'top';
    final int y0 = isTop ? 0 : src.height - totalH;
    if (y0 < 0) return;

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
  }

  // ── MINI MAP ────────────────────────────────────────────────
  static void _addMiniMapTopRight(img.Image src, Uint8List? mapBytes) {
    if (mapBytes == null) return;
    try {
      final mapImage = img.decodeImage(mapBytes);
      if (mapImage == null) return;
      const int mapWidth = 220;
      const int mapHeight = 140;
      final resizedMap = img.copyResize(mapImage, width: mapWidth, height: mapHeight);
      final mapX = src.width - mapWidth - 16;
      final mapY = 16;
      if (mapX > 0 && mapY > 0) {
        img.compositeImage(src, resizedMap, dstX: mapX, dstY: mapY);
        img.drawRect(src,
            x1: mapX - 1, y1: mapY - 1,
            x2: mapX + mapWidth, y2: mapY + mapHeight,
            color: img.ColorRgba8(30, 144, 255, 255), thickness: 2);
        final centerX = mapX + mapWidth ~/ 2;
        final centerY = mapY + mapHeight ~/ 2;
        img.fillCircle(src, x: centerX, y: centerY, radius: 6,
            color: img.ColorRgba8(255, 50, 50, 255));
        img.fillCircle(src, x: centerX, y: centerY, radius: 3,
            color: img.ColorRgba8(255, 255, 255, 255));
      }
    } catch (e) {
      debugPrint('Add mini map error: $e');
    }
  }

  // ── LAYOUT 5: HUD (perbaikan loop gelap) ─────────────────────
  static Uint8List _layoutHUD(
    img.Image src, DateTime timestamp, Position? position,
    String address, String weather, bool showWeather, bool showAccuracy, String watermarkPosition,
  ) {
    const int padX = 36;
    const int padY = 20;
    const int lineH = 28;
    const int accentH = 6;

    int rows = 2;
    if (position != null) rows += 1;
    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) rows += 1;
    if (showWeather && weather.isNotEmpty) rows += 1;

    final int panelH = padY * 2 + rows * lineH + (rows - 1) * 6 + accentH;
    final bool isTop = watermarkPosition == 'top';
    final int y0 = isTop ? 0 : src.height - panelH;
    if (y0 < 0) return Uint8List(0);

    final int yEnd = isTop ? y0 + panelH : src.height - accentH;
    for (int y = y0; y < yEnd; y++) {
      final progress = (y - y0) / (panelH).clamp(0.0, 1.0);
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

  // ─────────────────────────────────────────────────────────────
  // SAVE & SHARE
  // ─────────────────────────────────────────────────────────────

  // Di bagian atas, tambahkan import:
import 'package:device_info_plus/device_info_plus.dart';

// Ganti method _saveToGallery dengan kode berikut:
Future<void> _saveToGallery() async {
  if (_saveStatus == SaveStatus.saving || _displayImagePath == null) return;

  // Request permission berdasarkan versi Android
  if (Platform.isAndroid) {
    final granted = await _requestStoragePermission();
    if (!granted) {
      _showErrorSnackbar('Izin penyimpanan diperlukan untuk menyimpan foto');
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
    final bool? result = await GallerySaver.saveImage(
      _displayImagePath!,
      albumName: 'TermulLog',
    );

    if (!mounted) return;

    if (result == true) {
      // Hapus temp file setelah berhasil
      try {
        final tempFile = File(_displayImagePath!);
        if (await tempFile.exists()) await tempFile.delete();
      } catch (e) {
        debugPrint('Failed to delete temp file after save: $e');
      }
      _isFileSaved = true;
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
    _showErrorSnackbar('Gagal menyimpan: ${e.toString().substring(0, 50)}');
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saveStatus = SaveStatus.idle);
    });
  }
}

Future<bool> _requestStoragePermission() async {
  if (!Platform.isAndroid) return true;
  final androidInfo = await DeviceInfoPlugin().androidInfo;
  final sdkInt = androidInfo.version.sdkInt;

  if (sdkInt >= 33) {
    // Android 13+ : READ_MEDIA_IMAGES / Permission.photos
    final status = await Permission.photos.request();
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) {
      openAppSettings();
      return false;
    }
    return false;
  } else {
    // Android 12 ke bawah : WRITE_EXTERNAL_STORAGE
    final status = await Permission.storage.request();
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) {
      openAppSettings();
      return false;
    }
    return false;
  }
}

  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────

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
      final bool needGeocoding = (widget.address == null || widget.address!.isEmpty);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Memproses foto...', style: TextStyle(color: Colors.white70)),
            if (needGeocoding) ...[
              const SizedBox(height: 8),
              const Text('Mengambil alamat & cuaca', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ],
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Kembali'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() => _errorMessage = null);
                    _processImageAsync();
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Coba Lagi'),
                ),
              ],
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
          child: GestureDetector(
            onDoubleTapDown: (details) => _lastDoubleTapPos = details.localPosition,
            onDoubleTap: () {
              final scale = _transformController.value.getMaxScaleOnAxis();
              if (scale > 1.0) {
                _transformController.value = Matrix4.identity();
              } else {
                final pos = _lastDoubleTapPos ?? const Offset(0, 0);
                _transformController.value = Matrix4.identity()
                  ..translate(-pos.dx, -pos.dy)
                  ..scale(2.5)
                  ..translate(pos.dx / 2.5, pos.dy / 2.5);
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

// ─────────────────────────────────────────────────────────────
// TOMBOL AKSI GENERIK
// ─────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────
// TOMBOL SAVE — Animated
// ─────────────────────────────────────────────────────────────

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
