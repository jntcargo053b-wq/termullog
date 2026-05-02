// ══════════════════════════════════════════════════════════════════════════════
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
// ══════════════════════════════════════════════════════════════════════════════

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

// ══════════════════════════════════════════════════════════════════════════════
//  CONSTANTS
// ══════════════════════════════════════════════════════════════════════════════

const int kMaxOutputWidth = 1280;
const int kJpegQuality    = 85;
const int kSigMaxWidth    = 500;

// ══════════════════════════════════════════════════════════════════════════════
//  LAYOUT REGISTRY
// ══════════════════════════════════════════════════════════════════════════════

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

// ══════════════════════════════════════════════════════════════════════════════
//  WATERMARK ENGINE (ISOLATE)
// ══════════════════════════════════════════════════════════════════════════════

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

// ══════════════════════════════════════════════════════════════════════════════
//  APP
// ══════════════════════════════════════════════════════════════════════════════

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

// ══════════════════════════════════════════════════════════════════════════════
//  LOGIN
// ══════════════════════════════════════════════════════════════════════════════

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

// ══════════════════════════════════════════════════════════════════════════════
//  ITEM MODEL
// ══════════════════════════════════════════════════════════════════════════════

class Item {
  final String id;
  final String path;
  final String time;
  Item(this.id, this.path, this.time);
}

// ══════════════════════════════════════════════════════════════════════════════
//  WATERMARK SETTING
// ══════════════════════════════════════════════════════════════════════════════

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

// ══════════════════════════════════════════════════════════════════════════════
//  LOGO CACHE
// ══════════════════════════════════════════════════════════════════════════════

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

// ══════════════════════════════════════════════════════════════════════════════
//  DASHBOARD
// ══════════════════════════════════════════════════════════════════════════════

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

  // ── Delete item ───────────────────────────────────────────────────────────
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

      // ── FAB ─────────────────────────────────────────────────────────────────
      floatingActionButton: _CameraFAB(onTap: _openCamera),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

// ── Dashboard Header ──────────────────────────────────────────────────────────
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

// ── Empty state ───────────────────────────────────────────────────────────────
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

// ── Item Card ─────────────────────────────────────────────────────────────────
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

// ── Camera FAB ────────────────────────────────────────────────────────────────
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

