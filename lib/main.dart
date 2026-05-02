// ════════════════════════════════════════════════════════════════════════════
//  TermulLog — main.dart  (complete rewrite)
//
//  NEW pubspec.yaml dependency required:
//    camera: ^0.10.5+9
//
//  Android: add to AndroidManifest.xml inside <manifest>:
//    <uses-permission android:name="android.permission.CAMERA"/>
//    <uses-feature android:name="android.hardware.camera" android:required="false"/>
//
//  iOS: add to Info.plist:
//    NSCameraUsageDescription → "Diperlukan untuk mengambil foto laporan"
// ════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';

// ─── Global cameras list ─────────────────────────────────────────────────────
List<CameraDescription> _cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _cameras = await availableCameras();
  } catch (_) {}
  await WatermarkLayout.load();
  runApp(const App());
}

// ════════════════════════════════════════════════════════════════════════════
//  CONSTANTS
// ════════════════════════════════════════════════════════════════════════════

const int kMaxOutputWidth = 1280;
const int kJpegQuality    = 85;
const int kSigMaxWidth    = 500;

// ════════════════════════════════════════════════════════════════════════════
//  LAYOUT REGISTRY
// ════════════════════════════════════════════════════════════════════════════

class LayoutInfo {
  final String   id;
  final String   label;
  final String   description;
  final IconData icon;
  final Color    accentColor;
  const LayoutInfo({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.accentColor,
  });
}

const List<LayoutInfo> kLayouts = [
  LayoutInfo(
    id: 'layout1', label: 'Professional Report',
    description: 'Strip navy di bawah foto, kotak info abu-abu, tanda tangan kiri.',
    icon: Icons.article_outlined, accentColor: Color(0xFF1B4F72),
  ),
  LayoutInfo(
    id: 'layout2', label: 'Compact Field',
    description: 'Strip hijau, info ringkas, cocok untuk laporan cepat di lapangan.',
    icon: Icons.assignment_turned_in_outlined, accentColor: Color(0xFF27AE60),
  ),
  LayoutInfo(
    id: 'layout3', label: 'Dark Minimal',
    description: 'Latar gelap elegan, teks putih, garis aksen emas. Kesan premium.',
    icon: Icons.dark_mode_outlined, accentColor: Color(0xFF212121),
  ),
  LayoutInfo(
    id: 'layout4', label: 'Split Side-by-Side',
    description: 'Panel kiri: foto. Panel kanan: info & tanda tangan dua kolom ungu.',
    icon: Icons.view_column_outlined, accentColor: Color(0xFF6C3483),
  ),
];

// ════════════════════════════════════════════════════════════════════════════
//  WATERMARK ENGINE (ISOLATE)
// ════════════════════════════════════════════════════════════════════════════

Uint8List _processWatermark(Map<String, dynamic> p) {
  img.Image base = img.decodeImage(p['imageBytes'] as Uint8List)!;
  if (base.width > kMaxOutputWidth) {
    base = img.copyResize(base,
        width: kMaxOutputWidth, interpolation: img.Interpolation.linear);
  }

  final sigBytes = p['sigBytes'] as Uint8List?;
  img.Image? sig;
  if (sigBytes != null && sigBytes.isNotEmpty) {
    sig = img.decodeImage(sigBytes);
    if (sig != null && sig.width > kSigMaxWidth) {
      sig = img.copyResize(sig,
          width: kSigMaxWidth, interpolation: img.Interpolation.linear);
    }
  }

  final logoBytes = p['logoBytes'] as Uint8List?;
  final logo = logoBytes != null ? img.decodeImage(logoBytes) : null;

  final layout = p['layout'] as String? ?? 'layout1';
  final name   = p['name']   as String;
  final id     = p['id']     as String;
  final date   = p['date']   as String;
  final time   = p['time']   as String;

  switch (layout) {
    case 'layout2': return _layout2(base, sig, logo, name, id, date, time);
    case 'layout3': return _layout3(base, sig, logo, name, id, date, time);
    case 'layout4': return _layout4(base, sig, logo, name, id, date, time);
    default:        return _layout1(base, sig, logo, name, id, date, time);
  }
}

