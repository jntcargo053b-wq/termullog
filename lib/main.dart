import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
  await UploadQueueManager.instance.loadFromDisk();
  runApp(const TermulLogApp());
}

// ───────────────── CONFIG ─────────────────

const String kUploadEndpoint = '';

// ───────────────── APP ─────────────────

class TermulLogApp extends StatelessWidget {
  const TermulLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TermulLog',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const LoginScreen(),
    );
  }
}

// ───────────────── LOGIN ─────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final controller = TextEditingController();

  void login() {
    if (controller.text.trim().isEmpty) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DashboardScreen(name: controller.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TermulLog')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_shipping,
                size: 80, color: Colors.blue),
            const SizedBox(height: 24),

            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Nama Kurir',
                prefixIcon: Icon(Icons.person),
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

// ───────────────── MODEL ─────────────────

enum UploadStatus {
  pending,
  uploading,
  done,
  failed,
}

class DeliveryRecord {
  final String deliveryId;
  final int number;
  final String imagePath;
  final String timestamp;
  final String kurirName;

  final double? lat;
  final double? lng;
  final double? accuracy;

  final String? address;
  final String? weather;

  UploadStatus uploadStatus;
  int retryCount;

  DeliveryRecord({
    required this.deliveryId,
    required this.number,
    required this.imagePath,
    required this.timestamp,
    required this.kurirName,
    this.lat,
    this.lng,
    this.accuracy,
    this.address,
    this.weather,
    this.uploadStatus = UploadStatus.pending,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'deliveryId': deliveryId,
        'number': number,
        'imagePath': imagePath,
        'timestamp': timestamp,
        'kurirName': kurirName,
        'lat': lat,
        'lng': lng,
        'accuracy': accuracy,
        'address': address,
        'weather': weather,
        'uploadStatus': uploadStatus.name,
        'retryCount': retryCount,
      };

  factory DeliveryRecord.fromJson(Map<String, dynamic> json) {
    return DeliveryRecord(
      deliveryId: json['deliveryId'],
      number: json['number'],
      imagePath: json['imagePath'],
      timestamp: json['timestamp'],
      kurirName: json['kurirName'],
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      address: json['address'],
      weather: json['weather'],
      uploadStatus: UploadStatus.values.firstWhere(
        (e) => e.name == json['uploadStatus'],
        orElse: () => UploadStatus.pending,
      ),
      retryCount: json['retryCount'] ?? 0,
    );
  }
}

// ───────────────── DELIVERY ID ─────────────────

class DeliveryIdGenerator {
  static String generate() {
    final now = DateTime.now();

    final date = DateFormat('yyyyMMdd').format(now);
    final time = DateFormat('HHmmssSSS').format(now);

    return 'TRM-$date-$time';
  }
}

// ───────────────── WEATHER ─────────────────

class WeatherData {
  final double temperature;
  final double windspeed;
  final int weathercode;
  final String label;
  final String emoji;

  const WeatherData({
    required this.temperature,
    required this.windspeed,
    required this.weathercode,
    required this.label,
    required this.emoji,
  });

  String get watermarkText =>
      '$emoji $label ${temperature.toStringAsFixed(1)}°C'
      ' | Angin ${windspeed.toStringAsFixed(0)} km/h';
}

class WeatherHelper {
  static WeatherData _parse(
    int code,
    double temp,
    double wind,
  ) {
    final String label;
    final String emoji;

    if (code == 0) {
      label = 'Cerah';
      emoji = '☀';
    } else if (code <= 2) {
      label = 'Cerah Berawan';
      emoji = '⛅';
    } else if (code == 3) {
      label = 'Mendung';
      emoji = '☁';
    } else if (code <= 55) {
      label = 'Gerimis';
      emoji = '🌦';
    } else if (code <= 65) {
      label = 'Hujan';
      emoji = '🌧';
    } else {
      label = 'Badai';
      emoji = '⛈';
    }

    return WeatherData(
      temperature: temp,
      windspeed: wind,
      weathercode: code,
      label: label,
      emoji: emoji,
    );
  }

  static Future<WeatherData?> fetch(
    double lat,
    double lng,
  ) async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat'
        '&longitude=$lng'
        '&current_weather=true',
      );

      final res = await http.get(
        uri,
        headers: {
          'User-Agent': 'Mozilla/5.0',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      debugPrint('WEATHER STATUS: ${res.statusCode}');

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);

        final cw = body['current_weather'];

        if (cw != null) {
          return _parse(
            cw['weathercode'],
            (cw['temperature'] as num).toDouble(),
            (cw['windspeed'] as num).toDouble(),
          );
        }
      }
    } catch (e) {
      debugPrint('WEATHER ERROR: $e');
    }

    return null;
  }
}

