import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;

void main() {
  runApp(const TermulLogApp());
}

class TermulLogApp extends StatelessWidget {
  const TermulLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TermulLog',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

// ─── LOGIN ───────────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final nameController = TextEditingController();

  void login() {
    if (nameController.text.trim().isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DashboardScreen(name: nameController.text.trim()),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TermulLog')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_shipping, size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nama Kurir',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => login(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: login,
                icon: const Icon(Icons.login),
                label: const Text('MASUK'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── MODEL ───────────────────────────────────────────────────────────────────

class DeliveryRecord {
  final int number;
  final String imagePath;
  final String timestamp;
  final String kurirName;
  final double? lat;
  final double? lng;

  DeliveryRecord({
    required this.number,
    required this.imagePath,
    required this.timestamp,
    required this.kurirName,
    this.lat,
    this.lng,
  });
}

// ─── DASHBOARD ───────────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  final String name;
  const DashboardScreen({super.key, required this.name});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final List<DeliveryRecord> deliveries = [];
  bool isLoading = false;

  Future<void> captureDelivery() async {
    setState(() => isLoading = true);

    try {
      // 1. Ambil foto
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (photo == null) {
        setState(() => isLoading = false);
        return;
      }

      // 2. Ambil GPS
      double? lat, lng;
      try {
        LocationPermission perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.whileInUse ||
            perm == LocationPermission.always) {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          ).timeout(const Duration(seconds: 8));
          lat = pos.latitude;
          lng = pos.longitude;
        }
      } catch (_) {
        // GPS gagal, lanjut tanpa koordinat
      }

      // 3. Tambah watermark
      final now = DateTime.now();
      final timestamp = DateFormat('dd/MM/yyyy HH:mm:ss').format(now);
      final deliveryNum = deliveries.length + 1;

      final watermarkedPath = await _addWatermark(
        imagePath: photo.path,
        kurirName: widget.name,
        timestamp: timestamp,
        deliveryNum: deliveryNum,
        lat: lat,
        lng: lng,
      );

      setState(() {
        deliveries.insert(
          0,
          DeliveryRecord(
            number: deliveryNum,
            imagePath: watermarkedPath,
            timestamp: timestamp,
            kurirName: widget.name,
            lat: lat,
            lng: lng,
          ),
        );
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<String> _addWatermark({
    required String imagePath,
    required String kurirName,
    required String timestamp,
    required int deliveryNum,
    double? lat,
    double? lng,
  }) async {
    // Baca gambar
    final bytes = await File(imagePath).readAsBytes();
    img.Image? original = img.decodeImage(bytes);
    if (original == null) throw Exception('Gagal membaca gambar');

    // Resize jika terlalu besar (maks 1920px)
    if (original.width > 1920) {
      original = img.copyResize(original, width: 1920);
    }

    final w = original.width;
    final h = original.height;

    // Tinggi strip watermark di bawah
    final stripHeight = (h * 0.12).clamp(80.0, 160.0).toInt();

    // Buat kanvas baru dengan strip di bawah
    final canvas = img.Image(width: w, height: h + stripHeight);

    // Salin gambar asli
    img.compositeImage(canvas, original, dstX: 0, dstY: 0);

    // Isi strip hitam semi-transparan
    final black = img.ColorRgba8(0, 0, 0, 200);
    img.fillRect(
      canvas,
      x1: 0,
      y1: h,
      x2: w,
      y2: h + stripHeight,
      color: black,
    );

    // Teks watermark
    final white = img.ColorRgba8(255, 255, 255, 255);
    final yellow = img.ColorRgba8(255, 220, 50, 255);
    final fontSize = (stripHeight * 0.18).clamp(12.0, 22.0).toInt();
    final lineGap = (fontSize * 1.5).toInt();
    final padding = (w * 0.02).toInt();

    final font = _getFont(fontSize);

    int yPos = h + (stripHeight * 0.08).toInt();

    // Baris 1: Nomor kiriman (kuning)
    img.drawString(
      canvas,
      'KIRIMAN #$deliveryNum',
      font: font,
      x: padding,
      y: yPos,
      color: yellow,
    );

    yPos += lineGap;

    // Baris 2: Nama kurir
    img.drawString(
      canvas,
      'Kurir: $kurirName',
      font: font,
      x: padding,
      y: yPos,
      color: white,
    );

    yPos += lineGap;

    // Baris 3: Waktu
    img.drawString(
      canvas,
      'Waktu: $timestamp',
      font: font,
      x: padding,
      y: yPos,
      color: white,
    );

    yPos += lineGap;

    // Baris 4: GPS
    if (lat != null && lng != null) {
      final gpsText =
          'GPS: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
      img.drawString(
        canvas,
        gpsText,
        font: font,
        x: padding,
        y: yPos,
        color: white,
      );
    } else {
      img.drawString(
        canvas,
        'GPS: Tidak tersedia',
        font: font,
        x: padding,
        y: yPos,
        color: img.ColorRgba8(180, 180, 180, 255),
      );
    }

    // Tambah logo kecil "TermulLog" di kanan
    img.drawString(
      canvas,
      'TermulLog',
      font: font,
      x: w - (fontSize * 6),
      y: h + (stripHeight * 0.08).toInt(),
      color: yellow,
    );

    // Simpan ke file baru
    final dir = await getApplicationDocumentsDirectory();
    final outPath =
        '${dir.path}/delivery_${deliveryNum}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final outBytes = img.encodeJpg(canvas, quality: 88);
    await File(outPath).writeAsBytes(outBytes);

    return outPath;
  }

  img.BitmapFont _getFont(int size) {
    if (size <= 14) return img.arial14;
    if (size <= 24) return img.arial24;
    return img.arial48;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TermulLog Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(
                  label: 'Kurir',
                  value: widget.name,
                  icon: Icons.person,
                ),
                _StatItem(
                  label: 'Total Kiriman',
                  value: '${deliveries.length}',
                  icon: Icons.inventory_2,
                ),
              ],
            ),
          ),

          // Tombol foto
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isLoading ? null : captureDelivery,
                icon: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.camera_alt),
                label: Text(isLoading ? 'Memproses...' : '+ FOTO BUKTI KIRIM'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // List foto
          Expanded(
            child: deliveries.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_library_outlined,
                            size: 64, color: Colors.grey),
                        SizedBox(height: 12),
                        Text(
                          'Belum ada foto kiriman',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: deliveries.length,
                    itemBuilder: (context, index) {
                      final d = deliveries[index];
                      return _DeliveryCard(delivery: d);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── WIDGETS ─────────────────────────────────────────────────────────────────

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  final DeliveryRecord delivery;

  const _DeliveryCard({required this.delivery});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Foto
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PhotoViewScreen(imagePath: delivery.imagePath),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 200,
              child: Image.file(
                File(delivery.imagePath),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image, size: 48),
                ),
              ),
            ),
          ),
          // Info
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kiriman #${delivery.number}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(delivery.timestamp,
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 13)),
                  ],
                ),
                if (delivery.lat != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        '${delivery.lat!.toStringAsFixed(5)}, ${delivery.lng!.toStringAsFixed(5)}',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── FULL SCREEN PHOTO ───────────────────────────────────────────────────────

class PhotoViewScreen extends StatelessWidget {
  final String imagePath;
  const PhotoViewScreen({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Bukti Kiriman'),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.file(
            File(imagePath),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image, color: Colors.white, size: 64),
          ),
        ),
      ),
    );
  }
}