// ══════════════════════════════════════════════════════════════════════════════
//  PREVIEW PAGE
// ══════════════════════════════════════════════════════════════════════════════

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
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.7), Colors.transparent],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: Row(children: [
              const Icon(Icons.access_time_rounded,
                  size: 14, color: Colors.white70),
              const SizedBox(width: 6),
              Text(item.time,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13)),
              const Spacer(),
              // Quick share
              GestureDetector(
                onTap: onShare,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.share_rounded,
                        color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text('Bagikan',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onSave,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.download_rounded,
                        color: Color(0xFF1B4F72), size: 16),
                    SizedBox(width: 6),
                    Text('Simpan',
                        style: TextStyle(
                            color: Color(0xFF1B4F72),
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  BURST SELECTION PAGE
// ══════════════════════════════════════════════════════════════════════════════

class BurstSelectionPage extends StatefulWidget {
  final List<String>     paths;
  final Function(String) onSelect;
  const BurstSelectionPage({super.key, required this.paths, required this.onSelect});
  @override
  State<BurstSelectionPage> createState() => _BurstSelectionPageState();
}

class _BurstSelectionPageState extends State<BurstSelectionPage> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Pilih dari ${widget.paths.length} Foto Burst',
            style: const TextStyle(fontSize: 15)),
      ),
      body: Column(children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
            itemCount: widget.paths.length,
            itemBuilder: (_, i) {
              final selected = _selected == i;
              return GestureDetector(
                onTap: () => setState(() => _selected = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: selected ? Colors.amber : Colors.transparent,
                        width: 3),
                  ),
                  child: Stack(fit: StackFit.expand, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(widget.paths[i]),
                          fit: BoxFit.cover),
                    ),
                    // Frame number
                    Positioned(
                      top: 6, left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(6)),
                        child: Text('#${i + 1}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    // Selection checkmark
                    if (selected)
                      Container(
                        decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Center(
                          child: Icon(Icons.check_circle_rounded,
                              color: Colors.amber, size: 36),
                        ),
                      ),
                  ]),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _selected == null ? null : () {
                  widget.onSelect(widget.paths[_selected!]);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  disabledBackgroundColor: Colors.grey.shade800,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  _selected == null ? 'Pilih satu foto' : 'Lanjutkan →',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _selected == null
                          ? Colors.grey.shade500
                          : Colors.black),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  CAMERA PAGE — Advanced Camera Controls
//    ✦ Pinch to zoom  ✦ Flash control (off/auto/on/torch)
//    ✦ Grid overlay   ✦ Burst capture (hold shutter)
//    ✦ Tap to focus with animated indicator
// ══════════════════════════════════════════════════════════════════════════════

class CameraPage extends StatefulWidget {
  final Function(List<String>) onCapture;
  const CameraPage({super.key, required this.onCapture});
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _ctrl;
  bool   _ready      = false;
  String _error      = '';

  // Zoom
  double _minZoom    = 1.0;
  double _maxZoom    = 8.0;
  double _curZoom    = 1.0;
  double _baseZoom   = 1.0;

  // Flash
  FlashMode _flash   = FlashMode.off;

  // Grid
  bool _showGrid     = false;

  // Burst
  bool   _burstActive = false;
  Timer? _burstTimer;
  final  List<String> _burstPaths = [];

  // Tap-to-focus
  Offset? _focusPos;
  bool    _showFocus = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _burstTimer?.cancel();
    _ctrl?.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_ctrl == null || !_ctrl!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _ctrl!.dispose();
      if (mounted) setState(() => _ready = false);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    if (_cameras.isEmpty) {
      setState(() => _error = 'Kamera tidak tersedia di perangkat ini.');
      return;
    }
    final desc = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first);
    final ctrl = CameraController(desc, ResolutionPreset.high,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    try {
      await ctrl.initialize();
      _minZoom = await ctrl.getMinZoomLevel();
      _maxZoom = await ctrl.getMaxZoomLevel();
      _ctrl = ctrl;
      if (mounted) setState(() => _ready = true);
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = 'Akses kamera ditolak: ${e.description}');
    }
  }

  // ── Flash ─────────────────────────────────────────────────────────────────
  Future<void> _cycleFlash() async {
    final modes = [FlashMode.off, FlashMode.auto, FlashMode.always, FlashMode.torch];
    final next  = modes[(modes.indexOf(_flash) + 1) % modes.length];
    try { await _ctrl?.setFlashMode(next); } catch (_) {}
    setState(() => _flash = next);
  }

  IconData get _flashIcon {
    switch (_flash) {
      case FlashMode.off:    return Icons.flash_off_rounded;
      case FlashMode.auto:   return Icons.flash_auto_rounded;
      case FlashMode.always: return Icons.flash_on_rounded;
      case FlashMode.torch:  return Icons.highlight_rounded;
    }
  }

  String get _flashLabel {
    switch (_flash) {
      case FlashMode.off:    return 'OFF';
      case FlashMode.auto:   return 'AUTO';
      case FlashMode.always: return 'ON';
      case FlashMode.torch:  return 'TORCH';
    }
  }

  Color get _flashColor {
    switch (_flash) {
      case FlashMode.off:    return Colors.white70;
      case FlashMode.auto:   return Colors.amber;
      case FlashMode.always: return Colors.amber;
      case FlashMode.torch:  return Colors.orange;
    }
  }

  // ── Tap-to-focus ─────────────────────────────────────────────────────────
  Future<void> _onTapFocus(TapDownDetails d, Size previewSize) async {
    if (_ctrl == null || !_ready) return;
    final x = (d.localPosition.dx / previewSize.width).clamp(0.0, 1.0);
    final y = (d.localPosition.dy / previewSize.height).clamp(0.0, 1.0);
    try {
      await _ctrl!.setFocusPoint(Offset(x, y));
      await _ctrl!.setExposurePoint(Offset(x, y));
    } catch (_) {}
    setState(() {
      _focusPos  = d.localPosition;
      _showFocus = true;
    });
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _showFocus = false);
    });
  }

  // ── Capture single ────────────────────────────────────────────────────────
  Future<String?> _takePicture() async {
    if (_ctrl == null || !_ready || _ctrl!.value.isTakingPicture) return null;
    try {
      final xf = await _ctrl!.takePicture();
      return xf.path;
    } on CameraException {
      return null;
    }
  }

  // ── Burst ─────────────────────────────────────────────────────────────────
  void _startBurst() {
    if (_ctrl == null || !_ready) return;
    _burstPaths.clear();
    setState(() => _burstActive = true);
    _burstTimer = Timer.periodic(const Duration(milliseconds: 350), (_) async {
      final p = await _takePicture();
      if (p != null && mounted) setState(() => _burstPaths.add(p));
    });
    HapticFeedback.mediumImpact();
  }

  void _stopBurst() {
    _burstTimer?.cancel();
    if (!mounted) return;
    setState(() => _burstActive = false);
    if (_burstPaths.isNotEmpty) {
      HapticFeedback.lightImpact();
      widget.onCapture(List.from(_burstPaths));
      Navigator.pop(context);
    }
  }

  // ── Single tap shutter ────────────────────────────────────────────────────
  Future<void> _captureAndGo() async {
    HapticFeedback.lightImpact();
    final p = await _takePicture();
    if (p != null && mounted) {
      widget.onCapture([p]);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _error.isNotEmpty
            ? _ErrorView(message: _error)
            : !_ready
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white))
                : _buildCameraUI(),
      ),
    );
  }

  Widget _buildCameraUI() {
    return LayoutBuilder(builder: (ctx, constraints) {
      final previewSize = Size(constraints.maxWidth, constraints.maxHeight);

      return Stack(children: [
        // ── Camera preview (pinch + tap to focus) ─────────────────────────
        GestureDetector(
          onScaleStart:  (_) => _baseZoom = _curZoom,
          onScaleUpdate: (d) async {
            final z = (_baseZoom * d.scale).clamp(_minZoom, _maxZoom);
            if ((z - _curZoom).abs() > 0.02) {
              setState(() => _curZoom = z);
              await _ctrl?.setZoomLevel(z);
            }
          },
          onTapDown: (d) => _onTapFocus(d, previewSize),
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width:  _ctrl!.value.previewSize!.height,
                height: _ctrl!.value.previewSize!.width,
                child:  CameraPreview(_ctrl!),
              ),
            ),
          ),
        ),

        // ── Grid overlay ──────────────────────────────────────────────────
        if (_showGrid)
          const IgnorePointer(child: _GridOverlay()),

        // ── Focus indicator ───────────────────────────────────────────────
        if (_showFocus && _focusPos != null)
          Positioned(
            left: _focusPos!.dx - 32,
            top:  _focusPos!.dy - 32,
            child: const _FocusRing(),
          ),

        // ── Top bar ───────────────────────────────────────────────────────
        Positioned(
          top: 0, left: 0, right: 0,
          child: _TopBar(
            flashIcon:  _flashIcon,
            flashLabel: _flashLabel,
            flashColor: _flashColor,
            showGrid:   _showGrid,
            onFlash:    _cycleFlash,
            onGrid:     () => setState(() => _showGrid = !_showGrid),
            onClose:    () => Navigator.pop(context),
          ),
        ),

        // ── Zoom slider (right side, vertical) ────────────────────────────
        Positioned(
          right: 14, top: 110, bottom: 130,
          child: _VerticalZoomSlider(
            min: _minZoom, max: _maxZoom, value: _curZoom,
            onChanged: (v) async {
              setState(() => _curZoom = v);
              await _ctrl?.setZoomLevel(v);
            },
          ),
        ),

        // ── Burst counter badge ────────────────────────────────────────────
        if (_burstActive)
          Positioned(
            top: 90, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.red.withOpacity(0.5),
                          blurRadius: 12)
                    ]),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const _PulseDot(),
                  const SizedBox(width: 8),
                  Text('BURST  ${_burstPaths.length} foto',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          letterSpacing: 0.5)),
                ]),
              ),
            ),
          ),

        // ── Bottom controls ────────────────────────────────────────────────
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: _BottomBar(
            zoomLabel: '${_curZoom.toStringAsFixed(1)}×',
            burstActive: _burstActive,
            onTap:       _captureAndGo,
            onBurstStart: _startBurst,
            onBurstStop:  _stopBurst,
          ),
        ),
      ]);
    });
  }
}

