// lib/watermark/layouts/layout_timemark_style.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutTimeMarkStyle extends WatermarkLayoutBase {
  @override
  String get name => 'TimeMark Style';

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
    // ── Adaptive scaling ──────────────────────────────────────────
    final double scale = (src.width / 1080).clamp(0.7, 2.0);
    final double fsMultiplier = fontSize == 'small' ? 0.75 : fontSize == 'large' ? 1.4 : 1.0;

    final double padX = (20 * scale);
    final double padY = (14 * scale);
    final double mapSz = (130 * scale);
    final double margin = (10 * scale);

    // ── Hitung tinggi panel dinamis ──────────────────────────────
    int rowCount = 0;
    rowCount += 2; // jam + tanggal
    if (showCoordinates && hasPosition) rowCount += 1;
    if (showAccuracy && hasPosition) rowCount += 1;
    if (showAddress && address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      rowCount += _splitAddress(address).length;
    }
    if (showWeather && weather.isNotEmpty) rowCount += 1;

    final double lineH = (24 * scale * fsMultiplier);
    final double panelH = padY * 2 + rowCount * lineH + 40;

    final bool isTop = watermarkPosition == 'top';
    final double y0 = isTop ? 0.0 : src.height - panelH;
    if (y0 < 0 || y0 >= src.height) return WatermarkLayoutBase.encodeJpg(src);

    final int yi = y0.toInt();
    final int mi = margin.toInt();
    final int pi = panelH.toInt();

    // ── Card background ──────────────────────────────────────────
    img.fillRect(src,
        x1: mi, y1: yi + mi, x2: src.width - mi, y2: yi + pi - mi,
        color: img.ColorRgba8(0, 0, 0, (255 * opacity).toInt()));

    // ── Border ───────────────────────────────────────────────────
    if (showBorder) {
      img.drawRect(src,
          x1: mi, y1: yi + mi, x2: src.width - mi, y2: yi + pi - mi,
          color: img.ColorRgba8(255, 255, 255, 40), thickness: (1 * scale).round());
    }

    // ── Pilih font ───────────────────────────────────────────────
    final font = fontSize == 'small' ? img.arial14 : fontSize == 'large' ? img.arial24 : img.arial24;
    final smallFont = fontSize == 'small' ? img.arial14 : fontSize == 'large' ? img.arial24 : img.arial14;

    int cx = (padX + margin).toInt();
    int cy = (yi + padY + margin).toInt();

    // ── Jam besar (shadow) ───────────────────────────────────────
    img.drawString(src, DateFormat('HH:mm').format(timestamp),
        font: font, x: cx + 1, y: cy + 1, color: img.ColorRgba8(0, 0, 0, 100));
    img.drawString(src, DateFormat('HH:mm').format(timestamp),
        font: font, x: cx, y: cy, color: WatermarkLayoutBase.white);

    // ── Detik kecil ──────────────────────────────────────────────
    final int secX = (cx + 88 * scale).toInt();
    final int secY = (cy + 10 * scale).toInt();
    img.drawString(src, DateFormat('ss').format(timestamp),
        font: smallFont, x: secX, y: secY, color: WatermarkLayoutBase.blue);

    cy += (36 * scale).toInt();

    // ── Tanggal panjang (shadow) ─────────────────────────────────
    img.drawString(src,
        DateFormat('EEEE, dd MMMM yyyy', 'id').format(timestamp),
        font: smallFont, x: cx + 1, y: cy + 1, color: img.ColorRgba8(0, 0, 0, 100));
    img.drawString(src,
        DateFormat('EEEE, dd MMMM yyyy', 'id').format(timestamp),
        font: smallFont, x: cx, y: cy, color: WatermarkLayoutBase.white);

    cy += (24 * scale).toInt();

    // ── Koordinat DMS ────────────────────────────────────────────
    if (showCoordinates && hasPosition) {
      final coord = '${_toDMS(lat!, true)}   ${_toDMS(lon!, false)}';
      img.drawString(src, coord, font: smallFont, x: cx + 1, y: cy + 1,
          color: img.ColorRgba8(0, 0, 0, 100));
      img.drawString(src, coord, font: smallFont, x: cx, y: cy,
          color: WatermarkLayoutBase.blue);
      cy += (22 * scale).toInt();
    }

    // ── Akurasi ──────────────────────────────────────────────────
    if (showAccuracy && hasPosition) {
      img.drawString(src, '± ${acc?.toStringAsFixed(0) ?? '?'} m',
          font: smallFont, x: cx, y: cy, color: WatermarkLayoutBase.grey);
      cy += (20 * scale).toInt();
    }

    // ── Alamat ───────────────────────────────────────────────────
    if (showAddress && address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      for (final line in _splitAddress(address)) {
        img.drawString(src, line, font: smallFont, x: cx, y: cy, color: WatermarkLayoutBase.white);
        cy += (20 * scale).toInt();
      }
    }

    // ── Cuaca ────────────────────────────────────────────────────
    if (showWeather && weather.isNotEmpty) {
      // Chip background
      img.fillRect(src,
          x1: cx - 4, y1: cy - 2,
          x2: cx + weather.length * 7 + 12, y2: cy + (18 * scale).toInt(),
          color: img.ColorRgba8(30, 144, 255, 25));
      img.drawString(src, weather, font: smallFont, x: cx, y: cy, color: WatermarkLayoutBase.blue);
    }

    // ── Mini map ─────────────────────────────────────────────────
    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) {
      _drawMiniMapSync(src, mapBytes, y0: yi, panelH: pi, mapSz: mapSz, padX: padX, padY: padY, margin: margin);
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

  void _drawMiniMapSync(img.Image src, Uint8List mapBytes, {
    required int y0,
    required int panelH,
    required double mapSz,
    required double padX,
    required double padY,
    required double margin,
  }) {
    try {
      final mapImage = img.decodeImage(mapBytes);
      if (mapImage == null) return;
      final sz = mapSz.toInt();
      final mx = src.width - sz - padX.toInt() - margin.toInt();
      final my = y0 + panelH - sz - padY.toInt() - margin.toInt();
      if (mx < 0 || my < 0) return;
      final resized = img.copyResize(mapImage, width: sz, height: sz);
      // Shadow
      img.fillRect(src, x1: mx + 2, y1: my + 2, x2: mx + sz + 2, y2: my + sz + 2,
          color: img.ColorRgba8(0, 0, 0, 60));
      // Map
      img.compositeImage(src, resized, dstX: mx, dstY: my, blend: img.BlendMode.alpha);
      // Border
      img.drawRect(src, x1: mx - 1, y1: my - 1, x2: mx + sz, y2: my + sz,
          color: WatermarkLayoutBase.blue, thickness: 2);
      // Pin
      final pinX = mx + sz ~/ 2;
      final pinY = my + sz ~/ 2;
      img.fillCircle(src, x: pinX + 1, y: pinY + 1, radius: 5,
          color: img.ColorRgba8(0, 0, 0, 80));
      img.fillCircle(src, x: pinX, y: pinY, radius: 5,
          color: img.ColorRgba8(255, 50, 50, 255));
      img.fillCircle(src, x: pinX, y: pinY, radius: 2,
          color: WatermarkLayoutBase.white);
    } catch (_) {}
  }
}
