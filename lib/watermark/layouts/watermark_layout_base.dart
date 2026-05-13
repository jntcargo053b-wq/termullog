import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Base class untuk semua layout watermark
abstract class WatermarkLayoutBase {
  /// Nama layout untuk debugging
  String get name;
  
  /// Konstanta warna yang digunakan oleh semua layout
  static final white    = img.ColorRgba8(255, 255, 255, 255);
  static final offWhite = img.ColorRgba8(230, 230, 230, 255);
  static final blue     = img.ColorRgba8(30, 144, 255, 255);
  static final grey     = img.ColorRgba8(150, 150, 150, 255);
  
  /// Apply watermark ke gambar
  Uint8List apply({
    required img.Image src,
    required DateTime timestamp,
    required bool hasPosition,
    required double? lat,
    required double? lon,
    required double? acc,
    required String address,
    required String weather,
    required bool showWeather,
    required bool showAccuracy,
    required String watermarkPosition,
    required bool showMiniMap,
    Uint8List? mapBytes,
  });
  
  /// Helper untuk decode gambar dengan validasi
  static img.Image decodeOrThrow(Uint8List bytes) {
    if (bytes.isEmpty) throw Exception('Data gambar kosong');
    if (bytes.length < 100) throw Exception('Data gambar terlalu kecil, mungkin corrupt');
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Format gambar tidak didukung');
    return decoded;
  }
  
  /// Encode ke JPEG dengan quality standar
  static Uint8List encodeJpg(img.Image src, {int quality = 95}) {
    return Uint8List.fromList(img.encodeJpg(src, quality: quality));
  }

  /// Menggambar mini map di pojok kanan, di atas atau di bawah watermark
  /// [watermarkHeight] tinggi panel watermark agar mini map tidak overlap
  /// [isTop] true jika watermark di atas (mini map di pojok kanan bawah)
  static void drawMiniMap(
    img.Image src,
    Uint8List mapBytes, {
    int watermarkHeight = 0,
    bool isTop = false,
  }) {
    if (mapBytes.isEmpty) return;
    try {
      final mapImage = img.decodeImage(mapBytes);
      if (mapImage == null) return;

      const int mapW   = 220;
      const int mapH   = 140;
      const int margin = 16;

      final resized = (mapImage.width != mapW || mapImage.height != mapH)
          ? img.copyResize(mapImage, width: mapW, height: mapH)
          : mapImage;

      // Posisi: pojok kanan, hindari panel watermark
      final int mapX = src.width - mapW - margin;
      final int mapY = isTop
          ? watermarkHeight + margin           // watermark di atas → mini map tepat di bawahnya
          : src.height - watermarkHeight - mapH - margin; // watermark di bawah → mini map di atasnya

      if (mapX < 0 || mapY < 0) return;
      if (mapX + mapW > src.width || mapY + mapH > src.height) return;

      // Overlay
      img.compositeImage(src, resized, dstX: mapX, dstY: mapY);

      // Border biru
      img.drawRect(src,
          x1: mapX - 2, y1: mapY - 2,
          x2: mapX + mapW + 1, y2: mapY + mapH + 1,
          color: blue, thickness: 2);

      // Pin lokasi di tengah
      final int cx = mapX + mapW ~/ 2;
      final int cy = mapY + mapH ~/ 2;
      img.fillCircle(src, x: cx, y: cy, radius: 7,
          color: img.ColorRgba8(255, 50, 50, 255));
      img.fillCircle(src, x: cx, y: cy, radius: 3,
          color: white);
    } catch (_) {
      // Silent fail – mini map is optional
    }
  }
}