// ── Camera UI sub-widgets ─────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final IconData icon;
  final IconData flashIcon;
  final String   flashLabel;
  final Color    flashColor;
  final bool     showGrid;
  final VoidCallback onFlash, onGrid, onClose;

  const _TopBar({
    required this.flashIcon, required this.flashLabel, required this.flashColor,
    required this.showGrid,
    required this.onFlash, required this.onGrid, required this.onClose,
    IconData? icon,
  }) : icon = Icons.close;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0.65), Colors.transparent],
        ),
      ),
      child: Row(children: [
        _TopBtn(icon: Icons.close, onTap: onClose),
        const Spacer(),
        _TopBtn(icon: flashIcon, label: flashLabel,
            color: flashColor, onTap: onFlash),
        const SizedBox(width: 6),
        _TopBtn(
          icon: showGrid ? Icons.grid_on_rounded : Icons.grid_off_rounded,
          label: 'GRID',
          color: showGrid ? Colors.amber : Colors.white70,
          onTap: onGrid,
        ),
        const SizedBox(width: 6),
      ]),
    );
  }
}

class _TopBtn extends StatelessWidget {
  final IconData icon;
  final String?  label;
  final Color    color;
  final VoidCallback onTap;
  const _TopBtn({required this.icon, required this.onTap,
    this.label, this.color = Colors.white70});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(10)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 22),
        if (label != null) ...[
          const SizedBox(height: 2),
          Text(label!, style: TextStyle(
              color: color, fontSize: 9, fontWeight: FontWeight.w700)),
        ],
      ]),
    ),
  );
}

