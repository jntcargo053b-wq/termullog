import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:signature/signature.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const App());
}

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

/* ================= LOGIN ================= */

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final c = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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

/* ================= MODEL ================= */

class Record {
  final String id;
  final String path;
  final String time;

  Record(this.id, this.path, this.time);

  Map<String, dynamic> toJson() =>
      {"id": id, "path": path, "time": time};

  factory Record.fromJson(Map<String, dynamic> j) =>
      Record(j["id"], j["path"], j["time"]);
}

/* ================= WEATHER ================= */

class Weather {
  static Future<String?> get(double lat, double lng) async {
    final url = Uri.parse(
        "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lng&current_weather=true");

    final res = await http.get(url);
    if (res.statusCode == 200) {
      final d = jsonDecode(res.body);
      return "${d['current_weather']['temperature']}°C";
    }
    return null;
  }
}

/* ================= SETTINGS (ONLY LOGO) ================= */

class Settings extends StatefulWidget {
  final String? logo;

  const Settings({super.key, this.logo});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  String? logo;

  @override
  void initState() {
    super.initState();
    logo = widget.logo;
  }

  Future<void> pick() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (f == null) return;

    final p = await SharedPreferences.getInstance();
    await p.setString("logo", f.path);

    setState(() => logo = f.path);
  }

  Future<void> remove() async {
    final p = await SharedPreferences.getInstance();
    await p.remove("logo");
    setState(() => logo = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: Column(
        children: [
          const SizedBox(height: 20),
          CircleAvatar(
            radius: 40,
            backgroundImage:
                logo != null ? FileImage(File(logo!)) : null,
          ),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: pick, child: const Text("Change Logo")),
          if (logo != null)
            TextButton(onPressed: remove, child: const Text("Remove")),
        ],
      ),
    );
  }
}

/* ================= DASHBOARD ================= */

class Dashboard extends StatefulWidget {
  final String name;

  const Dashboard({super.key, required this.name});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  List<Record> list = [];
  bool loading = false;

  String? logo;
  String? signature;

  final sigCtrl = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
  );

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();

    logo = p.getString("logo");
    signature = p.getString("signature");

    final h = p.getStringList("history") ?? [];
    list = h.map((e) => Record.fromJson(jsonDecode(e))).toList();

    setState(() {});
  }

  Future<void> saveSig() async {
    if (sigCtrl.isEmpty) return;

    final bytes = await sigCtrl.toPngBytes();
    final dir = await getApplicationDocumentsDirectory();
    final f = File("${dir.path}/sig.png");

    await f.writeAsBytes(bytes!);

    final p = await SharedPreferences.getInstance();
    await p.setString("signature", f.path);

    signature = f.path;

    sigCtrl.clear();

    setState(() {});
  }

  Future<String> watermark(String path) async {
    final bytes = await File(path).readAsBytes();
    img.Image? i = img.decodeImage(bytes)!;

    final dir = await getApplicationDocumentsDirectory();
    final out = "${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg";

    final canvas = img.Image(width: i.width, height: i.height + 400);

    img.compositeImage(canvas, i);

    final sigFile = signature != null ? File(signature!) : null;
    img.Image? sigImg;

    if (sigFile != null && sigFile.existsSync()) {
      sigImg = img.decodeImage(await sigFile.readAsBytes());
    }

    if (sigImg != null) {
      final ratio = 0.3;
      final w = (sigImg.width * ratio).toInt();
      final h = (sigImg.height * ratio).toInt();

      final resized = img.copyResize(sigImg, width: w, height: h);

      img.compositeImage(
        canvas,
        resized,
        dstX: 50,
        dstY: i.height + 120,
      );
    }

    await File(out).writeAsBytes(img.encodeJpg(canvas));
    return out;
  }

  Future<void> capture() async {
    setState(() => loading = true);

    final f = await ImagePicker().pickImage(source: ImageSource.camera);
    if (f == null) return;

    final id = "TRM-${DateTime.now().millisecondsSinceEpoch}";
    final time = DateFormat("dd/MM HH:mm").format(DateTime.now());

    final out = await watermark(f.path);

    list.insert(0, Record(id, out, time));

    final p = await SharedPreferences.getInstance();
    await p.setStringList(
      "history",
      list.map((e) => jsonEncode(e.toJson())).toList(),
    );

    setState(() => loading = false);
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
              final r = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Settings(logo: logo),
                ),
              );

              if (r != null) load();
            },
          )
        ],
      ),
      body: Column(
        children: [
          /* ===== SIGNATURE DIRECT ===== */
          Container(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Signature(
                    controller: sigCtrl,
                    backgroundColor: Colors.white,
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => sigCtrl.clear(),
                        child: const Text("Clear"),
                      ),
                    ),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: saveSig,
                        child: const Text("Save TTD"),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),

          ElevatedButton(
            onPressed: loading ? null : capture,
            child: const Text("Capture"),
          ),

          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final d = list[i];

                return ListTile(
                  title: Text(d.id),
                  subtitle: Text(d.time),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.share),
                        onPressed: () =>
                            Share.shareXFiles([XFile(d.path)]),
                      ),
                      IconButton(
                        icon: const Icon(Icons.download),
                        onPressed: () =>
                            GallerySaver.saveImage(d.path),
                      ),
                    ],
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}
