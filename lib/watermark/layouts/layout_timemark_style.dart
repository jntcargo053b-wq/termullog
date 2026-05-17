// lib/watermark/layouts/layout_timemark_style.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'watermark_layout_base.dart';

class LayoutTimeMarkStyle extends WatermarkLayoutBase {
  @override
  String get name => 'TimeMark Style';

  static const int padX = 16;
  static const int padY = 12;
  static const int mapSize = 120;

  // ─── SYNC FALLBACK ────────────────────────────────────────────────
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
    final int panelH = 200;
    final int y0 = isTop ? 0 : src.height - panelH;
    if (y0 < 0) return encodeJpg(src);

    // Background semi-transparan
    img.fillRect(src, x1: 10, y1: y0 + 10, x2: src.width - 10, y2: y0 + panelH - 10,
        color: img.ColorRgba8(0, 0, 0, 180));

    // Border putih tipis
    img.drawRect(src, x1: 10, y1: y0 + 10, x2: src.width - 10, y2: y0 + panelH - 10,
        color: img.ColorRgba8(255, 255, 255, 40), thickness: 1);

    final font = img.arial24;
    int cx = padX + 10;
    int cy = y0 + padY + 10;

    // Waktu besar
    img.drawString(src, DateFormat('HH:mm').format(timestamp),
        font: font, x: cx, y: cy, color: imgWhite);
    // Detik kecil di samping
    img.drawString(src, DateFormat('ss').format(timestamp),
        font: font, x: cx + 80, y: cy + 6, color: imgBlue);

    cy += 30;
    // Tanggal panjang
    img.drawString(src, DateFormat('EEEE, dd MMMM yyyy', 'id').format(timestamp),
        font: font, x: cx, y: cy, color: imgOffWhite);

    cy += 28;
    if (hasPosition) {
      // Koordinat DMS
      final dmsLat = _toDMS(lat!, true);
      final dmsLon = _toDMS(lon!, false);
      img.drawString(src, '$dmsLat  $dmsLon',
          font: font, x: cx, y: cy, color: imgBlue);
      cy += 24;
    }