// ── Layout 1 — Professional Report (Navy) ────────────────────────────────────
Uint8List _layout1(img.Image base, img.Image? sig, img.Image? logo,
    String name, String id, String date, String time) {
  final W = base.width; final H = base.height;
  final S = (W * 0.22).clamp(280.0, 800.0).toInt();
  final canvas = img.Image(width: W, height: H + S);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(canvas, base, dstX: 0, dstY: 0);
  final navy = img.ColorRgb8(27, 79, 114);
  final white = img.ColorRgb8(255, 255, 255);
  final gray = img.ColorRgb8(240, 240, 240);
  img.fillRect(canvas, x1: 0, y1: H, x2: W, y2: H + 90, color: navy);
  img.drawString(canvas, 'DELIVERY REPORT', font: img.arial48, x: 20, y: H + 25, color: white);
  img.drawString(canvas, '$date  $time', font: img.arial24, x: W - 280, y: H + 30, color: white);
  final iY = H + 100;
  img.fillRect(canvas, x1: 0, y1: iY, x2: W, y2: iY + 140, color: gray);
  img.drawString(canvas, 'TEKNISI: $name', font: img.arial24, x: 20, y: iY + 20);
  img.drawString(canvas, 'ID: $id', font: img.arial24, x: 20, y: iY + 60);
  img.drawString(canvas, 'WAKTU: $date $time', font: img.arial24, x: 20, y: iY + 100);
  if (sig != null)  img.compositeImage(canvas, sig, dstX: 20, dstY: iY + 160);
  if (logo != null) {
    final l = img.copyResize(logo, width: 80, interpolation: img.Interpolation.linear);
    img.compositeImage(canvas, l, dstX: W - 100, dstY: iY + 20);
  }
  return img.encodeJpg(canvas, quality: kJpegQuality);
}

// ── Layout 2 — Compact Field (Green) ─────────────────────────────────────────
Uint8List _layout2(img.Image base, img.Image? sig, img.Image? logo,
    String name, String id, String date, String time) {
  final W = base.width; final H = base.height;
  final S = (W * 0.20).clamp(250.0, 700.0).toInt();
  final canvas = img.Image(width: W, height: H + S);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(canvas, base, dstX: 0, dstY: 0);
  final green = img.ColorRgb8(39, 174, 96);
  img.fillRect(canvas, x1: 0, y1: H, x2: W, y2: H + 70, color: green);
  img.drawString(canvas, 'PEKERJAAN SELESAI', font: img.arial48, x: 20, y: H + 15);
  final iY = H + 90;
  img.drawString(canvas, 'Teknisi: $name', font: img.arial24, x: 20, y: iY);
  img.drawString(canvas, 'ID: $id', font: img.arial24, x: 20, y: iY + 50);
  img.drawString(canvas, 'Waktu: $date $time', font: img.arial24, x: 20, y: iY + 100);
  if (sig != null)  img.compositeImage(canvas, sig, dstX: 20, dstY: iY + 150);
  if (logo != null) {
    final l = img.copyResize(logo, width: 70, interpolation: img.Interpolation.linear);
    img.compositeImage(canvas, l, dstX: W - 90, dstY: iY + 10);
  }
  return img.encodeJpg(canvas, quality: kJpegQuality);
}

// ── Layout 3 — Dark Minimal (Charcoal + Gold) ─────────────────────────────────
Uint8List _layout3(img.Image base, img.Image? sig, img.Image? logo,
    String name, String id, String date, String time) {
  final W = base.width; final H = base.height;
  final S = (W * 0.24).clamp(300.0, 850.0).toInt();
  final canvas = img.Image(width: W, height: H + S);
  img.fill(canvas, color: img.ColorRgb8(33, 33, 33));
  img.compositeImage(canvas, base, dstX: 0, dstY: 0);
  img.fillRect(canvas, x1: 0, y1: H, x2: W, y2: H + S, color: img.ColorRgb8(33, 33, 33));
  img.fillRect(canvas, x1: 0, y1: H, x2: W, y2: H + 4, color: img.ColorRgb8(212, 175, 55));
  img.fillRect(canvas, x1: 0, y1: H + 4, x2: 6, y2: H + S, color: img.ColorRgb8(212, 175, 55));
  final white = img.ColorRgb8(255, 255, 255);
  final gold  = img.ColorRgb8(212, 175, 55);
  const pX = 26;
  img.drawString(canvas, 'LAPORAN TEKNIS', font: img.arial48, x: pX, y: H + 18, color: gold);
  img.drawString(canvas, name, font: img.arial24, x: pX, y: H + 80, color: white);
  img.drawString(canvas, 'ID: $id', font: img.arial24, x: pX, y: H + 115, color: white);
  img.drawString(canvas, '$date  $time', font: img.arial24, x: pX, y: H + 150, color: white);
  if (sig != null) {
    img.fillRect(canvas,
        x1: pX - 4, y1: H + 188,
        x2: pX + sig.width + 4, y2: H + 188 + sig.height + 10,
        color: img.ColorRgba8(255, 255, 255, 25));
    img.compositeImage(canvas, sig, dstX: pX, dstY: H + 192);
  }
  if (logo != null) {
    final l = img.copyResize(logo, width: 70, interpolation: img.Interpolation.linear);
    img.compositeImage(canvas, l, dstX: W - 90, dstY: H + 18);
  }
  return img.encodeJpg(canvas, quality: kJpegQuality);
}

