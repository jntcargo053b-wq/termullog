import 'package:flutter/services.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:share_plus/share_plus.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const TermulLogApp());
}

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
          seedColor: Colors.blue,
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

// ================= LOGIN =================

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
              size: 100,
              color: Colors.blue,
            ),

            const SizedBox(height: 30),

            TextField(
              controller: controller,
              decoration:
                  const InputDecoration(
                labelText: 'Nama Kurir',
                border: OutlineInputBorder(),
                prefixIcon:
                    Icon(Icons.person),
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: login,
                icon: const Icon(Icons.login),
                label: const Text(
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

// ================= MODEL =================

class DeliveryRecord {
  final String deliveryId;
  final String imagePath;
  final String timestamp;
  final String? weather;
  final String? address;

  DeliveryRecord({
    required this.deliveryId,
    required this.imagePath,
    required this.timestamp,
    this.weather,
    this.address,
  });
}

// ================= DELIVERY ID =================

class DeliveryIdGenerator {
  static String generate() {
    final now = DateTime.now();

    return 'TRM-${DateFormat('yyyyMMdd-HHmmssSSS').format(now)}';
  }
}

// ================= WEATHER =================

class WeatherData {
  final double temperature;
  final double windspeed;

  WeatherData({
    required this.temperature,
    required this.windspeed,
  });

  String get text =>
      '${temperature.toStringAsFixed(1)}°C | '
      'Angin ${windspeed.toStringAsFixed(0)} km/h';
}

class WeatherHelper {
  static Future<WeatherData?> fetch(
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

        final cw =
            data['current_weather'];

        if (cw != null) {
          return WeatherData(
            temperature:
                (cw['temperature'] as num)
                    .toDouble(),
            windspeed:
                (cw['windspeed'] as num)
                    .toDouble(),
          );
        }
      }
    } catch (_) {}

    return null;
  }
}

// ================= LOAD LOGO =================

Future<img.Image?> loadLogo() async {
  try {
    final data =
        await rootBundle.load(
      'assets/logo.png',
    );

    return img.decodeImage(
      data.buffer.asUint8List(),
    );
  } catch (_) {
    return null;
  }
}

// ================= TEXT WRAP =================

List<String> wrapText(
  String text,
  int maxLength,
) {
  final words = text.split(' ');

  List<String> lines = [];

  String currentLine = '';

  for (final word in words) {
    final testLine =
        '$currentLine $word';

    if (testLine.length > maxLength) {
      lines.add(currentLine.trim());

      currentLine = word;
    } else {
      currentLine = testLine;
    }
  }

  if (currentLine.isNotEmpty) {
    lines.add(currentLine.trim());
  }

  return lines;
}

// ================= WATERMARK =================

Future<String> addWatermark({
  required String deliveryId,
  required String imagePath,
  required String kurirName,
  required String timestamp,
  required String? weather,
  required String? address,
  required double? lat,
  required double? lng,
}) async {
  final bytes =
      await File(imagePath).readAsBytes();

  img.Image? original =
      img.decodeImage(bytes);

  if (original == null) {
    throw Exception('Gagal membaca gambar');
  }

  if (original.width > 1080) {
    original = img.copyResize(
      original,
      width: 1080,
    );
  }

  final logo = await loadLogo();

  const panelHeight = 420;

  final canvas = img.Image(
    width: original.width,
    height:
        original.height + panelHeight,
  );

  img.compositeImage(
    canvas,
    original,
  );

  // PANEL BG
  img.fillRect(
    canvas,
    x1: 0,
    y1: original.height,
    x2: original.width,
    y2:
        original.height + panelHeight,
    color: img.ColorRgb8(
      18,
      22,
      28,
    ),
  );

  // TOP LINE
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
  if (logo != null) {
    final resizedLogo =
        img.copyResize(
      logo,
      width: 220,
    );

    img.compositeImage(
      canvas,
      resizedLogo,
      dstX: 20,
      dstY: original.height + 30,
    );
  }

  final textX = 270;

  int y = original.height + 30;

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

  y += 70;

  // ID
  img.drawString(
    canvas,
    deliveryId,
    font: img.arial24,
    x: textX,
    y: y,
    color: img.ColorRgb8(
      180,
      180,
      180,
    ),
  );

  y += 40;

  // KURIR
  img.drawString(
    canvas,
    'Kurir : $kurirName',
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

  // WAKTU
  img.drawString(
    canvas,
    'Waktu : $timestamp',
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

  // GPS
  final gps =
      lat != null && lng != null
          ? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
          : 'Tidak tersedia';

  img.drawString(
    canvas,
    'GPS : $gps',
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

  // WEATHER
  img.drawString(
    canvas,
    'Cuaca : ${weather ?? "-"}',
    font: img.arial24,
    x: textX,
    y: y,
    color: img.ColorRgb8(
      255,
      255,
      255,
    ),
  );

  y += 45;

  // ADDRESS TITLE
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

  // WRAP ADDRESS
  final lines = wrapText(
    address ?? 'Tidak tersedia',
    42,
  );

  for (final line in lines) {
    img.drawString(
      canvas,
      line,
      font: img.arial24,
      x: textX,
      y: y,
      color: img.ColorRgb8(
        255,
        255,
        255,
      ),
    );

    y += 32;
  }

  final dir =
      await getApplicationDocumentsDirectory();

  final path =
      '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';

  await File(path).writeAsBytes(
    img.encodeJpg(
      canvas,
      quality: 92,
    ),
  );

  return path;
}

// ================= DASHBOARD =================

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
                .checkPermission();

        if (permission ==
            LocationPermission.denied) {
          permission =
              await Geolocator
                  .requestPermission();
        }

        if (permission ==
                LocationPermission
                    .always ||
            permission ==
                LocationPermission
                    .whileInUse) {
          final pos =
              await Geolocator
                  .getCurrentPosition(
            desiredAccuracy:
                LocationAccuracy.high,
          );

          lat = pos.latitude;
          lng = pos.longitude;

          // ADDRESS
          try {
            final placemarks =
                await placemarkFromCoordinates(
              lat,
              lng,
            );

            if (placemarks.isNotEmpty) {
              final p =
                  placemarks.first;

              address = [
                p.street,
                p.subLocality,
                p.locality,
              ]
                  .where(
                    (e) =>
                        e != null &&
                        e.isNotEmpty,
                  )
                  .join(', ');
            }
          } catch (_) {}

          // WEATHER
          try {
            final w =
                await WeatherHelper.fetch(
              lat,
              lng,
            );

            if (w != null) {
              weather = w.text;
            }
          } catch (_) {}
        }
      } catch (_) {}

      final timestamp = DateFormat(
        'dd/MM/yyyy HH:mm:ss',
      ).format(DateTime.now());

      final deliveryId =
          DeliveryIdGenerator.generate();

      final finalPath =
          await addWatermark(
        deliveryId: deliveryId,
        imagePath: photo.path,
        kurirName: widget.name,
        timestamp: timestamp,
        weather: weather,
        address: address,
        lat: lat,
        lng: lng,
      );

      deliveries.insert(
        0,
        DeliveryRecord(
          deliveryId: deliveryId,
          imagePath: finalPath,
          timestamp: timestamp,
          weather: weather,
          address: address,
        ),
      );

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

  // SAVE

  Future<void> saveToGallery(
    String path,
  ) async {
    await GallerySaver.saveImage(path);

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      const SnackBar(
        content: Text(
          'Berhasil disimpan ke galeri',
        ),
      ),
    );
  }

  // SHARE

  Future<void> shareImage(
    String path,
  ) async {
    await Share.shareXFiles([
      XFile(path),
    ]);
  }

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
            child: SizedBox(
              width: double.infinity,
              height: 55,
              child:
                  ElevatedButton.icon(
                onPressed: loading
                    ? null
                    : captureDelivery,
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
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
                      ? 'Memproses...'
                      : '+ FOTO BUKTI KIRIM',
                ),
              ),
            ),
          ),

          Expanded(
            child: deliveries.isEmpty
                ? const Center(
                    child: Text(
                      'Belum ada kiriman',
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
                        elevation: 4,
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
                                    height: 6,
                                  ),

                                  Text(
                                    d.timestamp,
                                  ),

                                  const SizedBox(
                                    height: 12,
                                  ),

                                  Row(
                                    children: [
                                      Expanded(
                                        child:
                                            ElevatedButton.icon(
                                          onPressed:
                                              () =>
                                                  saveToGallery(
                                            d.imagePath,
                                          ),
                                          icon:
                                              const Icon(
                                            Icons
                                                .save_alt,
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
