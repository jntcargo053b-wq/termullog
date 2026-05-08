// ═══════════════════════════════════════════════════════════════
// PATCH: MINI MAP WATERMARK
// File ini berisi perubahan yang perlu diintegrasikan ke
// deepseek_dart_20260508_799ed5.dart
// ═══════════════════════════════════════════════════════════════
//
// DEPENDENCIES BARU di pubspec.yaml:
//
//   http: ^1.2.0       ← untuk fetch tile PNG dari OpenStreetMap
//
// Tidak butuh API key — OpenStreetMap tile gratis.
// ═══════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

// ─────────────────────────────────────────────────────────────
// STEP 1: Tambahkan di ImageProcessParams
//
// Tambahkan field baru:
//   final Uint8List? mapTileBytes;
//
// Dan tambahkan parameter di constructor:
//   this.mapTileBytes,
// ─────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────
// STEP 2: MiniMapFetcher — tambahkan class ini di camera_screen.dart
// (letakkan sebelum class ImageProcessParams)
// ─────────────────────────────────────────────────────────────

class MiniMapFetcher {
  // Ukuran tile map yang akan di-download (px)
  static const int tileSize = 256;

  // Zoom level OpenStreetMap (15 = detail jalan, 13 = overview)
  static const int zoomLevel = 15;

  // Ukuran minimap yang akan digambar di watermark (px)
  static const int miniMapSize = 110;

  // Radius lingkaran marker GPS (px)
  static const int markerRadius = 6;

  /// Konversi lat/lon ke tile X/Y pada zoom tertentu
  static ({int x, int y}) _latLonToTile(double lat, double lon, int zoom) {
    final n = pow(2, zoom);
    final x = ((lon + 180.0) / 360.0 * n).floor();
    final latRad = lat * pi / 180.0;
    final y = ((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) / 2.0 * n).floor();
    return (x: x, y: y);
  }

  /// Pixel offset dalam tile untuk posisi GPS tepat
  static ({double px, double py}) _latLonToPixelInTile(
    double lat, double lon, int tileX, int tileY, int zoom,
  ) {
    final n = pow(2, zoom).toDouble();
    final globalPx = (lon + 180.0) / 360.0 * n * tileSize;
    final latRad = lat * pi / 180.0;
    final globalPy =
        (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) / 2.0 * n * tileSize;
    final tilePx = globalPx - tileX * tileSize;
    final tilePy = globalPy - tileY * tileSize;
    return (px: tilePx, py: tilePy);
  }