// ── Layout 4 — Split Side-by-Side (Purple) ───────────────────────────────────
Uint8List _layout4(img.Image base, img.Image? sig, img.Image? logo,
    String name, String id, String date, String time) {
  final fW = base.width; final fH = base.height;
  final pW = (fW * 0.38).clamp(320.0, 700.0).toInt();
  final W = fW + pW; final H = fH;
  final canvas = img.Image(width: W, height: H);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(canvas, base, dstX: 0, dstY: 0);
  for (int y = 0; y < H; y++) {
    final t = y / H;
    final r = (72  + (108 - 72)  * t).round();
    final g = (26  + (52  - 26)  * t).round();
    final b = (107 + (131 - 107) * t).round();
    img.fillRect(canvas, x1: fW, y1: y, x2: W, y2: y + 1, color: img.ColorRgb8(r, g, b));
  }
  img.fillRect(canvas, x1: fW, y1: 0, x2: fW + 5, y2: H, color: img.ColorRgb8(212, 175, 55));
  final white = img.ColorRgb8(255, 255, 255);
  final gold  = img.ColorRgb8(212, 175, 55);
  final tX = fW + 5 + 18;
  img.drawString(canvas, 'TEKNISI', font: img.arial24, x: tX, y: 30, color: gold);
  img.drawString(canvas, name, font: img.arial48, x: tX, y: 58, color: white);
  img.fillRect(canvas, x1: tX, y1: 118, x2: W - 18, y2: 121, color: img.ColorRgb8(212, 175, 55));
  img.drawString(canvas, 'NO. TIKET', font: img.arial24, x: tX, y: 132, color: gold);
  img.drawString(canvas, id, font: img.arial24, x: tX, y: 160, color: white);
  img.drawString(canvas, 'TANGGAL', font: img.arial24, x: tX, y: 203, color: gold);
  img.drawString(canvas, date, font: img.arial24, x: tX, y: 231, color: white);
  img.drawString(canvas, 'JAM', font: img.arial24, x: tX, y: 274, color: gold);
  img.drawString(canvas, time, font: img.arial24, x: tX, y: 302, color: white);
  img.fillRect(canvas, x1: tX, y1: 345, x2: W - 18, y2: 348, color: img.ColorRgb8(212, 175, 55));
  img.drawString(canvas, 'TANDA TANGAN', font: img.arial24, x: tX, y: 358, color: gold);
  if (sig != null) {
    final maxSigW = pW - 36 - 5;
    img.Image s = sig;
    if (s.width > maxSigW) s = img.copyResize(s, width: maxSigW, interpolation: img.Interpolation.linear);
    img.compositeImage(canvas, s, dstX: tX, dstY: 392);
  }
  if (logo != null) {
    final l = img.copyResize(logo, width: 58, interpolation: img.Interpolation.linear);
    img.compositeImage(canvas, l, dstX: W - 58 - 18, dstY: H - 58 - 18);
  }
  return img.encodeJpg(canvas, quality: kJpegQuality);
}

// ════════════════════════════════════════════════════════════════════════════
//  APP
// ════════════════════════════════════════════════════════════════════════════

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B4F72)),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const Login(),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  LOGIN
// ════════════════════════════════════════════════════════════════════════════

