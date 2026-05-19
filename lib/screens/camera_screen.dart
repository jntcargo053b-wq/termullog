// lib/screens/camera_screen.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../services/location_weather_service.dart';
import 'preview_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isReady = false;
  bool _isRequestingPermission = false;
  String _errorMessage = '';
  
  // Location & Weather
  Position? _currentPosition;
  String _address = '';
  String _weather = '';
  bool _isLoadingLocation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCameraAndPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndRequestPermissions();
    }
  }

  Future<void> _checkAndRequestPermissions() async {
    // Request semua izin sekaligus
    final permissions = [
      Permission.camera,
      Permission.location,
      Permission.locationWhenInUse,
      Permission.locationAlways,
    ];
    
    if (await Permission.location.isDenied) {
      await Permission.location.request();
    }
    
    if (await Permission.camera.isDenied) {
      await Permission.camera.request();
    }
    
    await _initializeCameraAndPermissions();
  }

  Future<void> _initializeCameraAndPermissions() async {
    if (_isRequestingPermission) return;
    _isRequestingPermission = true;
    
    setState(() {
      _errorMessage = '';
      _isReady = false;
    });

    try {
      // 1. Cek dan minta izin kamera
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        setState(() {
          _errorMessage = 'Izin kamera diperlukan untuk mengambil foto';
          _isRequestingPermission = false;
        });
        
        // Tampilkan dialog jika izin ditolak permanen
        if (cameraStatus.isPermanentlyDenied) {
          _showPermissionDialog('Kamera');
        }
        return;
      }

      // 2. Cek dan minta izin lokasi
      final locationStatus = await Permission.location.request();
      if (!locationStatus.isGranted) {
        setState(() {
          _errorMessage = 'Izin lokasi diperlukan untuk watermark GPS';
          _isRequestingPermission = false;
        });
        
        if (locationStatus.isPermanentlyDenied) {
          _showPermissionDialog('Lokasi');
        }
        return;
      }

      // 3. Inisialisasi kamera
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _errorMessage = 'Tidak ada kamera yang tersedia';
          _isRequestingPermission = false;
        });
        return;
      }

      // Pilih kamera belakang (index 0)
      final camera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras![0],
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.max,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      
      if (mounted) {
        setState(() {
          _isReady = true;
          _isRequestingPermission = false;
        });
        
        // Ambil lokasi setelah kamera siap
        _getCurrentLocation();
      }
    } catch (e) {
      debugPrint('Camera initialization error: $e');
      setState(() {
        _errorMessage = 'Gagal menginisialisasi kamera: $e';
        _isRequestingPermission = false;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      // Cek apakah layanan lokasi aktif
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _address = 'Lokasi tidak aktif';
          _isLoadingLocation = false;
        });
        return;
      }

      // Dapatkan posisi
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      setState(() {
        _currentPosition = position;
      });

      // Ambil alamat
      try {
        final placemark = await Geolocator.placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemark.isNotEmpty) {
          setState(() {
            _address = '${placemark.first.street}, ${placemark.first.locality}';
          });
        }
      } catch (e) {
        debugPrint('Geocoding error: $e');
        setState(() {
          _address = '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
        });
      }

      // Ambil cuaca
      try {
        final weatherResult = await LocationWeatherService.fetchFromPosition(position);
        setState(() {
          _weather = weatherResult.weather;
        });
      } catch (e) {
        debugPrint('Weather error: $e');
        setState(() {
          _weather = '';
        });
      }
    } catch (e) {
      debugPrint('Location error: $e');
      setState(() {
        _address = 'Gagal mendapatkan lokasi';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  void _showPermissionDialog(String permissionName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Izin $permissionName Diperlukan'),
        content: Text('Aplikasi memerlukan izin $permissionName untuk berfungsi. Silakan berikan izin di pengaturan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Buka Pengaturan'),
          ),
        ],
      ),
    );
  }

  Future<void> _takePicture() async {
    if (!_isReady || _cameraController == null) return;

    try {
      final XFile picture = await _cameraController!.takePicture();
      
      if (!mounted) return;

      // Navigasi ke preview screen dengan data yang sudah ada
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PreviewScreen(
            imagePath: picture.path,
            timestamp: DateTime.now(),
            latitude: _currentPosition?.latitude,
            longitude: _currentPosition?.longitude,
            accuracy: _currentPosition?.accuracy,
            address: _address,
            weather: _weather,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error taking picture: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengambil foto: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview
          if (_isReady && _cameraController != null)
            Positioned.fill(
              child: CameraPreview(_cameraController!),
            ),
          
          // Error Message
          if (_errorMessage.isNotEmpty)
            Center(
              child: Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(_errorMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _checkAndRequestPermissions,
                      child: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              ),
            ),
          
          // Loading
          if (_isRequestingPermission)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('Meminta izin...', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          
          // Location & Weather Info (Overlay)
          if (_isReady && !_isRequestingPermission)
            Positioned(
              top: 40,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isLoadingLocation)
                      const Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text('Mendapatkan lokasi...', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      )
                    else ...[
                      if (_address.isNotEmpty)
                        Row(
                          children: [
                            const Icon(Icons.location_on, color: Colors.white70, size: 14),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _address,
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      if (_weather.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.wb_sunny, color: Colors.amber, size: 14),
                              const SizedBox(width: 4),
                              Text(_weather, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          
          // Shutter Button
          if (_isReady && !_isRequestingPermission)
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _takePicture,
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade800, width: 4),
                    ),
                    child: const Icon(Icons.camera_alt, color: Colors.black, size: 32),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
