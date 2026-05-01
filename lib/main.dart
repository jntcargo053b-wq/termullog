import 'dart:io';
import 'dart:math';
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

// ─── LOGIN ────────────────────────────────────────────────────────────────────

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

// ─── MODEL ────────────────────────────────────────────────────────────────────

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

// ─── MAP TILE ─────────────────────────────────────────────────────────────────

class MapTileHelper {
  static const int zoom = 16;
  static const int tileSize = 256;

  static int lonToTile(double lon) =>
      ((lon + 180.0) / 360.0 * (1 << zoom)).floor();

  static int latToTile(double lat) {
    final latRad = lat * pi / 180.0;
    return ((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) /
            2.0 *
            (1 << zoom))
        .floor();
  }

  static int lonToPixelOffset(double lon) {
    final worldTile = (lon + 180.0) / 360.0 * (1 << zoom);
    return ((worldTile - worldTile.floor()) * tileSize).floor();
  }

  static int latToPixelOffset(double lat) {
    final latRad = lat * pi / 180.0;
    final worldTile =
        (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) / 2.0 * (1 << zoom);
    return ((worldTile - worldTile.floor()) * tileSize).floor();
  }

  static Future<img.Image?> fetchMap(double lat, double lng) async {
    final tx = lonToTile(lng);
    final ty = latToTile(lat);
    final px = lonToPixelOffset(lng);
    final py = latToPixelOffset(lat);

    // Canvas putih RGB — tile OSM akan di-copy pixel per pixel
    final canvas = img.Image(width: tileSize * 3, height: tileSize * 3, numChannels: 3);
    // Fill putih sebagai background default (supaya area tile yang gagal tetap putih)
    img.fill(canvas, color: img.ColorRgb8(242, 239, 233));

    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        try {
          final url =
              'https://tile.openstreetmap.org/$zoom/${tx + dx}/${ty + dy}.png';
          final response = await http.get(
            Uri.parse(url),
            headers: {'User-Agent': 'TermulLogApp/1.0'},
          ).timeout(const Duration(seconds: 8));
          if (response.statusCode == 200) {
            img.Image? tile = img.decodePng(response.bodyBytes);
            if (tile != null) {
              // Konversi tile ke RGB agar channel match dengan canvas
              if (tile.numChannels != 3) {
                tile = img.copyResize(
                  img.remapColors(tile,
                    red:   img.Channel.red,
                    green: img.Channel.green,
                    blue:  img.Channel.blue,
                    alpha: img.Channel.luminance,
                  ),
                  width: tileSize,
                  height: tileSize,
                );
              }
              // Copy pixel per pixel agar tidak ada masalah alpha blending
              final dstX = (dx + 1) * tileSize;
              final dstY = (dy + 1) * tileSize;
              for (int py2 = 0; py2 < tileSize; py2++) {
                for (int px2 = 0; px2 < tileSize; px2++) {
                  final pixel = tile.getPixel(px2, py2);
                  canvas.setPixelRgb(
                    dstX + px2,
                    dstY + py2,
                    pixel.r.toInt(),
                    pixel.g.toInt(),
                    pixel.b.toInt(),
                  );
                }
              }
            }
          }
        } catch (_) {}
      }
    }

    final cropX = (tileSize + px - 256).clamp(0, tileSize * 3 - 512);
    final cropY = (tileSize + py - 256).clamp(0, tileSize * 3 - 512);
    final cropped = img.copyCrop(canvas, x: cropX, y: cropY, width: 512, height: 512);

    final markerX = tileSize + px - cropX;
    final markerY = tileSize + py - cropY;
    final red   = img.ColorRgb8(220, 30, 30);
    final white = img.ColorRgb8(255, 255, 255);
    img.fillCircle(cropped, x: markerX, y: markerY, radius: 12, color: red);
    img.drawCircle(cropped, x: markerX, y: markerY, radius: 12, color: white);
    img.fillCircle(cropped, x: markerX, y: markerY, radius: 4,  color: white);

    return cropped;
  }
}

// ─── WATERMARK ────────────────────────────────────────────────────────────────

