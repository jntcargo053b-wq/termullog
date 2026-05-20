// lib/watermark/layouts/layout_cinematic.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'watermark_layout_base.dart';

class LayoutCinematic extends WatermarkLayoutBase {
  @override
  String get name => 'GPS Timestamp';

  static const int _padX = 24;
  static const int _padY = 20;

  // ─── SYNC FALLBACK (isolate) ──────────────────────────────────
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
    final double scale = (src.width / 1080).clamp(0.7, 2.0);
    final int mapH = (120 * scale).round();
    final int lineH = (32 * scale).round();
    final int smallLine = (24 * scale).round();
    final int padX = (_padX * scale).round();
    final int padY = (_padY * scale).round();
    final int margin = (12 * scale).round();
    final fontMain = img.arial24;
    final fontSmall = img.arial14;

    int rowCount = 0;
    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) rowCount += 1;
    rowCount += 2; rowCount += 1;
    if (showCoordinates && hasPosition) rowCount += 1;
    if (showAddress && address.isNotEmpty) rowCount += 2;
    if (showWeather && weather.isNotEmpty) rowCount += 1;

    final int panelH = (showMiniMap && mapBytes != null && mapBytes.isNotEmpty ? mapH + padY : 0)
        + padY * 2 + rowCount * (smallLine + 4) + 20;
    final int y0 = src.height - panelH;
    if (y0 < 0 || y0 >= src.height) return WatermarkLayoutBase.encodeJpg(src);

    final int cardW = src.width - margin * 2;
    final int cardX = margin;

    img.fillRect(src, x1: cardX, y1: y0 + margin, x2: cardX + cardW, y2: y0 + panelH - margin,
        color: img.ColorRgba8(19, 19, 19, (255 * opacity).toInt()));

    int cy = y0 + margin + padY;

    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) {
      try {
        final map = img.decodeImage(mapBytes);
        if (map != null) {
          final resized = img.copyResize(map, width: cardW, height: mapH);
          img.fillRect(src, x1: cardX, y1: cy, x2: cardX + cardW, y2: cy + mapH,
              color: img.ColorRgba8(0, 0, 0, 60));
          img.compositeImage(src, resized, dstX: cardX, dstY: cy, blend: img.BlendMode.alpha);
          final pinX = cardX + cardW ~/ 2;
          final pinY = cy + mapH ~/ 2;
          img.fillCircle(src, x: pinX, y: pinY, radius: 6, color: img.ColorRgba8(255, 50, 50, 255));
        }
      } catch (_) {}
      cy += mapH + padY;
    }

    img.drawString(src, DateFormat('EEE, dd MMM yyyy').format(timestamp),
        font: fontMain, x: cardX + padX, y: cy, color: WatermarkLayoutBase.white);
    cy += lineH;
    img.drawString(src, DateFormat('HH:mm:ss').format(timestamp),
        font: fontMain, x: cardX + padX, y: cy, color: WatermarkLayoutBase.white);
    cy += lineH;
    img.fillRect(src, x1: cardX + padX, y1: cy, x2: cardX + cardW - padX, y2: cy + 2,
        color: img.ColorRgba8(255, 255, 255, 20));
    cy += 12;
    if (showAddress && address.isNotEmpty) {
      final lines = _splitAddress(address);
      for (final line in lines.take(2)) {
        img.drawString(src, line, font: fontSmall, x: cardX + padX, y: cy, color: WatermarkLayoutBase.white);
        cy += smallLine;
      }
    }
    if (showCoordinates && hasPosition) {
      img.drawString(src, '${lat!.toStringAsFixed(2)}°, ${lon!.toStringAsFixed(2)}°',
          font: fontSmall, x: cardX + padX, y: cy, color: WatermarkLayoutBase.blue);
    }
    return WatermarkLayoutBase.encodeJpg(src);
  }

  // ─── ASYNC FLUTTER CANVAS ─────────────────────────────────────
  @override
  Future<Uint8List> applyAsync({
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
  }) async {
    await WatermarkLayoutBase.loadFont();

    final uiImage = await WatermarkLayoutBase.toUiImage(src);
    final double w = uiImage.width.toDouble();
    final double h = uiImage.height.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
    canvas.drawImage(uiImage, Offset.zero, Paint());

    final double scale = (w / 1080).clamp(0.7, 2.0);
    final double fs = fontSize == 'small' ? 0.75 : fontSize == 'large' ? 1.4 : 1.0;

    final double mapH = (120 * scale);
    final double lineH = (32 * scale * fs);
    final double smallLine = (24 * scale * fs);
    final double padX = (_padX * scale);
    final double padY = (_padY * scale);
    final double margin = (12 * scale);

    int rowCount = 0;
    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) rowCount += 1;
    rowCount += 2; rowCount += 1;
    if (showCoordinates && hasPosition) rowCount += 1;
    if (showAddress && address.isNotEmpty) rowCount += 2;
    if (showWeather && weather.isNotEmpty) rowCount += 1;

    final double panelH = (showMiniMap && mapBytes != null && mapBytes.isNotEmpty ? mapH + padY : 0)
        + padY * 2 + rowCount * (smallLine + 4) + 20;
    final double y0 = h - panelH;
    if (y0 < 0 || y0 >= h) {
      final resultImg = await WatermarkLayoutBase.recorderToImg(recorder, w.toInt(), h.toInt());
      return WatermarkLayoutBase.encodeJpg(resultImg);
    }

    final double cardW = w - margin * 2;
    final double cardX = margin;

    final cardRect = RRect.fromLTRBR(cardX, y0 + margin, cardX + cardW, y0 + panelH - margin,
        const Radius.circular(16));
    canvas.drawRRect(cardRect, Paint()..color = const Color(0xFF131313).withOpacity(opacity));
    canvas.drawRRect(cardRect, Paint()..color = Colors.white.withOpacity(0.08)..style = PaintingStyle.stroke..strokeWidth = 1);

    double cy = y0 + margin + padY;

    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) {
      try {
        final map = img.decodeImage(mapBytes);
        if (map != null) {
          final mapUi = await WatermarkLayoutBase.toUiImage(map);
          final mapRect = Rect.fromLTWH(cardX, cy, cardW, mapH);
          canvas.drawRect(mapRect, Paint()..color = Colors.black.withOpacity(0.4));
          canvas.drawImageRect(mapUi,
              Rect.fromLTWH(0, 0, mapUi.width.toDouble(), mapUi.height.toDouble()),
              mapRect, Paint());
          final pinX = cardX + cardW / 2;
          final pinY = cy + mapH / 2;
          canvas.drawCircle(Offset(pinX + 1, pinY + 1), 6, Paint()..color = Colors.black54);
          canvas.drawCircle(Offset(pinX, pinY), 6, Paint()..color = const Color(0xFFFF3232));
          canvas.drawCircle(Offset(pinX, pinY), 2, Paint()..color = Colors.white);
        }
      } catch (_) {}
      cy += mapH + padY;
    }

    WatermarkLayoutBase.canvasDrawTextShadow(canvas,
        DateFormat('EEE, dd MMM yyyy').format(timestamp),
        x: cardX + padX, y: cy, color: Colors.white, bold: false, size: 16 * fs);
    cy += lineH;

    WatermarkLayoutBase.canvasDrawTextShadow(canvas,
        DateFormat('HH:mm:ss').format(timestamp),
        x: cardX + padX, y: cy, color: Colors.white, bold: true, size: 22 * fs);
    cy += lineH;

    canvas.drawLine(Offset(cardX + padX, cy), Offset(cardX + cardW - padX, cy),
        Paint()..color = Colors.white24..strokeWidth = 1);
    cy += 12 * scale;

    if (showAddress && address.isNotEmpty) {
      final lines = _splitAddress(address);
      for (final line in lines.take(2)) {
        WatermarkLayoutBase.canvasDrawTextShadow(canvas, line,
            x: cardX + padX, y: cy, color: Colors.white70, bold: false, size: 13 * fs);
        cy += smallLine;
      }
    }

    if (showCoordinates && hasPosition) {
      WatermarkLayoutBase.canvasDrawTextShadow(canvas,
          '${lat!.toStringAsFixed(2)}°, ${lon!.toStringAsFixed(2)}°',
          x: cardX + padX, y: cy, color: const Color(0xFF1E90FF), bold: false, size: 13 * fs);
    }

    final resultImg = await WatermarkLayoutBase.recorderToImg(recorder, w.toInt(), h.toInt());
    return WatermarkLayoutBase.encodeJpg(resultImg);
  }

  List<String> _splitAddress(String address) {
    const maxLen = 42;
    final parts = address.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return [address.length > maxLen ? '${address.substring(0, maxLen - 1)}…' : address];
    final l1 = parts.first;
    final rest = parts.skip(1).join(', ');
    return [
      l1.length > maxLen ? '${l1.substring(0, maxLen - 1)}…' : l1,
      if (rest.isNotEmpty) rest.length > maxLen ? '${rest.substring(0, maxLen - 1)}…' : rest,
    ];
  }
}
