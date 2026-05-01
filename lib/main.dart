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
  static const int zoom = 17;        // zoom 17 = lebih detail, jalan kecil kelihatan
  static const int tileSize = 256;
  static const int outputSize = 400; // ukuran output peta (px)

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

    // Canvas 5×5 tile agar ada cukup area untuk di-crop
    final canvasW = tileSize * 5;
    final canvasH = tileSize * 5;
    final canvas = img.Image(width: canvasW, height: canvasH, numChannels: 3);
    img.fill(canvas, color: img.ColorRgb8(242, 239, 233));

    for (int dy = -2; dy <= 2; dy++) {
      for (int dx = -2; dx <= 2; dx++) {
        try {
          final url =
              'https://tile.openstreetmap.org/$zoom/${tx + dx}/${ty + dy}.png';
          final response = await http.get(
            Uri.parse(url),
            headers: {'User-Agent': 'TermulLogApp/1.0'},
          ).timeout(const Duration(seconds: 10));
          if (response.statusCode == 200) {
            img.Image? tile = img.decodePng(response.bodyBytes);
            if (tile != null) {
              if (tile.numChannels != 3) {
                tile = img.copyResize(
                  img.remapColors(
                    tile,
                    red: img.Channel.red,
                    green: img.Channel.green,
                    blue: img.Channel.blue,
                    alpha: img.Channel.luminance,
                  ),
                  width: tileSize,
                  height: tileSize,
                );
              }
              final dstX = (dx + 2) * tileSize;
              final dstY = (dy + 2) * tileSize;
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

    // Titik center: tile (2,2) + offset piksel dalam tile tersebut
    final centerX = 2 * tileSize + px;
    final centerY = 2 * tileSize + py;
    final half = outputSize ~/ 2;

    final cropX = (centerX - half).clamp(0, canvasW - outputSize);
    final cropY = (centerY - half).clamp(0, canvasH - outputSize);
    final cropped = img.copyCrop(canvas,
        x: cropX, y: cropY, width: outputSize, height: outputSize);

    final markerX = centerX - cropX;
    final markerY = centerY - cropY;

    // Marker dengan shadow agar kontras di atas peta terang
    final shadow = img.ColorRgb8(0, 0, 0);
    final red    = img.ColorRgb8(220, 30, 30);
    final white  = img.ColorRgb8(255, 255, 255);
    img.fillCircle(cropped, x: markerX + 2, y: markerY + 2, radius: 14, color: shadow);
    img.fillCircle(cropped, x: markerX,     y: markerY,     radius: 14, color: red);
    img.drawCircle(cropped, x: markerX,     y: markerY,     radius: 14, color: white);
    img.fillCircle(cropped, x: markerX,     y: markerY,     radius: 5,  color: white);

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

  // Strip info tinggi tetap 260px — cukup untuk peta + semua teks
  const stripH       = 260;
  const mapDisplaySz = 260; // lebar/tinggi peta = sama dengan stripH
  final hasMap       = mapImage != null;
  final mapW         = hasMap ? mapDisplaySz : 0;

  // ── Kanvas akhir (foto + strip bawah) ────────────────────────────────────
  final canvas = img.Image(width: w, height: h + stripH, numChannels: 3);
  img.compositeImage(canvas, original, dstX: 0, dstY: 0);

  // ── Background strip: gradient manual abu gelap → hitam ──────────────────
  for (int row = 0; row < stripH; row++) {
    final t    = row / (stripH - 1);
    final gray = (35 * (1 - t) + 8 * t).toInt();
    img.drawLine(
      canvas,
      x1: 0,     y1: h + row,
      x2: w - 1, y2: h + row,
      color: img.ColorRgb8(gray, gray, gray + 4),
    );
  }

  // ── Garis aksen teal di batas foto-strip (3px) ───────────────────────────
  for (int x = 0; x < w; x++) {
    canvas.setPixelRgb(x, h,     0, 200, 180);
    canvas.setPixelRgb(x, h + 1, 0, 200, 180);
    canvas.setPixelRgb(x, h + 2, 0, 200, 180);
  }

  // ── Tempel peta di KIRI strip ─────────────────────────────────────────────
  if (hasMap) {
    final scaled =
        img.copyResize(mapImage!, width: mapDisplaySz, height: mapDisplaySz);
    img.compositeImage(canvas, scaled, dstX: 0, dstY: h);

    // Garis vertikal pemisah peta-teks (teal 2px)
    for (int row = 0; row < stripH; row++) {
      canvas.setPixelRgb(mapW,     h + row, 0, 200, 180);
      canvas.setPixelRgb(mapW + 1, h + row, 0, 200, 180);
    }
  }

  // ── Warna teks ───────────────────────────────────────────────────────────
  final cWhite  = img.ColorRgb8(255, 255, 255);
  final cTeal   = img.ColorRgb8(0, 210, 185);
  final cYellow = img.ColorRgb8(255, 210, 0);
  final cGrey   = img.ColorRgb8(155, 155, 155);

  final fontBig   = img.arial24; // header kiriman
  final fontSmall = img.arial14; // isi info

  final textX  = mapW + 16;       // X awal teks (setelah peta + padding)
  final maxTW  = w - textX - 12;  // lebar maksimal area teks
  int   ty     = h + 12;          // Y awal teks

  // ── Header: KIRIMAN #N ───────────────────────────────────────────────────
  img.drawString(
    canvas,
    'KIRIMAN #$deliveryNum',
    font: fontBig,
    x: textX,
    y: ty,
    color: cYellow,
  );
  ty += 34;

  // Garis dekoratif bawah header
  img.drawLine(
    canvas,
    x1: textX,       y1: ty - 4,
    x2: textX + 180, y2: ty - 4,
    color: cTeal,
  );
  ty += 6;

  // ── Kurir ────────────────────────────────────────────────────────────────
  img.drawString(
    canvas,
    'Kurir   : $kurirName',
    font: fontSmall,
    x: textX,
    y: ty,
    color: cWhite,
  );
  ty += 26;

  // ── Waktu ────────────────────────────────────────────────────────────────
  img.drawString(
    canvas,
    'Waktu   : $timestamp',
    font: fontSmall,
    x: textX,
    y: ty,
    color: cWhite,
  );
  ty += 26;

  // ── GPS ──────────────────────────────────────────────────────────────────
  if (lat != null && lng != null) {
    img.drawString(
      canvas,
      'GPS     : ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
      font: fontSmall,
      x: textX,
      y: ty,
      color: cWhite,
    );
  } else {
    img.drawString(
      canvas,
      'GPS     : Tidak tersedia',
      font: fontSmall,
      x: textX,
      y: ty,
      color: cGrey,
    );
  }
  ty += 26;

  // ── Alamat (wrap 2 baris) ────────────────────────────────────────────────
  // Estimasi lebar karakter arial14 ≈ 8px
  const charW   = 8;
  final maxChars = maxTW ~/ charW;

  if (address != null && address.isNotEmpty) {
    final line1 = address.length > maxChars
        ? address.substring(0, maxChars)
        : address;
    img.drawString(
      canvas,
      'Alamat  : $line1',
      font: fontSmall,
      x: textX,
      y: ty,
      color: cWhite,
    );
    ty += 22;

    if (address.length > maxChars) {
      final rest  = address.substring(maxChars);
      final line2 = rest.length > maxChars
          ? '${rest.substring(0, maxChars - 3)}...'
          : rest;
      img.drawString(
        canvas,
        '          $line2',
        font: fontSmall,
        x: textX,
        y: ty,
        color: cWhite,
      );
      ty += 22;
    }
  } else {
    img.drawString(
      canvas,
      'Alamat  : Tidak tersedia',
      font: fontSmall,
      x: textX,
      y: ty,
      color: cGrey,
    );
  }

  // ── Watermark brand di pojok kanan bawah strip ───────────────────────────
  img.drawString(
    canvas,
    'TermulLog',
    font: fontSmall,
    x: w - 92,
    y: h + stripH - 22,
    color: cTeal,
  );

  // ── Simpan ───────────────────────────────────────────────────────────────
  final dir     = await getApplicationDocumentsDirectory();
  final ms      = DateTime.now().millisecondsSinceEpoch.toString();
  final outPath = '${dir.path}/delivery_${deliveryNum}_$ms.jpg';
  await File(outPath).writeAsBytes(img.encodeJpg(canvas, quality: 90));
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
      final XFile? photo =
          await picker.pickImage(source: ImageSource.camera, imageQuality: 90);
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
              final p     = marks.first;
              final parts = [
                p.street,
                p.subLocality,
                p.locality,
                p.subAdministrativeArea
              ].where((s) => s != null && s.isNotEmpty).toList();
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
        deliveries.insert(
          0,
          DeliveryRecord(
            number:    num,
            imagePath: path,
            timestamp: timestamp,
            kurirName: widget.name,
            lat:       lat,
            lng:       lng,
            address:   address,
          ),
        );
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
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
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Info kurir & total kiriman ──────────────────────────────────
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
                    value: deliveries.length.toString(),
                    icon: Icons.inventory_2),
              ],
            ),
          ),

          // ── Tombol foto ─────────────────────────────────────────────────
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
                        child:
                            CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.camera_alt),
                label: Text(
                    isLoading ? 'Memproses...' : '+ FOTO BUKTI KIRIM'),
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

          // ── Daftar kiriman ───────────────────────────────────────────────
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
                    itemBuilder: (_, i) =>
                        _DeliveryCard(delivery: deliveries[i]),
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
  const _StatItem(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Icon(icon, color: Colors.blue),
      const SizedBox(height: 4),
      Text(value,
          style:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      Text(label,
          style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
          // Thumbnail foto (tap untuk fullscreen)
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
                errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image, size: 48)),
              ),
            ),
          ),

          // Info kiriman
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
                      ]),
                ] else if (delivery.lat != null) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.location_on,
                        size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '${delivery.lat!.toStringAsFixed(5)}, '
                      '${delivery.lng!.toStringAsFixed(5)}',
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
          child: Image.file(
            File(imagePath),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.broken_image,
              color: Colors.white,
              size: 64,
            ),
          ),
        ),
      ),
    );
  }
}
