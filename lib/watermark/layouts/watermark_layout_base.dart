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
}
