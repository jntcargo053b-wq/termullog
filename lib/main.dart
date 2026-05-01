
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

// ─── CONFIG ───────────────────────────────────────────────────────────────────
const String kUploadEndpoint = ''; // Set URL backend Anda di sini

// ─── APP ──────────────────────────────────────────────────────────────────────

class TermulLogApp extends StatelessWidget {
  const TermulLogApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TermulLog',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

// ─── LOGIN ────────────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final nameController = TextEditingController();

  void login() {
    if (nameController.text.trim().isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DashboardScreen(name: nameController.text.trim()),
        ),
      );
    }
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
            const Icon(Icons.local_shipping, size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nama Kurir',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => login(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: login,
                icon: const Icon(Icons.login),
                label: const Text('MASUK'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── MODEL ────────────────────────────────────────────────────────────────────

enum UploadStatus { pending, uploading, done, failed }

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

  factory DeliveryRecord.fromJson(Map<String, dynamic> json) => DeliveryRecord(
        deliveryId: json['deliveryId'] ?? 'TRM-unknown',
        number: json['number'] as int,
        imagePath: json['imagePath'] as String,
        timestamp: json['timestamp'] as String,
        kurirName: json['kurirName'] as String,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        accuracy: (json['accuracy'] as num?)?.toDouble(),
        address: json['address'] as String?,
        weather: json['weather'] as String?,
        uploadStatus: UploadStatus.values.firstWhere(
          (e) => e.name == json['uploadStatus'],
          orElse: () => UploadStatus.pending,
        ),
        retryCount: json['retryCount'] as int? ?? 0,
      );
}

// ─── DELIVERY ID GENERATOR ────────────────────────────────────────────────────

class DeliveryIdGenerator {
  /// Format: TRM-yyyyMMdd-HHmmssSSS  →  contoh: TRM-20250515-143022847
  static String generate() {
    final now  = DateTime.now();
    final date = DateFormat('yyyyMMdd').format(now);
    final time = DateFormat('HHmmssSSS').format(now);
    return 'TRM-$date-$time';
  }
}

// ─── WEATHER HELPER ───────────────────────────────────────────────────────────

class WeatherData {
  final double temperature;
  final double windspeed;
  final int    weathercode;
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
      '$emoji $label ${temperature.toStringAsFixed(1)}\u00B0C'
      ' | Angin ${windspeed.toStringAsFixed(0)} km/h';

  String get cardText =>
      '$emoji $label ${temperature.toStringAsFixed(1)}\u00B0C';
}

class WeatherHelper {
  static WeatherData _parse(int code, double temp, double wind) {
    final String label, emoji;
    if      (code == 0) { label = 'Cerah';         emoji = '\u2600'; }
    else if (code <= 2) { label = 'Cerah Berawan';  emoji = '\u26C5'; }
    else if (code == 3) { label = 'Mendung';        emoji = '\u2601'; }
    else if (code <= 48){ label = 'Berkabut';       emoji = '\uD83C\uDF2B'; }
    else if (code <= 55){ label = 'Gerimis';        emoji = '\uD83C\uDF26'; }
    else if (code <= 65){ label = 'Hujan';          emoji = '\uD83C\uDF27'; }
    else if (code <= 77){ label = 'Salju';          emoji = '\u2744'; }
    else if (code <= 82){ label = 'Hujan Deras';    emoji = '\uD83C\uDF27'; }
    else                { label = 'Badai';          emoji = '\u26C8'; }
    return WeatherData(
        temperature: temp, windspeed: wind,
        weathercode: code, label: label, emoji: emoji);
  }

  /// Gratis, tanpa API key — open-meteo.com
  static Future<WeatherData?> fetch(double lat, double lng) async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${lat.toStringAsFixed(4)}'
        '&longitude=${lng.toStringAsFixed(4)}'
        '&current_weather=true'
        '&timezone=auto',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final cw   = body['current_weather'] as Map<String, dynamic>?;
        if (cw != null) {
          return _parse(
            cw['weathercode'] as int,
            (cw['temperature'] as num).toDouble(),
            (cw['windspeed']   as num).toDouble(),
          );
        }
      }
    } catch (_) {}
    return null;
  }
}

