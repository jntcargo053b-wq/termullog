import 'dart:convert';
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
// WATERMARK ENGINE (ISOLATE)
// ═══════════════════════════════════════

Uint8List _processWatermark(Map<String, dynamic> p) {
  final base = img.decodeImage(p['imageBytes'])!;
  final sigBytes = p['sigBytes'] as Uint8List?;
  final logoBytes = p['logoBytes'] as Uint8List?;

  final sig = sigBytes != null ? img.decodeImage(sigBytes) : null;
  final logo = logoBytes != null ? img.decodeImage(logoBytes) : null;

  final layout = p['layout'] ?? 'layout1';

  return layout == 'layout2'
      ? _layout2(base, sig, logo, p['name'], p['id'], p['date'], p['time'])
      : _layout1(base, sig, logo, p['name'], p['id'], p['date'], p['time']);
}

// ═══════════════════════════════════════
// LAYOUT 1 (PROFESSIONAL REPORT)
// ═══════════════════════════════════════

Uint8List _layout1(
  img.Image base,
  img.Image? sig,
  img.Image? logo,
  String name,
  String id,
  String date,
  String time,
) {
  final W = base.width;
  final H = base.height;
  final S = (W * 0.22).clamp(280.0, 800.0).toInt();

  final canvas = img.Image(width: W, height: H + S);

  // FIX: wajib putih biar watermark tidak hilang
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

  img.compositeImage(canvas, base, dstX: 0, dstY: 0);

  final navy = img.ColorRgb8(27, 79, 114);
  final white = img.ColorRgb8(255, 255, 255);
  final gray = img.ColorRgb8(240, 240, 240);

  final wY = H;

  // HEADER
  img.fillRect(canvas, x1: 0, y1: wY, x2: W, y2: wY + 90, color: navy);

  img.drawString(canvas, 'DELIVERY REPORT',
      font: img.arial48, x: 20, y: wY + 25, color: white);

  img.drawString(canvas, '$date  $time',
      font: img.arial24, x: W - 280, y: wY + 30, color: white);

  // INFO BOX
  final infoY = wY + 100;

  img.fillRect(canvas,
      x1: 0, y1: infoY, x2: W, y2: infoY + 140, color: gray);

  img.drawString(canvas, 'TEKNISI: $name',
      font: img.arial24, x: 20, y: infoY + 20);

  img.drawString(canvas, 'ID: $id',
      font: img.arial24, x: 20, y: infoY + 60);

  img.drawString(canvas, 'WAKTU: $date $time',
      font: img.arial24, x: 20, y: infoY + 100);

  // SIGNATURE
  if (sig != null) {
    final sigR = img.copyResize(sig, width: (W * 0.5).toInt());
    img.compositeImage(canvas, sigR,
        dstX: 20, dstY: infoY + 160);
  }

  // LOGO
  if (logo != null) {
    final l = img.copyResize(logo, width: 80);
    img.compositeImage(canvas, l,
        dstX: W - 100, dstY: infoY + 20);
  }

  return img.encodeJpg(canvas, quality: 92);
}

// ═══════════════════════════════════════
// LAYOUT 2 (COMPACT FIELD REPORT)
// ═══════════════════════════════════════

