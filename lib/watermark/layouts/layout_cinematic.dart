// lib/watermark/layouts/layout_cinematic.dart
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'watermark_layout_base.dart';

class LayoutCinematic extends WatermarkLayoutBase {
  @override
  String get name => 'Cinematic Modern';

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
    required bool showMiniMap,
    Uint8List? mapBytes,
    bool showAddress = true,
    bool showCoordinates = true,
    double opacity = 0.85,
    bool showBorder = true,
    String fontSize = 'normal',
    String mapSize = 'medium',
    String dateFormat = 'dd MMM yyyy',
    String timeFormat = 'HH:mm:ss',
  }) {
    final double scale = (src.width / 1080).clamp(0.7, 2.0);
    final int padX   = (24 * scale).round();
    final int padY   = (20 * scale).round();
    final int margin = (16 * scale).round();

    // Font (hanya arial14, arial24, arial48 yang ada di image 4.x)
    final img.BitmapFont fontDate = fontSize == 'small' ? img.arial14 : img.arial24;
    final img.BitmapFont fontTime = img.arial24;
    final img.BitmapFont fontInfo = fontSize == 'large' ? img.arial24 : img.arial14;

    // FIX: gunakan .lineHeight (bukan .height yang tidak ada di image 4.8)
    final int dateH  = fontDate.lineHeight;
    final int timeH  = fontTime.lineHeight;
    final int infoH  = fontInfo.lineHeight;

    // Hitung tinggi panel dari baris yang benar-benar digambar
    int contentH = 0;
    contentH += dateH + 8;
    contentH += timeH + 12;
    contentH += 14; // separator

    final bool drawCoord   = showCoordinates && hasPosition && lat != null && lon != null;
    final bool drawAcc     = showAccuracy && hasPosition && acc != null;
    final bool drawWeather = showWeather && weather.isNotEmpty;
    final bool hasMap      = showMiniMap && mapBytes != null && mapBytes.isNotEmpty;
    final int  mapH        = (120 * scale).round();

    List<String> addressLines = [];
    if (showAddress && address.isNotEmpty && !address.startsWith('GPS:')) {
      addressLines = _splitAddress(address, scale);
      contentH += addressLines.length * (infoH + 6);
    }
    if (drawCoord)   contentH += infoH + 6;
    if (drawAcc)     contentH += infoH + 6;
    if (drawWeather) contentH += infoH + 6;
    if (hasMap)      contentH += mapH + padY;

    final int panelH = contentH + padY * 2;
    final int cardW  = src.width - margin * 2;
    final int cardX  = margin;

    if (panelH > src.height) return WatermarkLayoutBase.encodeJpg(src);
    final int cardY = (src.height - panelH - margin).clamp(0, src.height - panelH);

    // ── 1. Background gradien (16 step batch) ────────────────────────────
    final int alphaInt = (255 * opacity).round().clamp(0, 255);
    const int bgR1 = 20, bgG1 = 20, bgB1 = 28;
    const int bgR2 =  8, bgG2 =  8, bgB2 = 12;
    const int steps = 16;
    final int stepH = (panelH / steps).ceil();
    for (int s = 0; s < steps; s++) {
      final double t = s / (steps - 1);
      final int y1 = cardY + s * stepH;
      final int y2 = (y1 + stepH).clamp(0, cardY + panelH);
      if (y1 >= y2) continue;
      img.fillRect(src,
          x1: cardX, y1: y1, x2: cardX + cardW, y2: y2,
          color: img.ColorRgba8(
            _lerp(bgR1, bgR2, t),
            _lerp(bgG1, bgG2, t),
            _lerp(bgB1, bgB2, t),
            alphaInt,
          ));
    }

    // ── 2. Border ────────────────────────────────────────────────────────
    if (showBorder) {
      _drawBorder(src, cardX, cardY, cardW, panelH,
          img.ColorRgba8(255, 255, 255, 55), 2);
    }

    // ── 3. Shadow bawah ───────────────────────────────────────────────────
    final int shadowH  = (6 * scale).round();
    final int shadowY1 = cardY + panelH;
    final int shadowY2 = (shadowY1 + shadowH).clamp(0, src.height);
    if (shadowY1 < src.height && shadowY1 < shadowY2) {
      img.fillRect(src,
          x1: cardX + 4, y1: shadowY1,
          x2: cardX + cardW - 4, y2: shadowY2,
          color: img.ColorRgba8(0, 0, 0, 70));
    }

    // ── Render konten ────────────────────────────────────────────────────
    int cy = cardY + padY;

    // Mini map
    if (hasMap) {
      try {
        final map = img.decodeImage(mapBytes!);
        if (map != null) {
          final mapW    = cardW - padX * 2;
          final resized = img.copyResize(map, width: mapW, height: mapH);
          img.compositeImage(src, resized,
              dstX: cardX + padX, dstY: cy, blend: img.BlendMode.alpha);
          final pinX = cardX + padX + mapW ~/ 2;
          final pinY = cy + mapH ~/ 2;
          img.fillCircle(src, x: pinX, y: pinY,
              radius: (7 * scale).round(), color: img.ColorRgba8(255, 60, 60, 255));
          img.fillCircle(src, x: pinX, y: pinY,
              radius: (3 * scale).round(), color: img.ColorRgba8(255, 255, 255, 210));
        }
      } catch (_) {}
      cy += mapH + padY;
    }

    // Tanggal
    img.drawString(src, DateFormat(dateFormat).format(timestamp),
        font: fontDate, x: cardX + padX, y: cy,
        color: img.ColorRgba8(200, 200, 225, 255));
    cy += dateH + 8;

    // Waktu
    img.drawString(src, DateFormat(timeFormat).format(timestamp),
        font: fontTime, x: cardX + padX, y: cy,
        color: img.ColorRgba8(255, 255, 255, 255));
    cy += timeH + 12;

    // Separator
    img.fillRect(src,
        x1: cardX + padX, y1: cy,
        x2: cardX + cardW - padX, y2: cy + 2,
        color: img.ColorRgba8(255, 255, 255, 35));
    cy += 14;

    // Alamat
    for (final line in addressLines) {
      img.drawString(src, line,
          font: fontInfo, x: cardX + padX, y: cy,
          color: img.ColorRgba8(220, 220, 240, 255));
      cy += infoH + 6;
    }

    // Koordinat
    if (drawCoord) {
      img.drawString(src,
          '${lat!.toStringAsFixed(6)}, ${lon!.toStringAsFixed(6)}',
          font: fontInfo, x: cardX + padX, y: cy,
          color: img.ColorRgba8(100, 180, 250, 255));
      cy += infoH + 6;
    }

    // Akurasi
    if (drawAcc) {
      img.drawString(src,
          'Akurasi: +/-${acc!.toStringAsFixed(1)}m',
          font: fontInfo, x: cardX + padX, y: cy,
          color: img.ColorRgba8(180, 230, 180, 255));
      cy += infoH + 6;
    }

    // Cuaca
    if (drawWeather) {
      img.drawString(src, weather,
          font: fontInfo, x: cardX + padX, y: cy,
          color: img.ColorRgba8(160, 210, 255, 255));
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _drawBorder(img.Image src, int x, int y, int w, int h,
      img.Color color, int thickness) {
    for (int i = 0; i < thickness; i++) {
      img.fillRect(src, x1: x,         y1: y + i,         x2: x + w,     y2: y + i + 1,     color: color);
      img.fillRect(src, x1: x,         y1: y + h - i - 1, x2: x + w,     y2: y + h - i,     color: color);
      img.fillRect(src, x1: x + i,     y1: y,             x2: x + i + 1, y2: y + h,         color: color);
      img.fillRect(src, x1: x + w-i-1, y1: y,             x2: x + w - i, y2: y + h,         color: color);
    }
  }

  // FIX: terima int biasa (bukan num) — warna dikonversi sebelum dipanggil
  int _lerp(int a, int b, double t) =>
      (a + (b - a) * t).round().clamp(0, 255);

  List<String> _splitAddress(String address, double scale) {
    final int maxLen = (38 + (scale * 8).round()).clamp(38, 55);
    final words = address.split(' ');
    final lines = <String>[];
    String current = '';
    for (final word in words) {
      if ((current + word).length > maxLen) {
        if (current.isNotEmpty) lines.add(current.trim());
        if (lines.length >= 2) break;
        current = '$word ';
      } else {
        current += '$word ';
      }
    }
    if (lines.length < 2 && current.trim().isNotEmpty) lines.add(current.trim());
    return lines;
  }
}
