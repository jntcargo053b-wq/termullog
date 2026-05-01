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
  static const int zoom       = 18;   // detail maksimal OSM
  static const int tileSize   = 256;
  static const int outputSize = 480;  // ~75m radius di zoom 18

  static int _lonToTileX(double lon) =>
      ((lon + 180.0) / 360.0 * (1 << zoom)).floor();

  static int _latToTileY(double lat) {
    final rad = lat * pi / 180.0;
    return ((1.0 - log(tan(rad) + 1.0 / cos(rad)) / pi) / 2.0 * (1 << zoom))
        .floor();
  }

  static int _lonPixelOffset(double lon) {
    final world = (lon + 180.0) / 360.0 * (1 << zoom);
    return ((world - world.floor()) * tileSize).floor();
  }

  static int _latPixelOffset(double lat) {
    final rad   = lat * pi / 180.0;
    final world =
        (1.0 - log(tan(rad) + 1.0 / cos(rad)) / pi) / 2.0 * (1 << zoom);
    return ((world - world.floor()) * tileSize).floor();
  }

  // ── Fallback: gambar grid koordinat jika OSM tidak bisa diakses ──────────
  static img.Image _buildFallbackMap(double lat, double lng) {
    final out = img.Image(
        width: outputSize, height: outputSize, numChannels: 3);

    // Background abu-biru muda ala peta
    img.fill(out, color: img.ColorRgb8(220, 232, 245));

    // Grid garis setiap 80px (simulasi grid koordinat)
    final gridColor  = img.ColorRgb8(180, 200, 220);
    final gridColor2 = img.ColorRgb8(160, 185, 210);
    for (int i = 0; i < outputSize; i += 80) {
      img.drawLine(out, x1: i, y1: 0, x2: i, y2: outputSize - 1,
          color: gridColor);
      img.drawLine(out, x1: 0, y1: i, x2: outputSize - 1, y2: i,
          color: gridColor);
    }
    // Garis tengah (posisi GPS) lebih tebal
    for (int t = -1; t <= 1; t++) {
      img.drawLine(out,
          x1: outputSize ~/ 2 + t, y1: 0,
          x2: outputSize ~/ 2 + t, y2: outputSize - 1,
          color: gridColor2);
      img.drawLine(out,
          x1: 0,            y1: outputSize ~/ 2 + t,
          x2: outputSize - 1, y2: outputSize ~/ 2 + t,
          color: gridColor2);
    }

    // Label koordinat di tengah
    final latStr = lat.toStringAsFixed(5);
    final lngStr = lng.toStringAsFixed(5);
    img.drawString(out, latStr,
        font: img.arial14,
        x: outputSize ~/ 2 - 48,
        y: outputSize ~/ 2 - 26,
        color: img.ColorRgb8(40, 80, 140));
    img.drawString(out, lngStr,
        font: img.arial14,
        x: outputSize ~/ 2 - 48,
        y: outputSize ~/ 2 - 10,
        color: img.ColorRgb8(40, 80, 140));

    // Label "GPS Only" di pojok atas
    img.drawString(out, 'GPS Only',
        font: img.arial14,
        x: 6, y: 6,
        color: img.ColorRgb8(100, 100, 130));

    // Marker merah di tengah
    final mX = outputSize ~/ 2;
    final mY = outputSize ~/ 2;
    img.fillCircle(out, x: mX + 2, y: mY + 2, radius: 12,
        color: img.ColorRgb8(0, 0, 0));
    img.fillCircle(out, x: mX,     y: mY,     radius: 12,
        color: img.ColorRgb8(220, 30, 30));
    img.drawCircle(out, x: mX,     y: mY,     radius: 12,
        color: img.ColorRgb8(255, 255, 255));
    img.fillCircle(out, x: mX,     y: mY,     radius: 4,
        color: img.ColorRgb8(255, 255, 255));

    return out;
  }

  static Future<img.Image> fetchMap(double lat, double lng) async {
    final tx = _lonToTileX(lng);
    final ty = _latToTileY(lat);
    final px = _lonPixelOffset(lng);
    final py = _latPixelOffset(lat);

    // Grid 5×5 tile
    const grid     = 5;
    const halfGrid = 2;
    final canvasW  = tileSize * grid;
    final canvasH  = tileSize * grid;

    final canvas =
        img.Image(width: canvasW, height: canvasH, numChannels: 3);
    img.fill(canvas, color: img.ColorRgb8(242, 239, 233));

    int successCount = 0; // hitung tile yang berhasil di-fetch

    for (int dy = -halfGrid; dy <= halfGrid; dy++) {
      for (int dx = -halfGrid; dx <= halfGrid; dx++) {
        try {
          final url =
              'https://tile.openstreetmap.org/$zoom/${tx + dx}/${ty + dy}.png';
          final res = await http
              .get(Uri.parse(url),
                  headers: {'User-Agent': 'TermulLogApp/1.0'})
              .timeout(const Duration(seconds: 10));

          if (res.statusCode == 200) {
            img.Image? tile = img.decodePng(res.bodyBytes);
            if (tile == null) continue;

            if (tile.numChannels != 3) {
              tile = img.copyResize(
                img.remapColors(tile,
                    red:   img.Channel.red,
                    green: img.Channel.green,
                    blue:  img.Channel.blue,
                    alpha: img.Channel.luminance),
                width:  tileSize,
                height: tileSize,
              );
            }

            final dstX = (dx + halfGrid) * tileSize;
            final dstY = (dy + halfGrid) * tileSize;
            for (int row = 0; row < tileSize; row++) {
              for (int col = 0; col < tileSize; col++) {
                final p = tile.getPixel(col, row);
                canvas.setPixelRgb(
                  dstX + col, dstY + row,
                  p.r.toInt(), p.g.toInt(), p.b.toInt(),
                );
              }
            }
            successCount++;
          }
        } catch (_) {}
      }
    }

    // Jika tidak ada satu pun tile berhasil → pakai fallback grid
    if (successCount == 0) {
      return _buildFallbackMap(lat, lng);
    }

    // Crop ke area outputSize × outputSize di sekitar titik GPS
    final centerX = halfGrid * tileSize + px;
    final centerY = halfGrid * tileSize + py;
    final half    = outputSize ~/ 2;

    final cropX =
        (centerX - half).clamp(0, canvasW - outputSize);
    final cropY =
        (centerY - half).clamp(0, canvasH - outputSize);
    final cropped = img.copyCrop(canvas,
        x: cropX, y: cropY, width: outputSize, height: outputSize);

    final mX = centerX - cropX;
    final mY = centerY - cropY;

    // Marker kecil agar tidak menutupi nama jalan
    img.fillCircle(cropped, x: mX + 2, y: mY + 2, radius: 10,
        color: img.ColorRgb8(0, 0, 0));
    img.fillCircle(cropped, x: mX,     y: mY,     radius: 10,
        color: img.ColorRgb8(220, 30, 30));
    img.drawCircle(cropped, x: mX,     y: mY,     radius: 10,
        color: img.ColorRgb8(255, 255, 255));
    img.fillCircle(cropped, x: mX,     y: mY,     radius: 3,
        color: img.ColorRgb8(255, 255, 255));

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

  // ── Resize foto agar pas di layar HP (max 1080px) ────────────────────────
  if (original.width > 1080) {
    original = img.copyResize(original, width: 1080,
        interpolation: img.Interpolation.linear);
  }
  if (original.height > 1440) {
    original = img.copyResize(original, height: 1440,
        interpolation: img.Interpolation.linear);
  }

  final w = original.width;
  final h = original.height;

  // ── Ukuran strip ─────────────────────────────────────────────────────────
  // Semua teks pakai arial24 → perlu strip lebih tinggi: 320px
  const stripH       = 320;
  const mapDisplaySz = 320; // peta mengisi penuh tinggi strip
  final hasMap       = mapImage != null;
  final mapW         = hasMap ? mapDisplaySz : 0;

  // ── Kanvas ───────────────────────────────────────────────────────────────
  final canvas =
      img.Image(width: w, height: h + stripH, numChannels: 3);
  img.compositeImage(canvas, original, dstX: 0, dstY: 0);

  // ── Background strip: gradient gelap ─────────────────────────────────────
  for (int row = 0; row < stripH; row++) {
    final t    = row / (stripH - 1);
    final gray = (38 * (1 - t) + 8 * t).toInt();
    img.drawLine(canvas,
        x1: 0, y1: h + row, x2: w - 1, y2: h + row,
        color: img.ColorRgb8(gray, gray, gray + 5));
  }

  // ── Garis aksen teal (4px) di batas foto-strip ───────────────────────────
  for (int x = 0; x < w; x++) {
    for (int t = 0; t < 4; t++) {
      canvas.setPixelRgb(x, h + t, 0, 195, 175);
    }
  }

  // ── Tempel peta di KIRI ───────────────────────────────────────────────────
  if (hasMap) {
    final scaled =
        img.copyResize(mapImage!, width: mapDisplaySz, height: mapDisplaySz);
    img.compositeImage(canvas, scaled, dstX: 0, dstY: h);

    // Garis vertikal pemisah peta-teks
    for (int row = 0; row < stripH; row++) {
      canvas.setPixelRgb(mapW,     h + row, 0, 195, 175);
      canvas.setPixelRgb(mapW + 1, h + row, 0, 195, 175);
      canvas.setPixelRgb(mapW + 2, h + row, 0, 195, 175);
    }
  }

  // ── Warna teks ───────────────────────────────────────────────────────────
  final cWhite  = img.ColorRgb8(255, 255, 255);
  final cTeal   = img.ColorRgb8(0, 210, 185);
  final cYellow = img.ColorRgb8(255, 210, 0);
  final cGrey   = img.ColorRgb8(160, 160, 160);

  // Semua teks info pakai arial24 agar mudah dibaca
  final fontTitle = img.arial24;
  final fontInfo  = img.arial24;

  final textX  = mapW + 18;       // X mulai teks
  final maxTW  = w - textX - 14;  // lebar area teks
  int   ty     = h + 14;          // Y awal teks dalam strip

  // ── Header: KIRIMAN #N ───────────────────────────────────────────────────
  img.drawString(canvas, 'KIRIMAN #$deliveryNum',
      font: fontTitle, x: textX, y: ty, color: cYellow);
  ty += 38;

  // Garis dekoratif bawah header
  img.drawLine(canvas,
      x1: textX, y1: ty - 6,
      x2: textX + 200, y2: ty - 6,
      color: cTeal);
  ty += 4;

  // ── Kurir ────────────────────────────────────────────────────────────────
  img.drawString(canvas, 'Kurir : $kurirName',
      font: fontInfo, x: textX, y: ty, color: cWhite);
  ty += 34;

  // ── Waktu ────────────────────────────────────────────────────────────────
  img.drawString(canvas, 'Waktu : $timestamp',
      font: fontInfo, x: textX, y: ty, color: cWhite);
  ty += 34;

  // ── GPS ──────────────────────────────────────────────────────────────────
  if (lat != null && lng != null) {
    img.drawString(canvas,
        'GPS   : ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
        font: fontInfo, x: textX, y: ty, color: cWhite);
  } else {
    img.drawString(canvas, 'GPS   : Tidak tersedia',
        font: fontInfo, x: textX, y: ty, color: cGrey);
  }
  ty += 34;

  // ── Alamat (wrap otomatis ke baris ke-2 jika perlu) ───────────────────────
  // arial24: estimasi lebar karakter ~14px
  const charW    = 14;
  final maxChars = maxTW ~/ charW;

  if (address != null && address.isNotEmpty) {
    final prefix = 'Alamat: ';
    final avail  = maxChars - prefix.length;

    final line1text = address.length > avail
        ? address.substring(0, avail)
        : address;
    img.drawString(canvas, '$prefix$line1text',
        font: fontInfo, x: textX, y: ty, color: cWhite);
    ty += 30;

    if (address.length > avail) {
      final rest  = address.substring(avail);
      final line2 = rest.length > maxChars
          ? '${rest.substring(0, maxChars - 3)}...'
          : rest;
      img.drawString(canvas, '        $line2',
          font: fontInfo, x: textX, y: ty, color: cWhite);
    }
  } else {
    img.drawString(canvas, 'Alamat: Tidak tersedia',
        font: fontInfo, x: textX, y: ty, color: cGrey);
  }

  // ── Brand pojok kanan bawah strip ────────────────────────────────────────
  img.drawString(canvas, 'TermulLog',
      font: img.arial14, x: w - 92, y: h + stripH - 20, color: cTeal);

  // ── Simpan ───────────────────────────────────────────────────────────────
  final dir     = await getApplicationDocumentsDirectory();
  final ms      = DateTime.now().millisecondsSinceEpoch.toString();
  final outPath = '${dir.path}/delivery_${deliveryNum}_$ms.jpg';
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
                p.subAdministrativeArea,
              ].where((s) => s != null && s.isNotEmpty).toList();
              address = parts.join(', ');
            }
          } catch (_) {}

          // fetchMap sekarang selalu return img.Image (tidak nullable)
          // karena sudah ada fallback grid jika OSM gagal
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
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}')));
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
                          child: Text(delivery.address!,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
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