class _BottomBar extends StatelessWidget {
  final String     zoomLabel;
  final bool       burstActive;
  final VoidCallback onTap;
  final VoidCallback onBurstStart;
  final VoidCallback onBurstStop;
  const _BottomBar({
    required this.zoomLabel, required this.burstActive,
    required this.onTap, required this.onBurstStart, required this.onBurstStop,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter, end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.75), Colors.transparent],
        ),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        // Zoom label
        SizedBox(
          width: 52,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(8)),
              child: Text(zoomLabel,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ),
        const SizedBox(width: 28),

        // Shutter button
        GestureDetector(
          onTap:           burstActive ? null : onTap,
          onLongPressStart: (_) => onBurstStart(),
          onLongPressEnd:   (_) => onBurstStop(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width:  burstActive ? 78 : 72,
            height: burstActive ? 78 : 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: burstActive ? Colors.red : Colors.white,
              border: Border.all(
                  color: burstActive ? Colors.red.shade900 : Colors.grey.shade200,
                  width: 4.5),
              boxShadow: [
                BoxShadow(
                  color: (burstActive ? Colors.red : Colors.white)
                      .withOpacity(0.45),
                  blurRadius: 20,
                ),
              ],
            ),
            child: burstActive
                ? const Icon(Icons.stop_rounded, color: Colors.white, size: 30)
                : const SizedBox(),
          ),
        ),

        const SizedBox(width: 28),
        // Burst hint
        SizedBox(
          width: 52,
          child: Text(burstActive ? 'Lepas\nstop' : 'Tahan\nburst',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 10, height: 1.3)),
        ),
      ]),
    );
  }
}