// ───────────────── MAP TILE HELPER (FULL FIX STABLE) ─────────────────

class MapTileHelper {
  static const int zoom = 17;
  static const int tileSize = 256;
  static const int outputSize = 420;

  static int _lonToTileX(double lon) =>
      ((lon + 180.0) / 360.0 * (1 << zoom)).floor();

  static int _latToTileY(double lat) {
    final rad = lat * pi / 180.0;

    return (
      (1.0 - log(tan(rad) + 1.0 / cos(rad)) / pi) /
      2.0 *
      (1 << zoom)
    ).floor();
  }

  static int _lonPixelOffset(double lon) {
    final world =
        (lon + 180.0) / 360.0 * (1 << zoom);

    return (
      (world - world.floor()) * tileSize
    ).floor();
  }

  static int _latPixelOffset(double lat) {
    final rad = lat * pi / 180.0;

    final world =
        (1.0 - log(tan(rad) + 1.0 / cos(rad)) / pi) /
        2.0 *
        (1 << zoom);

    return (
      (world - world.floor()) * tileSize
    ).floor();
  }

  // ───────────────── FALLBACK MAP ─────────────────

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
      color: img.ColorRgb8(225, 235, 245),
    );

    // GRID
    for (int i = 0; i < outputSize; i += 60) {
      img.drawLine(
        out,
        x1: i,
        y1: 0,
        x2: i,
        y2: outputSize,
        color: img.ColorRgb8(190, 205, 220),
      );

      img.drawLine(
        out,
        x1: 0,
        y1: i,
        x2: outputSize,
        y2: i,
        color: img.ColorRgb8(190, 205, 220),
      );
    }

    img.drawString(
      out,
      'GPS ONLY',
      font: img.arial24,
      x: 20,
      y: 20,
      color: img.ColorRgb8(40, 40, 40),
    );

    img.drawString(
      out,
      lat.toStringAsFixed(5),
      font: img.arial24,
      x: 20,
      y: 80,
      color: img.ColorRgb8(40, 40, 40),
    );

    img.drawString(
      out,
      lng.toStringAsFixed(5),
      font: img.arial24,
      x: 20,
      y: 120,
      color: img.ColorRgb8(40, 40, 40),
    );

    final mx = outputSize ~/ 2;
    final my = outputSize ~/ 2;

    img.fillCircle(
      out,
      x: mx,
      y: my,
      radius: 10,
      color: img.ColorRgb8(220, 30, 30),
    );

    img.drawCircle(
      out,
      x: mx,
      y: my,
      radius: 10,
      color: img.ColorRgb8(255, 255, 255),
    );

    return out;
  }

  // ───────────────── FETCH MAP ─────────────────

  static Future<img.Image> fetchMap(
    double lat,
    double lng,
  ) async {
    try {

      final tx = _lonToTileX(lng);
      final ty = _latToTileY(lat);

      final px = _lonPixelOffset(lng);
      final py = _latPixelOffset(lat);

      // STABLE GRID
      const grid = 3;
      const half = 1;

      final canvas = img.Image(
        width: tileSize * grid,
        height: tileSize * grid,
      );

      img.fill(
        canvas,
        color: img.ColorRgb8(240, 240, 240),
      );

      int successCount = 0;

      for (int dy = -half; dy <= half; dy++) {
        for (int dx = -half; dx <= half; dx++) {

          try {

            // ───────────────── STADIA MAPS ─────────────────

            final url =
                'https://tiles.stadiamaps.com/tiles/alidade_smooth/'
                '$zoom/${tx + dx}/${ty + dy}.png';

            debugPrint(url);

            final response = await http.get(
              Uri.parse(url),
              headers: {
                'User-Agent': 'TermulLog/1.0',
                'Accept': 'image/png,image/*',
              },
            ).timeout(
              const Duration(seconds: 20),
            );

            debugPrint(
              'MAP STATUS: ${response.statusCode}',
            );

            if (response.statusCode == 200) {

              final tile = img.decodeImage(
                response.bodyBytes,
              );

              if (tile != null) {

                img.compositeImage(
                  canvas,
                  tile,
                  dstX: (dx + half) * tileSize,
                  dstY: (dy + half) * tileSize,
                );

                successCount++;
              }
            }

          } catch (e) {

            debugPrint(
              'MAP TILE ERROR: $e',
            );
          }
        }
      }

      // ───────────────── FALLBACK ─────────────────

      if (successCount == 0) {

        debugPrint(
          'SEMUA TILE GAGAL',
        );

        return _fallbackMap(
          lat,
          lng,
        );
      }

      // ───────────────── CROP CENTER ─────────────────

      final centerX =
          half * tileSize + px;

      final centerY =
          half * tileSize + py;

      final cropX =
          centerX - (outputSize ~/ 2);

      final cropY =
          centerY - (outputSize ~/ 2);

      final cropped = img.copyCrop(
        canvas,
        x: cropX.clamp(
          0,
          canvas.width - outputSize,
        ),
        y: cropY.clamp(
          0,
          canvas.height - outputSize,
        ),
        width: outputSize,
        height: outputSize,
      );

      final mx = outputSize ~/ 2;
      final my = outputSize ~/ 2;

      // ───────────────── MARKER SHADOW ─────────────────

      img.fillCircle(
        cropped,
        x: mx + 2,
        y: my + 2,
        radius: 11,
        color: img.ColorRgb8(0, 0, 0),
      );

      // ───────────────── RED MARKER ─────────────────

      img.fillCircle(
        cropped,
        x: mx,
        y: my,
        radius: 11,
        color: img.ColorRgb8(220, 30, 30),
      );

      // ───────────────── WHITE BORDER ─────────────────

      img.drawCircle(
        cropped,
        x: mx,
        y: my,
        radius: 11,
        color: img.ColorRgb8(255, 255, 255),
      );

      // ───────────────── CENTER DOT ─────────────────

      img.fillCircle(
        cropped,
        x: mx,
        y: my,
        radius: 4,
        color: img.ColorRgb8(255, 255, 255),
      );

      return cropped;

    } catch (e) {

      debugPrint(
        'MAP ERROR: $e',
      );

      return _fallbackMap(
        lat,
        lng,
      );
    }
  }
}

