// ════════════════════════════════════════════════════════════════════════════
//  TermulLog — main.dart
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
  try { _cameras = await availableCameras(); } catch (_) {}
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
  final String id, label, description;
  final IconData icon;
  final Color accentColor;
  const LayoutInfo({
    required this.id, required this.label, required this.description,
    required this.icon, required this.accentColor,
  });
}

const List<LayoutInfo> kLayouts = [
  LayoutInfo(id: 'layout1', label: 'Professional Report',
    description: 'Strip navy di bawah foto, kotak info abu-abu, tanda tangan kiri.',
    icon: Icons.article_outlined, accentColor: Color(0xFF1B4F72)),
  LayoutInfo(id: 'layout2', label: 'Compact Field',
    description: 'Strip hijau, info ringkas, cocok untuk laporan cepat di lapangan.',
    icon: Icons.assignment_turned_in_outlined, accentColor: Color(0xFF27AE60)),
  LayoutInfo(id: 'layout3', label: 'Dark Minimal',
    description: 'Latar gelap elegan, teks putih, garis aksen emas. Kesan premium.',
    icon: Icons.dark_mode_outlined, accentColor: Color(0xFF212121)),
  LayoutInfo(id: 'layout4', label: 'Split Side-by-Side',
    description: 'Panel kiri: foto. Panel kanan: info & tanda tangan dua kolom ungu.',
    icon: Icons.view_column_outlined, accentColor: Color(0xFF6C3483)),
];

// ════════════════════════════════════════════════════════════════════════════
//  WATERMARK ENGINE
// ════════════════════════════════════════════════════════════════════════════

Uint8List _processWatermark(Map<String, dynamic> p) {
  img.Image base = img.decodeImage(p['imageBytes'] as Uint8List)!;
  if (base.width > kMaxOutputWidth)
    base = img.copyResize(base, width: kMaxOutputWidth, interpolation: img.Interpolation.linear);

  final sigBytes = p['sigBytes'] as Uint8List?;
  img.Image? sig;
  if (sigBytes != null && sigBytes.isNotEmpty) {
    sig = img.decodeImage(sigBytes);
    if (sig != null && sig.width > kSigMaxWidth)
      sig = img.copyResize(sig, width: kSigMaxWidth, interpolation: img.Interpolation.linear);
  }

  final logoBytes = p['logoBytes'] as Uint8List?;
  final logo = logoBytes != null ? img.decodeImage(logoBytes) : null;
  final layout = p['layout'] as String? ?? 'layout1';
  final name = p['name'] as String;
  final id   = p['id']   as String;
  final date = p['date'] as String;
  final time = p['time'] as String;

  switch (layout) {
    case 'layout2': return _layout2(base, sig, logo, name, id, date, time);
    case 'layout3': return _layout3(base, sig, logo, name, id, date, time);
    case 'layout4': return _layout4(base, sig, logo, name, id, date, time);
    default:        return _layout1(base, sig, logo, name, id, date, time);
  }
}

