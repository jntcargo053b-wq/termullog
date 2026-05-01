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

const String kUploadEndpoint = '';

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
      appBar: AppBar(
        title: const Text('TermulLog'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.local_shipping,
              size: 80,
              color: Colors.blue,
            ),

            const SizedBox(height: 24),

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
              child: ElevatedButton.icon(
                onPressed: login,
                icon: const Icon(Icons.login),
                label: const Text('MASUK'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

class DeliveryIdGenerator {
  static String generate() {
    final now = DateTime.now();

    return 'TRM-${DateFormat('yyyyMMdd-HHmmssSSS').format(now)}';
  }
}

class WeatherData {
  final double temperature;
  final double windspeed;
  final String label;
  final String emoji;

  WeatherData({
    required this.temperature,
    required this.windspeed,
    required this.label,
    required this.emoji,
  });

  String get watermarkText =>
      '$emoji $label ${temperature.toStringAsFixed(1)}°C'
      ' | Angin ${windspeed.toStringAsFixed(0)} km/h';
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

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'Mozilla/5.0',
        },
      );

      if (response.statusCode == 200) {
        final data =
            jsonDecode(response.body);

        final cw =
            data['current_weather'];

        if (cw != null) {
          final temp =
              (cw['temperature'] as num)
                  .toDouble();

          final wind =
              (cw['windspeed'] as num)
                  .toDouble();

          return WeatherData(
            temperature: temp,
            windspeed: wind,
            label: 'Cuaca',
            emoji: '☁',
          );
        }
      }
    } catch (_) {}

    return null;
  }
}

class MapTileHelper {
  static const int outputSize = 420;

  static img.Image _fallbackMap(
    double lat,
    double lng,
  ) {
    final out = img.Image(
      width: outputSize,
      height: outputSize,
    );

    img.fill(
      out,
      color: img.ColorRgb8(
        225,
        235,
        245,
      ),
    );

    img.drawString(
      out,
      'GPS ONLY',
      font: img.arial24,
      x: 20,
      y: 20,
      color: img.ColorRgb8(
        40,
        40,
        40,
      ),
    );

    img.drawString(
      out,
      lat.toStringAsFixed(5),
      font: img.arial24,
      x: 20,
      y: 80,
      color: img.ColorRgb8(
        40,
        40,
        40,
      ),
    );

    img.drawString(
      out,
      lng.toStringAsFixed(5),
      font: img.arial24,
      x: 20,
      y: 120,
      color: img.ColorRgb8(
        40,
        40,
        40,
      ),
    );

    return out;
  }

  static Future<img.Image> fetchMap(
    double lat,
    double lng,
  ) async {
    try {
      final url =
          'https://staticmap.openstreetmap.de/staticmap.php'
          '?center=$lat,$lng'
          '&zoom=17'
          '&size=420x420'
          '&maptype=mapnik'
          '&markers=$lat,$lng,red-pushpin';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0',
          'Accept': 'image/png',
        },
      );

      if (response.statusCode == 200) {
        final image = img.decodeImage(
          response.bodyBytes,
        );

        if (image != null) {
          return image;
        }
      }

      return _fallbackMap(lat, lng);
    } catch (_) {
      return _fallbackMap(lat, lng);
    }
  }
}

Future<String> addWatermark({
  required String deliveryId,
  required String imagePath,
  required String kurirName,
  required String timestamp,
  required img.Image? mapImage,
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

  const stripHeight = 380;
  const mapSize = 380;

  final canvas = img.Image(
    width: original.width,
    height:
        original.height + stripHeight,
  );

  img.compositeImage(
    canvas,
    original,
  );

  img.fillRect(
    canvas,
    x1: 0,
    y1: original.height,
    x2: original.width,
    y2: original.height +
        stripHeight,
    color: img.ColorRgb8(
      20,
      20,
      20,
    ),
  );

  if (mapImage != null) {
    final resizedMap =
        img.copyResize(
      mapImage,
      width: mapSize,
      height: mapSize,
    );

    img.compositeImage(
      canvas,
      resizedMap,
      dstX: 0,
      dstY: original.height,
    );
  }

  final textX = mapSize + 16;

  int y = original.height + 20;

  img.drawString(
    canvas,
    deliveryId,
    font: img.arial24,
    x: textX,
    y: y,
    color: img.ColorRgb8(
      255,
      210,
      0,
    ),
  );

  y += 40;

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

  final gpsText =
      lat != null && lng != null
          ? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
          : 'Tidak tersedia';

  img.drawString(
    canvas,
    'GPS : $gpsText',
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

  img.drawString(
    canvas,
    'Cuaca : ${weather ?? "Tidak tersedia"}',
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

  img.drawString(
    canvas,
    'Alamat : ${address ?? "Tidak tersedia"}',
    font: img.arial24,
    x: textX,
    y: y,
    color: img.ColorRgb8(
      255,
      255,
      255,
    ),
  );

  final dir =
      await getApplicationDocumentsDirectory();

  final path =
      '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';

  await File(path).writeAsBytes(
    img.encodeJpg(
      canvas,
      quality: 90,
    ),
  );

  return path;
}

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
  final deliveries = <DeliveryRecord>[];

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

      img.Image? mapImage;

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

          try {
            final marks =
                await placemarkFromCoordinates(
              lat,
              lng,
            );

            if (marks.isNotEmpty) {
              final p = marks.first;

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

          try {
            final w =
                await WeatherHelper.fetch(
              lat,
              lng,
            );

            if (w != null) {
              weather =
                  w.watermarkText;
            }
          } catch (_) {}

          try {
            mapImage =
                await MapTileHelper
                    .fetchMap(
              lat,
              lng,
            );
          } catch (_) {}
        }
      } catch (_) {}

      final timestamp = DateFormat(
        'dd/MM/yyyy HH:mm:ss',
      ).format(DateTime.now());

      final deliveryId =
          DeliveryIdGenerator.generate();

      final watermarkedPath =
          await addWatermark(
        deliveryId: deliveryId,
        imagePath: photo.path,
        kurirName: widget.name,
        timestamp: timestamp,
        mapImage: mapImage,
        weather: weather,
        address: address,
        lat: lat,
        lng: lng,
      );

      deliveries.insert(
        0,
        DeliveryRecord(
          deliveryId: deliveryId,
          imagePath: watermarkedPath,
          timestamp: timestamp,
          weather: weather,
          address: address,
        ),
      );

      setState(() {
        loading = false;
      });
    } catch (_) {
      setState(() {
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TermulLog Dashboard',
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
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
                        child: Column(
                          children: [
                            Image.file(
                              File(
                                d.imagePath,
                              ),
                              fit: BoxFit.cover,
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
                                    height: 4,
                                  ),

                                  Text(
                                    d.timestamp,
                                  ),

                                  if (d.weather !=
                                      null)
                                    Text(
                                      d.weather!,
                                    ),

                                  if (d.address !=
                                      null)
                                    Text(
                                      d.address!,
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
