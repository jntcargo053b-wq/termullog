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
    bool showAddress = true,
    bool showCoordinates = true,
    double opacity = 0.85,
    bool showBorder = true,
    String fontSize = 'normal',
  }) {
    final bool isTop = watermarkPosition == 'top';
    final int panelH = _panelH.toInt();
    final int y0 = isTop ? 0 : src.height - panelH;
    if (y0 < 0) return WatermarkLayoutBase.encodeJpg(src);

    const m = 10;

    // Card background (opacity dari pengaturan)
    img.fillRect(src,
        x1: m, y1: y0 + m, x2: src.width - m, y2: y0 + panelH - m,
        color: img.ColorRgba8(0, 0, 0, (255 * opacity).toInt()));

    // Border putih tipis
    if (showBorder) {
      img.drawRect(src,
          x1: m, y1: y0 + m, x2: src.width - m, y2: y0 + panelH - m,
          color: img.ColorRgba8(255, 255, 255, 40), thickness: 1);
    }

    final font = fontSize == 'small' ? img.arial14 : fontSize == 'large' ? img.arial24 : img.arial24;
    final smallFont = fontSize == 'small' ? img.arial14 : fontSize == 'large' ? img.arial24 : img.arial14;

    int cx = (_padX + m).toInt();
    int cy = (y0 + _padY + m).toInt();

    // ── Jam besar ──
    img.drawString(src, DateFormat('HH:mm').format(timestamp),
        font: font, x: cx + 1, y: cy + 1, color: img.ColorRgba8(0, 0, 0, 100));
    img.drawString(src, DateFormat('HH:mm').format(timestamp),
        font: font, x: cx, y: cy, color: WatermarkLayoutBase.white);

    // ── Detik kecil ──
    img.drawString(src, DateFormat('ss').format(timestamp),
        font: smallFont, x: cx + 88, y: cy + 10, color: WatermarkLayoutBase.blue);

    cy += 36;

    // ── Tanggal panjang ──
    img.drawString(src,
        DateFormat('EEEE, dd MMMM yyyy', 'id').format(timestamp),
        font: smallFont, x: cx + 1, y: cy + 1, color: img.ColorRgba8(0, 0, 0, 100));
    img.drawString(src,
        DateFormat('EEEE, dd MMMM yyyy', 'id').format(timestamp),
        font: smallFont, x: cx, y: cy, color: WatermarkLayoutBase.white);

    cy += 24;

    // ── Koordinat DMS ──
    if (showCoordinates && hasPosition) {
      final coord = '${_toDMS(lat!, true)}   ${_toDMS(lon!, false)}';
      img.drawString(src, coord, font: smallFont, x: cx + 1, y: cy + 1,
          color: img.ColorRgba8(0, 0, 0, 100));
      img.drawString(src, coord, font: smallFont, x: cx, y: cy,
          color: WatermarkLayoutBase.blue);
      cy += 22;
    }

    // ── Akurasi ──
    if (showAccuracy && hasPosition) {
      img.drawString(src, '± ${acc?.toStringAsFixed(0) ?? '?'} m',
          font: smallFont, x: cx, y: cy, color: WatermarkLayoutBase.grey);
      cy += 20;
    }

    // ── Alamat ──
    if (showAddress && address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      for (final line in _splitAddress(address)) {
        img.drawString(src, line, font: smallFont, x: cx, y: cy, color: WatermarkLayoutBase.white);
        cy += 20;
      }
    }

    // ── Cuaca ──
    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, weather, font: smallFont, x: cx, y: cy, color: WatermarkLayoutBase.blue);
    }

    // ── Mini map ──
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
