// ════════════════════════════════════════════════════════════════════════════
//  services/logo_cache.dart
//  Cache in-memory untuk logo perusahaan (decoded image + raw PNG bytes)
// ════════════════════════════════════════════════════════════════════════════

import 'dart:io';


import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../core/constants.dart';

class LogoCache {
  LogoCache._();

  static Uint8List?  _bytes;
  static img.Image?  _decoded;
  static String?     _path;

  static Uint8List?  get bytes   => _bytes;
  static img.Image?  get decoded => _decoded;
  static bool        get hasLogo => _bytes != null;

  static Future<void> load(String path) async {
    if (_path == path) return; // sudah di-cache
    try {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('LogoCache: file not found $path');
        return;
      }

      final raw     = await file.readAsBytes();
      img.Image? decoded = img.decodeImage(raw);
      if (decoded == null) return;

      if (decoded.width > kLogoMaxWidth || decoded.height > kLogoMaxWidth) {
        decoded = img.copyResize(
          decoded,
          width: kLogoMaxWidth,
          interpolation: img.Interpolation.linear,
        );
      }
      if (decoded.width <= 0 || decoded.height <= 0) return;

      _bytes   = Uint8List.fromList(img.encodePng(decoded));
      _decoded = decoded;
      _path    = path;
    } catch (e) {
      debugPrint('LogoCache.load error: $e');
      _bytes = null; _decoded = null; _path = null;
    }
  }

  static void clear() {
    _bytes = null; _decoded = null; _path = null;
  }
}
