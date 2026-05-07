import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
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

class _CameraScreenState extends State<CameraScreen> {

  // ── CAMERA ──────────────────────────────────────────────────────────────
  CameraController? _controller;

  bool _isInitialized = false;
  bool _isTakingPhoto = false;

  // ── GPS ─────────────────────────────────────────────────────────────────
  StreamSubscription<Position>? _gpsStream;

  Position? _bestPosition;

  bool _gpsReady = false;

  String _gpsText = '🔍 Searching GPS...';

  // ── GPS POLISH ──────────────────────────────────────────────────────────
  bool _isPolishing = false;

  int _polishCountdown = 45;

  Timer? _countdownTimer;

  Completer<Position?>? _gpsCompleter;

  @override
  void initState() {
    super.initState();

    _initCamera();
    _startGpsTracking();
  }

  @override
  void dispose() {

    _controller?.dispose();
    _gpsStream?.cancel();
    _countdownTimer?.cancel();

    super.dispose();
  }

  // ── INIT CAMERA ─────────────────────────────────────────────────────────

  Future<void> _initCamera() async {

    if (CameraRegistry.cameras.isEmpty) return;

    _controller = CameraController(
      CameraRegistry.cameras[0],
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {

      await _controller!.initialize();

      if (mounted) {

        setState(() {
          _isInitialized = true;
        });
      }

    } catch (e) {

      debugPrint('Camera init error: $e');

    }
  }

  // ── START GPS ───────────────────────────────────────────────────────────

Future<void> _startGpsTracking() async {

  final serviceEnabled =
      await Geolocator.isLocationServiceEnabled();

  if (!serviceEnabled) {

    setState(() {
      _gpsText = '❌ GPS tidak aktif';
    });

    return;
  }

  LocationPermission permission =
      await Geolocator.checkPermission();

  if (permission == LocationPermission.denied) {

    permission =
        await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {

    setState(() {
      _gpsText = '❌ Izin GPS ditolak';
    });

    return;
  }

  // ── GPS WARMUP ──────────────────────────────────────────
  // Pancing GPS aktif lebih cepat
  // Agar tidak lama dapat koordinat pertama

  try {

    final warmup =
        await Geolocator.getCurrentPosition(

      locationSettings:
          const LocationSettings(

        accuracy:
            LocationAccuracy.low,
      ),

    ).timeout(
      const Duration(seconds: 5),
    );

    _bestPosition = warmup;

    setState(() {

      _gpsText =
          '🟡 GPS awal ±${warmup.accuracy.toStringAsFixed(0)}m';

    });

  } catch (_) {

    // Tidak masalah jika gagal
    // Stream tetap berjalan

  }

  // ── STREAM GPS REALTIME ────────────────────────────────

  _gpsStream =
      Geolocator.getPositionStream(

    locationSettings:
        const LocationSettings(

      accuracy:
          LocationAccuracy.bestForNavigation,

      distanceFilter: 1,
    ),

  ).listen((Position pos) {

    // Simpan posisi terbaru
    _bestPosition = pos;

    final acc =
        pos.accuracy;

    setState(() {

      if (acc <= 25) {

        _gpsReady = true;

        _gpsText =
            '🟢 GPS Locked ±${acc.toStringAsFixed(1)}m';

      } else if (acc <= 50) {

        _gpsReady = false;

        _gpsText =
            '🟡 GPS ±${acc.toStringAsFixed(1)}m';

      } else {

        _gpsReady = false;

        _gpsText =
            '🔴 Sinyal lemah ±${acc.toStringAsFixed(1)}m';
      }
    });

    // Jika sedang menunggu GPS
    if (_gpsCompleter != null &&
        !_gpsCompleter!.isCompleted &&
        acc <= 25) {

      _gpsCompleter!.complete(
        _bestPosition,
      );
    }
  });
}

  // ── AMBIL FOTO ──────────────────────────────────────────────────────────

Future<void> _ambilFoto() async {

  if (_controller == null ||
      !_controller!.value.isInitialized) {
    return;
  }

  if (_isTakingPhoto || _isPolishing) return;

  setState(() {
    _isTakingPhoto = true;
  });

  try {

  // ── AMBIL FOTO ─────────────────────────────────────────

final XFile file =
    await _controller!.takePicture();

final Uint8List bytes =
    await file.readAsBytes();

final DateTime waktuFoto =
    DateTime.now();

// ── DECODE IMAGE ────────────────────────────────────────

img.Image? original =
    img.decodeImage(bytes);

// Jika gagal decode
if (original == null) {

  throw Exception(
    'Gagal decode gambar',
  );
}

// ── FIX ROTASI FOTO ─────────────────────────────────────
// Beberapa device Android hasil kamera bisa miring

original = img.bakeOrientation(original);

    // ── TAMPILKAN OVERLAY GPS ─────────────────────────────

    setState(() {

      _isTakingPhoto = false;

      _isPolishing = true;

      _polishCountdown = 45;

    });

    // ── TUNGGU GPS TERBAIK ────────────────────────────────

    await _waitForBestGps();

    // ── GPS RESULT ────────────────────────────────────────

    if (_bestPosition == null) {

      ScaffoldMessenger.of(context).showSnackBar(

        const SnackBar(
          content: Text(
            'GPS tidak tersedia, foto tetap disimpan tanpa koordinat',
          ),
        ),
      );
    }

    final Position? gpsResult =
        _bestPosition;

    // ── AMBIL ALAMAT ──────────────────────────────────────

    final String alamat =
        gpsResult != null
            ? await _getAddress(gpsResult)
            : 'Lokasi tidak tersedia';

        // ── SIMPAN FOTO ───────────────────────────────────────

    final dir =
        await getTemporaryDirectory();

    final outputPath =
        '${dir.path}/termullog_${waktuFoto.millisecondsSinceEpoch}.jpg';

    await File(outputPath).writeAsBytes(

      img.encodeJpg(
        watermarked,
        quality: 90,
      ),
    );

    if (!mounted) return;

    setState(() {

      _isPolishing = false;

    });

    // ── BUKA PREVIEW ──────────────────────────────────────

    Navigator.push(

      context,

      MaterialPageRoute(
        builder: (_) => PreviewScreen(
          imagePath: outputPath,
        ),
      ),
    );

  } catch (e) {

    if (mounted) {

      setState(() {

        _isTakingPhoto = false;
        _isPolishing = false;

      });

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(
          content: Text(
            'Gagal: $e',
          ),
        ),
      );
    }

  } finally {

    _countdownTimer?.cancel();

    _gpsCompleter = null;

  }
}


// ── WAIT GPS ────────────────────────────────────────────────────────────

Future<void> _waitForBestGps() async {

  // Jika GPS sudah bagus
  if (_gpsReady &&
      _bestPosition != null) {
    return;
  }

  _gpsCompleter =
      Completer<Position?>();

  _startCountdown();

  // Tunggu GPS / timeout
  await _gpsCompleter!.future;
}


// ── WATERMARK ───────────────────────────────────────────────────────────

img.Image _addWatermark(
  img.Image src,
  DateTime now,
  Position? pos,
  String alamat,
) {

  final tanggal =
      DateFormat('dd MMM yyyy')
          .format(now);

  final jam =
      DateFormat('HH:mm:ss')
          .format(now);

  // ── GPS STATUS ─────────────────────────────────────────

  final bool gpsAvailable =
      pos != null &&
      pos.accuracy >= 0;

  final lat =
      gpsAvailable
          ? pos!.latitude.toStringAsFixed(6)
          : 'N/A';

  final lon =
      gpsAvailable
          ? pos.longitude.toStringAsFixed(6)
          : 'N/A';

  final acc =
      gpsAvailable
          ? '±${pos.accuracy.toStringAsFixed(1)}m'
          : 'GPS Unavailable';

  final finalAlamat =
      gpsAvailable
          ? alamat
          : 'Lokasi tidak tersedia';

  // ── POSISI WATERMARK ───────────────────────────────────

  final isBottom =
      WatermarkLayoutService.position != 'top';

  const stripHeight = 210;

  final y0 =
      isBottom
          ? src.height - stripHeight
          : 0;

  final y1 =
      isBottom
          ? src.height
          : stripHeight;

  // ── OVERLAY GELAP ──────────────────────────────────────

  for (int y = y0; y < y1; y++) {

    for (int x = 0; x < src.width; x++) {

      final orig =
          src.getPixel(x, y);

      src.setPixel(
        x,
        y,

        img.ColorRgba8(
          (orig.r * 0.3).toInt(),
          (orig.g * 0.3).toInt(),
          (orig.b * 0.3).toInt(),
          255,
        ),
      );
    }
  }

  // ── COLOR ──────────────────────────────────────────────

  final font = img.arial24;

  final white =
      img.ColorRgba8(
        255,
        255,
        255,
        255,
      );

  final yellow =
      img.ColorRgba8(
        255,
        200,
        0,
        255,
      );

  final green =
      img.ColorRgba8(
        100,
        220,
        100,
        255,
      );

  final red =
      img.ColorRgba8(
        255,
        80,
        80,
        255,
      );

  final textY =
      isBottom
          ? src.height - stripHeight + 8
          : 8;

  // ── DRAW TEXT ──────────────────────────────────────────

  img.drawString(
    src,
    '📦 TermulLog',

    font: font,

    x: 16,
    y: textY,

    color: yellow,
  );

  img.drawString(
    src,
    '$tanggal   $jam',

    font: font,

    x: 16,
    y: textY + 32,

    color: white,
  );

  img.drawString(
    src,
    'GPS: $lat, $lon',

    font: font,

    x: 16,
    y: textY + 64,

    color: white,
  );

  img.drawString(
    src,
    acc,

    font: font,

    x: 16,
    y: textY + 96,

    color:
        gpsAvailable
            ? green
            : red,
  );

  img.drawString(
    src,
    finalAlamat,

    font: font,

    x: 16,
    y: textY + 128,

    color: white,
  );

  return src;
}

  // ── COUNTDOWN ───────────────────────────────────────────────────────────

  void _startCountdown() {

    _countdownTimer?.cancel();

    _polishCountdown = 45;

    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),

      (t) {

        if (!mounted) {

          t.cancel();
          return;

        }

        setState(() {

          _polishCountdown--;

        });

        // Timeout
        if (_polishCountdown <= 0) {

          t.cancel();

          if (_gpsCompleter != null &&
              !_gpsCompleter!.isCompleted) {

            _gpsCompleter!.complete(
              _bestPosition,
            );
          }
        }
      },
    );
  }

  // ── GET ADDRESS ─────────────────────────────────────────────────────────

  Future<String> _getAddress(
    Position pos,
  ) async {

    try {

      // GPS gagal
      if (pos.accuracy < 0) {

        return 'Lat: ${pos.latitude.toStringAsFixed(6)}, '
               'Lon: ${pos.longitude.toStringAsFixed(6)}';
      }

      final placemarks =
          await placemarkFromCoordinates(
            pos.latitude,
            pos.longitude,
          );

      // Jika kosong
      if (placemarks.isEmpty) {

        return 'Lat: ${pos.latitude.toStringAsFixed(6)}, '
               'Lon: ${pos.longitude.toStringAsFixed(6)}';
      }

      final p = placemarks.first;

      final alamat =
          '${p.street ?? ''}, '
          '${p.subLocality ?? ''}, '
          '${p.locality ?? ''}, '
          '${p.administrativeArea ?? ''}';

      // Bersihkan koma kosong
      final cleaned =
          alamat
              .replaceAll(' ,', '')
              .replaceAll(', ,', ',')
              .trim();

      // Jika alamat kosong
      if (cleaned.isEmpty ||
          cleaned == ',') {

        return 'Lat: ${pos.latitude.toStringAsFixed(6)}, '
               'Lon: ${pos.longitude.toStringAsFixed(6)}';
      }

      return cleaned;

    } catch (e) {

      // Fallback lat long
      return 'Lat: ${pos.latitude.toStringAsFixed(6)}, '
             'Lon: ${pos.longitude.toStringAsFixed(6)}';
    }
  }

  // ── WATERMARK ───────────────────────────────────────────────────────────

