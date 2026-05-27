// lib/screens/camera_screen.dart (dengan GpsLockManager terintegrasi)
// Hanya menampilkan bagian yang diubah/ditambahkan, sisanya sama seperti sebelumnya.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:path_provider/path_provider.dart';

import '../models/watermark_position.dart';
import '../services/location_weather_service.dart';
import '../services/settings_cache.dart';
import '../watermark/watermark_engine.dart';
import '../core/constants.dart';
import '../widgets/draggable_watermark_overlay.dart';
import '../services/gps_lock_manager.dart';   // import GpsLockManager

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  // ... (variabel yang sudah ada: _controller, _isCameraReady, dll)

  // GpsLockManager instance
  final GpsLockManager _gpsLockManager = GpsLockManager();

  // Untuk UI status GPS lock
  bool _isGpsLocked = false;
  int _gpsLockProgress = 0;

  // Posisi terbaik yang dihasilkan oleh lock manager
  Position? _bestPosition;
  String _address = 'Mencari lokasi...';
  String _weather = '';

  // ... (variabel lain tetap)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettingsAndPosition();
  }

  Future<void> _initialize() async {
    await _initCamera();
    _initLocation(); // menggunakan GpsLockManager
    _startClock();
  }

  // ==================== LOCATION (dengan GpsLockManager) ====================
  Future<void> _initLocation() async {
    try {
      // Cek layanan dan izin (sama seperti sebelumnya)
      if (!await Geolocator.isLocationServiceEnabled()) { ... }
      // ... izin ...

      // Gunakan stream dengan interval 2 detik untuk lock cepat
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,        // update setiap 2 meter
        intervalDuration: Duration(seconds: 2),
      );

      Position? lastSample;
      _positionSub = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen((pos) async {
        final bool justLocked = _gpsLockManager.processSample(pos, lastSample);
        lastSample = pos;

        if (justLocked) {
          // Dapat lock baru, ambil posisi terbaik dari manager
          final lockData = _gpsLockManager.lockData;
          if (lockData != null) {
            setState(() {
              _bestPosition = lockData.position;
              _isGpsLocked = true;
            });
            // Ambil address dan weather dari posisi yang terkunci
            await _fetchAddressAndWeather(lockData.position);
            // Setelah address diambil, simpan ke lockData
            _gpsLockManager.updateLockAddress(_address, _weather);
          }
        } else {
          // Update progress UI
          final progress = _gpsLockManager.stationaryProgress;
          if (_gpsLockManager.state != GpsLockState.locked) {
            setState(() {
              _gpsLockProgress = progress;
              _isGpsLocked = false;
            });
          } else {
            // Sudah locked, mungkin perlu update posisi jika akurasi meningkat
            final lockData = _gpsLockManager.lockData;
            if (lockData != null && _bestPosition != lockData.position) {
              setState(() {
                _bestPosition = lockData.position;
              });
              // Update address/weather jika perlu (opsional)
              // ...
            }
          }
        }

        // Update loading state
        if (!_isGpsLocked && mounted) {
          setState(() => _isLoadingLocation = true);
        } else if (_isGpsLocked && mounted) {
          setState(() => _isLoadingLocation = false);
        }
      });
    } catch (e) {
      // error handling
    }
  }

  Future<void> _fetchAddressAndWeather(Position pos) async {
    try {
      final result = await LocationWeatherService.fetchFromPosition(pos)
          .timeout(const Duration(seconds: 12));
      if (mounted) {
        setState(() {
          _address = result.address;
          _weather = result.weather;
        });
      }
    } catch (e) {
      setState(() {
        _address = '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
      });
    }
  }

  // ==================== CAPTURE menggunakan posisi terbaik ====================
  Future<void> _takePhoto() async {
    if (_isCapturing) return;

    // Jangan izinkan capture jika belum locked
    if (!_isGpsLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masih mengunci GPS, tunggu sebentar...')),
      );
      return;
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    setState(() => _isCapturing = true);
    try {
      final XFile rawFile = await controller.takePicture();
      final rawBytes = await File(rawFile.path).readAsBytes();

      // Gunakan posisi terbaik dari lock manager
      final lockData = _gpsLockManager.lockData;
      if (lockData == null) throw Exception('GPS lock data hilang');

      final finalBytes = await WatermarkEngine.process(
        imageBytes: rawBytes,
        timestamp: _currentTimestamp,
        layout: _currentLayout,
        lat: lockData.position.latitude,
        lon: lockData.position.longitude,
        acc: lockData.position.accuracy,
        address: lockData.address,   // sudah berisi alamat setelah lock
        weather: lockData.weather,
        // ... parameter lain sama
      );

      // Simpan ke gallery
      // ...
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  // ==================== BUILD (tambahkan indikator GPS lock) ====================
  @override
  Widget build(BuildContext context) {
    // ... existing code ...

    return Scaffold(
      body: Stack(
        children: [
          CameraPreview(_controller!),
          if (_bestPosition != null) ... // watermark overlay (sama)

          // Indikator status GPS lock (gantikan chip "Mengambil GPS...")
          if (_isLoadingLocation && !_isGpsLocked)
            Positioned(
              top: 50,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.cyan),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _gpsLockManager.state == GpsLockState.searching
                                ? 'Mencari sinyal GPS...'
                                : 'Mengunci posisi... ${_gpsLockProgress}%',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                          if (_gpsLockProgress > 0)
                            LinearProgressIndicator(
                              value: _gpsLockProgress / 100,
                              backgroundColor: Colors.grey[800],
                              valueColor: const AlwaysStoppedAnimation(Colors.cyan),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Tombol capture (sama)
        ],
      ),
    );
  }
}
