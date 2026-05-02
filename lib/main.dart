import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';

void main() {
  runApp(const App());
}

// ═══════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════

const int kMaxOutputWidth = 1280;
const int kJpegQuality    = 85;
const int kSigMaxWidth    = 500;

// ═══════════════════════════════════════
// LAYOUT REGISTRY
// Daftarkan semua layout di sini.
// SettingsPage membaca list ini otomatis.
// ═══════════════════════════════════════

class LayoutInfo {
  final String  id;
  final String  label;
  final String  description;
  final IconData icon;
  final Color   accentColor;
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
    id: 'layout1',
    label: 'Professional Report',
    description: 'Strip navy di bawah foto, kotak info abu-abu, tanda tangan kiri.',
    icon: Icons.article_outlined,
    accentColor: Color(0xFF1B4F72),
  ),
  LayoutInfo(
    id: 'layout2',
    label: 'Compact Field',
    description: 'Strip hijau, info ringkas, cocok untuk laporan cepat di lapangan.',
    icon: Icons.assignment_turned_in_outlined,
    accentColor: Color(0xFF27AE60),
  ),
  LayoutInfo(
    id: 'layout3',
    label: 'Dark Minimal',
    description: 'Latar gelap elegan, teks putih, garis aksen emas. Kesan premium.',
    icon: Icons.dark_mode_outlined,
    accentColor: Color(0xFF212121),
  ),
  LayoutInfo(
    id: 'layout4',
    label: 'Split Side-by-Side',
    description: 'Panel kiri: foto. Panel kanan: info & tanda tangan dua kolom ungu.',
    icon: Icons.view_column_outlined,
    accentColor: Color(0xFF6C3483),
  ),
];

// ═══════════════════════════════════════
// WATERMARK ENGINE (ISOLATE)
// ═══════════════════════════════════════

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

// ═══════════════════════════════════════
// LAYOUT 1 — Professional Report (Navy)
// ═══════════════════════════════════════

Uint8List _layout1(img.Image base, img.Image? sig, img.Image? logo,
    String name, String id, String date, String time) {
  final W = base.width;
  final H = base.height;
  final S = (W * 0.22).clamp(280.0, 800.0).toInt();

  final canvas = img.Image(width: W, height: H + S);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(canvas, base, dstX: 0, dstY: 0);

  final navy  = img.ColorRgb8(27,  79,  114);
  final white = img.ColorRgb8(255, 255, 255);
  final gray  = img.ColorRgb8(240, 240, 240);

  img.fillRect(canvas, x1: 0, y1: H, x2: W, y2: H + 90, color: navy);
  img.drawString(canvas, 'DELIVERY REPORT',
      font: img.arial48, x: 20, y: H + 25, color: white);
  img.drawString(canvas, '$date  $time',
      font: img.arial24, x: W - 280, y: H + 30, color: white);

  final iY = H + 100;
  img.fillRect(canvas, x1: 0, y1: iY, x2: W, y2: iY + 140, color: gray);
  img.drawString(canvas, 'TEKNISI: $name',    font: img.arial24, x: 20, y: iY + 20);
  img.drawString(canvas, 'ID: $id',           font: img.arial24, x: 20, y: iY + 60);
  img.drawString(canvas, 'WAKTU: $date $time',font: img.arial24, x: 20, y: iY + 100);

  if (sig != null)  img.compositeImage(canvas, sig, dstX: 20, dstY: iY + 160);
  if (logo != null) {
    final l = img.copyResize(logo, width: 80, interpolation: img.Interpolation.linear);
    img.compositeImage(canvas, l, dstX: W - 100, dstY: iY + 20);
  }
  return img.encodeJpg(canvas, quality: kJpegQuality);
}

// ═══════════════════════════════════════
// LAYOUT 2 — Compact Field (Green)
// ═══════════════════════════════════════