img.Image _addWatermark(
  img.Image src,
  DateTime now,
  Position? pos,
  String alamat,
) {

  final tanggal =
      DateFormat('dd MMM yyyy')
          .format(now);

  final jam =
      DateFormat('HH:mm:ss')
          .format(now);

  // ── GPS STATUS ─────────────────────────────────────────

  final bool gpsAvailable =
      pos != null &&
      pos.accuracy >= 0;

  final lat =
      gpsAvailable
          ? pos!.latitude.toStringAsFixed(6)
          : 'N/A';

  final lon =
      gpsAvailable
          ? pos.longitude.toStringAsFixed(6)
          : 'N/A';

  final acc =
      gpsAvailable
          ? '±${pos.accuracy.toStringAsFixed(1)}m'
          : 'GPS Unavailable';

  final finalAlamat =
      gpsAvailable
          ? alamat
          : 'Lokasi tidak tersedia';

  // ── POSISI WATERMARK ───────────────────────────────────

  final isBottom =
      WatermarkLayoutService.position != 'top';

  const stripHeight = 210;

  final y0 =
      isBottom
          ? src.height - stripHeight
          : 0;

  final y1 =
      isBottom
          ? src.height
          : stripHeight;

  // ── OVERLAY GELAP ──────────────────────────────────────

  for (int y = y0; y < y1; y++) {

    for (int x = 0; x < src.width; x++) {

      final orig =
          src.getPixel(x, y);

      src.setPixel(
        x,
        y,

        img.ColorRgba8(
          (orig.r * 0.3).toInt(),
          (orig.g * 0.3).toInt(),
          (orig.b * 0.3).toInt(),
          255,
        ),
      );
    }
  }

  // ── FONT & COLOR ───────────────────────────────────────

  final font = img.arial24;

  final white =
      img.ColorRgba8(
        255,
        255,
        255,
        255,
      );

  final yellow =
      img.ColorRgba8(
        255,
        200,
        0,
        255,
      );

  final green =
      img.ColorRgba8(
        100,
        220,
        100,
        255,
      );

  final red =
      img.ColorRgba8(
        255,
        80,
        80,
        255,
      );

  final textY =
      isBottom
          ? src.height - stripHeight + 8
          : 8;

  // ── DRAW TEXT ──────────────────────────────────────────

  img.drawString(
    src,
    '📦 TermulLog',

    font: font,

    x: 16,
    y: textY,

    color: yellow,
  );

  img.drawString(
    src,
    '$tanggal   $jam',

    font: font,

    x: 16,
    y: textY + 32,

    color: white,
  );

  img.drawString(
    src,
    'GPS: $lat, $lon',

    font: font,

    x: 16,
    y: textY + 64,

    color: white,
  );

  img.drawString(
    src,
    acc,

    font: font,

    x: 16,
    y: textY + 96,

    color:
        gpsAvailable
            ? green
            : red,
  );

  img.drawString(
    src,
    finalAlamat,

    font: font,

    x: 16,
    y: textY + 128,

    color: white,
  );

  return src;
}

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: Colors.black,

      body: Stack(
        children: [

          // CAMERA PREVIEW
          if (_isInitialized &&
              _controller != null)

            SizedBox.expand(
              child: CameraPreview(
                _controller!,
              ),
            )

          else

            const Center(
              child:
                  CircularProgressIndicator(
                color: Colors.white,
              ),
            ),

          // GPS STATUS BAR
          Positioned(
            top: 0,
            left: 0,
            right: 0,

            child: Container(
              color: Colors.black54,

              padding:
                  const EdgeInsets.fromLTRB(
                16,
                52,
                16,
                12,
              ),

              child: Row(
                children: [

                  Icon(
                    _gpsReady
                        ? Icons.gps_fixed
                        : Icons.gps_not_fixed,

                    color: _gpsReady
                        ? Colors.greenAccent
                        : Colors.amber,

                    size: 16,
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: Text(

                      _bestPosition != null

                          ? '${_bestPosition!.latitude.toStringAsFixed(5)}, '
                            '${_bestPosition!.longitude.toStringAsFixed(5)}'

                          : _gpsText,

                      style:
                          const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),

                  Text(
                    _gpsText,

                    style: TextStyle(
                      color: _gpsReady
                          ? Colors.greenAccent
                          : Colors.amber,

                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // GPS POLISH OVERLAY
          if (_isPolishing)

            Container(
              color:
                  Colors.black.withOpacity(0.75),

              child: Center(
                child: Container(

                  margin:
                      const EdgeInsets.symmetric(
                    horizontal: 40,
                  ),

                  padding:
                      const EdgeInsets.all(28),

                  decoration: BoxDecoration(
                    color:
                        const Color(0xFF0D1B2A),

                    borderRadius:
                        BorderRadius.circular(20),

                    border: Border.all(
                      color: Colors.white12,
                    ),
                  ),

                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,

                    children: [

                      Stack(
                        alignment:
                            Alignment.center,

                        children: [

                          SizedBox(
                            width: 80,
                            height: 80,

                            child:
                                CircularProgressIndicator(
                              value:
                                  _polishCountdown /
                                  45,

                              strokeWidth: 6,

                              backgroundColor:
                                  Colors.white12,

                              color: _gpsReady
                                  ? Colors.greenAccent
                                  : Colors.amber,
                            ),
                          ),

                          Text(
                            '$_polishCountdown',

                            style:
                                const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(
                        height: 20,
                      ),

                      Text(
                        _gpsReady

                            ? '✅ GPS Terkunci!\nMenyimpan foto...'

                            : '📡 Menyempurnakan GPS...\n$_gpsText',

                        textAlign:
                            TextAlign.center,

                        style:
                            const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      Text(
                        _gpsReady

                            ? 'Koordinat berhasil dikunci'

                            : 'Foto sudah diambil.\n'
                              'Menunggu GPS presisi '
                              'atau timeout '
                              '$_polishCountdown detik',

                        textAlign:
                            TextAlign.center,

                        style:
                            const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // BOTTOM BUTTON
          if (!_isPolishing)

            Positioned(
              bottom: 0,
              left: 0,
              right: 0,

              child: Container(
                color: Colors.black87,

                padding:
                    const EdgeInsets.fromLTRB(
                  24,
                  20,
                  24,
                  40,
                ),

                child: Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceAround,

                  children: [

                    IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },

                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),

                    GestureDetector(
                      onTap:
                          _isTakingPhoto
                              ? null
                              : _ambilFoto,

                      child: Container(
                        width: 72,
                        height: 72,

                        decoration:
                            BoxDecoration(
                          shape: BoxShape.circle,

                          border: Border.all(
                            color: Colors.white,
                            width: 4,
                          ),

                          color: Colors.white
                              .withOpacity(0.15),
                        ),

                        child:
                            _isTakingPhoto

                                ? const Padding(
                                    padding:
                                        EdgeInsets
                                            .all(
                                      20,
                                    ),

                                    child:
                                        CircularProgressIndicator(
                                      color:
                                          Colors
                                              .white,

                                      strokeWidth:
                                          3,
                                    ),
                                  )

                                : const Icon(
                                    Icons
                                        .camera_alt,

                                    color:
                                        Colors
                                            .white,

                                    size: 32,
                                  ),
                      ),
                    ),

                    const SizedBox(
                      width: 48,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
