// ════════════════════════════════════════════════════════════════════════════
//  services/gallery_service.dart
//  Wrapper untuk GallerySaver dengan dukungan album name
// ════════════════════════════════════════════════════════════════════════════

import 'package:gallery_saver_plus/gallery_saver.dart';

class GalleryService {
  GalleryService._();

  /// Simpan file gambar ke galeri perangkat.
  /// [albumName] - nama album di galeri (default: 'TermulLog')
  /// Mengembalikan true jika berhasil.
  static Future<bool> saveImage(
    String filePath, {
    String albumName = 'TermulLog',
  }) async {
    final ok = await GallerySaver.saveImage(filePath, albumName: albumName);
    return ok == true;
  }
}
