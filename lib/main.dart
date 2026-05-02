import 'dart:convert';
import 'dart:io';

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

// ================= APP =================

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Login(),
    );
  }
}

// ================= LOGIN =================

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
              const Text("TermulLog",
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
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
                child: const Text("Masuk"),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ================= MODEL =================

class Item {
  final String id;
  final String path;
  final String time;

  Item(this.id, this.path, this.time);

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'time': time,
      };

  factory Item.fromJson(Map<String, dynamic> j) =>
      Item(j['id'], j['path'], j['time']);
}

// ================= DASHBOARD =================

class Dashboard extends StatefulWidget {
  final String name;
  const Dashboard({super.key, required this.name});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  List<Item> list = [];
  String? logo;
  int tab = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  // ================= LOAD FIX =================

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();

    logo = p.getString('logo');

    final data = p.getStringList('data') ?? [];

    list = [];

    for (final e in data) {
      try {
        final decoded = jsonDecode(e);
        list.add(Item.fromJson(Map<String, dynamic>.from(decoded)));
      } catch (_) {}
    }

    setState(() {});
  }

  // ================= SAVE FIX =================

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();

    final encoded = list.map((e) => jsonEncode(e.toJson())).toList();

    await p.setStringList('data', encoded);
  }

  // ================= CAPTURE =================

  Future<void> capture() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.camera);
    if (file == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SignaturePage(
          imagePath: file.path,
          logoPath: logo,
          onDone: (finalPath) async {
            list.insert(
              0,
              Item(
                "TRM-${DateTime.now().millisecondsSinceEpoch}",
                finalPath,
                DateFormat('dd/MM HH:mm').format(DateTime.now()),
              ),
            );

            await save();
            setState(() => tab = 1);
          },
        ),
      ),
    );
  }

  Future<void> saveImage(String path) async {
    await GallerySaver.saveImage(path);
  }

  Future<void> shareImage(String path) async {
    await Share.shareXFiles([XFile(path)]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              final picker = ImagePicker();
              final f =
                  await picker.pickImage(source: ImageSource.gallery);
              if (f == null) return;

              final p = await SharedPreferences.getInstance();
              await p.setString('logo', f.path);
              logo = f.path;

              setState(() {});
            },
          )
        ],
      ),
      body: tab == 0 ? captureUI() : galleryUI(),
    );
  }

  // ================= UI =================

  Widget captureUI() {
    return Center(
      child: ElevatedButton.icon(
        onPressed: capture,
        icon: const Icon(Icons.camera),
        label: const Text("Ambil Foto"),
      ),
    );
  }

  Widget galleryUI() {
    if (list.isEmpty) return const Center(child: Text("Kosong"));

    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final d = list[i];

        return Card(
          child: Column(
            children: [
              Image.file(File(d.path)),
              Text(d.id),
              Text(d.time),
              Row(
                children: [
                  TextButton(
                    onPressed: () => saveImage(d.path),
                    child: const Text("Save"),
                  ),
                  TextButton(
                    onPressed: () => shareImage(d.path),
                    child: const Text("Share"),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
  }
}

// ================= SIGNATURE PAGE =================

class SignaturePage extends StatefulWidget {
  final String imagePath;
  final String? logoPath;
  final Function(String) onDone;

  const SignaturePage({
    super.key,
    required this.imagePath,
    required this.logoPath,
    required this.onDone,
  });

  @override
  State<SignaturePage> createState() => _SignaturePageState();
}

class _SignaturePageState extends State<SignaturePage> {
  final controller = SignatureController(
    penStrokeWidth: 4,
    penColor: Colors.black,
  );

  Future<void> finish() async {
    if (controller.isEmpty) return;

    final sigBytes = await controller.toPngBytes();
    final sig = img.decodeImage(sigBytes!);

    final imgBytes = await File(widget.imagePath).readAsBytes();
    final base = img.decodeImage(imgBytes)!;

    final canvas =
        img.Image(width: base.width, height: base.height + 300);

    img.compositeImage(canvas, base);

    // LOGO
    if (widget.logoPath != null) {
      final l = img.decodeImage(
        await File(widget.logoPath!).readAsBytes(),
      );
      if (l != null) {
        final r = img.copyResize(l, width: 80);
        img.compositeImage(canvas, r,
            dstX: 20, dstY: base.height + 20);
      }
    }

    // SIGNATURE (PROPORSIONAL)
    if (sig != null) {
      final ratio = base.width / sig.width;
      final resized = img.copyResize(
        sig,
        width: (sig.width * ratio * 0.7).toInt(),
      );

      img.compositeImage(
        canvas,
        resized,
        dstX: 20,
        dstY: base.height + 120,
      );
    }

    final out =
        '${(await getApplicationDocumentsDirectory()).path}/${DateTime.now().millisecondsSinceEpoch}.jpg';

    await File(out).writeAsBytes(img.encodeJpg(canvas));

    controller.clear();

    widget.onDone(out);

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Tanda Tangan")),
      body: Column(
        children: [
          Expanded(
            child: Signature(
              controller: controller,
              backgroundColor: Colors.white,
            ),
          ),
          ElevatedButton(
            onPressed: finish,
            child: const Text("Simpan"),
          )
        ],
      ),
    );
  }
}