// ── Vertical zoom slider ──────────────────────────────────────────────────────
class _VerticalZoomSlider extends StatelessWidget {
  final double min, max, value;
  final ValueChanged<double> onChanged;
  const _VerticalZoomSlider({
    required this.min, required this.max, required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: RotatedBox(
        quarterTurns: -1,
        child: SliderTheme(
          data: SliderThemeData(
            trackHeight: 2.5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            thumbColor: Colors.white,
            activeTrackColor:   Colors.white,
            inactiveTrackColor: Colors.white30,
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min, max: max,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

// ── Grid overlay ──────────────────────────────────────────────────────────────
class _GridOverlay extends StatelessWidget {
  const _GridOverlay();
  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: CustomPaint(painter: _GridPainter()),
  );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..strokeWidth = 0.75;
    final dotPaint = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    // Rule of thirds lines
    for (int i = 1; i < 3; i++) {
      final x = size.width  * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // Intersection dots
    for (int i = 1; i < 3; i++) {
      for (int j = 1; j < 3; j++) {
        canvas.drawCircle(
            Offset(size.width * i / 3, size.height * j / 3), 3, dotPaint);
      }
    }

    // Center crosshair
    final cPaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..strokeWidth = 1;
    final cx = size.width / 2, cy = size.height / 2;
    canvas.drawLine(Offset(cx - 12, cy), Offset(cx + 12, cy), cPaint);
    canvas.drawLine(Offset(cx, cy - 12), Offset(cx, cy + 12), cPaint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Tap-to-focus ring ─────────────────────────────────────────────────────────
class _FocusRing extends StatefulWidget {
  const _FocusRing();
  @override
  State<_FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<_FocusRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale, _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _scale   = Tween(begin: 1.6, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _opacity = Tween(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => Transform.scale(
      scale: _scale.value,
      child: Opacity(
        opacity: _opacity.value,
        child: Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.amber, width: 1.8),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(children: [
            // Corner accents
            ..._corners(),
          ]),
        ),
      ),
    ),
  );

  List<Widget> _corners() {
    const s = 10.0;
    const w = 2.0;
    final c = Colors.amber;
    return [
      Positioned(top: 0,  left: 0,  child: Container(width: s, height: w, color: c)),
      Positioned(top: 0,  left: 0,  child: Container(width: w, height: s, color: c)),
      Positioned(top: 0,  right: 0, child: Container(width: s, height: w, color: c)),
      Positioned(top: 0,  right: 0, child: Container(width: w, height: s, color: c)),
      Positioned(bottom: 0, left: 0, child: Container(width: s, height: w, color: c)),
      Positioned(bottom: 0, left: 0, child: Container(width: w, height: s, color: c)),
      Positioned(bottom: 0, right: 0, child: Container(width: s, height: w, color: c)),
      Positioned(bottom: 0, right: 0, child: Container(width: w, height: s, color: c)),
    ];
  }
}

// ── Pulse dot for burst indicator ─────────────────────────────────────────────
class _PulseDot extends StatefulWidget {
  const _PulseDot();
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
        lowerBound: 0.6, upperBound: 1.0)
      ..repeat(reverse: true);
    _scale = _ctrl;
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _scale,
    builder: (_, __) => Transform.scale(
      scale: _scale.value,
      child: Container(
          width: 9, height: 9,
          decoration: const BoxDecoration(
              color: Colors.white, shape: BoxShape.circle)),
    ),
  );
}

// ── Error view ────────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.no_photography_outlined,
            color: Colors.white38, size: 64),
        const SizedBox(height: 16),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 14)),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
          child: const Text('Kembali'),
        ),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  SETTINGS PAGE
// ══════════════════════════════════════════════════════════════════════════════

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _selected = WatermarkLayout.get();

  Future<void> _select(String id) async {
    await WatermarkLayout.set(id);
    setState(() => _selected = id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B4F72),
        foregroundColor: Colors.white,
        title: const Text('Layout Watermark',
            style: TextStyle(fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: kLayouts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final info     = kLayouts[i];
          final isActive = _selected == info.id;
          return GestureDetector(
            onTap: () => _select(info.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: isActive ? info.accentColor : Colors.grey.shade200,
                    width: isActive ? 2.0 : 1),
                color: isActive
                    ? info.accentColor.withOpacity(0.06)
                    : Colors.white,
                boxShadow: isActive
                    ? [BoxShadow(
                        color: info.accentColor.withOpacity(0.15),
                        blurRadius: 14, offset: const Offset(0, 4))]
                    : [const BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                        color: info.accentColor,
                        borderRadius: BorderRadius.circular(13)),
                    child: Icon(info.icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      Expanded(child: Text(info.label,
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15,
                              color: isActive ? info.accentColor : Colors.black87))),
                      if (isActive)
                        Icon(Icons.check_circle_rounded,
                            color: info.accentColor, size: 22),
                    ]),
                    const SizedBox(height: 4),
                    Text(info.description,
                        style: TextStyle(
                            fontSize: 12.5, color: Colors.grey.shade600)),
                    const SizedBox(height: 10),
                    _LayoutPreviewBar(layoutId: info.id, accent: info.accentColor),
                  ])),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Layout preview bars ───────────────────────────────────────────────────────