Future<String> addWatermark({
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
  final stripH = (h * 0.20).clamp(140.0, 220.0).toInt();
  final mapSize = mapImage != null ? stripH : 0;

  // Kanvas RGB — wajib numChannels:3 agar tidak ada masalah alpha saat encode JPEG
  final canvas = img.Image(width: w, height: h + stripH, numChannels: 3);
  img.compositeImage(canvas, original, dstX: 0, dstY: 0);

  // Strip hitam solid
  img.fillRect(canvas,
      x1: 0, y1: h, x2: w, y2: h + stripH,
      color: img.ColorRgb8(20, 20, 20));

  // Tempel peta
  if (mapImage != null) {
    final scaled = img.copyResize(mapImage, width: mapSize, height: mapSize);
    img.compositeImage(canvas, scaled, dstX: w - mapSize, dstY: h);
    img.drawLine(canvas,
        x1: w - mapSize, y1: h,
        x2: w - mapSize, y2: h + stripH,
        color: img.ColorRgb8(200, 200, 200));
  }

  // Warna teks
  final cWhite  = img.ColorRgb8(255, 255, 255);
  final cYellow = img.ColorRgb8(255, 215, 40);
  final cGrey   = img.ColorRgb8(170, 170, 170);

  final fontSize = (stripH * 0.16).clamp(12.0, 22.0).toInt();
  final lineGap  = (fontSize * 1.6).toInt();
  final pad      = (w * 0.02).toInt();
  final maxW     = w - mapSize - pad * 2;

  img.BitmapFont font;
  if (fontSize <= 14) {
    font = img.arial14;
  } else if (fontSize <= 24) {
    font = img.arial24;
  } else {
    font = img.arial48;
  }

  int y = h + (stripH * 0.07).toInt();

  // Baris 1 — nomor kiriman
  final line1 = 'KIRIMAN #' + deliveryNum.toString();
  img.drawString(canvas, line1, font: font, x: pad, y: y, color: cYellow);
  img.drawString(canvas, 'TermulLog',
      font: font, x: w - mapSize - fontSize * 6, y: y, color: cYellow);
  y += lineGap;

  // Baris 2 — kurir
  img.drawString(canvas, 'Kurir : ' + kurirName,
      font: font, x: pad, y: y, color: cWhite);
  y += lineGap;

  // Baris 3 — waktu
  img.drawString(canvas, 'Waktu : ' + timestamp,
      font: font, x: pad, y: y, color: cWhite);
  y += lineGap;

  // Baris 4 — GPS
  if (lat != null && lng != null) {
    final gpsText = 'GPS   : ' +
        lat.toStringAsFixed(6) +
        ', ' +
        lng.toStringAsFixed(6);
    img.drawString(canvas, gpsText, font: font, x: pad, y: y, color: cWhite);
  } else {
    img.drawString(canvas, 'GPS   : Tidak tersedia',
        font: font, x: pad, y: y, color: cGrey);
  }
  y += lineGap;

  // Baris 5 — alamat
  String addrText;
  img.Color addrColor;
  if (address != null && address.isNotEmpty) {
    final maxChars = (maxW / (fontSize * 0.6)).floor();
    addrText = address.length > maxChars
        ? address.substring(0, maxChars) + '...'
        : address;
    addrColor = cWhite;
  } else {
    addrText = 'Tidak tersedia';
    addrColor = cGrey;
  }
  img.drawString(canvas, 'Alamat: ' + addrText,
      font: font, x: pad, y: y, color: addrColor);

  // Simpan
  final dir = await getApplicationDocumentsDirectory();
  final ms  = DateTime.now().millisecondsSinceEpoch.toString();
  final outPath = dir.path + '/delivery_' + deliveryNum.toString() + '_' + ms + '.jpg';
  await File(outPath).writeAsBytes(img.encodeJpg(canvas, quality: 88));
  return outPath;
}

// ─── DASHBOARD ────────────────────────────────────────────────────────────────

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
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
          source: ImageSource.camera, imageQuality: 90);
      if (photo == null) {
        setState(() => isLoading = false);
        return;
      }

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

          try {
            final marks = await placemarkFromCoordinates(lat, lng)
                .timeout(const Duration(seconds: 6));
            if (marks.isNotEmpty) {
              final p = marks.first;
              final parts = [p.street, p.subLocality, p.locality, p.subAdministrativeArea]
                  .where((s) => s != null && s.isNotEmpty)
                  .toList();
              address = parts.join(', ');
            }
          } catch (_) {}

          try {
            mapImage = await MapTileHelper.fetchMap(lat, lng);
          } catch (_) {}
        }
      } catch (_) {}

      final now       = DateTime.now();
      final timestamp = DateFormat('dd/MM/yyyy HH:mm:ss').format(now);
      final num       = deliveries.length + 1;

      final path = await addWatermark(
        imagePath:   photo.path,
        kurirName:   widget.name,
        timestamp:   timestamp,
        deliveryNum: num,
        lat:         lat,
        lng:         lng,
        address:     address,
        mapImage:    mapImage,
      );

      setState(() {
        deliveries.insert(0, DeliveryRecord(
          number:    num,
          imagePath: path,
          timestamp: timestamp,
          kurirName: widget.name,
          lat:       lat,
          lng:       lng,
          address:   address,
        ));
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: ' + e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TermulLog Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const LoginScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
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
                _StatItem(label: 'Kurir', value: widget.name, icon: Icons.person),
                _StatItem(
                    label: 'Total Kiriman',
                    value: deliveries.length.toString(),
                    icon: Icons.inventory_2),
              ],
            ),
          ),
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
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.camera_alt),
                label: Text(isLoading ? 'Memproses...' : '+ FOTO BUKTI KIRIM'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: deliveries.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('Belum ada foto kiriman',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: deliveries.length,
                    itemBuilder: (_, i) => _DeliveryCard(delivery: deliveries[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── WIDGETS ──────────────────────────────────────────────────────────────────

class _StatItem extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _StatItem({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Icon(icon, color: Colors.blue),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
    ]);
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
            onTap: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => PhotoViewScreen(imagePath: delivery.imagePath))),
            child: SizedBox(
              width: double.infinity,
              height: 200,
              child: Image.file(File(delivery.imagePath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Center(child: Icon(Icons.broken_image, size: 48))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kiriman #' + delivery.number.toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.access_time, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(delivery.timestamp,
                      style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ]),
                if (delivery.address != null) ...[
                  const SizedBox(height: 2),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.location_on, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(delivery.address!,
                          style: const TextStyle(color: Colors.grey, fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ] else if (delivery.lat != null) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.location_on, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      delivery.lat!.toStringAsFixed(5) +
                          ', ' +
                          delivery.lng!.toStringAsFixed(5),
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
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

// ─── FULL SCREEN PHOTO ────────────────────────────────────────────────────────

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
          child: Image.file(File(imagePath),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image, color: Colors.white, size: 64)),
        ),
      ),
    );
  }
}
