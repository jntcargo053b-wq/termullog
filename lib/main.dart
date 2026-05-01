import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

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
  final String? address;

  DeliveryRecord({
    required this.number,
    required this.imagePath,
    required this.timestamp,
    required this.kurirName,
    this.lat,
    this.lng,
    this.address,
  });
}

// ─── MAP TILE HELPER ─────────────────────────────────────────────────────────

class MapTileHelper {
  static const int zoom = 16;
  static const int tileSize = 256;

  static int lonToTile(double lon) =>
      ((lon + 180.0) / 360.0 * (1 << zoom)).floor();

  static int latToTile(double lat) {
    final latRad = lat * pi / 180.0;
    return ((1.0 -
                log(tan(latRad) + 1.0 / cos(latRad)) / pi) /
            2.0 *
            (1 << zoom))
        .floor();
  }

  // Pixel offset of lat/lng within the tile (0..255)
  static int lonToPixelOffset(double lon) {
    final worldTile = (lon + 180.0) / 360.0 * (1 << zoom);
    return ((worldTile - worldTile.floor()) * tileSize).floor();
  }

  static int latToPixelOffset(double lat) {
    final latRad = lat * pi / 180.0;
    final worldTile = (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) /
        2.0 *
        (1 << zoom);
    return ((worldTile - worldTile.floor()) * tileSize).floor();
  }