Uint8List _layout2(
  img.Image base,
  img.Image? sig,
  img.Image? logo,
  String name,
  String id,
  String date,
  String time,
) {
  final W = base.width;
  final H = base.height;
  final S = (W * 0.20).clamp(250.0, 700.0).toInt();

  final canvas = img.Image(width: W, height: H + S);

  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

  img.compositeImage(canvas, base, dstX: 0, dstY: 0);

  final green = img.ColorRgb8(39, 174, 96);

  final wY = H;

  img.fillRect(canvas, x1: 0, y1: wY, x2: W, y2: wY + 70, color: green);

  img.drawString(canvas, 'PEKERJAAN SELESAI',
      font: img.arial48, x: 20, y: wY + 15);

  final infoY = wY + 90;

  img.drawString(canvas, 'Teknisi: $name',
      font: img.arial24, x: 20, y: infoY);

  img.drawString(canvas, 'ID: $id',
      font: img.arial24, x: 20, y: infoY + 50);

  img.drawString(canvas, 'Waktu: $date $time',
      font: img.arial24, x: 20, y: infoY + 100);

  if (sig != null) {
    final sigR = img.copyResize(sig, width: (W * 0.4).toInt());
    img.compositeImage(canvas, sigR,
        dstX: 20, dstY: infoY + 150);
  }

  if (logo != null) {
    final l = img.copyResize(logo, width: 70);
    img.compositeImage(canvas, l,
        dstX: W - 90, dstY: infoY + 10);
  }

  return img.encodeJpg(canvas, quality: 92);
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
              TextField(controller: c),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Dashboard(name: c.text),
                    ),
                  );
                },
                child: const Text('Masuk'),
              )
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

  Map<String, dynamic> toJson() =>
      {'id': id, 'path': path, 'time': time};

  factory Item.fromJson(Map<String, dynamic> j) =>
      Item(j['id'], j['path'], j['time']);
}

// ═══════════════════════════════════════
// WATERMARK SETTING
// ═══════════════════════════════════════

class WatermarkLayout {
  static String layout = 'layout1';

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    layout = p.getString('layout') ?? 'layout1';
  }

  static Future<void> set(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('layout', v);
    layout = v;
  }

  static String get() => layout;
}

// ═══════════════════════════════════════
// DASHBOARD
// (SIMPLE VERSION BIAR FOKUS FIX ENGINE)
// ═══════════════════════════════════════

class Dashboard extends StatefulWidget {
  final String name;
  const Dashboard({super.key, required this.name});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  List<Item> list = [];
  String? logo;

  Future<void> _capture() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.camera);
    if (file == null) return;

    final now = DateTime.now();
    final id = 'TRM-${now.millisecondsSinceEpoch}';
    final time = DateFormat('dd/MM HH:mm').format(now);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SignaturePage(
          imagePath: file.path,
          logoPath: logo,
          techName: widget.name,
          itemId: id,
          itemTime: time,
          onDone: (path) {
            setState(() {
              list.add(Item(id, path, time));
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: Center(
        child: ElevatedButton(
          onPressed: _capture,
          child: const Text('Ambil Foto'),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════
// SIGNATURE PAGE
// ═══════════════════════════════════════

class SignaturePage extends StatefulWidget {
  final String imagePath;
  final String? logoPath;
  final String techName;
  final String itemId;
  final String itemTime;
  final Function(String) onDone;

  const SignaturePage({
    super.key,
    required this.imagePath,
    required this.logoPath,
    required this.techName,
    required this.itemId,
    required this.itemTime,
    required this.onDone,
  });

  @override
  State<SignaturePage> createState() => _SignaturePageState();
}

class _SignaturePageState extends State<SignaturePage> {
  final controller = SignatureController(
      penStrokeWidth: 3, penColor: Colors.black);

  bool loading = false;

  Future<void> _save() async {
    setState(() => loading = true);

    final imgBytes = await File(widget.imagePath).readAsBytes();
    final sigBytes = await controller.toPngBytes();

    final parts = widget.itemTime.split(' ');

    final result = await compute(_processWatermark, {
      'imageBytes': imgBytes,
      'sigBytes': sigBytes,
      'logoBytes': widget.logoPath != null
          ? await File(widget.logoPath!).readAsBytes()
          : null,
      'layout': WatermarkLayout.get(),
      'name': widget.techName,
      'id': widget.itemId,
      'date': parts[0],
      'time': parts.length > 1 ? parts[1] : '',
    });

    final dir = await getTemporaryDirectory();
    final file =
        File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg');

    await file.writeAsBytes(result);

    widget.onDone(file.path);

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signature')),
      body: Column(
        children: [
          Expanded(child: Signature(controller: controller)),
          ElevatedButton(
            onPressed: loading ? null : _save,
            child: const Text('Simpan'),
          )
        ],
      ),
    );
  }
}
