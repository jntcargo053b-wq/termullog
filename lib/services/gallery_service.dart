// ════════════════════════════════════════════════════════════════════════════
//  services/gallery_service.dart
//  Wrapper tipis untuk GallerySaver agar mudah di-mock saat testing
// ════════════════════════════════════════════════════════════════════════════

import 'package:gallery_saver_plus/gallery_saver.dart';

class GalleryService {
  GalleryService._();

  /// Simpan file gambar ke galeri perangkat.
  /// Mengembalikan true jika berhasil.
  static Future<bool> saveImage(String filePath) async {
    final ok = await GallerySaver.saveImage(filePath);
    return ok == true;
  }
}
