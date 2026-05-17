// lib/watermark/layouts/layout_timemark_style.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutTimeMarkStyle extends WatermarkLayoutBase {
  @override
  String get name => 'TimeMark Style';

  static const double _padX = 20;
  static const double _padY = 14;
  static const double _mapSz = 130;
  static const double _panelH = 210;
  static const double _radius = 10;

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
    final int panelH = _panelH.toInt();
    final int y0 = isTop ? 0 : src.height - panelH;
    if (y0 < 0) return WatermarkLayoutBase.encodeJpg(src);

    const m = 10;

    // Card background hitam
    img.fillRect(src,
        x1: m, y1: y0 + m, x2: src.width - m, y2: y0 + panelH - m,
        color: img.ColorRgba8(0, 0, 0, 200));

    // Border putih tipis
    img.drawRect(src,
        x1: m, y1: y0 + m, x2: src.width - m, y2: y0 + panelH - m,
        color: img.ColorRgba8(255, 255, 255, 40), thickness: 1);

    final f14 = img.arial14;
    final f24 = img.arial24;
    int cx = (_padX + m).toInt();
    int cy = (y0 + _padY + m).toInt();

    // Jam besar — PUTIH
    img.drawString(src, DateFormat('HH:mm').format(timestamp),
        font: f24, x: cx + 1, y: cy + 1, color: img.ColorRgba8(0, 0, 0, 100));
    img.drawString(src, DateFormat('HH:mm').format(timestamp),
        font: f24, x: cx, y: cy, color: WatermarkLayoutBase.white);

    // Detik kecil — BIRU
    img.drawString(src, DateFormat('ss').format(timestamp),
        font: f14, x: cx + 88, y: cy + 10, color: WatermarkLayoutBase.blue);

    cy += 36;

    // Tanggal panjang — PUTIH
    img.drawString(src,
        DateFormat('EEEE, dd MMMM yyyy', 'id').format(timestamp),
        font: f14, x: cx + 1, y: cy + 1, color: img.ColorRgba8(0, 0, 0, 100));
    img.drawString(src,
        DateFormat('EEEE, dd MMMM yyyy', 'id').format(timestamp),
        font: f14, x: cx, y: cy, color: WatermarkLayoutBase.white);

    cy += 24;

    // Koordinat DMS — BIRU
    if (hasPosition) {
      final coord = '${_toDMS(lat!, true)}   ${_toDMS(lon!, false)}';
      img.drawString(src, coord, font: f14, x: cx + 1, y: cy + 1,
          color: img.ColorRgba8(0, 0, 0, 100));
      img.drawString(src, coord, font: f14, x: cx, y: cy,
          color: WatermarkLayoutBase.blue);
      cy += 22;
    }

    // Akurasi — ABU-ABU
    if (showAccuracy && hasPosition) {
      img.drawString(src, '± ${acc?.toStringAsFixed(0) ?? '?'} m',
          font: f14, x: cx, y: cy, color: WatermarkLayoutBase.grey);
      cy += 20;
    }

    // Alamat (2 baris) — PUTIH
    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      for (final line in _splitAddress(address)) {
        img.drawString(src, line, font: f14, x: cx, y: cy, color: WatermarkLayoutBase.white);
        cy += 20;
      }
    }

    // Cuaca — BIRU
    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, weather, font: f14, x: cx, y: cy, color: WatermarkLayoutBase.blue);
    }

    // Mini map di kanan bawah
    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) {
      _drawMiniMapSync(src, mapBytes, y0: y0, panelH: panelH);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  String _toDMS(double coord, bool isLat) {
    final d = coord.abs().floor();
    final m = ((coord.abs() - d) * 60).floor();
    final s = ((coord.abs() - d - m / 60) * 3600).toStringAsFixed(1);
    final dir = isLat ? (coord >= 0 ? 'N' : 'S') : (coord >= 0 ? 'E' : 'W');
    return '$d°$m\'$s"$dir';
  }

  List<String> _splitAddress(String address) {
    final parts = address.split(',');
    if (parts.length <= 2) return [address.length > 52 ? '${address.substring(0, 49)}…' : address];
    final line1 = parts.take(2).join(',').trim();
    final raw2 = parts.skip(2).join(',').trim();
    final line2 = raw2.length > 52 ? '${raw2.substring(0, 49)}…' : raw2;
    return [line1, line2];
  }

  void _drawMiniMapSync(img.Image src, Uint8List mapBytes, {required int y0, required int panelH}) {
    try {
      final mapImage = img.decodeImage(mapBytes);
      if (mapImage == null) return;
      final sz = _mapSz.toInt();
      final mx = src.width - sz - _padX.toInt() - 10;
      final my = y0 + panelH - sz - _padY.toInt() - 10;
      if (mx < 0 || my < 0) return;
      final resized = img.copyResize(mapImage, width: sz, height: sz);
      img.compositeImage(src, resized, dstX: mx, dstY: my, blend: img.BlendMode.alpha);
      img.drawRect(src, x1: mx - 1, y1: my - 1, x2: mx + sz, y2: my + sz,
          color: WatermarkLayoutBase.blue, thickness: 2);
    } catch (_) {}
  }
}