// ───────────────── WATERMARK ─────────────────

Future<String> addWatermark({
  required String deliveryId,
  required String imagePath,
  required String kurirName,
  required String timestamp,
  required int deliveryNum,
  double? lat,
  double? lng,
  double? accuracy,
  String? address,
  String? weather,
  img.Image? mapImage,
}) async {
  final bytes = await File(imagePath).readAsBytes();

  img.Image? original = img.decodeImage(bytes);

  if (original == null) {
    throw Exception('Gagal membaca gambar');
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
    height: original.height + stripHeight,
  );

  img.compositeImage(canvas, original);

  img.fillRect(
    canvas,
    x1: 0,
    y1: original.height,
    x2: original.width,
    y2: original.height + stripHeight,
    color: img.ColorRgb8(25, 25, 25),
  );

  if (mapImage != null) {
    final map = img.copyResize(
      mapImage,
      width: mapSize,
      height: mapSize,
    );

    img.compositeImage(
      canvas,
      map,
      dstX: 0,
      dstY: original.height,
    );
  }

  final textX = mapSize + 16;

  int y = original.height + 16;

  img.drawString(
    canvas,
    'KIRIMAN #$deliveryNum',
    font: img.arial24,
    x: textX,
    y: y,
    color: img.ColorRgb8(255, 210, 0),
  );

  y += 36;

  img.drawString(
    canvas,
    deliveryId,
    font: img.arial14,
    x: textX,
    y: y,
    color: img.ColorRgb8(180, 180, 180),
  );

  y += 28;

  img.drawString(
    canvas,
    'Kurir : $kurirName',
    font: img.arial24,
    x: textX,
    y: y,
    color: img.ColorRgb8(255, 255, 255),
  );

  y += 34;

  img.drawString(
    canvas,
    'Waktu : $timestamp',
    font: img.arial24,
    x: textX,
    y: y,
    color: img.ColorRgb8(255, 255, 255),
  );

  y += 34;

  final gpsText = lat != null
      ? '${lat.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}'
      : 'Tidak tersedia';

  img.drawString(
    canvas,
    'GPS : $gpsText',
    font: img.arial24,
    x: textX,
    y: y,
    color: img.ColorRgb8(255, 255, 255),
  );

  y += 34;

  img.drawString(
    canvas,
    'Cuaca : ${weather ?? "Tidak tersedia"}',
    font: img.arial24,
    x: textX,
    y: y,
    color: img.ColorRgb8(255, 255, 255),
  );

  y += 34;

  img.drawString(
    canvas,
    'Alamat : ${address ?? "Tidak tersedia"}',
    font: img.arial24,
    x: textX,
    y: y,
    color: img.ColorRgb8(255, 255, 255),
  );

  final dir =
      await getApplicationDocumentsDirectory();

  final path =
      '${dir.path}/delivery_${DateTime.now().millisecondsSinceEpoch}.jpg';

  await File(path).writeAsBytes(
    img.encodeJpg(canvas, quality: 90),
  );

  return path;
}

