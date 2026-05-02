// =======================
// TERMULLOG PREMIUM FULL FIX
// CUSTOM LOGO PERSISTENT
// SIGNATURE WHITE BACKGROUND
// HISTORY PHOTO
// SAVE + SHARE
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
          seedColor: Colors.orange,
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
  State<LoginScreen> createState() =>
      _LoginScreenState();
}

class _LoginScreenState
    extends State<LoginScreen> {
  final controller = TextEditingController();

  void login() {
    if (controller.text.trim().isEmpty) {
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DashboardScreen(
          name: controller.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.local_shipping,
              size: 110,
              color: Colors.orange,
            ),

            const SizedBox(height: 30),

            TextField(
              controller: controller,
              decoration:
                  const InputDecoration(
                labelText: 'Nama Kurir',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: login,
                child: const Text(
                  'MASUK',
                  style: TextStyle(
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          ],
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

  Map<String, dynamic> toJson() {
    return {
      'deliveryId': deliveryId,
      'imagePath': imagePath,
      'timestamp': timestamp,
    };
  }

  factory DeliveryRecord.fromJson(
    Map<String, dynamic> json,
  ) {
    return DeliveryRecord(
      deliveryId: json['deliveryId'],
      imagePath: json['imagePath'],
      timestamp: json['timestamp'],
    );
  }
}

// =======================
// WEATHER
// =======================

class WeatherHelper {
  static Future<String?> fetch(
    double lat,
    double lng,
  ) async {
    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat'
        '&longitude=$lng'
        '&current_weather=true',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data =
            jsonDecode(response.body);

        final current =
            data['current_weather'];

        return
            '${current['temperature']}°C';
      }
    } catch (_) {}

    return null;
  }
}

// =======================
// LOAD LOGO
// =======================

Future<img.Image?> loadLogo(
  String? path,
) async {
  try {
    if (path != null &&
        File(path).existsSync()) {
      final bytes =
          await File(path).readAsBytes();

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
  final bytes =
      await File(imagePath).readAsBytes();

  img.Image? original =
      img.decodeImage(bytes);

  if (original == null) {
    throw Exception(
      'Gagal membaca gambar',
    );
  }

  if (original.width > 1080) {
    original = img.copyResize(
      original,
      width: 1080,
    );
  }

  const panelHeight = 430;

  final canvas = img.Image(
    width: original.width,
    height:
        original.height + panelHeight,
  );

  // FOTO

  img.compositeImage(
    canvas,
    original,
  );

  // PANEL

  img.fillRect(
    canvas,
    x1: 0,
    y1: original.height,
    x2: original.width,
    y2:
        original.height + panelHeight,
    color: img.ColorRgb8(
      20,
      20,
      20,
    ),
  );

  // GARIS ATAS

  img.fillRect(
    canvas,
    x1: 0,
    y1: original.height,
    x2: original.width,
    y2: original.height + 8,
    color: img.ColorRgb8(
      255,
      180,
      0,
    ),
  );

  // LOGO

  final logo =
      await loadLogo(logoPath);

  if (logo != null) {
    final resized =
        img.copyResize(
      logo,
      width: 220,
    );

    img.compositeImage(
      canvas,
      resized,
      dstX: 20,
      dstY: original.height + 30,
    );
  }

  int y = original.height + 30;

  const textX = 280;

  // TITLE

  img.drawString(
    canvas,
    'DELIVERY REPORT',
    font: img.arial48,
    x: textX,
    y: y,
    color: img.ColorRgb8(
      255,
      210,
      0,
    ),
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
      color: img.ColorRgb8(
        255,
        255,
        255,
      ),
    );

    y += 40;
  }

  // ALAMAT

  img.drawString(
    canvas,
    'Alamat :',
    font: img.arial24,
    x: textX,
    y: y,
    color: img.ColorRgb8(
      255,
      210,
      0,
    ),
  );

  y += 35;

  final addr =
      address ?? 'Tidak tersedia';

  final words = addr.split(' ');

  String line = '';

  for (final word in words) {
    final test =
        '$line $word';

    if (test.length > 42) {
      img.drawString(
        canvas,
        line.trim(),
        font: img.arial24,
        x: textX,
        y: y,
        color: img.ColorRgb8(
          255,
          255,
          255,
        ),
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
      color: img.ColorRgb8(
        255,
        255,
        255,
      ),
    );
  }

  // =======================
  // SIGNATURE
  // =======================

  if (signaturePath != null &&
      File(signaturePath).existsSync()) {
    final sigBytes =
        await File(signaturePath)
            .readAsBytes();

    final sig =
        img.decodeImage(sigBytes);

    if (sig != null) {
      final resizedSig =
          img.copyResize(
        sig,
        width: 220,
      );

      final signatureX =
          original.width - 260;

      final signatureY =
          original.height + 250;

      // BACKGROUND PUTIH

      img.fillRect(
        canvas,
        x1: signatureX - 10,
        y1: signatureY - 10,
        x2: signatureX + 230,
        y2: signatureY + 120,
        color: img.ColorRgb8(
          255,
          255,
          255,
        ),
      );

      img.compositeImage(
        canvas,
        resizedSig,
        dstX: signatureX,
        dstY: signatureY,
      );
    }
  }

  final dir =
      await getApplicationDocumentsDirectory();

  final output =
      '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';

  await File(output).writeAsBytes(
    img.encodeJpg(
      canvas,
      quality: 92,
    ),
  );

  return output;
}

// =======================
// DASHBOARD
// =======================

class DashboardScreen extends StatefulWidget {
  final String name;

  const DashboardScreen({
    super.key,
    required this.name,
  });

  @override
  State<DashboardScreen> createState() =>
      _DashboardScreenState();
}

class _DashboardScreenState
    extends State<DashboardScreen> {
  final deliveries =
      <DeliveryRecord>[];

  bool loading = false;

  String? customLogoPath;

  String? signaturePath;

  final SignatureController
      signatureController =
      SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
  );

  @override
  void initState() {
    super.initState();

    loadData();
  }

  // =======================
  // LOAD DATA
  // =======================

  Future<void> loadData() async {
    final prefs =
        await SharedPreferences
            .getInstance();

    customLogoPath =
        prefs.getString(
      'custom_logo',
    );

    signaturePath =
        prefs.getString(
      'signature',
    );

    final history =
        prefs.getStringList(
              'history',
            ) ??
            [];

    deliveries.clear();

    for (final item in history) {
      deliveries.add(
        DeliveryRecord.fromJson(
          jsonDecode(item),
        ),
      );
    }

    setState(() {});
  }

  // =======================
  // SAVE HISTORY
  // =======================

  Future<void> saveHistory() async {
    final prefs =
        await SharedPreferences
            .getInstance();

    final list = deliveries
        .map(
          (e) => jsonEncode(
            e.toJson(),
          ),
        )
        .toList();

    await prefs.setStringList(
      'history',
      list,
    );
  }

  // =======================
  // PICK LOGO
  // =======================

  Future<void> pickLogo() async {
    final picker = ImagePicker();

    final file =
        await picker.pickImage(
      source: ImageSource.gallery,
    );

    if (file == null) return;

    final prefs =
        await SharedPreferences
            .getInstance();

    await prefs.setString(
      'custom_logo',
      file.path,
    );

    setState(() {
      customLogoPath = file.path;
    });
  }

  // =======================
  // SIGNATURE
  // =======================

  Future<void> openSignature() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title:
                const Text('Tanda Tangan'),
          ),
          body: Column(
            children: [
              Expanded(
                child: Signature(
                  controller:
                      signatureController,
                  backgroundColor:
                      Colors.white,
                ),
              ),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        signatureController
                            .clear();
                      },
                      child: const Text(
                        'CLEAR',
                      ),
                    ),
                  ),

                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final bytes =
                            await signatureController
                                .toPngBytes();

                        if (bytes == null) {
                          return;
                        }

                        final dir =
                            await getApplicationDocumentsDirectory();

                        final file = File(
                          '${dir.path}/signature.png',
                        );

                        await file
                            .writeAsBytes(
                          bytes,
                        );

                        final prefs =
                            await SharedPreferences
                                .getInstance();

                        await prefs.setString(
                          'signature',
                          file.path,
                        );

                        setState(() {
                          signaturePath =
                              file.path;
                        });

                        if (mounted) {
                          Navigator.pop(
                            context,
                          );
                        }
                      },
                      child: const Text(
                        'SIMPAN',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =======================
  // CAPTURE
  // =======================

  Future<void> captureDelivery() async {
    setState(() {
      loading = true;
    });

    try {
      final picker = ImagePicker();

      final photo =
          await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );

      if (photo == null) {
        setState(() {
          loading = false;
        });

        return;
      }

      double? lat;
      double? lng;

      String? address;
      String? weather;

      try {
        LocationPermission permission =
            await Geolocator
                .requestPermission();

        if (permission ==
                LocationPermission
                    .whileInUse ||
            permission ==
                LocationPermission
                    .always) {
          final pos =
              await Geolocator
                  .getCurrentPosition();

          lat = pos.latitude;
          lng = pos.longitude;

          final placemarks =
              await placemarkFromCoordinates(
            lat,
            lng,
          );

          if (placemarks.isNotEmpty) {
            final p =
                placemarks.first;

            address =
                '${p.street}, ${p.locality}';
          }

          weather =
              await WeatherHelper.fetch(
            lat,
            lng,
          );
        }
      } catch (_) {}

      final timestamp = DateFormat(
        'dd/MM/yyyy HH:mm:ss',
      ).format(DateTime.now());

      final deliveryId =
          'TRM-${DateTime.now().millisecondsSinceEpoch}';

      final finalPath =
          await addWatermark(
        imagePath: photo.path,
        kurir: widget.name,
        deliveryId: deliveryId,
        timestamp: timestamp,
        address: address,
        weather: weather,
        lat: lat,
        lng: lng,
        logoPath: customLogoPath,
        signaturePath:
            signaturePath,
      );

      final record =
          DeliveryRecord(
        deliveryId: deliveryId,
        imagePath: finalPath,
        timestamp: timestamp,
      );

      deliveries.insert(
        0,
        record,
      );

      await saveHistory();

      setState(() {
        loading = false;
      });
    } catch (e) {
      debugPrint(e.toString());

      setState(() {
        loading = false;
      });
    }
  }

  // =======================
  // SAVE IMAGE
  // =======================

  Future<void> saveImage(
    String path,
  ) async {
    await GallerySaver.saveImage(path);

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      const SnackBar(
        content: Text(
          'Berhasil disimpan',
        ),
      ),
    );
  }

  // =======================
  // SHARE
  // =======================

  Future<void> shareImage(
    String path,
  ) async {
    await Share.shareXFiles([
      XFile(path),
    ]);
  }

  // =======================
  // UI
  // =======================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('TermulLog Dashboard'),
      ),

      body: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child:
                          ElevatedButton.icon(
                        onPressed:
                            pickLogo,
                        icon: const Icon(
                          Icons.image,
                        ),
                        label: const Text(
                          'GANTI LOGO',
                        ),
                      ),
                    ),

                    const SizedBox(
                      width: 10,
                    ),

                    Expanded(
                      child:
                          ElevatedButton.icon(
                        onPressed:
                            openSignature,
                        icon: const Icon(
                          Icons.draw,
                        ),
                        label: const Text(
                          'TANDA TANGAN',
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child:
                      ElevatedButton.icon(
                    onPressed: loading
                        ? null
                        : captureDelivery,
                    icon: loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt,
                          ),
                    label: Text(
                      loading
                          ? 'MEMPROSES...'
                          : '+ FOTO BUKTI',
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: deliveries.isEmpty
                ? const Center(
                    child: Text(
                      'Belum ada data',
                    ),
                  )
                : ListView.builder(
                    itemCount:
                        deliveries.length,
                    itemBuilder:
                        (_, index) {
                      final d =
                          deliveries[index];

                      return Card(
                        margin:
                            const EdgeInsets
                                .all(12),

                        child: Column(
                          children: [
                            Image.file(
                              File(
                                d.imagePath,
                              ),
                            ),

                            Padding(
                              padding:
                                  const EdgeInsets
                                      .all(12),

                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,

                                children: [
                                  Text(
                                    d.deliveryId,
                                    style:
                                        const TextStyle(
                                      fontWeight:
                                          FontWeight
                                              .bold,
                                    ),
                                  ),

                                  const SizedBox(
                                      height: 5),

                                  Text(
                                      d.timestamp),

                                  const SizedBox(
                                      height: 12),

                                  Row(
                                    children: [
                                      Expanded(
                                        child:
                                            ElevatedButton.icon(
                                          onPressed:
                                              () =>
                                                  saveImage(
                                            d.imagePath,
                                          ),
                                          icon:
                                              const Icon(
                                            Icons
                                                .save,
                                          ),
                                          label:
                                              const Text(
                                            'SAVE',
                                          ),
                                        ),
                                      ),

                                      const SizedBox(
                                        width: 10,
                                      ),

                                      Expanded(
                                        child:
                                            ElevatedButton.icon(
                                          onPressed:
                                              () =>
                                                  shareImage(
                                            d.imagePath,
                                          ),
                                          icon:
                                              const Icon(
                                            Icons
                                                .share,
                                          ),
                                          label:
                                              const Text(
                                            'SHARE',
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
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
