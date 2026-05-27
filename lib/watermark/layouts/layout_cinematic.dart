// lib/watermark/layouts/layout_cinematic.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
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
    final int padX = (24 * scale).round();
    final int padY = (20 * scale).round();
    final int margin = (16 * scale).round();
    final int radius = (24 * scale).round();

    // Pilih font berdasarkan fontSize
    final img.BitmapFont fontDate = (fontSize == 'large')
        ? img.arial24
        : (fontSize == 'small')
            ? img.arial14
            : img.arial20;
    final img.BitmapFont fontTime = (fontSize == 'large')
        ? img.arial24
        : (fontSize == 'small')
            ? img.arial20
            : img.arial24;
    final img.BitmapFont fontInfo = (fontSize == 'large')
        ? img.arial20
        : (fontSize == 'small')
            ? img.arial12
            : img.arial14;

    // Hitung tinggi panel
    int contentHeight = 0;
    contentHeight += (fontDate.height + 8).toInt();
    contentHeight += (fontTime.height + 12).toInt();
    contentHeight += 16; // separator
    if (showCoordinates && hasPosition && lat != null && lon != null)
      contentHeight += (fontInfo.height + 6).toInt();
    if (showAccuracy && hasPosition && acc != null)
      contentHeight += (fontInfo.height + 6).toInt();
    if (showAddress && address.isNotEmpty && !address.startsWith('GPS:')) {
      final lines = _splitAddress(address, scale);
      contentHeight += lines.length * (fontInfo.height + 6).toInt();
    }
    if (showWeather && weather.isNotEmpty)
      contentHeight += (fontInfo.height + 6).toInt();

    // Mini map
    final bool hasMap = showMiniMap && mapBytes != null && mapBytes.isNotEmpty;
    if (hasMap) {
      contentHeight += (120 * scale).round() + padY;
    }

    final int panelHeight = contentHeight + padY * 2;
    final int cardWidth = src.width - margin * 2;
    final int cardX = margin;
    final int cardY = src.height - panelHeight - margin;

    // 1. Gambar background dengan gradien (simulasi gradien dengan dua lapis)
    final bgColor1 = img.ColorRgba8(15, 15, 20, (255 * opacity).toInt());
    final bgColor2 = img.ColorRgba8(5, 5, 10, (255 * opacity).toInt());
    img.fillRect(src,
        x1: cardX, y1: cardY,
        x2: cardX + cardWidth, y2: cardY + panelHeight,
        color: bgColor1);
    // Efek gradien vertikal (lebih gelap di bawah)
    for (int y = cardY; y < cardY + panelHeight; y++) {
      final double t = (y - cardY) / panelHeight;
      final int r = (bgColor2.r * t + bgColor1.r * (1 - t)).round();
      final int g = (bgColor2.g * t + bgColor1.g * (1 - t)).round();
      final int b = (bgColor2.b * t + bgColor1.b * (1 - t)).round();
      img.drawLine(src,
          x1: cardX, y1: y,
          x2: cardX + cardWidth, y2: y,
          color: img.ColorRgba8(r, g, b, bgColor1.a));
    }

    // 2. Border radius (simulasi dengan gambar lingkaran di keempat sudut)
    _drawRoundedRect(src, cardX, cardY, cardX + cardWidth, cardY + panelHeight, radius);

    // 3. Border (jika aktif)
    if (showBorder) {
      _drawRectBorder(src, cardX, cardY, cardX + cardWidth, cardY + panelHeight, radius,
          img.ColorRgba8(255, 255, 255, 60), 2);
    }

    // 4. Shadow (simulasi bayangan bawah)
    final shadowOffset = (8 * scale).round();
    if (shadowOffset > 0) {
      img.fillRect(src,
          x1: cardX + 4, y1: cardY + panelHeight,
          x2: cardX + cardWidth - 4, y2: cardY + panelHeight + shadowOffset,
          color: img.ColorRgba8(0, 0, 0, 80));
    }

    int cy = cardY + padY;

    // Mini map
    if (hasMap) {
      try {
        final map = img.decodeImage(mapBytes!);
        if (map != null) {
          final mapH = (120 * scale).round();
          final resized = img.copyResize(map, width: cardWidth - padX * 2, height: mapH);
          final mapX = cardX + padX;
          img.compositeImage(src, resized, dstX: mapX, dstY: cy, blend: img.BlendMode.alpha);
          // Pin marker
          final pinX = mapX + resized.width ~/ 2;
          final pinY = cy + mapH ~/ 2;
          img.fillCircle(src,
              x: pinX, y: pinY, radius: (6 * scale).round(),
              color: img.ColorRgba8(255, 60, 60, 255));
          img.fillCircle(src,
              x: pinX, y: pinY, radius: (2 * scale).round(),
              color: img.ColorRgba8(255, 255, 255, 200));
        }
      } catch (_) {}
      cy += (120 * scale).round() + padY;
    }

    // Tanggal (dengan icon kalender kecil - opsional)
    final dateStr = DateFormat(dateFormat).format(timestamp);
    img.drawString(src, dateStr,
        font: fontDate,
        x: cardX + padX,
        y: cy,
        color: img.ColorRgba8(200, 200, 220, 255));
    cy += fontDate.height + 8;

    // Waktu (dengan efek neon)
    final timeStr = DateFormat(timeFormat).format(timestamp);
    img.drawString(src, timeStr,
        font: fontTime,
        x: cardX + padX,
        y: cy,
        color: img.ColorRgba8(255, 255, 255, 255));
    cy += fontTime.height + 12;

    // Separator garis halus dengan gradasi
    final lineY = cy;
    for (int x = cardX + padX; x < cardX + cardWidth - padX; x++) {
      final alpha = (30 + ((x - (cardX + padX)) % 10) * 2).clamp(20, 50);
      img.drawPixel(src, x, lineY, img.ColorRgba8(255, 255, 255, alpha));
      img.drawPixel(src, x, lineY + 1, img.ColorRgba8(255, 255, 255, alpha ~/ 2));
    }
    cy += 16;

    // Alamat
    if (showAddress && address.isNotEmpty && !address.startsWith('GPS:')) {
      final lines = _splitAddress(address, scale);
      for (final line in lines) {
        img.drawString(src, line,
            font: fontInfo,
            x: cardX + padX,
            y: cy,
            color: img.ColorRgba8(220, 220, 240, 255));
        cy += fontInfo.height + 6;
      }
    }

    // Koordinat
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      img.drawString(src,
          '📍 ${lat.toStringAsFixed(5)}°, ${lon.toStringAsFixed(5)}°',
          font: fontInfo,
          x: cardX + padX,
          y: cy,
          color: img.ColorRgba8(100, 180, 250, 255));
      cy += fontInfo.height + 6;
    }

    // Akurasi
    if (showAccuracy && hasPosition && acc != null) {
      img.drawString(src,
          '🎯 Akurasi ±${acc.toStringAsFixed(1)}m',
          font: fontInfo,
          x: cardX + padX,
          y: cy,
          color: img.ColorRgba8(180, 230, 180, 255));
      cy += fontInfo.height + 6;
    }

    // Cuaca
    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, weather,
          font: fontInfo,
          x: cardX + padX,
          y: cy,
          color: img.ColorRgba8(160, 210, 255, 255));
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  // Simulasi rounded rectangle dengan menggambar lingkaran di keempat sudut
  void _drawRoundedRect(img.Image src, int x1, int y1, int x2, int y2, int radius) {
    final color = img.ColorRgba8(0, 0, 0, 0); // transparent, hanya untuk memotong sudut
    // Sebenarnya image library tidak support clip, jadi kita gambar kotak biasa dan tidak ada efek rounded.
    // Tapi kita bisa gambar border dengan rounded jika ada fungsi, namun sementara diabaikan.
    // Untuk rounded yang sebenarnya, kita perlu plugin yang lebih canggih. Alternatif: gambar border rounded.
  }

  // Gambar border dengan radius (simulasi)
  void _drawRectBorder(img.Image src, int x1, int y1, int x2, int y2, int radius, img.Color color, int thickness) {
    // Sederhana: gambar border tebal di tepi
    for (int i = 0; i < thickness; i++) {
      // atas
      img.drawLine(src, x1: x1 + radius, y1: y1 + i, x2: x2 - radius, y2: y1 + i, color: color);
      // bawah
      img.drawLine(src, x1: x1 + radius, y1: y2 - i - 1, x2: x2 - radius, y2: y2 - i - 1, color: color);
      // kiri
      img.drawLine(src, x1: x1 + i, y1: y1 + radius, x2: x1 + i, y2: y2 - radius, color: color);
      // kanan
      img.drawLine(src, x1: x2 - i - 1, y1: y1 + radius, x2: x2 - i - 1, y2: y2 - radius, color: color);
    }
    // Tambahkan lengkungan sudut (opsional, untuk efek halus)
  }

  // Helper split address
  List<String> _splitAddress(String address, double scale) {
    final int maxLen = (38 + (scale * 8).round()).clamp(38, 55);
    final words = address.split(' ');
    final lines = <String>[];
    String current = '';
    for (final word in words) {
      if ((current + word).length > maxLen) {
        lines.add(current.trim());
        current = '$word ';
      } else {
        current += '$word ';
      }
    }
    if (current.trim().isNotEmpty) lines.add(current.trim());
    return lines.take(2).toList(); // maksimal 2 baris
  }
}
