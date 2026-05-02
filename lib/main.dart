// =======================
// TERMULLOG PREMIUM
// MODERN WATERMARK LAYOUT
// SIGNATURE PERSISTENT + FULLSIZE
// SETTINGS MENU TOP RIGHT
// GALLERY + SHARE
// =======================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:share_plus/share_plus.dart';

import 'package:image_picker/image_picker.dart';

import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

import 'package:path_provider/path_provider.dart';

import 'package:intl/intl.dart';

import 'package:image/image.dart' as img;

import 'package:http/http.dart' as http;

import 'package:shared_preferences/shared_preferences.dart';

import 'package:signature/signature.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TermulLogApp());
}

// =======================
// APP
// =======================

class TermulLogApp extends StatelessWidget {
  const TermulLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TermulLog',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF8C00),
          brightness: Brightness.light,
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

// =======================
// LOGIN
// =======================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final controller = TextEditingController();

  void login() {
    if (controller.text.trim().isEmpty) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DashboardScreen(name: controller.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF8C00), Color(0xFFFF4500)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF8C00).withOpacity(0.4),
                        blurRadius: 32,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.local_shipping_rounded,
                    size: 52,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 48),
              const Text(
                'TermulLog',
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Bukti pengiriman profesional',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withOpacity(0.45),
                ),
              ),
              const SizedBox(height: 44),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white),
                  onSubmitted: (_) => login(),
                  decoration: InputDecoration(
                    labelText: 'Nama Kurir',
                    labelStyle:
                        TextStyle(color: Colors.white.withOpacity(0.45)),
                    prefixIcon: Icon(Icons.person_outline_rounded,
                        color: Colors.white.withOpacity(0.45)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 18),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C00),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text(
                    'MASUK',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =======================
// MODEL
// =======================

class DeliveryRecord {
  final String deliveryId;
  final String imagePath;
  final String timestamp;

  DeliveryRecord({
    required this.deliveryId,
    required this.imagePath,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'deliveryId': deliveryId,
        'imagePath': imagePath,
        'timestamp': timestamp,
      };

  factory DeliveryRecord.fromJson(Map<String, dynamic> json) => DeliveryRecord(
        deliveryId: json['deliveryId'],
        imagePath: json['imagePath'],
        timestamp: json['timestamp'],
      );
}

// =======================
// WEATHER
// =======================

class WeatherHelper {
  static Future<String?> fetch(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lng&current_weather=true',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return '${data['current_weather']['temperature']}°C';
      }
    } catch (_) {}
    return null;
  }
}

// =======================
// LOAD LOGO
// =======================

Future<img.Image?> loadLogo(String? path) async {
  try {
    if (path != null && File(path).existsSync()) {
      final bytes = await File(path).readAsBytes();
      return img.decodeImage(bytes);
    }
  } catch (_) {}
  return null;
}

// =======================
// DRAW ROUNDED RECT HELPER
// =======================

void drawRoundedRect(
  img.Image canvas, {
  required int x1,
  required int y1,
  required int x2,
  required int y2,
  required img.Color color,
  int radius = 12,
}) {
  // Fill main body
  img.fillRect(canvas, x1: x1, y1: y1 + radius, x2: x2, y2: y2 - radius, color: color);
  img.fillRect(canvas, x1: x1 + radius, y1: y1, x2: x2 - radius, y2: y2, color: color);
  // Four corners
  img.fillCircle(canvas, x: x1 + radius, y: y1 + radius, radius: radius, color: color);
  img.fillCircle(canvas, x: x2 - radius, y: y1 + radius, radius: radius, color: color);
  img.fillCircle(canvas, x: x1 + radius, y: y2 - radius, radius: radius, color: color);
  img.fillCircle(canvas, x: x2 - radius, y: y2 - radius, radius: radius, color: color);
}

// =======================
// MODERN WATERMARK
// =======================

