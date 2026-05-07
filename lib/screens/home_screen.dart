import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../core/camera_registry.dart';
import 'gps_lock_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _bukaKamera(BuildContext context) {
    if (CameraRegistry.cameras.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kamera tidak tersedia'),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const GpsLockScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),

      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B2A),
        elevation: 0,
        centerTitle: true,

        title: const Text(
          'TermulLog',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
            letterSpacing: 1.5,
          ),
        ),
      ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              const SizedBox(height: 16),

              const Text(
                'Bukti Penerimaan\nBarang Logistik',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Foto dan catat penerimaan barang di lokasi.',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 48),

              // ───────────────────────────────────────────────────────────
              // BUTTON KAMERA
              // ───────────────────────────────────────────────────────────

              GestureDetector(
                onTap: () => _bukaKamera(context),

                child: Container(
                  width: double.infinity,

                  padding: const EdgeInsets.symmetric(
                    vertical: 28,
                  ),

                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0),

                    borderRadius: BorderRadius.circular(20),

                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1565C0)
                            .withOpacity(0.4),

                        blurRadius: 20,

                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),

                  child: const Column(
                    children: [

                      Icon(
                        Icons.camera_alt_rounded,
                        color: Colors.white,
                        size: 52,
                      ),

                      SizedBox(height: 12),

                      Text(
                        'Ambil Foto Bukti',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      SizedBox(height: 4),

                      Text(
                        'Tap untuk membuka kamera',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ───────────────────────────────────────────────────────────
              // INFO CARD
              // ───────────────────────────────────────────────────────────

              Container(
                width: double.infinity,

                padding: const EdgeInsets.all(16),

                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),

                  borderRadius: BorderRadius.circular(14),

                  border: Border.all(
                    color: Colors.white12,
                  ),
                ),

                child: const Row(
                  children: [

                    Icon(
                      Icons.gps_fixed,
                      color: Colors.white38,
                      size: 20,
                    ),

                    SizedBox(width: 12),

                    Expanded(
                      child: Text(
                        'Aplikasi akan mencari GPS terlebih dahulu sebelum kamera dibuka agar lokasi lebih akurat.',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