class _LayoutPreviewBar extends StatelessWidget {
  final String layoutId;
  final Color  accent;
  const _LayoutPreviewBar({required this.layoutId, required this.accent});

  @override
  Widget build(BuildContext context) {
    switch (layoutId) {
      case 'layout1': return _l1();
      case 'layout2': return _l2();
      case 'layout3': return _l3();
      case 'layout4': return _l4();
      default:        return const SizedBox();
    }
  }

  Widget _l1() => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Column(children: [
      _photo(28),
      _bar(14, const Color(0xFF1B4F72), child: _label('DELIVERY REPORT', Colors.white)),
      Container(height: 22, color: const Color(0xFFF0F0F0),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(children: [
            _pill(50, Colors.grey.shade400), const SizedBox(width: 6),
            _pill(35, Colors.grey.shade400),
          ])),
    ]),
  );

  Widget _l2() => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Column(children: [
      _photo(28),
      _bar(14, const Color(0xFF27AE60), child: _label('PEKERJAAN SELESAI', Colors.white)),
      Container(height: 22, color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(children: [
            _pill(45, Colors.grey.shade400), const SizedBox(width: 6),
            _pill(30, Colors.grey.shade400),
          ])),
    ]),
  );

  Widget _l3() => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Column(children: [
      _photo(28),
      Container(height: 3, color: const Color(0xFFD4AF37)),
      Container(height: 33, color: const Color(0xFF212121),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 5, color: const Color(0xFFD4AF37)),
            const SizedBox(width: 6),
            Expanded(child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              _label('LAPORAN TEKNIS', const Color(0xFFD4AF37)),
              const SizedBox(height: 3),
              _pill(45, Colors.white38),
            ])),
          ])),
    ]),
  );

  Widget _l4() => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: SizedBox(
      height: 64,
      child: Row(children: [
        Expanded(flex: 3, child: _photo(64)),
        Container(width: 3, height: 64, color: const Color(0xFFD4AF37)),
        Expanded(flex: 2, child: Container(
          height: 64,
          decoration: const BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF481A6B), Color(0xFF6C3483)],
          )),
          padding: const EdgeInsets.all(7),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center, children: [
            _label('TEKNISI', const Color(0xFFD4AF37)),
            _pill(38, Colors.white),
            const SizedBox(height: 4),
            _label('NO. TIKET', const Color(0xFFD4AF37)),
            _pill(28, Colors.white54),
          ]),
        )),
      ]),
    ),
  );

  Widget _photo(double h) => Container(
    height: h, color: Colors.grey.shade300,
    child: const Center(child: Icon(Icons.image, size: 14, color: Colors.grey)),
  );
  Widget _bar(double h, Color color, {Widget? child}) => Container(
    height: h, color: color,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    alignment: Alignment.centerLeft, child: child,
  );
  Widget _label(String t, Color c) =>
      Text(t, style: TextStyle(color: c, fontSize: 6, fontWeight: FontWeight.bold));
  Widget _pill(double w, Color c) =>
      Container(height: 3, width: w, color: c);
}

// ══════════════════════════════════════════════════════════════════════════════
//  SIGNATURE PAGE
// ══════════════════════════════════════════════════════════════════════════════

class SignaturePage extends StatefulWidget {
  final String imagePath;
  final String techName;
  final String itemId;
  final String itemTime;
  final Function(String) onDone;

  const SignaturePage({
    super.key,
    required this.imagePath,
    required this.techName,
    required this.itemId,
    required this.itemTime,
    required this.onDone,
  });

  @override
  State<SignaturePage> createState() => _SignaturePageState();
}

class _SignaturePageState extends State<SignaturePage> {
  final _sigCtrl = SignatureController(penStrokeWidth: 3, penColor: Colors.black);
  bool    _loading  = false;
  String? _errorMsg;