Future<String> addWatermark({
  required String imagePath,
  required String kurir,
  required String deliveryId,
  required String timestamp,
  required String? address,
  required String? weather,
  required double? lat,
  required double? lng,
  required String? logoPath,
  required String? signaturePath,
}) async {
  final bytes = await File(imagePath).readAsBytes();
  img.Image? original = img.decodeImage(bytes);
  if (original == null) throw Exception('Gagal membaca gambar');

  // Resize agar lebar konsisten
  if (original.width > 1080) {
    original = img.copyResize(original, width: 1080);
  }

  final W = original.width;

  // Panel tinggi cukup untuk semua konten + signature besar
  const panelHeight = 520;

  final canvas = img.Image(
    width: W,
    height: original.height + panelHeight,
  );

  // ── FOTO ──────────────────────────────────────
  img.compositeImage(canvas, original);

  final pY = original.height; // panel Y start

  // ── BACKGROUND PANEL: dark gradient effect ────
  // Gradasi manual dari atas ke bawah
  for (int row = 0; row < panelHeight; row++) {
    final t = row / panelHeight;
    final r = (15 + (25 * t)).round().clamp(0, 255);
    final g = (15 + (20 * t)).round().clamp(0, 255);
    final b = (28 + (15 * t)).round().clamp(0, 255);
    img.fillRect(
      canvas,
      x1: 0,
      y1: pY + row,
      x2: W,
      y2: pY + row + 1,
      color: img.ColorRgb8(r, g, b),
    );
  }

  // ── ACCENT LINE ATAS ──────────────────────────
  // Gradasi oranye
  for (int x = 0; x < W; x++) {
    final t = x / W;
    final r = 255;
    final g = (140 + (60 * t)).round().clamp(0, 255);
    final b = (0 + (30 * t)).round().clamp(0, 255);
    img.fillRect(
      canvas,
      x1: x, y1: pY, x2: x + 1, y2: pY + 6,
      color: img.ColorRgb8(r, g, b),
    );
  }

  // ── HEADER ROW: Logo kiri + Title kanan ───────
  final logo = await loadLogo(logoPath);
  const logoSize = 90;
  const headerPad = 24;
  const headerH = logoSize + headerPad * 2;

  // Logo box background
  drawRoundedRect(
    canvas,
    x1: headerPad,
    y1: pY + headerPad,
    x2: headerPad + logoSize,
    y2: pY + headerPad + logoSize,
    color: img.ColorRgb8(255, 140, 0),
    radius: 14,
  );

  if (logo != null) {
    final resized = img.copyResize(logo, width: logoSize - 16, height: logoSize - 16);
    img.compositeImage(
      canvas, resized,
      dstX: headerPad + 8,
      dstY: pY + headerPad + 8,
    );
  } else {
    // Default icon teks jika tidak ada logo
    img.drawString(
      canvas, 'TL',
      font: img.arial48,
      x: headerPad + 14,
      y: pY + headerPad + 20,
      color: img.ColorRgb8(255, 255, 255),
    );
  }

  // Title DELIVERY REPORT
  img.drawString(
    canvas, 'DELIVERY REPORT',
    font: img.arial48,
    x: headerPad + logoSize + 20,
    y: pY + headerPad + 4,
    color: img.ColorRgb8(255, 200, 60),
  );

  img.drawString(
    canvas, 'TermulLog  \u2022  Verified',
    font: img.arial24,
    x: headerPad + logoSize + 22,
    y: pY + headerPad + 58,
    color: img.ColorRgb8(180, 190, 210),
  );

  // ── DIVIDER ───────────────────────────────────
  final divY = pY + headerH + 10;
  img.fillRect(
    canvas,
    x1: headerPad, y1: divY,
    x2: W - headerPad, y2: divY + 1,
    color: img.ColorRgb8(60, 70, 90),
  );

  // ── INFO GRID ─────────────────────────────────
  // 2 kolom grid: kiri dan kanan
  final infoY = divY + 18;
  const col1X = headerPad;
  final col2X = W ~/ 2 + 10;
  final labelColor = img.ColorRgb8(255, 200, 60);
  final valueColor = img.ColorRgb8(230, 235, 245);
  final dimColor = img.ColorRgb8(140, 155, 175);

  // ── KOLOM KIRI ────────────────────────────────
  img.drawString(canvas, 'ID KIRIMAN', font: img.arial24, x: col1X, y: infoY,
      color: dimColor);
  img.drawString(canvas, deliveryId, font: img.arial24, x: col1X, y: infoY + 22,
      color: valueColor);

  img.drawString(canvas, 'KURIR', font: img.arial24, x: col1X, y: infoY + 60,
      color: dimColor);
  img.drawString(canvas, kurir, font: img.arial24, x: col1X, y: infoY + 82,
      color: valueColor);

  img.drawString(canvas, 'WAKTU', font: img.arial24, x: col1X, y: infoY + 120,
      color: dimColor);
  img.drawString(canvas, timestamp, font: img.arial24, x: col1X, y: infoY + 142,
      color: valueColor);

  // ── KOLOM KANAN ───────────────────────────────
  final gpsText = lat != null
      ? '${lat.toStringAsFixed(4)}, ${lng!.toStringAsFixed(4)}'
      : 'Tidak tersedia';

  img.drawString(canvas, 'GPS', font: img.arial24, x: col2X, y: infoY,
      color: dimColor);
  img.drawString(canvas, gpsText, font: img.arial24, x: col2X, y: infoY + 22,
      color: valueColor);

  img.drawString(canvas, 'CUACA', font: img.arial24, x: col2X, y: infoY + 60,
      color: dimColor);
  img.drawString(canvas, weather ?? '-', font: img.arial24, x: col2X, y: infoY + 82,
      color: valueColor);

  img.drawString(canvas, 'STATUS', font: img.arial24, x: col2X, y: infoY + 120,
      color: dimColor);

  // Status badge (TERKIRIM)
  drawRoundedRect(
    canvas,
    x1: col2X, y1: infoY + 138,
    x2: col2X + 130, y2: infoY + 162,
    color: img.ColorRgb8(30, 180, 100),
    radius: 6,
  );
  img.drawString(
    canvas, '  TERKIRIM',
    font: img.arial24,
    x: col2X + 6, y: infoY + 142,
    color: img.ColorRgb8(255, 255, 255),
  );

  // ── ALAMAT ────────────────────────────────────
  final addrY = infoY + 180;
  img.fillRect(
    canvas,
    x1: headerPad, y1: addrY,
    x2: W - headerPad, y2: addrY + 1,
    color: img.ColorRgb8(60, 70, 90),
  );

  img.drawString(canvas, 'ALAMAT PENGIRIMAN', font: img.arial24,
      x: headerPad, y: addrY + 12, color: dimColor);

  // Word wrap alamat
  final addr = address ?? 'Lokasi tidak tersedia';
  final words = addr.split(' ');
  String line = '';
  int addrLineY = addrY + 36;

  for (final word in words) {
    final test = line.isEmpty ? word : '$line $word';
    if (test.length > 55) {
      img.drawString(canvas, line, font: img.arial24,
          x: headerPad, y: addrLineY, color: valueColor);
      addrLineY += 26;
      line = word;
    } else {
      line = test;
    }
  }
  if (line.isNotEmpty) {
    img.drawString(canvas, line, font: img.arial24,
        x: headerPad, y: addrLineY, color: valueColor);
    addrLineY += 26;
  }

  // ── SIGNATURE SECTION ─────────────────────────
  // Signature di bawah, full width dengan background putih yang proporsional

  final sigSectionY = pY + panelHeight - 175; // 175px dari bawah panel

  // Label
  img.fillRect(
    canvas,
    x1: headerPad, y1: sigSectionY - 14,
    x2: W - headerPad, y2: sigSectionY - 13,
    color: img.ColorRgb8(60, 70, 90),
  );
  img.drawString(canvas, 'TANDA TANGAN PENERIMA', font: img.arial24,
      x: headerPad, y: sigSectionY - 10, color: dimColor);

  // Kotak putih signature — lebih besar dan proporsional
  final sigBoxX1 = headerPad;
  final sigBoxY1 = sigSectionY + 14;
  final sigBoxX2 = W - headerPad;
  final sigBoxY2 = sigSectionY + 150;

  drawRoundedRect(
    canvas,
    x1: sigBoxX1, y1: sigBoxY1,
    x2: sigBoxX2, y2: sigBoxY2,
    color: img.ColorRgb8(255, 255, 255),
    radius: 10,
  );

  if (signaturePath != null && File(signaturePath).existsSync()) {
    final sigBytes = await File(signaturePath).readAsBytes();
    final sig = img.decodeImage(sigBytes);

    if (sig != null) {
      // Resize signature agar memenuhi kotak dengan padding
      final targetW = (sigBoxX2 - sigBoxX1 - 24);
      final targetH = (sigBoxY2 - sigBoxY1 - 16);
      final resizedSig = img.copyResize(sig, width: targetW, height: targetH);

      img.compositeImage(
        canvas, resizedSig,
        dstX: sigBoxX1 + 12,
        dstY: sigBoxY1 + 8,
      );
    }
  } else {
    // Placeholder text jika tidak ada signature
    img.drawString(
      canvas, 'Belum ada tanda tangan',
      font: img.arial24,
      x: sigBoxX1 + 20,
      y: sigBoxY1 + (sigBoxY2 - sigBoxY1) ~/ 2 - 12,
      color: img.ColorRgb8(180, 180, 180),
    );
  }

  // ── FOOTER ────────────────────────────────────
  final footY = pY + panelHeight - 18;
  img.drawString(
    canvas,
    'Dibuat oleh TermulLog  \u2022  ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
    font: img.arial24,
    x: headerPad,
    y: footY,
    color: img.ColorRgb8(80, 95, 120),
  );

  final dir = await getApplicationDocumentsDirectory();
  final output = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
  await File(output).writeAsBytes(img.encodeJpg(canvas, quality: 93));
  return output;
}