Uint8List _layout1(img.Image base, img.Image? sig, img.Image? logo,
    String name, String id, String date, String time) {
  final W = base.width; final H = base.height;
  final S = (W * 0.22).clamp(280.0, 800.0).toInt();
  final canvas = img.Image(width: W, height: H + S);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(canvas, base, dstX: 0, dstY: 0);
  final navy  = img.ColorRgb8(27, 79, 114);
  final white = img.ColorRgb8(255, 255, 255);
  final gray  = img.ColorRgb8(240, 240, 240);
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

Uint8List _layout2(img.Image base, img.Image? sig, img.Image? logo,
    String name, String id, String date, String time) {
  final W = base.width; final H = base.height;
  final S = (W * 0.20).clamp(250.0, 700.0).toInt();
  final canvas = img.Image(width: W, height: H + S);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(canvas, base, dstX: 0, dstY: 0);
  img.fillRect(canvas, x1: 0, y1: H, x2: W, y2: H + 70, color: img.ColorRgb8(39, 174, 96));
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
    img.fillRect(canvas, x1: fW, y1: y, x2: W, y2: y + 1,
        color: img.ColorRgb8(
          (72 + (108 - 72) * t).round(),
          (26 + (52 - 26) * t).round(),
          (107 + (131 - 107) * t).round()));
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
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B4F72)),
      useMaterial3: true, fontFamily: 'Roboto',
    ),
    home: const Login(),
  );
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
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF0D2137), Color(0xFF1B4F72), Color(0xFF2980B9)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 24),
                const Text('TermulLog',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800,
                        color: Colors.white, letterSpacing: -0.5)),
                const SizedBox(height: 6),
                Text('Laporan Lapangan Digital',
                    style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.7),
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
                      prefixIcon: Icon(Icons.person_outline, color: Colors.white.withOpacity(0.6)),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1B4F72),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: () {
                      if (c.text.trim().isEmpty) return;
                      Navigator.pushReplacement(context,
                          MaterialPageRoute(builder: (_) => Dashboard(name: c.text.trim())));
                    },
                    child: const Text('Masuk',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
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
  final String id, path, time;
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

  Future<void> _openCamera() async {
    if (_cameras.isEmpty) { await _captureFallback(); return; }
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CameraPage(
        onCapture: (paths) {
          if (paths.isEmpty) return;
          if (paths.length == 1) {
            _goToSignature(paths.first);
          } else {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => BurstSelectionPage(
                paths: paths, onSelect: _goToSignature)));
          }
        },
      ),
    ));
  }

  Future<void> _captureFallback() async {
    final file = await ImagePicker().pickImage(
        source: ImageSource.camera, maxWidth: kMaxOutputWidth.toDouble(), imageQuality: 90);
    if (file == null || !mounted) return;
    _goToSignature(file.path);
  }

  void _goToSignature(String imagePath) {
    final now  = DateTime.now();
    final id   = 'TRM-${now.millisecondsSinceEpoch}';
    final time = DateFormat('dd/MM HH:mm').format(now);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SignaturePage(
        imagePath: imagePath, techName: widget.name,
        itemId: id, itemTime: time,
        onDone: (path) => setState(() => list.add(Item(id, path, time))),
      ),
    ));
  }

  Future<void> _pickLogo() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 200);
    if (file == null) return;
    setState(() => _logoPath = file.path);
    await LogoCache.load(file.path);
  }

  Future<void> _shareItem(Item item) async {
    try {
      await Share.shareXFiles([XFile(item.path)],
          subject: 'Laporan ${item.id}',
          text: 'Laporan teknisi — ${item.id} — ${item.time}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal share: $e')));
    }
  }

  Future<void> _saveToGallery(Item item) async {
    try {
      final ok = await GallerySaver.saveImage(item.path);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok == true ? 'Tersimpan ke galeri ✓' : 'Gagal menyimpan'),
        backgroundColor: ok == true ? Colors.green.shade700 : Colors.red.shade700,
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')));
    }
  }

  void _previewItem(Item item) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => PreviewPage(
        item: item,
        onShare: () => _shareItem(item),
        onSave:  () => _saveToGallery(item),
      ),
    ));
  }

  void _deleteItem(Item item) {
    setState(() => list.removeWhere((e) => e.id == item.id));
    try { File(item.path).deleteSync(); } catch (_) {}
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Laporan dihapus')));
  }

  @override
  Widget build(BuildContext context) {
    final today      = DateFormat('dd/MM').format(DateTime.now());
    final todayCount = list.where((e) => e.time.startsWith(today)).length;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: Column(children: [
        _DashboardHeader(
          name: widget.name, total: list.length, todayCount: todayCount,
          logoPath: _logoPath, onPickLogo: _pickLogo,
          onClearLogo: () { setState(() => _logoPath = null); LogoCache.clear(); },
          onSettings: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsPage())),
        ),
        Expanded(
          child: list.isEmpty
              ? _EmptyState(onCapture: _openCamera)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final item = list[list.length - 1 - i];
                    return _ItemCard(
                      item: item,
                      onTap:    () => _previewItem(item),
                      onShare:  () => _shareItem(item),
                      onSave:   () => _saveToGallery(item),
                      onDelete: () => _deleteItem(item),
                    );
                  }),
        ),
      ]),
      floatingActionButton: _CameraFAB(onTap: _openCamera),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