Uint8List _layout2(img.Image base, img.Image? sig, img.Image? logo,
    String name, String id, String date, String time) {
  final W = base.width;
  final H = base.height;
  final S = (W * 0.20).clamp(250.0, 700.0).toInt();

  final canvas = img.Image(width: W, height: H + S);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(canvas, base, dstX: 0, dstY: 0);

  final green = img.ColorRgb8(39, 174, 96);

  img.fillRect(canvas, x1: 0, y1: H, x2: W, y2: H + 70, color: green);
  img.drawString(canvas, 'PEKERJAAN SELESAI', font: img.arial48, x: 20, y: H + 15);

  final iY = H + 90;
  img.drawString(canvas, 'Teknisi: $name',     font: img.arial24, x: 20, y: iY);
  img.drawString(canvas, 'ID: $id',            font: img.arial24, x: 20, y: iY + 50);
  img.drawString(canvas, 'Waktu: $date $time', font: img.arial24, x: 20, y: iY + 100);

  if (sig != null)  img.compositeImage(canvas, sig, dstX: 20, dstY: iY + 150);
  if (logo != null) {
    final l = img.copyResize(logo, width: 70, interpolation: img.Interpolation.linear);
    img.compositeImage(canvas, l, dstX: W - 90, dstY: iY + 10);
  }
  return img.encodeJpg(canvas, quality: kJpegQuality);
}

// ═══════════════════════════════════════
// LAYOUT 3 — Dark Minimal (Charcoal + Gold)
//
//  [  foto  ]
//  ══════════ garis emas 3px ══════════
//  [  charcoal bg                      ]
//  [ | bar emas 6px | info putih + ttd ]
// ═══════════════════════════════════════