// ───────────────── QUEUE ─────────────────

class UploadQueueManager {
  UploadQueueManager._();

  static final instance =
      UploadQueueManager._();

  Future<void> loadFromDisk() async {}
}

// ───────────────── DASHBOARD ─────────────────

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
  final List<DeliveryRecord> deliveries = [];

  bool loading = false;

  Future<void> captureDelivery() async {
    setState(() => loading = true);

    try {
      final picker = ImagePicker();

      final XFile? photo =
          await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );

      if (photo == null) {
        setState(() => loading = false);
        return;
      }

      double? lat;
      double? lng;
      double? accuracy;

      String? address;
      String? weather;

      img.Image? map;

      try {
        LocationPermission permission =
            await Geolocator.checkPermission();

        if (permission ==
            LocationPermission.denied) {
          permission =
              await Geolocator.requestPermission();
        }

        if (permission ==
                LocationPermission.always ||
            permission ==
                LocationPermission.whileInUse) {
          final pos =
              await Geolocator.getCurrentPosition(
            desiredAccuracy:
                LocationAccuracy.high,
          );

          lat = pos.latitude;
          lng = pos.longitude;
          accuracy = pos.accuracy;

          try {
            final placemarks =
                await placemarkFromCoordinates(
              lat,
              lng,
            );

            if (placemarks.isNotEmpty) {
              final p = placemarks.first;

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
              weather = w.watermarkText;
            }
          } catch (_) {}

          try {
            map =
                await MapTileHelper.fetchMap(
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

      final path = await addWatermark(
        deliveryId: deliveryId,
        imagePath: photo.path,
        kurirName: widget.name,
        timestamp: timestamp,
        deliveryNum: deliveries.length + 1,
        lat: lat,
        lng: lng,
        accuracy: accuracy,
        address: address,
        weather: weather,
        mapImage: map,
      );

      deliveries.insert(
        0,
        DeliveryRecord(
          deliveryId: deliveryId,
          number: deliveries.length + 1,
          imagePath: path,
          timestamp: timestamp,
          kurirName: widget.name,
          lat: lat,
          lng: lng,
          accuracy: accuracy,
          address: address,
          weather: weather,
        ),
      );

      setState(() => loading = false);
    } catch (e) {
      debugPrint(e.toString());

      setState(() => loading = false);
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
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    loading ? null : captureDelivery,
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.camera_alt),
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
                    child:
                        Text('Belum ada kiriman'),
                  )
                : ListView.builder(
                    itemCount: deliveries.length,
                    itemBuilder: (_, i) {
                      final d = deliveries[i];

                      return Card(
                        margin:
                            const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Image.file(
                              File(d.imagePath),
                              fit: BoxFit.cover,
                            ),

                            Padding(
                              padding:
                                  const EdgeInsets.all(
                                      12),
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
                                      height: 4),

                                  Text(d.timestamp),

                                  if (d.weather !=
                                      null)
                                    Text(d.weather!),

                                  if (d.address !=
                                      null)
                                    Text(d.address!),
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
