// lib/services/gallery_service.dart
// Wrapper untuk GallerySaver dengan error handling
import 'package:gallery_saver_plus/gallery_saver.dart';

class GalleryService {
  GalleryService._();

  /// Simpan file gambar ke galeri perangkat.
  /// [filePath] - path absolut file gambar
  /// [albumName] - nama album di galeri (default: 'TermulLog')
  /// Returns `true` jika berhasil, `false` jika gagal (permission, error, dll)
  static Future<bool> saveImage(
    String filePath, {
    String albumName = 'TermulLog',
  }) async {
    try {
      final result = await GallerySaver.saveImage(filePath, albumName: albumName);
      return result == true;
    } catch (_) {
      return false;
    }
  }
}