Uint8List _layout3(img.Image base, img.Image? sig, img.Image? logo,
    String name, String id, String date, String time) {
  final W = base.width;
  final H = base.height;
  final S = (W * 0.24).clamp(300.0, 850.0).toInt();

  final canvas = img.Image(width: W, height: H + S);
  img.fill(canvas, color: img.ColorRgb8(33, 33, 33));
  img.compositeImage(canvas, base, dstX: 0, dstY: 0);

  // Charcoal strip
  img.fillRect(canvas, x1: 0, y1: H, x2: W, y2: H + S,
      color: img.ColorRgb8(33, 33, 33));

  // Garis emas horizontal pemisah foto–strip
  img.fillRect(canvas, x1: 0, y1: H, x2: W, y2: H + 4,
      color: img.ColorRgb8(212, 175, 55));

  // Bar emas vertikal kiri
  img.fillRect(canvas, x1: 0, y1: H + 4, x2: 6, y2: H + S,
      color: img.ColorRgb8(212, 175, 55));

  final white = img.ColorRgb8(255, 255, 255);
  final gold  = img.ColorRgb8(212, 175, 55);
  const pX    = 26; // padding setelah bar emas

  img.drawString(canvas, 'LAPORAN TEKNIS',
      font: img.arial48, x: pX, y: H + 18, color: gold);

  img.drawString(canvas, name,
      font: img.arial24, x: pX, y: H + 80, color: white);
  img.drawString(canvas, 'ID: $id',
      font: img.arial24, x: pX, y: H + 115, color: white);
  img.drawString(canvas, '$date  $time',
      font: img.arial24, x: pX, y: H + 150, color: white);

  if (sig != null) {
    // Patch semi-transparan biar tanda tangan terbaca di latar gelap
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

// ═══════════════════════════════════════
// LAYOUT 4 — Split Side-by-Side (Purple)
//
//  Canvas diperlebar: [foto | panel info]
//  Panel info = 38% lebar foto (min 320 px)
//  Tinggi canvas = tinggi foto
//
//  Gradien ungu vertikal pada panel kanan.
//  Garis emas pemisah vertikal.
//  Label gold + nilai putih.
// ═══════════════════════════════════════

Uint8List _layout4(img.Image base, img.Image? sig, img.Image? logo,
    String name, String id, String date, String time) {
  final fW = base.width;
  final fH = base.height;
  final pW = (fW * 0.38).clamp(320.0, 700.0).toInt();
  final W  = fW + pW;
  final H  = fH;

  final canvas = img.Image(width: W, height: H);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(canvas, base, dstX: 0, dstY: 0);

  // Gradien vertikal ungu manual
  for (int y = 0; y < H; y++) {
    final t = y / H;
    final r = (72  + (108 - 72)  * t).round();
    final g = (26  + (52  - 26)  * t).round();
    final b = (107 + (131 - 107) * t).round();
    img.fillRect(canvas, x1: fW, y1: y, x2: W, y2: y + 1,
        color: img.ColorRgb8(r, g, b));
  }

  // Garis emas vertikal pemisah
  img.fillRect(canvas, x1: fW, y1: 0, x2: fW + 5, y2: H,
      color: img.ColorRgb8(212, 175, 55));

  final white = img.ColorRgb8(255, 255, 255);
  final gold  = img.ColorRgb8(212, 175, 55);
  final tX    = fW + 5 + 18;

  // Info
  img.drawString(canvas, 'TEKNISI',
      font: img.arial24, x: tX, y: 30, color: gold);
  img.drawString(canvas, name,
      font: img.arial48, x: tX, y: 58, color: white);

  // Garis tipis pemisah
  img.fillRect(canvas, x1: tX, y1: 118, x2: W - 18, y2: 121,
      color: img.ColorRgb8(212, 175, 55));

  img.drawString(canvas, 'NO. TIKET',
      font: img.arial24, x: tX, y: 132, color: gold);
  img.drawString(canvas, id,
      font: img.arial24, x: tX, y: 160, color: white);

  img.drawString(canvas, 'TANGGAL',
      font: img.arial24, x: tX, y: 203, color: gold);
  img.drawString(canvas, date,
      font: img.arial24, x: tX, y: 231, color: white);

  img.drawString(canvas, 'JAM',
      font: img.arial24, x: tX, y: 274, color: gold);
  img.drawString(canvas, time,
      font: img.arial24, x: tX, y: 302, color: white);

  img.fillRect(canvas, x1: tX, y1: 345, x2: W - 18, y2: 348,
      color: img.ColorRgb8(212, 175, 55));

  img.drawString(canvas, 'TANDA TANGAN',
      font: img.arial24, x: tX, y: 358, color: gold);

  if (sig != null) {
    final maxSigW = pW - 36 - 5;
    img.Image s   = sig;
    if (s.width > maxSigW) {
      s = img.copyResize(s, width: maxSigW, interpolation: img.Interpolation.linear);
    }
    img.compositeImage(canvas, s, dstX: tX, dstY: 392);
  }

  if (logo != null) {
    final l = img.copyResize(logo, width: 58, interpolation: img.Interpolation.linear);
    img.compositeImage(canvas, l, dstX: W - 58 - 18, dstY: H - 58 - 18);
  }
  return img.encodeJpg(canvas, quality: kJpegQuality);
}

// ═══════════════════════════════════════
// APP CORE
// ═══════════════════════════════════════

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B4F72)),
        useMaterial3: true,
      ),
      home: const Login(),
    );
  }
}

// ═══════════════════════════════════════
// LOGIN
// ═══════════════════════════════════════