class Login extends StatelessWidget {
  const Login({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TextEditingController();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D2137), Color(0xFF1B4F72), Color(0xFF2980B9)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white24, width: 1),
                    ),
                    child: const Icon(Icons.photo_camera_rounded,
                        color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 24),
                  const Text('TermulLog',
                      style: TextStyle(
                          fontSize: 32, fontWeight: FontWeight.w800,
                          color: Colors.white, letterSpacing: -0.5)),
                  const SizedBox(height: 6),
                  Text('Laporan Lapangan Digital',
                      style: TextStyle(
                          fontSize: 14, color: Colors.white.withOpacity(0.7),
                          letterSpacing: 0.5)),
                  const SizedBox(height: 48),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: TextField(
                      controller: c,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Nama Teknisi',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                        prefixIcon: Icon(Icons.person_outline,
                            color: Colors.white.withOpacity(0.6)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1B4F72),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      onPressed: () {
                        if (c.text.trim().isEmpty) return;
                        Navigator.pushReplacement(context, MaterialPageRoute(
                            builder: (_) => Dashboard(name: c.text.trim())));
                      },
                      child: const Text('Masuk',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ITEM MODEL
// ════════════════════════════════════════════════════════════════════════════

class Item {
  final String id;
  final String path;
  final String time;
  Item(this.id, this.path, this.time);
}

// ════════════════════════════════════════════════════════════════════════════
//  WATERMARK SETTING
// ════════════════════════════════════════════════════════════════════════════

class WatermarkLayout {
  static String _layout = 'layout1';
  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _layout = p.getString('layout') ?? 'layout1';
  }
  static Future<void> set(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('layout', v);
    _layout = v;
  }
  static String get() => _layout;
}

// ════════════════════════════════════════════════════════════════════════════
//  LOGO CACHE
// ════════════════════════════════════════════════════════════════════════════

class LogoCache {
  static Uint8List? _bytes;
  static String?    _path;
  static Future<void> load(String path) async {
    if (_path == path) return;
    _bytes = await File(path).readAsBytes();
    _path  = path;
  }
  static Uint8List? get bytes => _bytes;
  static void clear() { _bytes = null; _path = null; }
}

// ════════════════════════════════════════════════════════════════════════════
//  DASHBOARD
// ════════════════════════════════════════════════════════════════════════════

class Dashboard extends StatefulWidget {
  final String name;
  const Dashboard({super.key, required this.name});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  List<Item> list = [];
  String? _logoPath;

  // ── Open camera page ──────────────────────────────────────────────────────
  Future<void> _openCamera() async {
    if (_cameras.isEmpty) {
      await _captureFallback();
      return;
    }
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CameraPage(
        onCapture: (paths) {
          if (paths.isEmpty) return;
          if (paths.length == 1) {
            _goToSignature(paths.first);
          } else {
            // Burst: show selection page
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => BurstSelectionPage(
                paths: paths,
                onSelect: _goToSignature,
              ),
            ));
          }
        },
      ),
    ));
  }

  Future<void> _captureFallback() async {
    final file = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: kMaxOutputWidth.toDouble(),
        imageQuality: 90);
    if (file == null || !mounted) return;
    _goToSignature(file.path);
  }

  void _goToSignature(String imagePath) {
    final now  = DateTime.now();
    final id   = 'TRM-${now.millisecondsSinceEpoch}';
    final time = DateFormat('dd/MM HH:mm').format(now);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SignaturePage(
        imagePath: imagePath,
        techName:  widget.name,
        itemId:    id,
        itemTime:  time,
        onDone: (path) => setState(() => list.add(Item(id, path, time))),
      ),
    ));
  }

  Future<void> _pickLogo() async {
    final file = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 200);
    if (file == null) return;
    setState(() => _logoPath = file.path);
    await LogoCache.load(file.path);
  }

  // ── Share a single item ───────────────────────────────────────────────────
  Future<void> _shareItem(Item item) async {
    try {
      await Share.shareXFiles([XFile(item.path)],
          subject: 'Laporan ${item.id}',
          text: 'Laporan teknisi — ${item.id} — ${item.time}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal share: $e')));
      }
    }
  }

  // ── Save to gallery ───────────────────────────────────────────────────────
  Future<void> _saveToGallery(Item item) async {
    try {
      final ok = await GallerySaver.saveImage(item.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok == true ? 'Tersimpan ke galeri ✓' : 'Gagal menyimpan'),
          backgroundColor: ok == true ? Colors.green.shade700 : Colors.red.shade700,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ── Preview full screen ───────────────────────────────────────────────────
  void _previewItem(Item item) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => PreviewPage(
        item: item,
        onShare: () => _shareItem(item),
        onSave: () => _saveToGallery(item),
      ),
    ));
  }

  // ── Delete item ──────────────────────────────────────────────────────────
  void _deleteItem(Item item) {
    setState(() => list.removeWhere((e) => e.id == item.id));
    try { File(item.path).deleteSync(); } catch (_) {}
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Laporan dihapus')));
  }

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('dd/MM').format(DateTime.now());
    final todayCount = list.where((e) => e.time.startsWith(today)).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: Column(children: [
        // ── Header gradient ──────────────────────────────────────────────────
        _DashboardHeader(
          name: widget.name,
          total: list.length,
          todayCount: todayCount,
          logoPath: _logoPath,
          onPickLogo: _pickLogo,
          onClearLogo: () {
            setState(() => _logoPath = null);
            LogoCache.clear();
          },
          onSettings: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsPage())),
        ),

        // ── List or empty state ──────────────────────────────────────────────
        Expanded(
          child: list.isEmpty
              ? _EmptyState(onCapture: _openCamera)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final item = list[list.length - 1 - i]; // newest first
                    return _ItemCard(
                      item: item,
                      onTap:    () => _previewItem(item),
                      onShare:  () => _shareItem(item),
                      onSave:   () => _saveToGallery(item),
                      onDelete: () => _deleteItem(item),
                    );
                  },
                ),
        ),
      ]),

      // ── FAB ────────────────────────────────────────────────────────────
      floatingActionButton: _CameraFAB(onTap: _openCamera),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