  /// Fetch a 2×2 tile grid (512×512) centered near the location,
  /// returns null on failure.
  static Future<img.Image?> fetchMap(double lat, double lng) async {
    final tx = lonToTile(lng);
    final ty = latToTile(lat);
    final px = lonToPixelOffset(lng);
    final py = latToPixelOffset(lat);

    // We fetch a 3×3 grid then crop a 512×512 around the marker
    final canvas = img.Image(width: tileSize * 3, height: tileSize * 3);

    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        try {
          final url =
              'https://tile.openstreetmap.org/$zoom/${tx + dx}/${ty + dy}.png';
          final response =
              await http.get(Uri.parse(url), headers: {
            'User-Agent': 'TermulLogApp/1.0'
          }).timeout(const Duration(seconds: 8));

          if (response.statusCode == 200) {
            final tile = img.decodePng(response.bodyBytes);
            if (tile != null) {
              img.compositeImage(
                canvas,
                tile,
                dstX: (dx + 1) * tileSize,
                dstY: (dy + 1) * tileSize,
              );
            }
          }
        } catch (_) {
          // Tile gagal, biarkan kosong
        }
      }
    }

    // Crop 512×512 centered on the marker
    final cropX = (tileSize + px - 256).clamp(0, tileSize * 3 - 512);
    final cropY = (tileSize + py - 256).clamp(0, tileSize * 3 - 512);
    final cropped = img.copyCrop(canvas,
        x: cropX, y: cropY, width: 512, height: 512);

    // Hitung posisi marker di cropped image
    final markerX = (tileSize + px - cropX);
    final markerY = (tileSize + py - cropY);

    // Gambar lingkaran merah sebagai marker
    final red = img.ColorRgba8(220, 30, 30, 255);
    final white = img.ColorRgba8(255, 255, 255, 255);
    img.fillCircle(cropped, x: markerX, y: markerY, radius: 10, color: red);
    img.drawCircle(cropped, x: markerX, y: markerY, radius: 10, color: white);
    img.drawCircle(cropped, x: markerX, y: markerY, radius: 11, color: red);
    // Titik putih kecil di tengah
    img.fillCircle(cropped, x: markerX, y: markerY, radius: 3, color: white);

    return cropped;
  }
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
      String? address;
      img.Image? mapImage;

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

          // Reverse geocoding
          try {
            final placemarks =
                await placemarkFromCoordinates(lat, lng)
                    .timeout(const Duration(seconds: 6));
            if (placemarks.isNotEmpty) {
              final p = placemarks.first;
              final parts = [
                p.street,
                p.subLocality,
                p.locality,
                p.subAdministrativeArea,
              ].where((s) => s != null && s.isNotEmpty).toList();
              address = parts.join(', ');
            }
          } catch (_) {}

          // Fetch peta OSM
          try {
            mapImage = await MapTileHelper.fetchMap(lat, lng);
          } catch (_) {}
        }
      } catch (_) {
        // GPS gagal
      }

      // 3. Buat watermark
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
        address: address,
        mapImage: mapImage,
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
            address: address,
          ),
        );
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
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
    String? address,
    img.Image? mapImage,
  }) async {
    final bytes = await File(imagePath).readAsBytes();
    img.Image? original = img.decodeImage(bytes);
    if (original == null) throw Exception('Gagal membaca gambar');

    if (original.width > 1920) {
      original = img.copyResize(original, width: 1920);
    }

    final w = original.width;
    final h = original.height;

    // Tinggi strip teks di bawah
    final stripHeight = (h * 0.20).clamp(140.0, 220.0).toInt();

    // Lebar peta di sisi kanan strip (proporsional)
    final mapSize = mapImage != null ? stripHeight : 0;

    final canvas = img.Image(width: w, height: h + stripHeight);
    img.compositeImage(canvas, original, dstX: 0, dstY: 0);

    // Background strip hitam
    img.fillRect(
      canvas,
      x1: 0,
      y1: h,
      x2: w,
      y2: h + stripHeight,
      color: img.ColorRgba8(0, 0, 0, 210),
    );

    // Tempel peta di sisi kanan strip
    if (mapImage != null) {
      final scaledMap = img.copyResize(mapImage,
          width: mapSize, height: mapSize);
      img.compositeImage(canvas, scaledMap,
          dstX: w - mapSize, dstY: h);

      // Border putih tipis di kiri peta
      img.drawLine(canvas,
          x1: w - mapSize, y1: h,
          x2: w - mapSize, y2: h + stripHeight,
          color: img.ColorRgba8(255, 255, 255, 120));
    }

    // Teks watermark
    final white  = img.ColorRgba8(255, 255, 255, 255);
    final yellow = img.ColorRgba8(255, 220, 50, 255);
    final grey   = img.ColorRgba8(180, 180, 180, 255);

    final fontSize = (stripHeight * 0.16).clamp(12.0, 22.0).toInt();
    final lineGap  = (fontSize * 1.55).toInt();
    final padding  = (w * 0.02).toInt();
    final textMaxW = w - mapSize - padding * 2;

    final font = _getFont(fontSize);

    int yPos = h + (stripHeight * 0.07).toInt();

    // Baris 1: KIRIMAN #N + "TermulLog" di kanan atas strip teks
    img.drawString(canvas, 'KIRIMAN #$deliveryNum',
        font: font, x: padding, y: yPos, color: yellow);

    img.drawString(canvas, 'TermulLog',
        font: font,
        x: w - mapSize - (fontSize * 6),
        y: yPos,
        color: yellow);

    yPos += lineGap;

    // Baris 2: Kurir
    img.drawString(canvas, 'Kurir : $kurirName',
        font: font, x: padding, y: yPos, color: white);
    yPos += lineGap;

    // Baris 3: Waktu
    img.drawString(canvas, 'Waktu : $timestamp',
        font: font, x: padding, y: yPos, color: white);
    yPos += lineGap;

    // Baris 4: GPS
    if (lat != null && lng != null) {
      final latStr = lat.toStringAsFixed(6);
      final lngStr = lng.toStringAsFixed(6);
      img.drawString(canvas, 'GPS   : $latStr, $lngStr',
          font: font, x: padding, y: yPos, color: white);
    } else {
      img.drawString(canvas, 'GPS   : Tidak tersedia',
          font: font, x: padding, y: yPos, color: grey);
    }
    yPos += lineGap;

    // Baris 5: Alamat (potong jika terlalu panjang)
    final maxChars = (textMaxW / (fontSize * 0.58)).floor();
    String addrDisplay = 'Tidak tersedia';
    Color addrColor = grey;
    if (address != null && address.isNotEmpty) {
      addrDisplay = address.length > maxChars
          ? address.substring(0, maxChars) + '...'
          : address;
      addrColor = white;
    }
    img.drawString(canvas, 'Alamat: $addrDisplay',
        font: font, x: padding, y: yPos, color: addrColor);

    // Simpan
    final dir = await getApplicationDocumentsDirectory();
    final outPath =
        '${dir.path}/delivery_${deliveryNum}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(outPath).writeAsBytes(img.encodeJpg(canvas, quality: 88));
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
                    icon: Icons.person),
                _StatItem(
                    label: 'Total Kiriman',
                    value: '${deliveries.length}',
                    icon: Icons.inventory_2),
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
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // List
          Expanded(
            child: deliveries.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_library_outlined,
                            size: 64, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('Belum ada foto kiriman',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: deliveries.length,
                    itemBuilder: (context, index) =>
                        _DeliveryCard(delivery: deliveries[index]),
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
  const _StatItem(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue),
        const SizedBox(height: 4),
        Text(value,
            style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    PhotoViewScreen(imagePath: delivery.imagePath),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 200,
              child: Image.file(
                File(delivery.imagePath),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Center(child: Icon(Icons.broken_image, size: 48)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kiriman #${delivery.number}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.access_time,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(delivery.timestamp,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 13)),
                ]),
                if (delivery.address != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          delivery.address!,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ] else if (delivery.lat != null) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.location_on,
                        size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '${delivery.lat!.toStringAsFixed(5)}, ${delivery.lng!.toStringAsFixed(5)}',
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 13),
                    ),
                  ]),
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
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image,
                color: Colors.white, size: 64),
          ),
        ),
      ),
    );
  }
}
