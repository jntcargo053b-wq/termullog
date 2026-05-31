// lib/services/gallery_service.dart
// Wrapper untuk GallerySaver dengan dukungan album name
// - Safe try-catch untuk mencegah crash
// - Tidak crash jika permission / plugin error
// - Return bool konsisten (true = berhasil, false = gagal)
import 'package:gallery_saver_plus/gallery_saver.dart';

class GalleryService {
  GalleryService._();

  /// Simpan file gambar ke galeri perangkat.
  ///
  /// [filePath] - path absolut file gambar
  /// [albumName] - nama album di galeri (default: 'TermulLog')
  ///
  /// Returns:
  /// - `true` jika berhasil
  /// - `false` jika gagal (permission ditolak, plugin error, dll)
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