class Login extends StatelessWidget {
  const Login({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TextEditingController();
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('TermulLog',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(controller: c,
                  decoration: const InputDecoration(
                      hintText: 'Nama Teknisi', border: OutlineInputBorder())),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => Dashboard(name: c.text)),
                  ),
                  child: const Text('Masuk'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════
// ITEM MODEL
// ═══════════════════════════════════════

class Item {
  final String id;
  final String path;
  final String time;
  Item(this.id, this.path, this.time);
  Map<String, dynamic> toJson() => {'id': id, 'path': path, 'time': time};
  factory Item.fromJson(Map<String, dynamic> j) => Item(j['id'], j['path'], j['time']);
}

// ═══════════════════════════════════════
// WATERMARK SETTING
// ═══════════════════════════════════════

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

// ═══════════════════════════════════════
// LOGO CACHE
// ═══════════════════════════════════════

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

// ═══════════════════════════════════════
// DASHBOARD
// ═══════════════════════════════════════

class Dashboard extends StatefulWidget {
  final String name;
  const Dashboard({super.key, required this.name});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  List<Item> list      = [];
  String?    _logoPath;

  @override
  void initState() {
    super.initState();
    WatermarkLayout.load();
  }

  Future<void> _capture() async {
    final picker = ImagePicker();
    final file   = await picker.pickImage(
      source:       ImageSource.camera,
      maxWidth:     kMaxOutputWidth.toDouble(),
      maxHeight:    kMaxOutputWidth.toDouble(),
      imageQuality: 90,
    );
    if (file == null || !mounted) return;

    final now  = DateTime.now();
    final id   = 'TRM-${now.millisecondsSinceEpoch}';
    final time = DateFormat('dd/MM HH:mm').format(now);

    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SignaturePage(
        imagePath: file.path,
        techName:  widget.name,
        itemId:    id,
        itemTime:  time,
        onDone: (path) => setState(() => list.add(Item(id, path, time))),
      ),
    ));
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final file   = await picker.pickImage(source: ImageSource.gallery, maxWidth: 200);
    if (file == null) return;
    setState(() => _logoPath = file.path);
    await LogoCache.load(file.path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
              icon: const Icon(Icons.image_outlined),
              onPressed: _pickLogo,
              tooltip: 'Pilih Logo'),
          IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsPage())),
              tooltip: 'Pengaturan Layout'),
        ],
      ),
      body: Column(
        children: [
          if (_logoPath != null)
            Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Image.file(File(_logoPath!), height: 36),
                const SizedBox(width: 8),
                const Text('Logo aktif', style: TextStyle(fontWeight: FontWeight.w500)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close, size: 18),
                    onPressed: () { setState(() => _logoPath = null); LogoCache.clear(); }),
              ]),
            ),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.photo_camera_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('Belum ada foto', style: TextStyle(color: Colors.grey)),
                    ]))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) => ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.file(File(list[i].path),
                            width: 56, height: 56, fit: BoxFit.cover),
                      ),
                      title:    Text(list[i].id),
                      subtitle: Text(list[i].time),
                    )),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _capture,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Ambil Foto'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════
