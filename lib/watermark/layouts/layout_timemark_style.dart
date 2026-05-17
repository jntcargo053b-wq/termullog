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

  static const double _padX   = 20;
  static const double _padY   = 14;
  static const double _mapSz  = 130;
  static const double _panelH = 210;
  static const double _radius = 10;

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
    final int panelH = _panelH.toInt();
    final int y0 = isTop ? 0 : src.height - panelH;
    if (y0 < 0) return WatermarkLayoutBase.encodeJpg(src);

    const m = 10;
    img.fillRect(src,
        x1: m, y1: y0 + m, x2: src.width - m, y2: y0 + panelH - m,
        color: img.ColorRgba8(0, 0, 0, 185));
    img.drawRect(src,
        x1: m, y1: y0 + m, x2: src.width - m, y2: y0 + panelH - m,
        color: img.ColorRgba8(255, 255, 255, 35), thickness: 1);

    final f14 = img.arial14;
    final f24 = img.arial24;
    int cx = (_padX + m).toInt();
    int cy = (y0 + _padY + m).toInt();

    // Waktu
    img.drawString(src, DateFormat('HH:mm').format(timestamp),
        font: f24, x: cx + 1, y: cy + 1, color: img.ColorRgba8(0, 0, 0, 100));
    img.drawString(src, DateFormat('HH:mm').format(timestamp),
        font: f24, x: cx, y: cy, color: WatermarkLayoutBase.imgWhite);
    img.drawString(src, DateFormat('ss').format(timestamp),
        font: f14, x: cx + 88, y: cy + 10,
        color: WatermarkLayoutBase.imgBlue);

    cy += 36;
    // Tanggal
    img.drawString(src,
        DateFormat('EEEE, dd MMMM yyyy', 'id').format(timestamp),
        font: f14, x: cx + 1, y: cy + 1, color: img.ColorRgba8(0, 0, 0, 100));
    img.drawString(src,
        DateFormat('EEEE, dd MMMM yyyy', 'id').format(timestamp),
        font: f14, x: cx, y: cy, color: WatermarkLayoutBase.imgOffWhite);

    cy += 24;
    if (hasPosition) {
      final coord = '${_toDMS(lat!, true)}   ${_toDMS(lon!, false)}';
      img.drawString(src, coord, font: f14, x: cx + 1, y: cy + 1,
          color: img.ColorRgba8(0, 0, 0, 100));
      img.drawString(src, coord, font: f14, x: cx, y: cy,
          color: WatermarkLayoutBase.imgBlue);
      cy += 22;
    }

    if (showAccuracy && hasPosition) {
      img.drawString(src, '± ${acc?.toStringAsFixed(0) ?? '?'} m',
          font: f14, x: cx, y: cy,
          color: WatermarkLayoutBase.imgGrey);
      cy += 20;
    }

    if (address.isNotEmpty &&
        address != 'Tidak ada lokasi' &&
        !address.startsWith('GPS:')) {
      for (final line in _splitAddress(address)) {
        img.drawString(src, line, font: f14, x: cx, y: cy,
            color: WatermarkLayoutBase.imgOffWhite);
        cy += 20;
      }
    }

    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, weather, font: f14, x: cx, y: cy,
          color: WatermarkLayoutBase.imgBlue);
    }

    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) {
      _drawMiniMapSync(src, mapBytes, y0: y0, panelH: panelH);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  // ─── ASYNC CANVAS VERSION ─────────────────────────────────────────
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
  }) async {
    await WatermarkLayoutBase.loadFont();

    final uiImage = await WatermarkLayoutBase.toUiImage(src);
    final w = uiImage.width.toDouble();
    final h = uiImage.height.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
    canvas.drawImage(uiImage, Offset.zero, Paint());

    final bool isTop = watermarkPosition == 'top';
    final double y0 = isTop ? 0.0 : h - _panelH;
    const double m = 10.0;

    // Card background
    final cardRect = RRect.fromLTRBR(
      m, y0 + m, w - m, y0 + _panelH - m,
      Radius.circular(_radius),
    );
    canvas.drawRRect(cardRect,
        Paint()..color = Colors.black.withOpacity(0.72));
    canvas.drawRRect(cardRect,
        Paint()
          ..color = Colors.white.withOpacity(0.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);

    // Garis aksen kiri biru
    canvas.drawRRect(
      RRect.fromLTRBR(m, y0 + m, m + 4, y0 + _panelH - m, Radius.circular(2)),
      Paint()..color = const Color(0xFF1E90FF),
    );

    double cx = _padX + m + 10;
    double cy = y0 + _padY + m;

    // ── Jam besar ──
    WatermarkLayoutBase.canvasDrawText(canvas,
        DateFormat('HH:mm').format(timestamp),
        x: cx, y: cy,
        color: Colors.white, bold: true, size: 32, letterSpacing: 2);
    // Detik kecil
    WatermarkLayoutBase.canvasDrawText(canvas,
        DateFormat('ss').format(timestamp),
        x: cx + 104, y: cy + 6,
        color: const Color(0xFF1E90FF), bold: false, size: 15);

    cy += 40;

    // ── Tanggal ──
    WatermarkLayoutBase.canvasDrawText(canvas,
        DateFormat('EEEE, dd MMMM yyyy', 'id').format(timestamp),
        x: cx, y: cy,
        color: const Color(0xFFE6E6E6), bold: false, size: 13);

    cy += 24;

    // ── Koordinat DMS ──
    if (hasPosition) {
      WatermarkLayoutBase.canvasDrawText(canvas,
          '${_toDMS(lat!, true)}   ${_toDMS(lon!, false)}',
          x: cx, y: cy,
          color: const Color(0xFF1E90FF), bold: false, size: 13);
      cy += 22;
    }

    // ── Akurasi ──
    if (showAccuracy && hasPosition) {
      WatermarkLayoutBase.canvasDrawText(canvas,
          '± ${acc?.toStringAsFixed(0) ?? '?'} m',
          x: cx, y: cy,
          color: Colors.grey, bold: false, size: 12);
      cy += 20;
    }

    // ── Alamat ──
    if (address.isNotEmpty &&
        address != 'Tidak ada lokasi' &&
        !address.startsWith('GPS:')) {
      for (final line in _splitAddress(address)) {
        WatermarkLayoutBase.canvasDrawText(canvas, line,
            x: cx, y: cy,
            color: const Color(0xFFDCDCDC), bold: false, size: 12);
        cy += 19;
      }
    }

    // ── Cuaca ──
    if (showWeather && weather.isNotEmpty) {
      // Chip background
      final chipRect = RRect.fromLTRBR(
        cx - 4, cy - 2, cx + 170, cy + 18,
        const Radius.circular(4),
      );
      canvas.drawRRect(chipRect,
          Paint()..color = const Color(0xFF1E90FF).withOpacity(0.18));
      canvas.drawRRect(chipRect,
          Paint()
            ..color = const Color(0xFF1E90FF).withOpacity(0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8);
      WatermarkLayoutBase.canvasDrawText(canvas, weather,
          x: cx + 2, y: cy + 1,
          color: const Color(0xFF1E90FF), bold: false, size: 12);
    }

    // ── Mini map ──
    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) {
      try {
        final mapImgData = img.decodeImage(mapBytes);
        if (mapImgData != null) {
          final mapUi = await WatermarkLayoutBase.toUiImage(mapImgData);
          final double mapX = w - _mapSz - _padX - m;
          final double mapY = y0 + _panelH - _mapSz - _padY - m;

          // Shadow
          canvas.drawRect(
            Rect.fromLTWH(mapX + 2, mapY + 2, _mapSz, _mapSz),
            Paint()..color = Colors.black.withOpacity(0.4),
          );
          // Map image
          canvas.drawImageRect(
            mapUi,
            Rect.fromLTWH(0, 0, mapUi.width.toDouble(), mapUi.height.toDouble()),
            Rect.fromLTWH(mapX, mapY, _mapSz, _mapSz),
            Paint(),
          );
          // Border biru
          canvas.drawRect(
            Rect.fromLTWH(mapX, mapY, _mapSz, _mapSz),
            Paint()
              ..color = const Color(0xFF1E90FF).withOpacity(0.8)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
          // Pin
          final pinX = mapX + _mapSz / 2;
          final pinY = mapY + _mapSz / 2;
          canvas.drawCircle(Offset(pinX + 1, pinY + 1), 7,
              Paint()..color = Colors.black.withOpacity(0.4));
          canvas.drawCircle(Offset(pinX, pinY), 7,
              Paint()..color = const Color(0xFFFF3232));
          canvas.drawCircle(Offset(pinX, pinY), 3,
              Paint()..color = Colors.white);
        }
      } catch (_) {}
    }

    // Perbaikan: recorderToImg(width, height)
    final resultImg = await WatermarkLayoutBase.recorderToImg(
        recorder, uiImage.width, uiImage.height);
    return WatermarkLayoutBase.encodeJpg(resultImg);
  }

  // ─── HELPERS ──────────────────────────────────────────────────────

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
    final raw2  = parts.skip(2).join(',').trim();
    final line2 = raw2.length > 52 ? '${raw2.substring(0, 49)}…' : raw2;
    return [line1, line2];
  }

  void _drawMiniMapSync(img.Image src, Uint8List mapBytes,
      {required int y0, required int panelH}) {
    try {
      final mapImage = img.decodeImage(mapBytes);
      if (mapImage == null) return;
      final sz  = _mapSz.toInt();
      final mx  = src.width - sz - _padX.toInt() - 10;
      final my  = y0 + panelH - sz - _padY.toInt() - 10;
      if (mx < 0 || my < 0) return;
      final resized = img.copyResize(mapImage, width: sz, height: sz);
      img.compositeImage(src, resized, dstX: mx, dstY: my,
          blend: img.BlendMode.alpha);
      img.drawRect(src, x1: mx - 1, y1: my - 1, x2: mx + sz, y2: my + sz,
          color: WatermarkLayoutBase.imgBlue, thickness: 2);
    } catch (_) {}
  }
}