// ─── UPLOAD QUEUE (persisten + retry eksponensial) ───────────────────────────

class UploadQueueManager {
  UploadQueueManager._();
  static final UploadQueueManager instance = UploadQueueManager._();

  static const int    _maxRetries = 5;
  static const String _queueFile  = 'upload_queue.json';

  final List<DeliveryRecord> _queue = [];
  bool _isProcessing = false;

  VoidCallback? onQueueUpdate;

  List<DeliveryRecord> get queue => List.unmodifiable(_queue);

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_queueFile');
  }

  Future<void> loadFromDisk() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final List<dynamic> list =
          jsonDecode(await f.readAsString()) as List;
      _queue.clear();
      _queue.addAll(list.map(
          (e) => DeliveryRecord.fromJson(e as Map<String, dynamic>)));
      for (final r in _queue) {
        if (r.uploadStatus == UploadStatus.uploading) {
          r.uploadStatus = UploadStatus.pending; // sesi sebelumnya terputus
        }
      }
      await _save();
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(
          jsonEncode(_queue.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> enqueue(DeliveryRecord record) async {
    _queue.removeWhere((e) => e.deliveryId == record.deliveryId);
    _queue.add(record);
    await _save();
    processQueue();
  }

  Future<void> processQueue() async {
    if (_isProcessing || kUploadEndpoint.isEmpty) return;
    _isProcessing = true;

    final pending = _queue
        .where((r) =>
            r.uploadStatus == UploadStatus.pending ||
            (r.uploadStatus == UploadStatus.failed &&
                r.retryCount < _maxRetries))
        .toList();

    for (final record in pending) {
      record.uploadStatus = UploadStatus.uploading;
      onQueueUpdate?.call();
      await _save();

      final ok = await _upload(record);

      if (ok) {
        record.uploadStatus = UploadStatus.done;
      } else {
        record.retryCount++;
        record.uploadStatus = record.retryCount >= _maxRetries
            ? UploadStatus.failed
            : UploadStatus.pending;
        // Backoff: 2s, 4s, 8s, 16s, 32s
        final wait =
            Duration(seconds: min(32, pow(2, record.retryCount).toInt()));
        await Future.delayed(wait);
      }

      onQueueUpdate?.call();
      await _save();
    }

    _isProcessing = false;
  }

  Future<bool> _upload(DeliveryRecord record) async {
    if (kUploadEndpoint.isEmpty) return false;
    try {
      final req =
          http.MultipartRequest('POST', Uri.parse(kUploadEndpoint));
      req.fields['deliveryId'] = record.deliveryId;
      req.fields['number']     = record.number.toString();
      req.fields['kurirName']  = record.kurirName;
      req.fields['timestamp']  = record.timestamp;
      if (record.lat      != null) req.fields['lat']      = record.lat.toString();
      if (record.lng      != null) req.fields['lng']      = record.lng.toString();
      if (record.accuracy != null) req.fields['accuracy'] = record.accuracy!.toStringAsFixed(1);
      if (record.address  != null) req.fields['address']  = record.address!;
      if (record.weather  != null) req.fields['weather']  = record.weather!;
      if (await File(record.imagePath).exists()) {
        req.files.add(
            await http.MultipartFile.fromPath('image', record.imagePath));
      }
      final res = await req.send().timeout(const Duration(seconds: 30));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}

// ─── MAP TILE ─────────────────────────────────────────────────────────────────

class MapTileHelper {
  static const int zoom       = 18;
  static const int tileSize   = 256;
  static const int outputSize = 480;

  static int _lonToTileX(double lon) =>
      ((lon + 180.0) / 360.0 * (1 << zoom)).floor();

  static int _latToTileY(double lat) {
    final rad = lat * pi / 180.0;
    return ((1.0 - log(tan(rad) + 1.0 / cos(rad)) / pi) / 2.0 * (1 << zoom))
        .floor();
  }

  static int _lonPixelOffset(double lon) {
    final world = (lon + 180.0) / 360.0 * (1 << zoom);
    return ((world - world.floor()) * tileSize).floor();
  }

  static int _latPixelOffset(double lat) {
    final rad   = lat * pi / 180.0;
    final world =
        (1.0 - log(tan(rad) + 1.0 / cos(rad)) / pi) / 2.0 * (1 << zoom);
    return ((world - world.floor()) * tileSize).floor();
  }

  static img.Image _buildFallbackMap(double lat, double lng) {
    final out =
        img.Image(width: outputSize, height: outputSize, numChannels: 3);
    img.fill(out, color: img.ColorRgb8(220, 232, 245));
    final gc  = img.ColorRgb8(180, 200, 220);
    final gc2 = img.ColorRgb8(160, 185, 210);
    for (int i = 0; i < outputSize; i += 80) {
      img.drawLine(out, x1: i, y1: 0, x2: i, y2: outputSize - 1, color: gc);
      img.drawLine(out, x1: 0, y1: i, x2: outputSize - 1, y2: i, color: gc);
    }
    for (int t = -1; t <= 1; t++) {
      img.drawLine(out, x1: outputSize ~/ 2 + t, y1: 0,
          x2: outputSize ~/ 2 + t, y2: outputSize - 1, color: gc2);
      img.drawLine(out, x1: 0, y1: outputSize ~/ 2 + t,
          x2: outputSize - 1, y2: outputSize ~/ 2 + t, color: gc2);
    }
    img.drawString(out, lat.toStringAsFixed(5), font: img.arial14,
        x: outputSize ~/ 2 - 48, y: outputSize ~/ 2 - 26,
        color: img.ColorRgb8(40, 80, 140));
    img.drawString(out, lng.toStringAsFixed(5), font: img.arial14,
        x: outputSize ~/ 2 - 48, y: outputSize ~/ 2 - 10,
        color: img.ColorRgb8(40, 80, 140));
    img.drawString(out, 'GPS Only', font: img.arial14, x: 6, y: 6,
        color: img.ColorRgb8(100, 100, 130));
    final mX = outputSize ~/ 2, mY = outputSize ~/ 2;
    img.fillCircle(out, x: mX+2, y: mY+2, radius: 12, color: img.ColorRgb8(0,0,0));
    img.fillCircle(out, x: mX,   y: mY,   radius: 12, color: img.ColorRgb8(220,30,30));
    img.drawCircle(out, x: mX,   y: mY,   radius: 12, color: img.ColorRgb8(255,255,255));
    img.fillCircle(out, x: mX,   y: mY,   radius:  4, color: img.ColorRgb8(255,255,255));
    return out;
  }

  static Future<img.Image> fetchMap(double lat, double lng) async {
    final tx = _lonToTileX(lng), ty = _latToTileY(lat);
    final px = _lonPixelOffset(lng), py = _latPixelOffset(lat);
    const grid = 5, halfGrid = 2;
    final canvasW = tileSize * grid, canvasH = tileSize * grid;
    final canvas  = img.Image(width: canvasW, height: canvasH, numChannels: 3);
    img.fill(canvas, color: img.ColorRgb8(242, 239, 233));
    int successCount = 0;

    for (int dy = -halfGrid; dy <= halfGrid; dy++) {
      for (int dx = -halfGrid; dx <= halfGrid; dx++) {
        try {
          final url =
              'https://tile.openstreetmap.org/$zoom/${tx+dx}/${ty+dy}.png';
          final res = await http
              .get(Uri.parse(url), headers: {'User-Agent': 'TermulLogApp/1.0'})
              .timeout(const Duration(seconds: 10));
          if (res.statusCode == 200) {
            img.Image? tile = img.decodePng(res.bodyBytes);
            if (tile == null) continue;
            if (tile.numChannels != 3) {
              tile = img.copyResize(
                img.remapColors(tile,
                    red: img.Channel.red, green: img.Channel.green,
                    blue: img.Channel.blue, alpha: img.Channel.luminance),
                width: tileSize, height: tileSize);
            }
            final dstX = (dx + halfGrid) * tileSize;
            final dstY = (dy + halfGrid) * tileSize;
            for (int row = 0; row < tileSize; row++) {
              for (int col = 0; col < tileSize; col++) {
                final p = tile.getPixel(col, row);
                canvas.setPixelRgb(dstX+col, dstY+row,
                    p.r.toInt(), p.g.toInt(), p.b.toInt());
              }
            }
            successCount++;
          }
        } catch (_) {}
      }
    }

    if (successCount == 0) return _buildFallbackMap(lat, lng);

    final centerX = halfGrid * tileSize + px;
    final centerY = halfGrid * tileSize + py;
    final half    = outputSize ~/ 2;
    final cropX   = (centerX - half).clamp(0, canvasW - outputSize);
    final cropY   = (centerY - half).clamp(0, canvasH - outputSize);
    final cropped = img.copyCrop(canvas,
        x: cropX, y: cropY, width: outputSize, height: outputSize);
    final mX = centerX - cropX, mY = centerY - cropY;
    img.fillCircle(cropped, x: mX+2, y: mY+2, radius: 10, color: img.ColorRgb8(0,0,0));
    img.fillCircle(cropped, x: mX,   y: mY,   radius: 10, color: img.ColorRgb8(220,30,30));
    img.drawCircle(cropped, x: mX,   y: mY,   radius: 10, color: img.ColorRgb8(255,255,255));
    img.fillCircle(cropped, x: mX,   y: mY,   radius:  3, color: img.ColorRgb8(255,255,255));
    return cropped;
  }
}

// ─── WATERMARK ────────────────────────────────────────────────────────────────
//
//  Strip 380px — 7 baris info:
//   [1] KIRIMAN #N          kuning  arial24
//   [2] TRM-yyyyMMdd-...    silver  arial14
//   [3] Kurir  : ...        putih   arial24
//   [4] Waktu  : ...        putih   arial24
//   [5] GPS    : lat,lng ±Xm putih  arial24  ← akurasi GPS
//   [6] Cuaca  : ...        putih   arial24  ← open-meteo
//   [7] Alamat : ...        putih   arial24  (auto-wrap 2 baris)

Future<String> addWatermark({
  required String deliveryId,
  required String imagePath,
  required String kurirName,
  required String timestamp,
  required int    deliveryNum,
  double? lat,
  double? lng,
  double? accuracy,
  String? address,
  String? weather,
  img.Image? mapImage,
}) async {
  final bytes = await File(imagePath).readAsBytes();
  img.Image? original = img.decodeImage(bytes);
  if (original == null) throw Exception('Gagal membaca gambar');

  if (original.width  > 1080) original = img.copyResize(original, width:  1080);
  if (original.height > 1440) original = img.copyResize(original, height: 1440);

  final w = original.width, h = original.height;
  const stripH       = 380;
  const mapDisplaySz = 380;
  final hasMap       = mapImage != null;
  final mapW         = hasMap ? mapDisplaySz : 0;

  final canvas = img.Image(width: w, height: h + stripH, numChannels: 3);
  img.compositeImage(canvas, original, dstX: 0, dstY: 0);

  // Gradient gelap
  for (int row = 0; row < stripH; row++) {
    final t    = row / (stripH - 1);
    final gray = (38 * (1 - t) + 8 * t).toInt();
    img.drawLine(canvas, x1: 0, y1: h+row, x2: w-1, y2: h+row,
        color: img.ColorRgb8(gray, gray, gray + 5));
  }
  // Garis teal 4px
  for (int x = 0; x < w; x++) {
    for (int t = 0; t < 4; t++) canvas.setPixelRgb(x, h+t, 0, 195, 175);
  }

  // Peta kiri
  if (hasMap) {
    final scaled =
        img.copyResize(mapImage!, width: mapDisplaySz, height: mapDisplaySz);
    img.compositeImage(canvas, scaled, dstX: 0, dstY: h);
    for (int row = 0; row < stripH; row++) {
      canvas.setPixelRgb(mapW,   h+row, 0, 195, 175);
      canvas.setPixelRgb(mapW+1, h+row, 0, 195, 175);
      canvas.setPixelRgb(mapW+2, h+row, 0, 195, 175);
    }
  }

  final cWhite  = img.ColorRgb8(255, 255, 255);
  final cTeal   = img.ColorRgb8(0,   210, 185);
  final cYellow = img.ColorRgb8(255, 210, 0);
  final cGrey   = img.ColorRgb8(160, 160, 160);
  final cSilver = img.ColorRgb8(130, 145, 155);

  final textX  = mapW + 18;
  final maxTW  = w - textX - 14;
  int   ty     = h + 12;

  // [1] Judul
  img.drawString(canvas, 'KIRIMAN #$deliveryNum',
      font: img.arial24, x: textX, y: ty, color: cYellow);
  ty += 34;

  // [2] ID unik
  img.drawString(canvas, deliveryId,
      font: img.arial14, x: textX + 2, y: ty, color: cSilver);
  ty += 20;

  // Divider
  img.drawLine(canvas, x1: textX, y1: ty, x2: textX + 220, y2: ty, color: cTeal);
  ty += 10;

  // [3] Kurir
  img.drawString(canvas, 'Kurir : $kurirName',
      font: img.arial24, x: textX, y: ty, color: cWhite);
  ty += 32;

  // [4] Waktu
  img.drawString(canvas, 'Waktu : $timestamp',
      font: img.arial24, x: textX, y: ty, color: cWhite);
  ty += 32;

  // [5] GPS + akurasi
  if (lat != null && lng != null) {
    final accStr = accuracy != null
        ? ' \u00B1${accuracy.toStringAsFixed(0)}m'
        : '';
    img.drawString(canvas,
        'GPS   : ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}$accStr',
        font: img.arial24, x: textX, y: ty, color: cWhite);
  } else {
    img.drawString(canvas, 'GPS   : Tidak tersedia',
        font: img.arial24, x: textX, y: ty, color: cGrey);
  }
  ty += 32;

  // [6] Cuaca
  if (weather != null && weather.isNotEmpty) {
    img.drawString(canvas, 'Cuaca : $weather',
        font: img.arial24, x: textX, y: ty, color: cWhite);
  } else {
    img.drawString(canvas, 'Cuaca : Tidak tersedia',
        font: img.arial24, x: textX, y: ty, color: cGrey);
  }
  ty += 32;

  // [7] Alamat (auto-wrap)
  const charW    = 14;
  final maxChars = maxTW ~/ charW;
  if (address != null && address.isNotEmpty) {
    const prefix = 'Alamat: ';
    final avail  = maxChars - prefix.length;
    final line1  = address.length > avail
        ? address.substring(0, avail) : address;
    img.drawString(canvas, '$prefix$line1',
        font: img.arial24, x: textX, y: ty, color: cWhite);
    ty += 28;
    if (address.length > avail) {
      final rest  = address.substring(avail);
      final line2 = rest.length > maxChars
          ? '${rest.substring(0, maxChars - 3)}...' : rest;
      img.drawString(canvas, '        $line2',
          font: img.arial24, x: textX, y: ty, color: cWhite);
    }
  } else {
    img.drawString(canvas, 'Alamat: Tidak tersedia',
        font: img.arial24, x: textX, y: ty, color: cGrey);
  }

  // Brand pojok kanan bawah
  img.drawString(canvas, 'TermulLog',
      font: img.arial14, x: w - 92, y: h + stripH - 20, color: cTeal);

  final dir     = await getApplicationDocumentsDirectory();
  final outPath =
      '${dir.path}/delivery_${deliveryNum}_${DateTime.now().millisecondsSinceEpoch}.jpg';
  await File(outPath).writeAsBytes(img.encodeJpg(canvas, quality: 88));
  return outPath;
}

// ─── DASHBOARD ────────────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  final String name;
  const DashboardScreen({super.key, required this.name});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final List<DeliveryRecord> deliveries = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    UploadQueueManager.instance.onQueueUpdate = () {
      if (mounted) setState(() {});
    };
    UploadQueueManager.instance.processQueue();
  }

  @override
  void dispose() {
    UploadQueueManager.instance.onQueueUpdate = null;
    super.dispose();
  }

  Future<void> captureDelivery() async {
    setState(() => isLoading = true);
    try {
      final picker = ImagePicker();
      final XFile? photo =
          await picker.pickImage(source: ImageSource.camera, imageQuality: 90);
      if (photo == null) { setState(() => isLoading = false); return; }

      double? lat, lng, accuracy;
      String? address, weather;
      img.Image? mapImage;

      try {
        LocationPermission perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.whileInUse ||
            perm == LocationPermission.always) {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          ).timeout(const Duration(seconds: 8));
          lat      = pos.latitude;
          lng      = pos.longitude;
          accuracy = pos.accuracy;

          try {
            final marks =
                await placemarkFromCoordinates(lat, lng)
                    .timeout(const Duration(seconds: 6));
            if (marks.isNotEmpty) {
              final p = marks.first;
              address = [p.street, p.subLocality, p.locality,
                p.subAdministrativeArea]
                  .where((s) => s != null && s.isNotEmpty)
                  .join(', ');
            }
          } catch (_) {}

          try {
            final wd = await WeatherHelper.fetch(lat, lng);
            if (wd != null) weather = wd.watermarkText;
          } catch (_) {}

          try {
            mapImage = await MapTileHelper.fetchMap(lat, lng);
          } catch (_) {}
        }
      } catch (_) {}

      final now        = DateTime.now();
      final timestamp  = DateFormat('dd/MM/yyyy HH:mm:ss').format(now);
      final deliveryId = DeliveryIdGenerator.generate();
      final num        = deliveries.length + 1;

      final path = await addWatermark(
        deliveryId:  deliveryId,
        imagePath:   photo.path,
        kurirName:   widget.name,
        timestamp:   timestamp,
        deliveryNum: num,
        lat:         lat,
        lng:         lng,
        accuracy:    accuracy,
        address:     address,
        weather:     weather,
        mapImage:    mapImage,
      );

      final record = DeliveryRecord(
        deliveryId:   deliveryId,
        number:       num,
        imagePath:    path,
        timestamp:    timestamp,
        kurirName:    widget.name,
        lat:          lat,
        lng:          lng,
        accuracy:     accuracy,
        address:      address,
        weather:      weather,
        uploadStatus: UploadStatus.pending,
      );

      await UploadQueueManager.instance.enqueue(record);

      setState(() { deliveries.insert(0, record); isLoading = false; });
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _retryUpload(DeliveryRecord record) {
    record.uploadStatus = UploadStatus.pending;
    record.retryCount   = 0;
    UploadQueueManager.instance.processQueue();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = deliveries
        .where((d) => d.uploadStatus == UploadStatus.pending ||
                      d.uploadStatus == UploadStatus.uploading)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TermulLog Dashboard'),
        actions: [
          if (pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Badge(
                  label: Text('$pendingCount'),
                  child: const Icon(Icons.cloud_upload_outlined),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const LoginScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(label: 'Kurir',
                    value: widget.name, icon: Icons.person),
                _StatItem(label: 'Total Kiriman',
                    value: deliveries.length.toString(),
                    icon: Icons.inventory_2),
                _StatItem(
                  label: 'Pending Upload',
                  value: pendingCount.toString(),
                  icon: Icons.cloud_upload,
                  iconColor: pendingCount > 0 ? Colors.orange : Colors.green,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isLoading ? null : captureDelivery,
                icon: isLoading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.camera_alt),
                label: Text(isLoading ? 'Memproses...' : '+ FOTO BUKTI KIRIM'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: deliveries.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_library_outlined,
                            size: 64, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('Belum ada foto kiriman',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: deliveries.length,
                    itemBuilder: (_, i) => _DeliveryCard(
                      delivery: deliveries[i],
                      onRetry:  () => _retryUpload(deliveries[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── WIDGETS ──────────────────────────────────────────────────────────────────

class _StatItem extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color? iconColor;
  const _StatItem(
      {required this.label, required this.value,
       required this.icon, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Icon(icon, color: iconColor ?? Colors.blue),
      const SizedBox(height: 4),
      Text(value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      Text(label,
          style: const TextStyle(color: Colors.grey, fontSize: 12)),
    ]);
  }
}

class _DeliveryCard extends StatelessWidget {
  final DeliveryRecord delivery;
  final VoidCallback   onRetry;
  const _DeliveryCard({required this.delivery, required this.onRetry});

  static ({Color color, IconData icon, String label}) _meta(UploadStatus s) =>
      switch (s) {
        UploadStatus.done      => (color: Colors.green,  icon: Icons.cloud_done,   label: 'Terupload'),
        UploadStatus.uploading => (color: Colors.blue,   icon: Icons.cloud_upload, label: 'Mengunggah…'),
        UploadStatus.failed    => (color: Colors.red,    icon: Icons.cloud_off,    label: 'Gagal'),
        UploadStatus.pending   => (color: Colors.orange, icon: Icons.cloud_queue,  label: 'Menunggu'),
      };

  @override
  Widget build(BuildContext context) {
    final m = _meta(delivery.uploadStatus);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => PhotoViewScreen(imagePath: delivery.imagePath))),
            child: SizedBox(
              width: double.infinity, height: 200,
              child: Image.file(File(delivery.imagePath), fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Center(child: Icon(Icons.broken_image, size: 48))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Kiriman #${delivery.number}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    GestureDetector(
                      onTap: delivery.uploadStatus == UploadStatus.failed
                          ? onRetry : null,
                      child: Chip(
                        avatar: Icon(m.icon, size: 14, color: m.color),
                        label: Text(m.label,
                            style: TextStyle(fontSize: 11, color: m.color)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(color: m.color, width: 0.8),
                        backgroundColor: m.color.withOpacity(0.08),
                      ),
                    ),
                  ],
                ),
                Text(delivery.deliveryId,
                    style: const TextStyle(color: Colors.blueGrey,
                        fontSize: 11, fontFamily: 'monospace')),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.access_time, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(delivery.timestamp,
                      style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ]),
                if (delivery.lat != null) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.gps_fixed, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '${delivery.lat!.toStringAsFixed(5)}, '
                      '${delivery.lng!.toStringAsFixed(5)}'
                      '${delivery.accuracy != null ? ' \u00B1${delivery.accuracy!.toStringAsFixed(0)}m' : ''}',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ]),
                ],
                if (delivery.weather != null) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.wb_sunny_outlined,
                        size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(delivery.weather!,
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 13)),
                  ]),
                ],
                if (delivery.address != null) ...[
                  const SizedBox(height: 2),
                  Row(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on,
                            size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(delivery.address!,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── FULL SCREEN PHOTO ────────────────────────────────────────────────────────

class PhotoViewScreen extends StatelessWidget {
  final String imagePath;
  const PhotoViewScreen({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Bukti Kiriman'),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.file(File(imagePath), fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image, color: Colors.white, size: 64)),
        ),
      ),
    );
  }
}
```