  Future<void> _save() async {
    if (_sigCtrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tambahkan tanda tangan dulu!')));
      return;
    }
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final results = await Future.wait([
        File(widget.imagePath).readAsBytes(),
        _sigCtrl.toPngBytes().then((v) => v ?? Uint8List(0)),
      ]);
      final imgBytes = results[0] as Uint8List;
      final sigBytes = results[1] as Uint8List;
      final parts    = widget.itemTime.split(' ');

      final result = await compute(_processWatermark, {
        'imageBytes': imgBytes,
        'sigBytes':   sigBytes.isNotEmpty ? sigBytes : null,
        'logoBytes':  LogoCache.bytes,
        'layout':     WatermarkLayout.get(),
        'name':       widget.techName,
        'id':         widget.itemId,
        'date':       parts[0],
        'time':       parts.length > 1 ? parts[1] : '',
      });

      final dir  = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/termulog_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(result);

      widget.onDone(file.path);
      if (mounted) {
        // Offer to save to gallery
        _showSaveDialog(file.path);
      }
    } catch (e) {
      setState(() { _errorMsg = 'Gagal memproses: $e'; _loading = false; });
    }
  }

  void _showSaveDialog(String path) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Icon(Icons.check_circle_rounded,
              color: Colors.green, size: 48),
          const SizedBox(height: 12),
          const Text('Laporan tersimpan!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Simpan juga ke galeri foto?',
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);  // dismiss sheet
                  Navigator.pop(context);  // back to dashboard
                },
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                child: const Text('Nanti saja'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  try {
                    await GallerySaver.saveImage(path);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Tersimpan ke galeri ✓'),
                              backgroundColor: Colors.green));
                    }
                  } catch (_) {}
                  if (context.mounted) {
                    Navigator.pop(context);
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.save_alt_rounded),
                label: const Text('Simpan'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B4F72),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
              ),
            ),
          ]),
        ]),
      ),
    ).then((_) {
      // If sheet dismissed without navigating, still go back
      if (mounted && _loading) {
        setState(() => _loading = false);
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() { _sigCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final activeLayout = kLayouts.firstWhere(
        (l) => l.id == WatermarkLayout.get(), orElse: () => kLayouts.first);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B4F72),
        foregroundColor: Colors.white,
        title: const Text('Tanda Tangan',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          TextButton.icon(
            onPressed: _loading ? null : () => _sigCtrl.clear(),
            icon: const Icon(Icons.refresh_rounded,
                color: Colors.white70, size: 18),
            label: const Text('Hapus',
                style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: Column(children: [
        // Preview strip
        SizedBox(
          height: 150,
          child: Stack(fit: StackFit.expand, children: [
            Image.file(File(widget.imagePath),
                fit: BoxFit.cover, cacheWidth: 800),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent,
                    Colors.black.withOpacity(0.45)],
                ),
              ),
            ),
            Positioned(bottom: 12, left: 14,
              child: Text(widget.itemId,
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            Positioned(bottom: 12, right: 14,
              child: Text(widget.itemTime,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          ]),
        ),

        // Layout badge
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: activeLayout.accentColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: activeLayout.accentColor.withOpacity(0.35))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(activeLayout.icon,
                    size: 14, color: activeLayout.accentColor),
                const SizedBox(width: 6),
                Text(activeLayout.label,
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: activeLayout.accentColor)),
              ]),
            ),
            const Spacer(),
            Text('Tanda tangani di bawah',
                style: TextStyle(
                    fontSize: 12.5, color: Colors.grey.shade600)),
          ]),
        ),

        // Signature canvas
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05),
                    blurRadius: 10, offset: const Offset(0, 2)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(children: [
                Signature(
                    controller: _sigCtrl, backgroundColor: Colors.white),
                // Guide text overlay (disappears when user draws)
                IgnorePointer(
                  child: Center(
                    child: Text('Tanda tangan di sini',
                        style: TextStyle(
                            color: Colors.grey.shade300,
                            fontSize: 16,
                            fontWeight: FontWeight.w300)),
                  ),
                ),
              ]),
            ),
          ),
        ),

        if (_errorMsg != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_errorMsg!,
                style: const TextStyle(color: Colors.red)),
          ),

        // Save button
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _save,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B4F72),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0),
                child: _loading
                    ? const SizedBox(height: 22, width: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline_rounded, size: 20),
                          SizedBox(width: 8),
                          Text('Proses & Simpan',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                        ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