// SETTINGS PAGE
// ═══════════════════════════════════════

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
      appBar: AppBar(title: const Text('Pilih Layout Watermark')),
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
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isActive ? info.accentColor : Colors.grey.shade300,
                  width: isActive ? 2.5 : 1,
                ),
                color: isActive
                    ? info.accentColor.withOpacity(0.06)
                    : Colors.white,
                boxShadow: isActive
                    ? [BoxShadow(
                        color: info.accentColor.withOpacity(0.18),
                        blurRadius: 12, offset: const Offset(0, 4))]
                    : [],
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Ikon
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                        color: info.accentColor,
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(info.icon, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),

                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: Text(info.label,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: isActive ? info.accentColor : Colors.black87))),
                        if (isActive)
                          Icon(Icons.check_circle_rounded,
                              color: info.accentColor, size: 22),
                      ]),
                      const SizedBox(height: 4),
                      Text(info.description,
                          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),

                      // Mini preview visual
                      const SizedBox(height: 10),
                      _LayoutPreviewBar(layoutId: info.id, accent: info.accentColor),
                    ],
                  )),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Mini preview bar tiap layout ──────────────────────────────────────────

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

  // LAYOUT 1: foto abu → strip navy → box abu-abu
  Widget _l1() => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Column(children: [
      _photoPlaceholder(28),
      _bar(14, const Color(0xFF1B4F72),
          child: _label('DELIVERY REPORT', Colors.white)),
      Container(height: 22, color: const Color(0xFFF0F0F0),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(children: [
            _pill(50, Colors.grey.shade400),
            const SizedBox(width: 6),
            _pill(35, Colors.grey.shade400),
          ])),
    ]),
  );

  // LAYOUT 2: foto abu → strip hijau
  Widget _l2() => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Column(children: [
      _photoPlaceholder(28),
      _bar(14, const Color(0xFF27AE60),
          child: _label('PEKERJAAN SELESAI', Colors.white)),
      Container(height: 22, color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(children: [
            _pill(45, Colors.grey.shade400),
            const SizedBox(width: 6),
            _pill(30, Colors.grey.shade400),
          ])),
    ]),
  );

  // LAYOUT 3: foto abu → garis emas → charcoal + bar emas kiri
  Widget _l3() => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Column(children: [
      _photoPlaceholder(28),
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

  // LAYOUT 4: [foto kiri | panel ungu kanan]
  Widget _l4() => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: SizedBox(
      height: 64,
      child: Row(children: [
        Expanded(flex: 3, child: _photoPlaceholder(64)),
        Container(width: 3, height: 64, color: const Color(0xFFD4AF37)),
        Expanded(flex: 2, child: Container(
          height: 64,
          decoration: const BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter,
            end:   Alignment.bottomCenter,
            colors: [Color(0xFF481A6B), Color(0xFF6C3483)],
          )),
          padding: const EdgeInsets.all(7),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
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

  // Helpers
  Widget _photoPlaceholder(double h) => Container(
    height: h, color: Colors.grey.shade300,
    child: const Center(child: Icon(Icons.image, size: 14, color: Colors.grey)),
  );

  Widget _bar(double h, Color color, {Widget? child}) => Container(
    height: h, color: color,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    alignment: Alignment.centerLeft,
    child: child,
  );

  Widget _label(String t, Color c) =>
      Text(t, style: TextStyle(color: c, fontSize: 6, fontWeight: FontWeight.bold));

  Widget _pill(double w, Color c) =>
      Container(height: 3, width: w, color: c);
}

// ═══════════════════════════════════════
// SIGNATURE PAGE
// ═══════════════════════════════════════

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
  final _sigCtrl  = SignatureController(penStrokeWidth: 3, penColor: Colors.black);
  bool    _loading  = false;
  String? _errorMsg;

  Future<void> _save() async {
    if (_sigCtrl.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Tanda tangan dulu ya!')));
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
      final file = File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(result);
      widget.onDone(file.path);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _errorMsg = 'Gagal: $e'; _loading = false; });
    }
  }

  @override
  void dispose() { _sigCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final activeLayout = kLayouts.firstWhere(
        (l) => l.id == WatermarkLayout.get(), orElse: () => kLayouts.first);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tanda Tangan'),
        actions: [
          TextButton(
            onPressed: _loading ? null : () => _sigCtrl.clear(),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 160, width: double.infinity,
          child: Image.file(File(widget.imagePath),
              fit: BoxFit.cover, cacheWidth: 600),
        ),

        // Badge layout aktif
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color:  activeLayout.accentColor.withOpacity(0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: activeLayout.accentColor.withOpacity(0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(activeLayout.icon, size: 14, color: activeLayout.accentColor),
            const SizedBox(width: 6),
            Text('Layout: ${activeLayout.label}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: activeLayout.accentColor)),
          ]),
        ),

        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text('Tanda tangan di bawah:',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ),

        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Signature(controller: _sigCtrl, backgroundColor: Colors.white),
            ),
          ),
        ),

        if (_errorMsg != null)
          Padding(padding: const EdgeInsets.all(8),
              child: Text(_errorMsg!, style: const TextStyle(color: Colors.red))),

        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const SizedBox(height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Simpan'),
            ),
          ),
        ),
      ]),
    );
  }
}
