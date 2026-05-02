// =======================
// TERMULLOG PREMIUM FULL FIX
// MODERN CARD THEME
// SIGNATURE BORDER VISIBLE
// GALLERY WITH SHARE
// =======================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        fontFamily: 'Roboto',
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
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo Area
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
                        blurRadius: 24,
                        offset: const Offset(0, 8),
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
              const SizedBox(height: 40),

              // Title
              const Text(
                'TermulLog',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Bukti pengiriman profesional',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 40),

              // Input
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.12),
                  ),
                ),
                child: TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Nama Kurir',
                    labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                    prefixIcon: Icon(
                      Icons.person_outline_rounded,
                      color: Colors.white.withOpacity(0.5),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Button
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
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'MASUK',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
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
        final current = data['current_weather'];
        return '${current['temperature']}°C';
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
// WATERMARK
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

  if (original.width > 1080) {
    original = img.copyResize(original, width: 1080);
  }

  const panelHeight = 430;
  final canvas = img.Image(
    width: original.width,
    height: original.height + panelHeight,
  );

  img.compositeImage(canvas, original);

  img.fillRect(
    canvas,
    x1: 0,
    y1: original.height,
    x2: original.width,
    y2: original.height + panelHeight,
    color: img.ColorRgb8(20, 20, 20),
  );

  img.fillRect(
    canvas,
    x1: 0,
    y1: original.height,
    x2: original.width,
    y2: original.height + 8,
    color: img.ColorRgb8(255, 180, 0),
  );

  final logo = await loadLogo(logoPath);
  if (logo != null) {
    final resized = img.copyResize(logo, width: 220);
    img.compositeImage(canvas, resized, dstX: 20, dstY: original.height + 30);
  }

  int y = original.height + 30;
  const textX = 280;

  img.drawString(
    canvas,
    'DELIVERY REPORT',
    font: img.arial48,
    x: textX,
    y: y,
    color: img.ColorRgb8(255, 210, 0),
  );

  y += 65;

  final items = [
    'ID : $deliveryId',
    'Kurir : $kurir',
    'Waktu : $timestamp',
    'GPS : ${lat ?? '-'}, ${lng ?? '-'}',
    'Cuaca : ${weather ?? '-'}',
  ];

  for (final item in items) {
    img.drawString(
      canvas,
      item,
      font: img.arial24,
      x: textX,
      y: y,
      color: img.ColorRgb8(255, 255, 255),
    );
    y += 40;
  }

  img.drawString(
    canvas,
    'Alamat :',
    font: img.arial24,
    x: textX,
    y: y,
    color: img.ColorRgb8(255, 210, 0),
  );
  y += 35;

  final addr = address ?? 'Tidak tersedia';
  final words = addr.split(' ');
  String line = '';

  for (final word in words) {
    final test = '$line $word';
    if (test.length > 42) {
      img.drawString(
        canvas,
        line.trim(),
        font: img.arial24,
        x: textX,
        y: y,
        color: img.ColorRgb8(255, 255, 255),
      );
      y += 30;
      line = word;
    } else {
      line = test;
    }
  }

  if (line.isNotEmpty) {
    img.drawString(
      canvas,
      line.trim(),
      font: img.arial24,
      x: textX,
      y: y,
      color: img.ColorRgb8(255, 255, 255),
    );
  }

  // SIGNATURE
  if (signaturePath != null && File(signaturePath).existsSync()) {
    final sigBytes = await File(signaturePath).readAsBytes();
    final sig = img.decodeImage(sigBytes);

    if (sig != null) {
      final resizedSig = img.copyResize(sig, width: 220);
      final signatureX = original.width - 260;
      final signatureY = original.height + 250;

      img.fillRect(
        canvas,
        x1: signatureX - 10,
        y1: signatureY - 10,
        x2: signatureX + 230,
        y2: signatureY + 120,
        color: img.ColorRgb8(255, 255, 255),
      );

      img.compositeImage(canvas, resizedSig, dstX: signatureX, dstY: signatureY);
    }
  }

  final dir = await getApplicationDocumentsDirectory();
  final output = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
  await File(output).writeAsBytes(img.encodeJpg(canvas, quality: 92));
  return output;
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
  int _selectedTab = 0; // 0 = capture, 1 = gallery

  final SignatureController signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
  );

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
    final list = deliveries.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList('history', list);
  }

  Future<void> pickLogo() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_logo', file.path);
    setState(() => customLogoPath = file.path);
  }

  // =======================
  // SIGNATURE — BORDER VISIBLE
  // =======================

  Future<void> openSignature() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1A1A2E),
            foregroundColor: Colors.white,
            elevation: 0,
            title: const Text(
              'Tanda Tangan',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tanda tangan di area bawah:',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 12),

                // ✅ KOTAK TANDA TANGAN — BORDER JELAS TERLIHAT
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
                        color: const Color(0xFFFF8C00).withOpacity(0.3),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: SizedBox(
                      height: 300,
                      child: Signature(
                        controller: signatureController,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),

                // Label
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF8C00),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Area tanda tangan (latar putih)',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => signatureController.clear(),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('ULANGI'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final bytes = await signatureController.toPngBytes();
                          if (bytes == null) return;
                          final dir = await getApplicationDocumentsDirectory();
                          final file = File('${dir.path}/signature.png');
                          await file.writeAsBytes(bytes);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('signature', file.path);
                          setState(() => signaturePath = file.path);
                          if (mounted) Navigator.pop(context);
                        },
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('SIMPAN'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF8C00),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =======================
  // CAPTURE
  // =======================

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
            address = '${p.street}, ${p.locality}';
          }
          weather = await WeatherHelper.fetch(lat, lng);
        }
      } catch (_) {}

      final timestamp = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());
      final deliveryId = 'TRM-${DateTime.now().millisecondsSinceEpoch}';

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
        signaturePath: signaturePath,
      );

      final record = DeliveryRecord(
        deliveryId: deliveryId,
        imagePath: finalPath,
        timestamp: timestamp,
      );

      deliveries.insert(0, record);
      await saveHistory();

      setState(() {
        loading = false;
        _selectedTab = 1; // Auto-switch ke gallery setelah foto
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
  // UI
  // =======================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      body: SafeArea(
        child: Column(
          children: [
            // ===== HEADER =====
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF8C00), Color(0xFFFF4500)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.local_shipping_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
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
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            'Halo, ${widget.name}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Stats badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF8C00).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFFFF8C00).withOpacity(0.4),
                          ),
                        ),
                        child: Text(
                          '${deliveries.length} Kiriman',
                          style: const TextStyle(
                            color: Color(0xFFFF8C00),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Tab Bar
                  Row(
                    children: [
                      _buildTab('Ambil Foto', Icons.camera_alt_rounded, 0),
                      const SizedBox(width: 8),
                      _buildTab('Galeri', Icons.photo_library_rounded, 1),
                    ],
                  ),
                ],
              ),
            ),

            // ===== CONTENT =====
            Expanded(
              child: _selectedTab == 0
                  ? _buildCaptureTab()
                  : _buildGalleryTab(),
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFFF8C00) : Colors.transparent,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isActive ? Colors.white : Colors.white38),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white38,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                fontSize: 14,
              ),
            ),
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
          const Text(
            'Pengaturan',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8892A4),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),

          // Settings Cards
          _buildSettingCard(
            icon: Icons.image_rounded,
            iconColor: const Color(0xFF3498DB),
            title: 'Logo Perusahaan',
            subtitle: customLogoPath != null
                ? 'Logo sudah diatur'
                : 'Belum ada logo',
            hasImage: customLogoPath != null,
            imagePath: customLogoPath,
            onTap: pickLogo,
            actionLabel: 'GANTI',
          ),

          const SizedBox(height: 12),

          _buildSettingCard(
            icon: Icons.draw_rounded,
            iconColor: const Color(0xFF9B59B6),
            title: 'Tanda Tangan',
            subtitle: signaturePath != null
                ? 'Tanda tangan sudah diatur'
                : 'Belum ada tanda tangan',
            hasImage: signaturePath != null,
            imagePath: signaturePath,
            onTap: openSignature,
            actionLabel: 'UBAH',
          ),

          const SizedBox(height: 32),

          // Capture Button
          GestureDetector(
            onTap: loading ? null : captureDelivery,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 140,
              decoration: BoxDecoration(
                gradient: loading
                    ? const LinearGradient(
                        colors: [Color(0xFF555), Color(0xFF444)],
                      )
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
                          color: const Color(0xFFFF8C00).withOpacity(0.4),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
              ),
              child: Center(
                child: loading
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'MEMPROSES...',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.white,
                            size: 42,
                          ),
                          SizedBox(height: 10),
                          Text(
                            'AMBIL FOTO BUKTI',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              letterSpacing: 1.5,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'GPS + Cuaca + Tanda tangan',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Quick info chips
          Row(
            children: [
              _infoChip(Icons.location_on_rounded, 'GPS Otomatis'),
              const SizedBox(width: 8),
              _infoChip(Icons.cloud_rounded, 'Cuaca Real-time'),
              const SizedBox(width: 8),
              _infoChip(Icons.draw_rounded, 'TTD Digital'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool hasImage,
    required String? imagePath,
    required VoidCallback onTap,
    required String actionLabel,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: hasImage && imagePath != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.cover,
                  ),
                )
              : Icon(icon, color: iconColor, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: hasImage ? const Color(0xFF2ECC71) : const Color(0xFF8892A4),
            fontSize: 12,
          ),
        ),
        trailing: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFFF8C00),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFFF8C00)),
            ),
          ),
          child: Text(
            actionLabel,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: const Color(0xFFFF8C00)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF555),
            ),
          ),
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
              child: const Icon(
                Icons.photo_library_outlined,
                size: 36,
                color: Color(0xFFFF8C00),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Belum ada foto',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2C3E50),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ambil foto bukti pengiriman\npada tab Ambil Foto',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF8892A4),
                fontSize: 14,
              ),
            ),
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
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: exists
                    ? GestureDetector(
                        onTap: () => _openImageFullscreen(d.imagePath),
                        child: Stack(
                          children: [
                            Image.file(
                              File(d.imagePath),
                              width: double.infinity,
                              height: 200,
                              fit: BoxFit.cover,
                            ),
                            // View overlay
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.zoom_in_rounded,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Lihat',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Index badge
                            Positioned(
                              top: 10,
                              left: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFF8C00), Color(0xFFFF4500)],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '#${deliveries.length - index}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        height: 120,
                        color: const Color(0xFFF0F0F0),
                        child: const Center(
                          child: Icon(
                            Icons.broken_image_rounded,
                            color: Color(0xFFCCC),
                            size: 40,
                          ),
                        ),
                      ),
              ),

              // Info
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF8C00).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            d.deliveryId,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: Color(0xFFFF8C00),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time_rounded,
                          size: 14,
                          color: Color(0xFF8892A4),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          d.timestamp,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF8892A4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: _actionButton(
                            icon: Icons.save_alt_rounded,
                            label: 'Simpan',
                            color: const Color(0xFF3498DB),
                            onTap: exists ? () => saveImage(d.imagePath) : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _actionButton(
                            icon: Icons.share_rounded,
                            label: 'Bagikan',
                            color: const Color(0xFF2ECC71),
                            onTap: exists ? () => shareImage(d.imagePath) : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _actionButton(
                            icon: Icons.open_in_full_rounded,
                            label: 'Lihat',
                            color: const Color(0xFF9B59B6),
                            onTap: exists
                                ? () => _openImageFullscreen(d.imagePath)
                                : null,
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

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: onTap != null ? color.withOpacity(0.1) : Colors.grey.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: onTap != null ? color.withOpacity(0.3) : Colors.grey.withOpacity(0.2),
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: onTap != null ? color : Colors.grey,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: onTap != null ? color : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =======================
  // FULLSCREEN IMAGE VIEWER
  // =======================

  void _openImageFullscreen(String path) {
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
                tooltip: 'Simpan',
              ),
              IconButton(
                icon: const Icon(Icons.share_rounded),
                onPressed: () => shareImage(path),
                tooltip: 'Bagikan',
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.file(File(path)),
            ),
          ),
        ),
      ),
    );
  }
}