    if (showAccuracy && hasPosition) {
      img.drawString(src, 'Accuracy: ±${acc?.toStringAsFixed(0) ?? '?'} m',
          font: font, x: cx, y: cy, color: imgGrey);
      cy += 24;
    }

    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      final lines = _splitAddress(address);
      for (final line in lines) {
        img.drawString(src, line, font: font, x: cx, y: cy, color: imgOffWhite);
        cy += 22;
      }
    }

    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, weather, font: font, x: cx, y: cy, color: imgBlue);
    }

    // Mini map di kanan bawah
    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) {
      try {
        final mapImage = img.decodeImage(mapBytes);
        if (mapImage != null) {
          final resized = img.copyResize(mapImage, width: mapSize, height: mapSize);
          final mapX = src.width - mapSize - padX - 10;
          final mapY = y0 + panelH - mapSize - padY - 10;
          img.compositeImage(src, resized, dstX: mapX, dstY: mapY, blend: img.BlendMode.alpha);
          img.drawRect(src, x1: mapX-1, y1: mapY-1, x2: mapX+mapSize, y2: mapY+mapSize,
              color: img.ColorRgba8(255, 255, 255, 60), thickness: 1);
        }
      } catch (_) {}
    }

    return encodeJpg(src);
  }

  // ─── ASYNC CANVAS VERSION ─────────────────────────────────────────
  @override
  Future<Uint8List> applyAsync({
    required img.Image srcImg,
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
  }) async {
    await loadFont();

    final uiImage = await toUiImage(srcImg);
    final w = uiImage.width.toDouble();
    final h = uiImage.height.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
    canvas.drawImage(uiImage, Offset.zero, Paint());

    final bool isTop = watermarkPosition == 'top';
    const double panelH = 200;
    final double y0 = isTop ? 0.0 : h - panelH;
    const double margin = 10.0;

    // Background card
    final cardRect = RRect.fromLTRBR(margin, y0 + margin, w - margin, y0 + panelH - margin, const Radius.circular(8));
    canvas.drawRRect(cardRect, Paint()..color = Colors.black.withOpacity(0.7));
    canvas.drawRRect(cardRect, Paint()..color = Colors.white.withOpacity(0.1)..style = PaintingStyle.stroke..strokeWidth = 1);

    double cx = padX + margin;
    double cy = y0 + padY + margin;

    // Waktu — jam:menit besar
    canvasDrawText(canvas, DateFormat('HH:mm').format(timestamp),
        x: cx, y: cy, color: uiWhite, bold: true, size: 28, letterSpacing: 2);
    // Detik kecil
    canvasDrawText(canvas, DateFormat('ss').format(timestamp),
        x: cx + 90, y: cy + 8, color: uiBlue, bold: false, size: 14);

    cy += 34;
    // Tanggal
    canvasDrawText(canvas, DateFormat('EEEE, dd MMMM yyyy', 'id').format(timestamp),
        x: cx, y: cy, color: uiOffWhite, bold: false, size: 12);

    cy += 26;
    if (hasPosition) {
      final dmsLat = _toDMS(lat!, true);
      final dmsLon = _toDMS(lon!, false);
      canvasDrawText(canvas, '$dmsLat  $dmsLon',
          x: cx, y: cy, color: uiBlue, bold: false, size: 13);
      cy += 22;
    }

    if (showAccuracy && hasPosition) {
      canvasDrawText(canvas, 'Accuracy: ±${acc?.toStringAsFixed(0) ?? '?'} m',
          x: cx, y: cy, color: uiGrey, bold: false, size: 12);
      cy += 22;
    }

    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      final lines = _splitAddress(address);
      for (final line in lines) {
        canvasDrawText(canvas, line, x: cx, y: cy, color: uiOffWhite, bold: false, size: 12);
        cy += 20;
      }
    }

    if (showWeather && weather.isNotEmpty) {
      canvasDrawChip(canvas, x: cx, y: cy - 2, width: 160, height: 22);
      canvasDrawText(canvas, weather, x: cx + 6, y: cy + 2, color: uiBlue, bold: false, size: 11);
    }

    // Mini map
    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) {
      try {
        final mapImg = img.decodeImage(mapBytes);
        if (mapImg != null) {
          final mapUi = await toUiImage(mapImg);
          final double mapX = w - mapSize - padX - margin;
          final double mapY = y0 + panelH - mapSize - padY - margin;
          canvas.drawImageRect(
            mapUi,
            Rect.fromLTWH(0, 0, mapUi.width.toDouble(), mapUi.height.toDouble()),
            Rect.fromLTWH(mapX, mapY, mapSize.toDouble(), mapSize.toDouble()),
            Paint(),
          );
          canvas.drawRect(
            Rect.fromLTWH(mapX, mapY, mapSize.toDouble(), mapSize.toDouble()),
            Paint()..color = Colors.white.withOpacity(0.2)..style = PaintingStyle.stroke..strokeWidth = 1,
          );
        }
      } catch (_) {}
    }

    final resultImg = await recorderToImg(recorder, uiImage.width, uiImage.height);
    return encodeJpg(resultImg);
  }

  // ─── HELPERS ──────────────────────────────────────────────────────
  String _toDMS(double coord, bool isLat) {
    final d = coord.abs().floor();
    final m = ((coord.abs() - d) * 60).floor();
    final s = ((coord.abs() - d - m / 60) * 3600).toStringAsFixed(1);
    final dir = isLat ? (coord >= 0 ? 'N' : 'S') : (coord >= 0 ? 'E' : 'W');
    return '${d}°$m\'$s"$dir';
  }

  List<String> _splitAddress(String address) {
    // Split alamat menjadi 2 baris maksimal
    final parts = address.split(',');
    if (parts.length <= 2) return [address];
    final line1 = parts.take(2).join(',').trim();
    final line2 = parts.skip(2).join(',').trim();
    return [line1, line2.length > 50 ? '${line2.substring(0, 47)}…' : line2];
  }
}
