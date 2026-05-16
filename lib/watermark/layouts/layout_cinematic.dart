import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutCinematic extends WatermarkLayoutBase {
  @override
  String get name => 'Cinematic';

  // ── Dimensi area gradient ───────────────────────────────────────────────
  static const int gradH    = 280;
  static const int padX     = 32;
  static const int padY     = 20;    
  static const int lineH    = 34;
  static const int lineHSm  = 22;

  // ── Mini-map ────────────────────────────────────────────────────────────
  static const int mapSize  = 120;
  static const int mapMar   = 24;
  static const int mapBorder = 2;

  // ── Warna cinematic (non-const karena ColorRgba8 bukan const) ──
  static final img.Color cinematicBlue = img.ColorRgba8(30, 144, 255, 255);
  static final img.Color cinematicWhite = img.ColorRgba8(255, 255, 255, 255);
  static final img.Color cinematicOffWhite = img.ColorRgba8(229, 226, 225, 255);
  static final img.Color cinematicGrey = img.ColorRgba8(198, 198, 199, 180);
  static final img.Color cinematicDarkOverlay = img.ColorRgba8(20, 19, 19, 200);
  static final img.Color cinematicRed = img.ColorRgba8(255, 60, 60, 255);

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

    // Hitung tinggi gradient dinamis berdasarkan konten
    int rowCount = 2;
    if (hasPosition) {
      rowCount += 1;
      if (showAccuracy) rowCount += 1;
    }
    final bool showAddr = address.isNotEmpty &&
        address != 'Tidak ada lokasi' &&
        !address.startsWith('GPS:');
    if (showAddr) rowCount += _addressLineCount(src.width, address);
    if (showWeather && weather.isNotEmpty) rowCount += 1;

    final int dynGradH = (padY + lineH + lineH + 12 + 
        (rowCount - 2) * lineHSm + padY + 20)
        .clamp(gradH, gradH + 80);

    final int gradY0 = isTop ? 0 : src.height - dynGradH;

    // 1. Gradient cinematic
    _applyCinematicGradient(src, gradY0, dynGradH, isTop);

    // 2. Garis aksen biru
    final int accentLineY = isTop 
        ? padY + lineH + lineH + 8 
        : gradY0 + padY + lineH + lineH + 8;
    
    final int mapReservedWidth = (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) 
        ? mapSize + mapMar + 12 
        : 0;
    final int accentLineWidth = src.width - padX * 2 - mapReservedWidth;
    
    if (accentLineWidth > 50) {
      img.fillRect(src,
          x1: padX, y1: accentLineY,
          x2: padX + accentLineWidth, y2: accentLineY + 2,
          color: cinematicBlue);
    }

    // 3. Area teks
    final int textMaxX = src.width - padX - mapReservedWidth;
    final int textW = textMaxX - padX;

    final fontDisplay = img.arial24;
    final fontMeta = img.arial14;     // menggunakan arial14 (tersedia)
    final fontSmall = img.arial12;    // menggunakan arial12 (tersedia)

    int cy = isTop ? padY + 8 : gradY0 + padY + 8;

    // ── JAM ──
    _drawDisplayText(src, 
        DateFormat('HH : mm : ss').format(timestamp),
        fontDisplay, padX, cy, cinematicWhite);
    cy += lineH;

    // ── TANGGAL ──
    _drawDisplayText(src, 
        DateFormat('dd MMMM yyyy').format(timestamp).toUpperCase(),
        fontMeta, padX, cy, cinematicBlue);
    cy += lineH + 10;

    // ── KOORDINAT ──
    if (hasPosition && lat != null && lon != null) {
      final latDir = lat >= 0 ? 'N' : 'S';
      final lonDir = lon >= 0 ? 'E' : 'W';
      final latAbs = lat.abs().toStringAsFixed(6);
      final lonAbs = lon.abs().toStringAsFixed(6);
      
      _drawMetaText(src,
          '$latAbs°$latDir   $lonAbs°$lonDir',
          fontSmall, padX, cy, cinematicOffWhite);
      cy += lineHSm;

      if (showAccuracy && acc != null) {
        _drawMetaText(src,
            'ACCURACY  ±${acc.toStringAsFixed(1)}m',
            fontSmall, padX, cy, cinematicGrey);
        cy += lineHSm;
      }
    }

    // ── ALAMAT ──
    if (showAddr) {
      final lines = _wrapText(address, textW, fontSmall, maxLines: 2);
      for (final line in lines) {
        _drawMetaText(src, line, fontSmall, padX, cy, cinematicGrey);
        cy += lineHSm;
      }
    }

    // ── WEATHER ──
    if (showWeather && weather.isNotEmpty) {
      _drawMetaText(src, weather, fontSmall, padX, cy, cinematicBlue);
    }

    // 4. Mini-map
    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) {
      _drawCinematicMiniMap(src, mapBytes, isTop, dynGradH, gradY0);
    }

    // 5. REC indicator
    if (isTop) {
      _drawRecIndicator(src, padX, gradY0 + dynGradH - 28);
    } else {
      _drawRecIndicator(src, padX, gradY0 - 22);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  // ── Gradient cinematic ──
  void _applyCinematicGradient(img.Image src, int gradY0, int dynGradH, bool isTop) {
    for (int y = gradY0; y < gradY0 + dynGradH && y < src.height; y++) {
      if (y < 0) continue;
      
      double t;
      if (isTop) {
        t = 1.0 - ((y - gradY0) / dynGradH);
        t = t * t;
      } else {
        t = (y - gradY0) / dynGradH;
        t = t * t;
      }
      
      final int alpha = (t * 230).toInt().clamp(0, 230);
      
      for (int x = 0; x < src.width; x++) {
        final px = src.getPixel(x, y);
        final int r = (px.r * (255 - alpha)) ~/ 255;
        final int g = (px.g * (255 - alpha)) ~/ 255;
        final int b = (px.b * (255 - alpha)) ~/ 255;
        src.setPixel(x, y, img.ColorRgba8(r, g, b, 255));
      }
    }
  }

  // ── Teks display dengan outline tebal ──
  void _drawDisplayText(
    img.Image src, String text, img.BitmapFont font,
    int x, int y, img.Color color,
  ) {
    final shadowColor = img.ColorRgba8(0, 0, 0, 200);
    
    for (int dx = -2; dx <= 2; dx++) {
      for (int dy = -2; dy <= 2; dy++) {
        if (dx == 0 && dy == 0) continue;
        if (dx.abs() + dy.abs() <= 2) {
          img.drawString(src, text, font: font,
              x: x + dx, y: y + dy, color: shadowColor);
        }
      }
    }
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  // ── Teks metadata dengan outline tipis ──
  void _drawMetaText(
    img.Image src, String text, img.BitmapFont font,
    int x, int y, img.Color color,
  ) {
    final shadowColor = img.ColorRgba8(0, 0, 0, 160);
    
    for (int dx = -1; dx <= 1; dx++) {
      for (int dy = -1; dy <= 1; dy++) {
        if (dx == 0 && dy == 0) continue;
        img.drawString(src, text, font: font,
            x: x + dx, y: y + dy, color: shadowColor);
      }
    }
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  // ── REC Indicator ──
  void _drawRecIndicator(img.Image src, int x, int y) {
    final int pillW = 85;
    final int pillH = 24;
    final int pillX = src.width - pillW - padX;
    final int pillY = y;
    
    if (pillY < 0 || pillY + pillH > src.height) return;
    
    img.fillRect(src,
        x1: pillX, y1: pillY,
        x2: pillX + pillW, y2: pillY + pillH,
        color: img.ColorRgba8(0, 0, 0, 180));
    
    img.drawRect(src,
        x1: pillX, y1: pillY,
        x2: pillX + pillW, y2: pillY + pillH,
        color: img.ColorRgba8(255, 255, 255, 40),
        thickness: 1);
    
    final int dotX = pillX + 10;
    final int dotY = pillY + (pillH ~/ 2) - 4;
    img.fillCircle(src, x: dotX, y: dotY, radius: 5,
        color: cinematicRed);
    
    _drawMetaText(src, "REC 4K", img.arial12,
        pillX + 22, pillY + 6, cinematicWhite);
  }

  // ── Mini-map cinematic ──
  void _drawCinematicMiniMap(
    img.Image src, Uint8List mapBytes,
    bool isTop, int dynGradH, int gradY0,
  ) {
    img.Image? mapImage;
    try { mapImage = img.decodeImage(mapBytes); } catch (_) {}
    if (mapImage == null) return;

    try {
      final resized = img.copyResize(mapImage,
          width: mapSize, height: mapSize,
          interpolation: img.Interpolation.average);

      final int mapX = src.width - mapSize - mapMar;
      final int mapY = isTop
          ? mapMar + padY
          : src.height - mapSize - mapMar - padY - 8;

      if (mapX < 0 || mapY < 0 ||
          mapX + mapSize > src.width || mapY + mapSize > src.height) return;

      // Glass panel background
      img.fillRect(src,
          x1: mapX - mapBorder, y1: mapY - mapBorder,
          x2: mapX + mapSize + mapBorder, y2: mapY + mapSize + mapBorder,
          color: img.ColorRgba8(20, 19, 19, 160));
      
      // Border biru cinematic (tanpa withAlpha)
      final blueBorder = img.ColorRgba8(
          cinematicBlue.r, cinematicBlue.g, cinematicBlue.b, 100);
      img.drawRect(src,
          x1: mapX - mapBorder, y1: mapY - mapBorder,
          x2: mapX + mapSize + mapBorder, y2: mapY + mapSize + mapBorder,
          color: blueBorder,
          thickness: mapBorder);
      
      // Inner border tipis
      img.drawRect(src,
          x1: mapX, y1: mapY,
          x2: mapX + mapSize, y2: mapY + mapSize,
          color: img.ColorRgba8(255, 255, 255, 30),
          thickness: 1);

      // Composite map
      img.compositeImage(src, resized,
          dstX: mapX, dstY: mapY, blend: img.BlendMode.alpha);
      
      // Overlay gelap tipis
      for (int y = mapY; y < mapY + mapSize && y < src.height; y++) {
        for (int x = mapX; x < mapX + mapSize && x < src.width; x++) {
          final px = src.getPixel(x, y);
          src.setPixel(x, y, img.ColorRgba8(
            (px.r * 0.7).toInt().clamp(0, 255),
            (px.g * 0.7).toInt().clamp(0, 255),
            (px.b * 0.9).toInt().clamp(0, 255),
            255,
          ));
        }
      }
      
      // Position dot di tengah
      final int dotX = mapX + (mapSize ~/ 2);
      final int dotY = mapY + (mapSize ~/ 2);
      img.fillCircle(src, x: dotX, y: dotY, radius: 5,
          color: cinematicBlue);
      img.fillCircle(src, x: dotX, y: dotY, radius: 2,
          color: cinematicWhite);
      
      // Label
      _drawMetaText(src, "LIVE TRACK", img.arial10,
          mapX + 6, mapY + mapSize - 14, cinematicGrey);
          
    } catch (_) {}
  }

  // ── Word-wrap ──
  List<String> _wrapText(String text, int maxWidth, img.BitmapFont font, {int maxLines = 3}) {
    int charW;
    if (font == img.arial24) charW = 14;
    else if (font == img.arial14) charW = 8;
    else charW = 7;
    
    final int maxChars = (maxWidth / charW).floor().clamp(25, 150);

    final words = text.split(' ');
    final lines = <String>[];
    var current = '';

    for (final word in words) {
      final candidate = current.isEmpty ? word : '$current $word';
      if (candidate.length <= maxChars) {
        current = candidate;
      } else {
        if (current.isNotEmpty) lines.add(current);
        current = word.length > maxChars
            ? '${word.substring(0, maxChars - 2)}..'
            : word;
      }
    }
    if (current.isNotEmpty && lines.length < maxLines) lines.add(current);
    
    return lines;
  }

  int _addressLineCount(int imageWidth, String address) {
    final int textW = imageWidth - padX * 2 - mapSize - mapMar - 20;
    return _wrapText(address, textW, img.arial12).length;
  }
}
