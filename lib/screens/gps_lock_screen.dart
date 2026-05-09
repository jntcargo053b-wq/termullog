import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'camera_screen.dart';

class GpsLockScreen extends StatefulWidget {
  const GpsLockScreen({super.key});

  @override
  State<GpsLockScreen> createState() => _GpsLockScreenState();
}

class _GpsLockScreenState extends State<GpsLockScreen> {

  // ── GPS STATE ────────────────────────────────────────────────────────────
  StreamSubscription<Position>? _gpsStream;
  Position? _bestPosition;
  bool _gpsReady = false;
  String _gpsText = '🔍 Searching GPS...';
  String _coordText = '-';
  String _accText = '-';

  @override
  void initState() {
    super.initState();
    _startGpsTracking();
  }

  @override
  void dispose() {
    _gpsStream?.cancel();
    super.dispose();
  }

  // ── GPS TRACKING ─────────────────────────────────────────────────────────

  Future<void> _startGpsTracking() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _gpsText = '❌ GPS tidak aktif. Aktifkan GPS terlebih dahulu.');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() => _gpsText = '❌ Izin GPS ditolak.');
      return;
    }

    _gpsStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    ).listen((Position pos) {
      // Selalu simpan posisi dengan akurasi terbaik
      if (_bestPosition == null || pos.accuracy < _bestPosition!.accuracy) {
        _bestPosition = pos;
      }

      final acc = _bestPosition!.accuracy;
      final lat = _bestPosition!.latitude.toStringAsFixed(6);
      final lon = _bestPosition!.longitude.toStringAsFixed(6);

      setState(() {
        _coordText = '$lat, $lon';
        _accText = '±${acc.toStringAsFixed(1)}m';

        if (acc <= 10) {
          _gpsReady = true;
          _gpsText = '🟢 GPS Terkunci';
        } else if (acc <= 30) {
          _gpsReady = false;
          _gpsText = '🟡 Mendapatkan sinyal...';
        } else {
          _gpsReady = false;
          _gpsText = '🔴 Sinyal lemah, tunggu sebentar...';
        }
      });
    });
  }

  // ── LANJUT KE KAMERA ─────────────────────────────────────────────────────

  void _lanjutKeKamera() {
    if (!_gpsReady || _bestPosition == null) return;
    _gpsStream?.cancel(); // hentikan stream, posisi sudah dikunci

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        // lockedPosition dihapus: GPS kini dikelola sepenuhnya di dalam CameraScreen
        builder: (_) => const CameraScreen(),
      ),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B2A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Kunci Lokasi GPS',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 32),

            // ── Animasi ikon GPS ──────────────────────────────────────────
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.9, end: 1.1),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOut,
              builder: (_, scale, child) => Transform.scale(
                scale: _gpsReady ? 1.0 : scale,
                child: child,
              ),
              child: Icon(
                _gpsReady ? Icons.gps_fixed : Icons.gps_not_fixed,
                size: 80,
                color: _gpsReady ? Colors.greenAccent : Colors.amber,
              ),
            ),

            const SizedBox(height: 24),

            // ── Status teks ───────────────────────────────────────────────
            Text(
              _gpsText,
              style: TextStyle(
                color: _gpsReady ? Colors.greenAccent : Colors.amber,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // ── Info koordinat ────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  _infoRow(Icons.location_on, 'Koordinat', _coordText),
                  const Divider(color: Colors.white12, height: 24),
                  _infoRow(Icons.radar, 'Akurasi', _accText),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Keterangan akurasi ────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '💡 GPS dianggap terkunci jika akurasi ≤ 10m.\n'
                'Pastikan berada di area terbuka untuk hasil terbaik.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),

            const Spacer(),

            // ── Tombol lanjut ─────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _gpsReady ? _lanjutKeKamera : null,
                icon: const Icon(Icons.camera_alt_rounded),
                label: Text(
                  _gpsReady ? 'Buka Kamera' : 'Menunggu GPS...',
                  style: const TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  disabledBackgroundColor: Colors.white12,
                  disabledForegroundColor: Colors.white38,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.white38, size: 18),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
