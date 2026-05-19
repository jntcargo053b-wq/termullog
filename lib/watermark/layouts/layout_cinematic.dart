// lib/watermark/layouts/layout_cinematic.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutCinematic extends WatermarkLayoutBase {
  @override
  String get name => 'GPS Timestamp';

  static const int _padX = 24;
  static const int _padY = 20;

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
    // ── Adaptive scaling berdasarkan lebar foto ──────────────────
    final double scale = (src.width / 1080).clamp(0.7, 2.0);

    final int mapH      = (120 * scale).round();
    final int lineH     = (32 * scale).round();
    final int smallLine = (24 * scale).round();
    final int padX      = (_padX * scale).round();
    final int padY      = (_padY * scale).round();
    final int margin    = (12 * scale).round();
    final int pinRadius = (8 * scale).round();

    // ── Pilih font berdasarkan ukuran foto & setting ─────────────
    final double fs = fontSize == 'small' ? 0.8 : fontSize == 'large' ? 1.3 : 1.0;
    final bool isLarge = src.width > 2500;
    final img.BitmapFont fontMain = (isLarge || fontSize == 'large')
        ? img.arial24
        : (fontSize == 'small' ? img.arial14 : img.arial24);
    final img.BitmapFont fontSmall = (isLarge || fontSize == 'large')
        ? img.arial24
        : img.arial14;

    // ── Hitung tinggi panel ─────────────────────────────────────
    int rowCount = 0;
    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) rowCount += 1;
    rowCount += 2; // jam + tanggal
    rowCount += 1; // divider
    if (showCoordinates && hasPosition) rowCount += 1;
    if (showAddress && address.isNotEmpty) rowCount += 2;
    if (showWeather && weather.isNotEmpty) rowCount += 1;

    final int panelH = (showMiniMap && mapBytes != null && mapBytes.isNotEmpty ? mapH + padY : 0)
        + padY * 2 + rowCount * (smallLine + 4) + 20;
    final int y0 = src.height - panelH;
    if (y0 < 0 || y0 >= src.height) return WatermarkLayoutBase.encodeJpg(src);

    final int cardW = src.width - margin * 2;
    final int cardX = margin;

    // ── Card background ────────────────────────────────────────
    img.fillRect(src,
        x1: cardX, y1: y0 + margin,
        x2: cardX + cardW, y2: y0 + panelH - margin,
        color: img.ColorRgba8(19, 19, 19, (255 * opacity).toInt()));

    if (showBorder) {
      img.drawRect(src,
          x1: cardX, y1: y0 + margin,
          x2: cardX + cardW, y2: y0 + panelH - margin,
          color: img.ColorRgba8(255, 255, 255, 20), thickness: 1);
    }

    int cy = y0 + margin + padY;

    // ── Mini map di atas ───────────────────────────────────────
    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) {
      try {
        final map = img.decodeImage(mapBytes);
        if (map != null) {
          final resized = img.copyResize(map, width: cardW, height: mapH);
          final mapX = cardX;
          final mapY = cy;
          img.fillRect(src,
              x1: mapX, y1: mapY,
              x2: mapX + cardW, y2: mapY + mapH,
              color: img.ColorRgba8(0, 0, 0, 60));
          img.compositeImage(src, resized,
              dstX: mapX, dstY: mapY, blend: img.BlendMode.alpha);
          // Pin lokasi dengan shadow
          final pinX = mapX + cardW ~/ 2;
          final pinY = mapY + mapH ~/ 2;
          img.fillCircle(src, x: pinX + 1, y: pinY + 1, radius: pinRadius,
              color: img.ColorRgba8(0, 0, 0, 100));
          img.fillCircle(src, x: pinX, y: pinY, radius: pinRadius,
              color: img.ColorRgba8(255, 50, 50, 255));
          img.fillCircle(src, x: pinX, y: pinY, radius: (pinRadius * 0.4).round(),
              color: WatermarkLayoutBase.white);
        }
      } catch (_) {}
      cy += mapH + padY;
    }

    // ── Tanggal ────────────────────────────────────────────────
    _shadowText(src,
        DateFormat('EEE, dd MMM yyyy').format(timestamp),
        font: fontMain, x: cardX + padX, y: cy,
        color: WatermarkLayoutBase.white);
    cy += lineH;

    // ── Jam ────────────────────────────────────────────────────
    _shadowText(src,
        DateFormat('HH:mm:ss').format(timestamp),
        font: fontMain, x: cardX + padX, y: cy,
        color: WatermarkLayoutBase.white);
    cy += lineH;

    // ── Divider ────────────────────────────────────────────────
    img.fillRect(src,
        x1: cardX + padX, y1: cy,
        x2: cardX + cardW - padX, y2: cy + (1.5 * scale).round(),
        color: img.ColorRgba8(255, 255, 255, 20));
    cy += (12 * scale).round();

    // ── Alamat ─────────────────────────────────────────────────
    if (showAddress && address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      final lines = _splitAddress(address);
      for (final line in lines.take(2)) {
        _shadowText(src, line,
            font: fontSmall, x: cardX + padX, y: cy,
            color: WatermarkLayoutBase.white);
        cy += smallLine;
      }
    }

    // ── Koordinat ──────────────────────────────────────────────
    if (showCoordinates && hasPosition) {
      _shadowText(src,
          '${lat!.toStringAsFixed(2)}°, ${lon!.toStringAsFixed(2)}°',
          font: fontSmall, x: cardX + padX, y: cy,
          color: WatermarkLayoutBase.blue);
      cy += smallLine;
    }

    // ── Akurasi ────────────────────────────────────────────────
    if (showAccuracy && hasPosition && acc != null) {
      _shadowText(src,
          'Accuracy: ±${acc.toStringAsFixed(0)} m',
          font: fontSmall, x: cardX + padX, y: cy,
          color: WatermarkLayoutBase.grey);
      cy += smallLine;
    }

    // ── Cuaca ──────────────────────────────────────────────────
    if (showWeather && weather.isNotEmpty) {
      _shadowText(src, weather,
          font: fontSmall, x: cardX + padX, y: cy,
          color: WatermarkLayoutBase.blue);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  // ── Helper: shadow text ────────────────────────────────────────
  void _shadowText(img.Image src, String text, {
    required img.BitmapFont font,
    required int x, required int y,
    required img.Color color,
  }) {
    // Shadow
    img.drawString(src, text, font: font, x: x + 2, y: y + 2,
        color: img.ColorRgba8(0, 0, 0, 120));
    // Teks utama
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  List<String> _splitAddress(String address) {
    const maxLen = 42;
    final parts = address.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return [address.length > maxLen ? '${address.substring(0, maxLen - 1)}…' : address];
    final l1 = parts.first;
    final rest = parts.skip(1).join(', ');
    return [
      l1.length > maxLen ? '${l1.substring(0, maxLen - 1)}…' : l1,
      if (rest.isNotEmpty)
        rest.length > maxLen ? '${rest.substring(0, maxLen - 1)}…' : rest,
    ];
  }
}