// ── Dashboard Header ──────────────────────────────────────────────────────────
class _DashboardHeader extends StatelessWidget {
  final String name; final int total, todayCount;
  final String? logoPath;
  final VoidCallback onPickLogo, onClearLogo, onSettings;
  const _DashboardHeader({
    required this.name, required this.total, required this.todayCount,
    required this.logoPath, required this.onPickLogo,
    required this.onClearLogo, required this.onSettings,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF0D2137), Color(0xFF1B4F72)]),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Selamat datang,',
                    style: TextStyle(fontSize: 12.5,
                        color: Colors.white.withOpacity(0.65), letterSpacing: 0.3)),
                const SizedBox(height: 2),
                Text(name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                        color: Colors.white),
                    overflow: TextOverflow.ellipsis),
              ])),
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
              IconButton(icon: Icon(Icons.image_outlined,
                  color: Colors.white.withOpacity(0.85), size: 22),
                  onPressed: onPickLogo),
              IconButton(icon: Icon(Icons.tune_rounded,
                  color: Colors.white.withOpacity(0.85), size: 22),
                  onPressed: onSettings),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              _StatChip(label: 'Semua',   value: '$total',      icon: Icons.photo_library_outlined),
              const SizedBox(width: 10),
              _StatChip(label: 'Hari ini', value: '$todayCount', icon: Icons.today_outlined),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label, value; final IconData icon;
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
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
    ]),
  );
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCapture;
  const _EmptyState({required this.onCapture});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 100, height: 100,
        decoration: BoxDecoration(
            color: const Color(0xFF1B4F72).withOpacity(0.08), shape: BoxShape.circle),
        child: const Icon(Icons.add_a_photo_outlined, size: 44, color: Color(0xFF1B4F72)),
      ),
      const SizedBox(height: 20),
      const Text('Belum ada laporan',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF1B4F72))),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      ),
    ]),
  );
}

class _ItemCard extends StatelessWidget {
  final Item item;
  final VoidCallback onTap, onShare, onSave, onDelete;
  const _ItemCard({required this.item, required this.onTap, required this.onShare,
      required this.onSave, required this.onDelete});
  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: Colors.red.shade400, borderRadius: BorderRadius.circular(16)),
        child: const Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.delete_outline_rounded, color: Colors.white, size: 26),
          SizedBox(height: 4),
          Text('Hapus', style: TextStyle(color: Colors.white, fontSize: 11)),
        ]),
      ),
      confirmDismiss: (_) async => await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Hapus Laporan?'),
          content: Text('${item.id} akan dihapus permanen.'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Hapus', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ) ?? false,
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06),
              blurRadius: 12, offset: const Offset(0, 3))],
        ),
        child: InkWell(
          onTap: onTap, borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Hero(
                tag: 'thumb_${item.id}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(File(item.path),
                      width: 72, height: 72, fit: BoxFit.cover, cacheWidth: 144),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: const Color(0xFF1B4F72).withOpacity(0.09),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(item.id,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: Color(0xFF1B4F72)),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.access_time_rounded, size: 13, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(item.time, style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  _ActionBtn(icon: Icons.visibility_outlined, label: 'Preview',
                      color: const Color(0xFF1B4F72), onTap: onTap),
                  const SizedBox(width: 8),
                  _ActionBtn(icon: Icons.share_outlined, label: 'Bagikan',
                      color: Colors.teal, onTap: onShare),
                  const SizedBox(width: 8),
                  _ActionBtn(icon: Icons.save_alt_rounded, label: 'Simpan',
                      color: Colors.orange, onTap: onSave),
                ]),
              ])),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(0.09), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ]),
    ),
  );
}