// ── Dashboard Header ─────────────────────────────────────────────────────────
class _DashboardHeader extends StatelessWidget {
  final String  name;
  final int     total;
  final int     todayCount;
  final String? logoPath;
  final VoidCallback onPickLogo;
  final VoidCallback onClearLogo;
  final VoidCallback onSettings;

  const _DashboardHeader({
    required this.name,
    required this.total,
    required this.todayCount,
    required this.logoPath,
    required this.onPickLogo,
    required this.onClearLogo,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D2137), Color(0xFF1B4F72)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Top row
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Selamat datang,',
                      style: TextStyle(
                          fontSize: 12.5, color: Colors.white.withOpacity(0.65),
                          letterSpacing: 0.3)),
                  const SizedBox(height: 2),
                  Text(name,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700,
                          color: Colors.white),
                      overflow: TextOverflow.ellipsis),
                ]),
              ),
              // Logo & Settings
              if (logoPath != null)
                GestureDetector(
                  onTap: onClearLogo,
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Image.file(File(logoPath!), height: 30),
                      const SizedBox(width: 4),
                      const Icon(Icons.close, size: 14, color: Colors.white70),
                    ]),
                  ),
                ),
              _HeaderIconBtn(icon: Icons.image_outlined,    onTap: onPickLogo),
              _HeaderIconBtn(icon: Icons.tune_rounded,      onTap: onSettings),
            ]),
            const SizedBox(height: 18),
            // Stats row
            Row(children: [
              _StatChip(label: 'Semua',  value: '$total',      icon: Icons.photo_library_outlined),
              const SizedBox(width: 10),
              _StatChip(label: 'Hari ini', value: '$todayCount', icon: Icons.today_outlined),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _HeaderIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIconBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon, color: Colors.white.withOpacity(0.85), size: 22),
    onPressed: onTap,
  );
}

class _StatChip extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _StatChip({required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: Colors.white70, size: 16),
      const SizedBox(width: 7),
      Text('$value $label',
          style: const TextStyle(
              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
    ]),
  );
}

// ── Empty state ───────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onCapture;
  const _EmptyState({required this.onCapture});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 100, height: 100,
        decoration: BoxDecoration(
            color: const Color(0xFF1B4F72).withOpacity(0.08),
            shape: BoxShape.circle),
        child: const Icon(Icons.add_a_photo_outlined,
            size: 44, color: Color(0xFF1B4F72)),
      ),
      const SizedBox(height: 20),
      const Text('Belum ada laporan',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
              color: Color(0xFF1B4F72))),
      const SizedBox(height: 6),
      Text('Ketuk tombol kamera untuk mulai',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
      const SizedBox(height: 28),
      OutlinedButton.icon(
        onPressed: onCapture,
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('Ambil Foto'),
        style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF1B4F72),
            side: const BorderSide(color: Color(0xFF1B4F72)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14))),
      ),
    ]),
  );
}

// ── Item Card ────────────────────────────────────────────────────────────
class _ItemCard extends StatelessWidget {
  final Item         item;
  final VoidCallback onTap;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback onDelete;