  /// Download tile dari OpenStreetMap dan gambar marker GPS
  /// Returns null jika gagal (no internet, dll.)
  static Future<Uint8List?> fetchMiniMap(Position pos) async {
    try {
      final tile = _latLonToTile(pos.latitude, pos.longitude, zoomLevel);

      // Gunakan tile server OpenStreetMap (gratis, no API key)
      // Bisa diganti dengan: 'https://tile.openstreetmap.org'
      final url =
          'https://tile.openstreetmap.org/$zoomLevel/${tile.x}/${tile.y}.png';

      final response = await http
          .get(Uri.parse(url), headers: {
            // User-Agent wajib untuk OSM tile policy
            'User-Agent': 'TermulLog/1.0 (GPS Camera App)',
          })
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return null;

      final tileImage = img.decodePng(response.bodyBytes);
      if (tileImage == null) return null;

      // Hitung offset pixel GPS dalam tile
      final offset = _latLonToPixelInTile(
        pos.latitude,
        pos.longitude,
        tile.x,
        tile.y,
        zoomLevel,
      );

      // Crop minimap dengan GPS di tengah
      final halfSize = miniMapSize ~/ 2;
      final cropX = (offset.px - halfSize).round().clamp(0, tileSize - miniMapSize);
      final cropY = (offset.py - halfSize).round().clamp(0, tileSize - miniMapSize);

      final cropped = img.copyCrop(
        tileImage,
        x: cropX,
        y: cropY,
        width: miniMapSize,
        height: miniMapSize,
      );

      // ── Gambar marker GPS di tengah crop ──────────────────────
      final cx = (offset.px - cropX).round().clamp(0, miniMapSize - 1);
      final cy = (offset.py - cropY).round().clamp(0, miniMapSize - 1);

      // Lingkaran luar putih
      img.drawCircle(
        cropped,
        x: cx,
        y: cy,
        radius: markerRadius + 2,
        color: img.ColorRgba8(255, 255, 255, 220),
        antialias: true,
      );
      // Lingkaran dalam merah
      img.drawCircle(
        cropped,
        x: cx,
        y: cy,
        radius: markerRadius,
        color: img.ColorRgba8(220, 50, 50, 255),
        antialias: true,
      );
      // Titik tengah putih kecil
      img.drawCircle(
        cropped,
        x: cx,
        y: cy,
        radius: 2,
        color: img.ColorRgba8(255, 255, 255, 255),
        antialias: true,
      );

      // ── Border tipis di sekeliling minimap ────────────────────
      img.drawRect(
        cropped,
        x1: 0,
        y1: 0,
        x2: miniMapSize - 1,
        y2: miniMapSize - 1,
        color: img.ColorRgba8(255, 255, 255, 180),
        thickness: 2,
      );

      return Uint8List.fromList(img.encodePng(cropped));
    } catch (e) {
      debugPrint('MiniMap fetch error: $e');
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────
// STEP 3: Modifikasi ImageProcessParams
//
// Ganti class ImageProcessParams yang ada dengan ini:
// ─────────────────────────────────────────────────────────────

class ImageProcessParamsWithMap {
  final Uint8List imageBytes;
  final DateTime timestamp;
  final Position? position;
  final String address;
  final int quality;
  final int maxDimension;
  final String watermarkPosition;
  final Uint8List? mapTileBytes; // ← BARU

  const ImageProcessParamsWithMap({
    required this.imageBytes,
    required this.timestamp,
    this.position,
    required this.address,
    required this.quality,
    required this.maxDimension,
    required this.watermarkPosition,
    this.mapTileBytes, // ← BARU
  });
}

// ─────────────────────────────────────────────────────────────
// STEP 4: Modifikasi _addWatermarkFast
//
// Tambahkan minimap di kanan watermark.
// Ganti fungsi _addWatermarkFast yang lama dengan versi ini:
// ─────────────────────────────────────────────────────────────

img.Image addWatermarkWithMiniMap(
    img.Image src, ImageProcessParamsWithMap params) {
  final now = params.timestamp;
  final pos = params.position;
  final alamat = params.address;

  final tanggal = _formatDate(now);
  final jam = _formatTime(now);

  final gpsAvailable = pos != null;
  final lat =
      gpsAvailable ? pos.latitude.toStringAsFixed(5) : 'N/A';
  final lon =
      gpsAvailable ? pos.longitude.toStringAsFixed(5) : 'N/A';
  final acc =
      gpsAvailable ? '${pos.accuracy.toStringAsFixed(0)}m' : 'No GPS';

  // ── Tinggi strip watermark ─────────────────────────────────
  final int stripHeight =
      (src.height * CameraConstants.watermarkHeightRatio)
          .toInt()
          .clamp(
            CameraConstants.watermarkMinHeight,
            CameraConstants.watermarkMaxHeight,
          );

  final isBottom = params.watermarkPosition != 'top';
  final y0 = isBottom ? src.height - stripHeight : 0;

  if (y0 < 0) return src;

  // Background strip transparan hitam
  img.fillRect(
    src,
    x1: 0,
    y1: y0,
    x2: src.width - 1,
    y2: y0 + stripHeight - 1,
    color: img.ColorRgba8(0, 0, 0, 190),
  );

  // ── Gambar minimap di kanan watermark ─────────────────────
  final mapBytes = params.mapTileBytes;
  int textAreaWidth = src.width;

  if (mapBytes != null) {
    final mapImage = img.decodeImage(mapBytes);
    if (mapImage != null) {
      // Hitung ukuran map agar fit di dalam strip
      final maxMapSize = (stripHeight - 8).clamp(60, MiniMapFetcher.miniMapSize);
      final scaledMap = img.copyResize(
        mapImage,
        width: maxMapSize,
        height: maxMapSize,
        interpolation: img.Interpolation.linear,
      );

      final mapX = src.width - scaledMap.width - 8;
      final mapY = y0 + (stripHeight - scaledMap.height) ~/ 2;

      img.compositeImage(src, scaledMap, dstX: mapX, dstY: mapY);

      // Teks hanya sampai sebelum peta (sisakan 10px padding)
      textAreaWidth = mapX - 10;
    }
  }

  // ── Teks watermark ────────────────────────────────────────
  final font = src.width > 1500 ? img.arial24 : img.arial14;
  final white = img.ColorRgba8(255, 255, 255, 255);
  final yellow = img.ColorRgba8(255, 200, 0, 255);
  final green = img.ColorRgba8(100, 220, 100, 255);

  final lineH = (stripHeight / CameraConstants.watermarkLineDivider)
      .floor()
      .clamp(
        CameraConstants.watermarkMinLineHeight,
        CameraConstants.watermarkMaxLineHeight,
      );
  final y = y0 + CameraConstants.watermarkStartOffset;

  if (y + lineH * 5 <= src.height) {
    img.drawString(src, 'TermulLog', font: font, x: 10, y: y, color: yellow);
    img.drawString(src, '$tanggal  $jam', font: font, x: 10, y: y + lineH, color: white);
    img.drawString(src, '$lat, $lon', font: font, x: 10, y: y + lineH * 2, color: white);
    img.drawString(
      src,
      'Acc: $acc',
      font: font,
      x: 10,
      y: y + lineH * 3,
      color: gpsAvailable ? green : white,
    );

    // Potong alamat sesuai lebar area teks tersedia
    final maxAddrChars = (textAreaWidth / 7).floor()
        .clamp(20, CameraConstants.watermarkMaxAddressLength);
    final shortAddr = alamat.length > maxAddrChars
        ? '${alamat.substring(0, maxAddrChars - 3)}...'
        : alamat;

    if (shortAddr.isNotEmpty && y + lineH * 4 < src.height) {
      img.drawString(src, shortAddr, font: font, x: 10, y: y + lineH * 4, color: white);
    }
  }

  return src;
}

// ─────────────────────────────────────────────────────────────
// STEP 5: Modifikasi _ambilFoto di _CameraScreenState
//
// Tambahkan fetch minimap SETELAH _waitForBestGps()
// dan sebelum compute():
//
// // Fetch minimap tile (berjalan paralel dengan reverse geocoding)
// final results = await Future.wait([
//   _getAddressCached(_bestPosition),
//   MiniMapFetcher.fetchMiniMap(_bestPosition!).catchError((_) => null),
// ]);
// final String alamat = results[0] as String? ?? 'Lokasi tidak tersedia';
// final Uint8List? mapTile = results[1] as Uint8List?;
//
// final result = await compute(_processImageOptimized, ImageProcessParamsWithMap(
//   imageBytes: bytes,
//   timestamp: waktuFoto,
//   position: _bestPosition,
//   address: alamat,
//   quality: _photoQuality,
//   maxDimension: CameraConstants.maxImageDimensionPx,
//   watermarkPosition: WatermarkLayoutService.position,
//   mapTileBytes: mapTile,   // ← BARU
// ));
// ─────────────────────────────────────────────────────────────

// Helper private functions (pindahkan dari existing code)
String _formatDate(DateTime dt) {
  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final y = dt.year.toString().substring(2);
  return '$d/$m/$y';
}

String _formatTime(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  final s = dt.second.toString().padLeft(2, '0');
  return '$h:$m:$s';
}

// ─────────────────────────────────────────────────────────────
// STEP 6: Ganti fungsi top-level _processImageOptimized
//
// Ganti dengan versi yang menerima ImageProcessParamsWithMap:
// ─────────────────────────────────────────────────────────────

ProcessedImage processImageWithMap(ImageProcessParamsWithMap params) {
  img.Image? src;

  try {
    src = img.decodeImage(params.imageBytes);
    if (src == null) throw Exception('Decode failed');

    // Bake EXIF orientation (fix rotasi foto kamera Android)
    src = img.bakeOrientation(src);

    if (src.width > params.maxDimension || src.height > params.maxDimension) {
      src = img.copyResize(
        src,
        width: src.width > src.height ? params.maxDimension : null,
        height: src.height > src.width ? params.maxDimension : null,
        interpolation: img.Interpolation.average,
      );
    }

    src = addWatermarkWithMiniMap(src, params);
    final jpegData = img.encodeJpg(src, quality: params.quality);

    return ProcessedImage(jpegData: Uint8List.fromList(jpegData));
  } finally {
    src?.clear();
  }
}

// ─────────────────────────────────────────────────────────────
// Dummy CameraConstants (sudah ada di file utama, ini hanya
// referensi agar file ini bisa di-analyze tanpa error)
// ─────────────────────────────────────────────────────────────
class CameraConstants {
  static const double watermarkHeightRatio = 0.14;
  static const int watermarkMinHeight = 100;
  static const int watermarkMaxHeight = 180;
  static const double watermarkLineDivider = 5.5;
  static const int watermarkMinLineHeight = 16;
  static const int watermarkMaxLineHeight = 28;
  static const int watermarkStartOffset = 10;
  static const int watermarkMaxAddressLength = 42;
}

class ProcessedImage {
  final Uint8List jpegData;
  const ProcessedImage({required this.jpegData});
}