class _CameraFAB extends StatelessWidget {
  final VoidCallback onTap;
  const _CameraFAB({required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 60, padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1B4F72), Color(0xFF2980B9)]),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: const Color(0xFF1B4F72).withOpacity(0.45),
            blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.camera_alt_rounded, color: Colors.white, size: 22),
        SizedBox(width: 10),
        Text('Ambil Foto', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  PREVIEW PAGE
// ════════════════════════════════════════════════════════════════════════════

class SignaturePage extends StatefulWidget {
  final String imagePath, techName, itemId, itemTime;
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
  final SignatureController _signature = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
  );

  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;

    setState(() => _saving = true);

    try {
      final imageBytes = await File(widget.imagePath).readAsBytes();

      Uint8List? sigBytes;

      if (_signature.isNotEmpty) {
        sigBytes = await _signature.toPngBytes();
      }

      final result = await compute(_processWatermark, {
        'imageBytes': imageBytes,
        'sigBytes': sigBytes,
        'logoBytes': LogoCache.bytes,
        'layout': WatermarkLayout.get(),
        'name': widget.techName,
        'id': widget.itemId,
        'date': DateFormat('dd/MM/yyyy').format(DateTime.now()),
        'time': DateFormat('HH:mm').format(DateTime.now()),
      });

      final dir = await getApplicationDocumentsDirectory();

      final file = File('${dir.path}/${widget.itemId}.jpg');

      await file.writeAsBytes(result);

      widget.onDone(file.path);

      if (mounted) {
        Navigator.pop(context);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Laporan berhasil dibuat'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Save error: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    if (mounted) {
      setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _signature.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        title: const Text('Tanda Tangan'),
      ),

      body: Column(
        children: [
          Expanded(
            child: Image.file(
              File(widget.imagePath),
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),

          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Signature(
                    controller: _signature,
                    backgroundColor: Colors.white,
                  ),
                ),

                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _signature.clear(),
                        child: const Text('Hapus'),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text('Simpan'),
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
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  CAMERA PAGE
// ════════════════════════════════════════════════════════════════════════════

class CameraPage extends StatefulWidget {
  final Function(List<String>) onCapture;
  const CameraPage({super.key, required this.onCapture});
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _ctrl;
  int    _camIdx      = 0;
  bool   _initialized = false;
  bool   _busy        = false;

  FlashMode _flash = FlashMode.off;

  double _zoom = 1.0, _baseZoom = 1.0, _minZoom = 1.0, _maxZoom = 8.0;

  Offset? _focusPoint;
  bool    _showFocus = false;

  bool         _burstMode    = false;
  bool         _burstRunning = false;
  Timer?       _burstTimer;
  List<String> _burstPaths   = [];

  late AnimationController _shutterAnim;
  late Animation<double>   _shutterOpacity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shutterAnim = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 150));
    _shutterOpacity = Tween<double>(begin: 0.0, end: 0.7).animate(
        CurvedAnimation(parent: _shutterAnim, curve: Curves.easeOut));
    _initCamera(_camIdx);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _burstTimer?.cancel();
    _shutterAnim.dispose();
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(_camIdx);
    }
  }

  Future<void> _initCamera(int idx) async {
    if (_cameras.isEmpty) return;
    await _ctrl?.dispose();
    final controller = CameraController(
        _cameras[idx], ResolutionPreset.high,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    _ctrl = controller;
    try {
      await controller.initialize();
      await controller.setFlashMode(_flash);
      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = await controller.getMaxZoomLevel();
      _zoom    = _minZoom;
    } catch (e) { debugPrint('Camera init error: $e'); }
    if (mounted) setState(() => _initialized = true);
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    setState(() => _initialized = false);
    _camIdx = (_camIdx + 1) % _cameras.length;
    await _initCamera(_camIdx);
  }

  Future<void> _cycleFlash() async {
    final next = _flash == FlashMode.off ? FlashMode.auto
        : _flash == FlashMode.auto ? FlashMode.always : FlashMode.off;
    setState(() => _flash = next);
    await _ctrl?.setFlashMode(next);
  }

  Future<void> _onTapFocus(TapDownDetails d, BoxConstraints c) async {
    if (_ctrl == null || !_initialized) return;
    final x = (d.localPosition.dx / c.biggest.width).clamp(0.0, 1.0);
    final y = (d.localPosition.dy / c.biggest.height).clamp(0.0, 1.0);
    setState(() { _focusPoint = d.localPosition; _showFocus = true; });
    try {
      await _ctrl!.setFocusPoint(Offset(x, y));
      await _ctrl!.setExposurePoint(Offset(x, y));
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _showFocus = false);
  }

  void _onScaleStart(ScaleStartDetails _) => _baseZoom = _zoom;
  Future<void> _onScaleUpdate(ScaleUpdateDetails d) async {
    if (_ctrl == null) return;
    final z = (_baseZoom * d.scale).clamp(_minZoom, _maxZoom);
    setState(() => _zoom = z);
    await _ctrl!.setZoomLevel(z);
  }

  Future<void> _flashShutter() async {
    await _shutterAnim.forward();
    await _shutterAnim.reverse();
  }

  Future<void> _capture() async {
  if (_ctrl == null || !_initialized || _busy) return;

  setState(() => _busy = true);

  unawaited(_flashShutter());

  try {
    final file = await _ctrl!.takePicture();

    if (!mounted) return;

    widget.onCapture([file.path]);

    Navigator.pop(context);

  } catch (e) {
    debugPrint('Capture error: $e');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error kamera: $e'),
        ),
      );
    }
  }

  if (mounted) {
    setState(() => _busy = false);
  }
}

  void _startBurst() {
    setState(() { _burstRunning = true; _burstPaths = []; });
    _burstTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) async {
      if (!mounted || _ctrl == null) return;
      try {
        unawaited(_flashShutter());
        final file = await _ctrl!.takePicture();
        if (mounted) setState(() => _burstPaths.add(file.path));
      } catch (_) {}
    });
  }

  void _stopBurst() {
  _burstTimer?.cancel();

  setState(() => _burstRunning = false);

  if (_burstPaths.isNotEmpty && mounted) {

    widget.onCapture(List.from(_burstPaths));

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }
}

  Future<void> _pickFromGallery() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    widget.onCapture([file.path]);
    Navigator.pop(context);
  }

  IconData get _flashIcon => _flash == FlashMode.always
      ? Icons.flash_on_rounded
      : _flash == FlashMode.auto ? Icons.flash_auto_rounded : Icons.flash_off_rounded;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(
      child: Column(children: [
        _buildTopBar(),
        Expanded(child: _buildPreview()),
        if (_burstPaths.isNotEmpty) _buildBurstStrip(),
        _buildBottomBar(),
      ]),
    ),
  );

  Widget _buildTopBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    color: Colors.black,
    child: Row(children: [
      IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
        onPressed: () => Navigator.pop(context)),
      const Spacer(),
      _CamBtn(icon: _flashIcon,
          label: _flash == FlashMode.off ? 'Off' : _flash == FlashMode.auto ? 'Auto' : 'On',
          onTap: _cycleFlash),
      const SizedBox(width: 4),
      _CamBtn(icon: Icons.burst_mode_rounded, label: 'Burst', active: _burstMode,
          onTap: () => setState(() {
            _burstMode = !_burstMode;
            if (!_burstMode && _burstRunning) _stopBurst();
          })),
      const SizedBox(width: 4),
      _CamBtn(icon: Icons.flip_camera_ios_rounded, label: 'Balik', onTap: _switchCamera),
    ]),
  );

  Widget _buildPreview() {
    if (!_initialized || _ctrl == null) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: Colors.white54),
        SizedBox(height: 16),
        Text('Memuat kamera…', style: TextStyle(color: Colors.white54, fontSize: 13)),
      ]));
    }
    return LayoutBuilder(builder: (_, constraints) => GestureDetector(
      onTapDown:     (d) => _onTapFocus(d, constraints),
      onScaleStart:  _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      child: Stack(fit: StackFit.expand, children: [
        ClipRect(child: OverflowBox(
          alignment: Alignment.center,
          child: FittedBox(fit: BoxFit.cover,
            child: SizedBox(
              width:  _ctrl!.value.previewSize!.height,
              height: _ctrl!.value.previewSize!.width,
              child: CameraPreview(_ctrl!),
            )),
        )),
        AnimatedBuilder(
          animation: _shutterOpacity,
          builder: (_, __) => Opacity(
              opacity: _shutterOpacity.value,
              child: Container(color: Colors.white)),
        ),
        if (_showFocus && _focusPoint != null)
          Positioned(
            left: _focusPoint!.dx - 28, top: _focusPoint!.dy - 28,
            child: _FocusBox()),
        if (_zoom > _minZoom + 0.05)
          Positioned(
            top: 14, left: 0, right: 0,
            child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.black54,
                  borderRadius: BorderRadius.circular(20)),
              child: Text('${_zoom.toStringAsFixed(1)}×',
                  style: const TextStyle(color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.w600)),
            )),
          ),
        if (_burstRunning)
          Positioned(
            top: 14, right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.red.shade600,
                  borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.fiber_manual_record, color: Colors.white, size: 10),
                const SizedBox(width: 5),
                Text('${_burstPaths.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
      ]),
    ));
  }

  Widget _buildBurstStrip() => Container(
    height: 72, color: Colors.black87,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      itemCount: _burstPaths.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ClipRRect(borderRadius: BorderRadius.circular(6),
          child: Image.file(File(_burstPaths[i]),
              width: 56, height: 56, fit: BoxFit.cover)),
      ),
    ),
  );

  Widget _buildBottomBar() => Container(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
    color: Colors.black,
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      _CircleBtn(icon: Icons.photo_library_outlined, size: 48, onTap: _pickFromGallery),
      GestureDetector(
        onTap: _burstMode ? (_burstRunning ? _stopBurst : _startBurst) : _capture,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 72, height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: _burstRunning ? Colors.red.shade400 : Colors.white, width: 4)),
          child: Center(child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width:  _burstRunning ? 24 : 54,
            height: _burstRunning ? 24 : 54,
            decoration: BoxDecoration(
              color: _burstRunning ? Colors.red.shade500 : Colors.white,
              borderRadius: BorderRadius.circular(_burstRunning ? 6 : 27)),
          )),
        ),
      ),
      _CircleBtn(icon: Icons.info_outline_rounded, size: 48, onTap: _showInfoSheet),
    ]),
  );

  void _showInfoSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: const [
          Text('Petunjuk Kamera',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          SizedBox(height: 14),
          _InfoRow(icon: Icons.touch_app_rounded,      text: 'Ketuk layar untuk fokus'),
          _InfoRow(icon: Icons.zoom_in_rounded,         text: 'Jepit/rentang untuk zoom'),
          _InfoRow(icon: Icons.burst_mode_rounded,      text: 'Burst: aktifkan toggle → tekan shutter mulai, tekan lagi berhenti'),
          _InfoRow(icon: Icons.flash_auto_rounded,      text: 'Ikon kilat: Off → Auto → On'),
          _InfoRow(icon: Icons.flip_camera_ios_rounded, text: 'Ikon flip: ganti kamera depan/belakang'),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  BURST SELECTION PAGE
// ════════════════════════════════════════════════════════════════════════════

class BurstSelectionPage extends StatelessWidget {
  final List<String> paths;
  final Function(String) onSelect;
  const BurstSelectionPage({super.key, required this.paths, required this.onSelect});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black, foregroundColor: Colors.white,
      title: Text('Pilih Foto (${paths.length})',
          style: const TextStyle(fontSize: 16)),
    ),
    body: GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4),
      itemCount: paths.length,
      itemBuilder: (_, i) => GestureDetector(
        onTap: () { onSelect(paths[i]); Navigator.pop(context); },
        child: Stack(fit: StackFit.expand, children: [
          ClipRRect(borderRadius: BorderRadius.circular(6),
              child: Image.file(File(paths[i]), fit: BoxFit.cover)),
          Positioned(bottom: 4, right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: Colors.black54,
                  borderRadius: BorderRadius.circular(8)),
              child: Text('${i + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w700)),
            )),
        ]),
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  SIGNATURE PAGE
// ════════════════════════════════════════════════════════════════════════════

class SignaturePage extends StatefulWidget {
  final String imagePath, techName, itemId, itemTime;
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
  final SignatureController _signature = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
  );

  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;

    setState(() => _saving = true);

    try {
      final imageBytes = await File(widget.imagePath).readAsBytes();

      Uint8List? sigBytes;

      if (_signature.isNotEmpty) {
        sigBytes = await _signature.toPngBytes();
      }

      final result = await compute(_processWatermark, {
        'imageBytes': imageBytes,
        'sigBytes': sigBytes,
        'logoBytes': LogoCache.bytes,
        'layout': WatermarkLayout.get(),
        'name': widget.techName,
        'id': widget.itemId,
        'date': DateFormat('dd/MM/yyyy').format(DateTime.now()),
        'time': DateFormat('HH:mm').format(DateTime.now()),
      });

      final dir = await getApplicationDocumentsDirectory();

      final file = File(
        '${dir.path}/${widget.itemId}.jpg',
      );

      await file.writeAsBytes(result);

      widget.onDone(file.path);

      if (mounted) {
        Navigator.pop(context);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Laporan berhasil dibuat'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Save error: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    if (mounted) {
      setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _signature.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),

      appBar: AppBar(
        title: const Text('Tambah Tanda Tangan'),
      ),

      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              child: Image.file(
                File(widget.imagePath),
                width: double.infinity,
                fit: BoxFit.contain,
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tanda Tangan Teknisi',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 12),

                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.grey.shade300,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),

                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Signature(
                      controller: _signature,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _signature.clear(),
                        icon: const Icon(Icons.clear),
                        label: const Text('Hapus'),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,

                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_alt_rounded),

                        label: Text(
                          _saving ? 'Menyimpan...' : 'Simpan',
                        ),

                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B4F72),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                        ),
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
  }
}
// ════════════════════════════════════════════════════════════════════════════
//  SETTINGS PAGE (placeholder)
// ════════════════════════════════════════════════════════════════════════════

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String selected = WatermarkLayout.get();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih Layout'),
      ),

      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: kLayouts.length,

        itemBuilder: (_, i) {
          final l = kLayouts[i];

          final active = selected == l.id;

          return Card(
            elevation: active ? 4 : 1,

            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: active
                    ? l.accentColor
                    : Colors.transparent,
                width: 2,
              ),
            ),

            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: l.accentColor.withOpacity(0.15),
                child: Icon(
                  l.icon,
                  color: l.accentColor,
                ),
              ),

              title: Text(
                l.label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),

              subtitle: Text(l.description),

              trailing: active
                  ? Icon(
                      Icons.check_circle,
                      color: l.accentColor,
                    )
                  : null,

              onTap: () async {
                setState(() => selected = l.id);

                await WatermarkLayout.set(l.id);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${l.label} dipilih',
                      ),
                    ),
                  );
                }
              },
            ),
          );
        },
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SHARED CAMERA HELPER WIDGETS
// ════════════════════════════════════════════════════════════════════════════