// =======================
// SETTINGS SCREEN
// =======================

class SettingsScreen extends StatefulWidget {
  final String? currentLogoPath;
  final String? currentSignaturePath;

  const SettingsScreen({
    super.key,
    required this.currentLogoPath,
    required this.currentSignaturePath,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? logoPath;
  String? signaturePath;
  bool signatureChanged = false;

  final SignatureController signatureController = SignatureController(
    penStrokeWidth: 4,
    penColor: Colors.black,
  );

  @override
  void initState() {
    super.initState();
    logoPath = widget.currentLogoPath;
    signaturePath = widget.currentSignaturePath;
  }

  @override
  void dispose() {
    signatureController.dispose();
    super.dispose();
  }

  Future<void> pickLogo() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_logo', file.path);
    setState(() => logoPath = file.path);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      _snackBar('Logo berhasil diubah', const Color(0xFF2ECC71)),
    );
  }

  Future<void> removeLogo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('custom_logo');
    setState(() => logoPath = null);
  }

  Future<void> saveSignature() async {
    if (signatureController.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        _snackBar('Silakan buat tanda tangan dahulu', const Color(0xFFE74C3C)),
      );
      return;
    }

    final bytes = await signatureController.toPngBytes();
    if (bytes == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/signature.png');
    await file.writeAsBytes(bytes);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('signature', file.path);

    setState(() {
      signaturePath = file.path;
      signatureChanged = true;
    });

    signatureController.clear();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      _snackBar('Tanda tangan berhasil disimpan', const Color(0xFF2ECC71)),
    );
  }

  Future<void> removeSignature() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('signature');
    setState(() {
      signaturePath = null;
      signatureChanged = true;
    });
  }

  SnackBar _snackBar(String msg, Color color) {
    return SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Pengaturan',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context, {
            'logoPath': logoPath,
            'signaturePath': signaturePath,
          }),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── LOGO SECTION ──────────────────────────────
            _sectionLabel('LOGO PERUSAHAAN'),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Preview logo
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF8C00).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFFF8C00).withOpacity(0.4),
                            width: 2,
                          ),
                        ),
                        child: logoPath != null && File(logoPath!).existsSync()
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.file(
                                  File(logoPath!),
                                  fit: BoxFit.cover,
                                ),
                              )
                            : const Icon(
                                Icons.business_rounded,
                                color: Color(0xFFFF8C00),
                                size: 32,
                              ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              logoPath != null ? 'Logo aktif' : 'Belum ada logo',
                              style: TextStyle(
                                color: logoPath != null
                                    ? const Color(0xFF2ECC71)
                                    : Colors.white60,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              logoPath != null
                                  ? 'Logo akan muncul di watermark foto'
                                  : 'Tambahkan logo untuk watermark profesional',
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _outlinedBtn(
                          icon: Icons.photo_library_rounded,
                          label: logoPath != null ? 'GANTI LOGO' : 'PILIH LOGO',
                          color: const Color(0xFFFF8C00),
                          onTap: pickLogo,
                        ),
                      ),
                      if (logoPath != null) ...[
                        const SizedBox(width: 10),
                        _iconBtn(
                          icon: Icons.delete_outline_rounded,
                          color: const Color(0xFFE74C3C),
                          onTap: removeLogo,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── SIGNATURE SECTION ─────────────────────────
            _sectionLabel('TANDA TANGAN DIGITAL'),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Preview tanda tangan tersimpan
                  if (signaturePath != null && File(signaturePath!).existsSync()) ...[
                    const Text(
                      'Tanda tangan tersimpan:',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 90,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF2ECC71),
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(signaturePath!),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Area gambar tanda tangan baru
                  const Text(
                    'Buat tanda tangan baru:',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 8),

                  // ✅ KOTAK TTD: border oranye tebal + shadow
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFFF8C00),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF8C00).withOpacity(0.35),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: SizedBox(
                        height: 220,
                        child: Stack(
                          children: [
                            Signature(
                              controller: signatureController,
                              backgroundColor: Colors.white,
                            ),
                            // Hint text
                            Positioned(
                              bottom: 12,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Text(
                                  '— tanda tangan di sini —',
                                  style: TextStyle(
                                    color: Colors.grey.withOpacity(0.4),
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF8C00),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Area bertanda tangan — latar putih',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),

                  Row(
                    children: [
                      Expanded(
                        child: _outlinedBtn(
                          icon: Icons.refresh_rounded,
                          label: 'ULANGI',
                          color: Colors.white38,
                          onTap: () => signatureController.clear(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: _filledBtn(
                          icon: Icons.check_rounded,
                          label: 'SIMPAN TANDA TANGAN',
                          color: const Color(0xFFFF8C00),
                          onTap: saveSignature,
                        ),
                      ),
                    ],
                  ),

                  if (signaturePath != null) ...[
                    const SizedBox(height: 10),
                    _outlinedBtn(
                      icon: Icons.delete_outline_rounded,
                      label: 'HAPUS TANDA TANGAN',
                      color: const Color(0xFFE74C3C),
                      onTap: removeSignature,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Color(0xFF8892A4),
        letterSpacing: 1.4,
      ),
    );
  }

  Widget _outlinedBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.6)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _filledBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}

// =======================
// DASHBOARD
// =======================

class DashboardScreen extends StatefulWidget {
  final String name;
  const DashboardScreen({super.key, required this.name});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final deliveries = <DeliveryRecord>[];
  bool loading = false;
  String? customLogoPath;
  String? signaturePath;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    customLogoPath = prefs.getString('custom_logo');
    signaturePath = prefs.getString('signature');
    final history = prefs.getStringList('history') ?? [];
    deliveries.clear();
    for (final item in history) {
      deliveries.add(DeliveryRecord.fromJson(jsonDecode(item)));
    }
    setState(() {});
  }

  Future<void> saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'history', deliveries.map((e) => jsonEncode(e.toJson())).toList());
  }

  // ── BUKA SETTINGS ──────────────────────────────────
  Future<void> openSettings() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          currentLogoPath: customLogoPath,
          currentSignaturePath: signaturePath,
        ),
      ),
    );

    // Update state dari hasil settings
    if (result != null && result is Map) {
      setState(() {
        customLogoPath = result['logoPath'];
        signaturePath = result['signaturePath'];
      });
    }
  }

  // ── CAPTURE ────────────────────────────────────────
  Future<void> captureDelivery() async {
    setState(() => loading = true);

    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (photo == null) {
        setState(() => loading = false);
        return;
      }

      double? lat;
      double? lng;
      String? address;
      String? weather;

      try {
        LocationPermission permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          final pos = await Geolocator.getCurrentPosition();
          lat = pos.latitude;
          lng = pos.longitude;
          final placemarks = await placemarkFromCoordinates(lat, lng);
          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            address = '${p.street}, ${p.subLocality ?? ''}, ${p.locality}';
          }
          weather = await WeatherHelper.fetch(lat, lng);
        }
      } catch (_) {}

      final timestamp =
          DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());
      final deliveryId = 'TRM-${DateTime.now().millisecondsSinceEpoch}';

      // Reload signature path dari prefs agar selalu fresh
      final prefs = await SharedPreferences.getInstance();
      final freshSignaturePath = prefs.getString('signature');

      final finalPath = await addWatermark(
        imagePath: photo.path,
        kurir: widget.name,
        deliveryId: deliveryId,
        timestamp: timestamp,
        address: address,
        weather: weather,
        lat: lat,
        lng: lng,
        logoPath: customLogoPath,
        signaturePath: freshSignaturePath,
      );

      deliveries.insert(
          0,
          DeliveryRecord(
            deliveryId: deliveryId,
            imagePath: finalPath,
            timestamp: timestamp,
          ));
      await saveHistory();

      setState(() {
        loading = false;
        _selectedTab = 1;
      });
    } catch (e) {
      debugPrint(e.toString());
      setState(() => loading = false);
    }
  }

  Future<void> saveImage(String path) async {
    await GallerySaver.saveImage(path);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 8),
            Text('Berhasil disimpan ke galeri'),
          ],
        ),
        backgroundColor: const Color(0xFF2ECC71),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> shareImage(String path) async {
    await Share.shareXFiles([XFile(path)]);
  }

  // =======================
  // BUILD
  // =======================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F8),
      body: SafeArea(
        child: Column(
          children: [
            // ── HEADER ──────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 0),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F0F1A), Color(0xFF1A1A2E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF8C00), Color(0xFFFF4500)],
                          ),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(Icons.local_shipping_rounded,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TermulLog',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 18),
                          ),
                          Text(
                            'Halo, ${widget.name}',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Counter
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF8C00).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: const Color(0xFFFF8C00).withOpacity(0.3)),
                        ),
                        child: Text(
                          '${deliveries.length} Kiriman',
                          style: const TextStyle(
                              color: Color(0xFFFF8C00),
                              fontWeight: FontWeight.w700,
                              fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // ✅ SETTINGS ICON KANAN ATAS
                      IconButton(
                        onPressed: openSettings,
                        icon: const Icon(Icons.settings_rounded,
                            color: Colors.white60, size: 24),
                        tooltip: 'Pengaturan',
                        padding: const EdgeInsets.all(8),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // Tab bar
                  Row(
                    children: [
                      _buildTab('Ambil Foto', Icons.camera_alt_rounded, 0),
                      const SizedBox(width: 6),
                      _buildTab('Galeri', Icons.photo_library_rounded, 1),
                    ],
                  ),
                ],
              ),
            ),

            // ── CONTENT ─────────────────────────────────
            Expanded(
              child: _selectedTab == 0 ? _buildCaptureTab() : _buildGalleryTab(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String label, IconData icon, int index) {
    final isActive = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFFF8C00) : Colors.transparent,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(10)),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 15,
                color: isActive ? Colors.white : Colors.white38),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: isActive ? Colors.white : Colors.white38,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }

  // =======================
  // TAB CAPTURE
  // =======================

  Widget _buildCaptureTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status cards
          Row(
            children: [
              Expanded(
                child: _statusCard(
                  icon: Icons.image_rounded,
                  label: 'Logo',
                  value: customLogoPath != null ? 'Aktif' : 'Belum diatur',
                  color: customLogoPath != null
                      ? const Color(0xFF2ECC71)
                      : const Color(0xFF8892A4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statusCard(
                  icon: Icons.draw_rounded,
                  label: 'Tanda Tangan',
                  value: signaturePath != null ? 'Aktif' : 'Belum diatur',
                  color: signaturePath != null
                      ? const Color(0xFF2ECC71)
                      : const Color(0xFF8892A4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Tap settings hint
          if (customLogoPath == null || signaturePath == null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFF8C00).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFFF8C00).withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: Color(0xFFFF8C00), size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Atur logo & tanda tangan di menu ⚙️ kanan atas',
                      style: TextStyle(
                          color: Color(0xFFFF8C00),
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // ── BIG CAPTURE BUTTON ────────────────────────
          GestureDetector(
            onTap: loading ? null : captureDelivery,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 150,
              decoration: BoxDecoration(
                gradient: loading
                    ? const LinearGradient(
                        colors: [Color(0xFF444), Color(0xFF333)])
                    : const LinearGradient(
                        colors: [Color(0xFFFF8C00), Color(0xFFFF4500)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: loading
                    ? []
                    : [
                        BoxShadow(
                          color: const Color(0xFFFF8C00).withOpacity(0.45),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
              ),
              child: Center(
                child: loading
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                          SizedBox(height: 12),
                          Text('MEMPROSES...',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5)),
                        ],
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt_rounded,
                              color: Colors.white, size: 46),
                          SizedBox(height: 10),
                          Text('AMBIL FOTO BUKTI',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                  letterSpacing: 1.5)),
                          SizedBox(height: 4),
                          Text('GPS + Cuaca + Tanda Tangan Otomatis',
                              style: TextStyle(
                                  color: Colors.white60, fontSize: 12)),
                        ],
                      ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          Row(
            children: [
              _chip(Icons.location_on_rounded, 'GPS Otomatis'),
              const SizedBox(width: 8),
              _chip(Icons.cloud_rounded, 'Cuaca Live'),
              const SizedBox(width: 8),
              _chip(Icons.draw_rounded, 'TTD Digital'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Color(0xFF8892A4),
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                Text(value,
                    style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 11, color: const Color(0xFFFF8C00)),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF444))),
        ],
      ),
    );
  }

  // =======================
  // TAB GALLERY
  // =======================

  Widget _buildGalleryTab() {
    if (deliveries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFFF8C00).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.photo_library_outlined,
                  size: 36, color: Color(0xFFFF8C00)),
            ),
            const SizedBox(height: 16),
            const Text('Belum ada foto',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2C3E50))),
            const SizedBox(height: 8),
            const Text('Ambil foto bukti pengiriman\ndi tab Ambil Foto',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8892A4), fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: deliveries.length,
      itemBuilder: (_, index) {
        final d = deliveries[index];
        final exists = File(d.imagePath).existsSync();

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.07),
                  blurRadius: 16,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                child: exists
                    ? GestureDetector(
                        onTap: () => _openFullscreen(d.imagePath),
                        child: Stack(
                          children: [
                            Image.file(
                              File(d.imagePath),
                              width: double.infinity,
                              height: 210,
                              fit: BoxFit.cover,
                            ),
                            Positioned(
                              top: 10,
                              left: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [
                                    Color(0xFFFF8C00),
                                    Color(0xFFFF4500)
                                  ]),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text('#${deliveries.length - index}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800)),
                              ),
                            ),
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.zoom_in_rounded,
                                        color: Colors.white, size: 13),
                                    SizedBox(width: 4),
                                    Text('Lihat Detail',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        height: 100,
                        color: const Color(0xFFF0F0F0),
                        child: const Center(
                          child: Icon(Icons.broken_image_rounded,
                              color: Color(0xFFCCC), size: 36),
                        ),
                      ),
              ),

              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF8C00).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(d.deliveryId,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                  color: Color(0xFFFF8C00))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded,
                            size: 13, color: Color(0xFF8892A4)),
                        const SizedBox(width: 4),
                        Text(d.timestamp,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF8892A4))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _actionBtn(
                            icon: Icons.save_alt_rounded,
                            label: 'Simpan',
                            color: const Color(0xFF3498DB),
                            onTap: exists ? () => saveImage(d.imagePath) : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _actionBtn(
                            icon: Icons.share_rounded,
                            label: 'Bagikan',
                            color: const Color(0xFF2ECC71),
                            onTap: exists ? () => shareImage(d.imagePath) : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _actionBtn(
                            icon: Icons.open_in_full_rounded,
                            label: 'Lihat',
                            color: const Color(0xFF9B59B6),
                            onTap: exists ? () => _openFullscreen(d.imagePath) : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    final active = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.08) : Colors.grey.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: active ? color.withOpacity(0.25) : Colors.grey.withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 19, color: active ? color : Colors.grey),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: active ? color : Colors.grey)),
          ],
        ),
      ),
    );
  }

  void _openFullscreen(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.save_alt_rounded),
                onPressed: () => saveImage(path),
              ),
              IconButton(
                icon: const Icon(Icons.share_rounded),
                onPressed: () => shareImage(path),
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5.0,
              child: Image.file(File(path)),
            ),
          ),
        ),
      ),
    );
  }
}
