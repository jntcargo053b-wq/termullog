import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutGpsCard extends WatermarkLayoutBase {
  @override
  String get name => 'GPS Card';
  
  static const int panelH = 160;
  static const int padX = 16;
  static const int mapW = 160;
  static const int mapH = 100;
  static const int maxAddrLen = 45;

  @override
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
  }) {
    final bool isTop = watermarkPosition == 'top';
    final int y0 = isTop ? 0 : src.height - panelH;
    if (y0 < 0) return WatermarkLayoutBase.encodeJpg(src);

    // Background panel dengan gradient
    for (int y = y0; y < y0 + panelH; y++) {
      final t = (y - y0) / panelH;
      final r = (15 + t * 5).toInt().clamp(0, 20);
      final g = (15 + t * 5).toInt().clamp(0, 20);
      final b = (25 + t * 10).toInt().clamp(0, 35);
      final a = (200 + t * 40).toInt().clamp(200, 240);
      img.fillRect(src, x1: 0, y1: y, x2: src.width - 1, y2: y + 1,
          color: img.ColorRgba8(r, g, b, a));
    }

    // Garis aksen dengan glow
    img.fillRect(src, x1: 0, y1: y0 - 2, x2: src.width - 1, y2: y0 + 1,
        color: img.ColorRgba8(0, 180, 255, 30));
    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + 4,
        color: img.ColorRgba8(0, 180, 255, 255));

    final font = img.arial24;
    int cy = y0 + 10;
    int textX = padX;

    // Pin merah kecil
    img.fillCircle(src, x: textX + 6, y: cy + 10, radius: 5,
        color: img.ColorRgba8(255, 50, 50, 255));
    img.fillCircle(src, x: textX + 6, y: cy + 10, radius: 2,
        color: img.ColorRgba8(255, 255, 255, 200));

    // Mini map
    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) {
      try {
        final mapImage = img.decodeImage(mapBytes);
        if (mapImage != null) {
          final resized = img.copyResize(mapImage, width: mapW, height: mapH);
          final mapX = src.width - mapW - padX;
          final mapY = y0 + 30;
          // Border map
          img.fillRect(src, x1: mapX - 2, y1: mapY - 2, x2: mapX + mapW + 2, y2: mapY + mapH + 2,
              color: img.ColorRgba8(0, 180, 255, 80));
          img.compositeImage(src, resized, dstX: mapX, dstY: mapY, blend: img.BlendMode.alpha);
          // Border dalam
          img.drawRect(src, x1: mapX, y1: mapY, x2: mapX + mapW - 1, y2: mapY + mapH - 1,
              color: img.ColorRgba8(255, 255, 255, 30), thickness: 1);
        }
      } catch (_) {}
    }

    // Tanggal + Jam dengan shadow
    _drawWithShadow(src, DateFormat('yyyy-MM-dd  HH:mm:ss').format(timestamp),
        font: font, x: textX + 16, y: cy, color: WatermarkLayoutBase.white);
    cy += 28;

    // Koordinat
    if (hasPosition) {
      final latStr = _toDMS(lat!, true);
      final lonStr = _toDMS(lon!, false);
      String coordLine = '$latStr  $lonStr';
      if (showAccuracy) coordLine += '  ±${acc?.toStringAsFixed(0) ?? '?'}m';
      _drawWithShadow(src, coordLine, font: font, x: textX + 16, y: cy, color: WatermarkLayoutBase.blue);
      cy += 28;
    }

    // Alamat
    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      String addr = address.length > maxAddrLen ? '${address.substring(0, maxAddrLen - 1)}…' : address;
      img.drawString(src, addr, font: font, x: textX + 16, y: cy, color: WatermarkLayoutBase.grey);
      cy += 28;
    }

    // Cuaca dengan chip
    if (showWeather && weather.isNotEmpty) {
      img.fillRect(src, x1: textX + 12, y1: cy - 2, x2: textX + 200, y2: cy + 22,
          color: img.ColorRgba8(0, 180, 255, 30));
      img.drawString(src, weather, font: font, x: textX + 16, y: cy, color: WatermarkLayoutBase.blue);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  void _drawWithShadow(img.Image src, String text, {required img.BitmapFont font, required int x, required int y, required img.Color color}) {
    img.drawString(src, text, font: font, x: x + 1, y: y + 1, color: img.ColorRgba8(0, 0, 0, 80));
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  String _toDMS(double coord, bool isLat) {
    final d = coord.abs().floor();
    final m = ((coord.abs() - d) * 60).floor();
    final s = ((coord.abs() - d - m / 60) * 3600).toStringAsFixed(1);
    final dir = isLat ? (coord >= 0 ? 'N' : 'S') : (coord >= 0 ? 'E' : 'W');
    return '${d}°${m}\'${s}"$dir';
  }
}