class _CamBtn extends StatelessWidget {
  final IconData icon; final String label; final bool active; final VoidCallback onTap;
  const _CamBtn({required this.icon, required this.label, required this.onTap, this.active = false});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: active ? Colors.white38 : Colors.transparent)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: active ? Colors.yellowAccent : Colors.white, size: 18),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(
            color: active ? Colors.yellowAccent : Colors.white70,
            fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

class _CircleBtn extends StatelessWidget {
  final IconData icon; final double size; final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.size, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: size, height: size,
      decoration: BoxDecoration(shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.1)),
      child: Icon(icon, color: Colors.white70, size: size * 0.45),
    ),
  );
}

class _FocusBox extends StatefulWidget {
  @override
  State<_FocusBox> createState() => _FocusBoxState();
}

class _FocusBoxState extends State<_FocusBox> with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double> _scale, _opacity;
  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _scale   = Tween<double>(begin: 1.4, end: 1.0)
        .animate(CurvedAnimation(parent: _ac, curve: Curves.easeOut));
    _opacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ac, curve: Curves.easeIn));
    _ac.forward();
  }
  @override
  void dispose() { _ac.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ac,
    builder: (_, __) => Opacity(opacity: _opacity.value,
      child: Transform.scale(scale: _scale.value,
        child: Container(width: 56, height: 56,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.yellowAccent, width: 1.5),
            borderRadius: BorderRadius.circular(4))))));
}

class _InfoRow extends StatelessWidget {
  final IconData icon; final String text;
  const _InfoRow({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Icon(icon, color: Colors.white54, size: 18),
      const SizedBox(width: 12),
      Expanded(child: Text(text,
          style: const TextStyle(color: Colors.white70, fontSize: 13))),
    ]),
  );
}