  const _ItemCard({
    required this.item,
    required this.onTap,
    required this.onShare,
    required this.onSave,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: Colors.red.shade400,
            borderRadius: BorderRadius.circular(16)),
        child: const Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.delete_outline_rounded, color: Colors.white, size: 26),
          SizedBox(height: 4),
          Text('Hapus', style: TextStyle(color: Colors.white, fontSize: 11)),
        ]),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Hapus Laporan?'),
            content: Text('${item.id} akan dihapus permanen.'),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false),
                  child: const Text('Batal')),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Hapus',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06),
                blurRadius: 12, offset: const Offset(0, 3)),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              // ── Thumbnail ──
              Hero(
                tag: 'thumb_${item.id}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(File(item.path),
                      width: 72, height: 72, fit: BoxFit.cover,
                      cacheWidth: 144),
                ),
              ),
              const SizedBox(width: 14),

              // ── Info ──
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: const Color(0xFF1B4F72).withOpacity(0.09),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(item.id,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700,
                              color: Color(0xFF1B4F72)),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.access_time_rounded,
                        size: 13, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(item.time,
                        style: const TextStyle(
                            fontSize: 12.5, color: Colors.grey)),
                  ]),
                  const SizedBox(height: 10),
                  // Action buttons
                  Row(children: [
                    _ActionBtn(icon: Icons.visibility_outlined,
                        label: 'Preview', color: const Color(0xFF1B4F72),
                        onTap: onTap),
                    const SizedBox(width: 8),
                    _ActionBtn(icon: Icons.share_outlined,
                        label: 'Bagikan', color: Colors.teal.shade600,
                        onTap: onShare),
                    const SizedBox(width: 8),
                    _ActionBtn(icon: Icons.save_alt_rounded,
                        label: 'Simpan', color: Colors.orange.shade700,
                        onTap: onSave),
                  ]),
                ],
              )),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label,
    required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
          color: color.withOpacity(0.09),
          borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ]),
    ),
  );
}

// ── Camera FAB ───────────────────────────────────────────────────────────
class _CameraFAB extends StatelessWidget {
  final VoidCallback onTap;
  const _CameraFAB({required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF1B4F72), Color(0xFF2980B9)]),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(color: const Color(0xFF1B4F72).withOpacity(0.45),
              blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.camera_alt_rounded, color: Colors.white, size: 22),
        SizedBox(width: 10),
        Text('Ambil Foto',
            style: TextStyle(color: Colors.white,
                fontSize: 16, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  PREVIEW PAGE
// ════════════════════════════════════════════════════════════════════════════

class PreviewPage extends StatelessWidget {
  final Item         item;
  final VoidCallback onShare;
  final VoidCallback onSave;

  const PreviewPage({
    super.key,
    required this.item,
    required this.onShare,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(item.id,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: onShare,
            tooltip: 'Bagikan',
          ),
          IconButton(
            icon: const Icon(Icons.save_alt_rounded),
            onPressed: onSave,
            tooltip: 'Simpan ke galeri',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(children: [
        // Full-screen zoomable image
        Center(
          child: Hero(
            tag: 'thumb_${item.id}',
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 6.0,
              child: Image.file(File(item.path), fit: BoxFit.contain),
            ),
          ),
        ),
        // Bottom info strip
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.id, style: const TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(item.time, style: TextStyle(
                    color: Colors.white.withOpacity(0.8), fontSize: 13)),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  CAMERA PAGE (PLACEHOLDER)
// ════════════════════════════════════════════════════════════════════════════

class CameraPage extends StatelessWidget {
  final Function(List<String>) onCapture;
  const CameraPage({required this.onCapture});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Camera')),
      body: const Center(child: Text('Camera Page')),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  BURST SELECTION PAGE (PLACEHOLDER)
// ════════════════════════════════════════════════════════════════════════════

class BurstSelectionPage extends StatelessWidget {
  final List<String> paths;
  final Function(String) onSelect;
  const BurstSelectionPage({required this.paths, required this.onSelect});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Photo')),
      body: const Center(child: Text('Burst Selection Page')),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SIGNATURE PAGE (PLACEHOLDER)
// ════════════════════════════════════════════════════════════════════════════

class SignaturePage extends StatelessWidget {
  final String imagePath;
  final String techName;
  final String itemId;
  final String itemTime;
  final Function(String) onDone;

  const SignaturePage({
    required this.imagePath,
    required this.techName,
    required this.itemId,
    required this.itemTime,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Signature')),
      body: const Center(child: Text('Signature Page')),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SETTINGS PAGE (PLACEHOLDER)
// ════════════════════════════════════════════════════════════════════════════

class SettingsPage extends StatelessWidget {
  const SettingsPage();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(child: Text('Settings Page')),
    );
  }
}
