// lib/watermark/watermark_preview_painter.dart
// ============================================================
// WATERMARK PREVIEW PAINTER — Timemark Style Edition
// Live overlay di viewfinder kamera. Dipanggil setiap detik.
// Scale disesuaikan dengan ukuran layar (bukan foto).
// ============================================================

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';

class WatermarkPreviewPainter extends CustomPainter {
  final DateTime timestamp;
  final bool hasPosition;
  final double? lat;
  final double? lon;
  final double? acc;
  final String address;
  final String weather;
  final bool showWeather;
  final bool showAccuracy;
  final bool showAddress;
  final bool showCoordinates;
  final double opacity;
  final bool showBorder;
  final WatermarkLayout layout;

  const WatermarkPreviewPainter({
    required this.timestamp,
    required this.hasPosition,
    this.lat,
    this.lon,
    this.acc,
    required this.address,
    required this.weather,
    required this.showWeather,
    required this.showAccuracy,
    required this.showAddress,
    required this.showCoordinates,
    required this.opacity,
    required this.showBorder,
    required this.layout,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double W = size.width;
    final double H = size.height;
    // Preview di layar: referensi 390px lebar layar phone
    final double sc = (W / 390.0).clamp(0.7, 2.0);

    switch (layout) {
      case WatermarkLayout.podCorporate:
        _drawTimemarkLight(canvas, W, H, sc);
        break;
      case WatermarkLayout.podDarkField:
        _drawTimemarkDark(canvas, W, H, sc);
        break;
      case WatermarkLayout.podGovern:
        _drawTimemarkClean(canvas, W, H, sc);
        break;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // LAYOUT 1 — Timemark Light (panel putih bawah)
  // ─────────────────────────────────────────────────────────────
  void _drawTimemarkLight(Canvas canvas, double W, double H, double sc) {
    final double panelH = _lightPanelHeight(sc);
    final double panelY = H - panelH;
    final double padL = 14 * sc;

    // Panel putih
    canvas.drawRect(
      Rect.fromLTWH(0, panelY, W, panelH),
      Paint()..color = Colors.white.withOpacity(opacity.clamp(0.88, 1.0)),
    );

    // Aksen kuning kiri
    canvas.drawRect(
      Rect.fromLTWH(0, panelY, 6 * sc, 72 * sc),
      Paint()..color = const Color(0xFFF5C518),
    );

    // ─── Baris 1: badge kuning + jam + brand ───
    final double row1Y = panelY + 10 * sc;
    final double badgeW = 100 * sc;
    final double badgeH = 46 * sc;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(padL, row1Y, badgeW, badgeH),
        Radius.circular(8 * sc),
      ),
      Paint()..color = const Color(0xFFF5C518),
    );
    _t(canvas, 'termullog', 14 * sc, row1Y + 14 * sc,
        const Color(0xFF1A1A1A), bold: true, x: padL + badgeW / 2, centerX: true);

    // Jam besar
    _t(canvas, DateFormat('HH:mm').format(timestamp),
        36 * sc, row1Y, const Color(0xFF1565C0), bold: true,
        x: padL + badgeW + 14 * sc);

    // Brand kanan
    _t(canvas, 'Termullog', 16 * sc, row1Y + 4 * sc,
        const Color(0xFFF5C518), bold: true, x: W - 120 * sc);
    _t(canvas, 'Camera', 10 * sc, row1Y + 24 * sc,
        Colors.black87, x: W - 120 * sc);

    // ─── Divider ───
    final double divY = panelY + 68 * sc;
    canvas.drawRect(Rect.fromLTWH(0, divY, W, 1 * sc),
        Paint()..color = const Color(0xFFE0E0E0));

    double ry = divY + 8 * sc;

    // Tanggal
    _t(canvas, DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(timestamp),
        13 * sc, ry, const Color(0xFF222222), bold: true, x: padL);
    ry += 20 * sc;

    // Koordinat
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final coord =
          '${lat!.abs().toStringAsFixed(6)}°${lat! < 0 ? 'S' : 'N'}, '
          '${lon!.abs().toStringAsFixed(6)}°${lon! < 0 ? 'W' : 'E'}';
      _t(canvas, coord, 11 * sc, ry, const Color(0xFF555555), x: padL);
      ry += 18 * sc;
    }

    // Alamat
    if (showAddress && address.isNotEmpty) {
      _t(canvas, _trunc(address, 52), 10 * sc, ry, const Color(0xFF777777),
          x: padL, maxW: W - padL * 2 - 40 * sc);
      ry += 16 * sc;
    }

    // Weather
    if (showWeather && weather.isNotEmpty) {
      _t(canvas, weather, 10 * sc, ry, const Color(0xFF006064), x: padL);
      ry += 16 * sc;
    }

    // Footer shield
    final double ftY = H - 28 * sc;
    canvas.drawRect(Rect.fromLTWH(0, ftY, W, 1 * sc),
        Paint()..color = const Color(0xFFDDDDDD));
    _t(canvas, '🛡 Termullog menjamin keaslian waktu',
        8 * sc, ftY + 6 * sc, const Color(0xFF999999), x: padL);

    if (showBorder) {
      canvas.drawRect(Rect.fromLTWH(0, panelY, W, 3 * sc),
          Paint()..color = const Color(0xFFF5C518));
    }
  }

  double _lightPanelHeight(double sc) {
    double h = 68 * sc + 8 * sc; // header + div
    h += 20 * sc; // tanggal
    if (showCoordinates && hasPosition) h += 18 * sc;
    if (showAddress && address.isNotEmpty) h += 16 * sc;
    if (showWeather && weather.isNotEmpty) h += 16 * sc;
    h += 28 * sc; // footer
    return h.clamp(120 * sc, 220 * sc);
  }

  // ─────────────────────────────────────────────────────────────
  // LAYOUT 2 — Timemark Dark (panel gelap full-width)
  // ─────────────────────────────────────────────────────────────
  void _drawTimemarkDark(Canvas canvas, double W, double H, double sc) {
    final double panelH = _darkPanelHeight(sc);
    final double panelY = H - panelH;
    final double padL = 18 * sc;

    // Panel gelap
    canvas.drawRect(
      Rect.fromLTWH(0, panelY, W, panelH),
      Paint()..color = Color.fromRGBO(18, 18, 18, opacity.clamp(0.82, 0.96)),
    );

    // Garis kuning atas
    canvas.drawRect(Rect.fromLTWH(0, panelY, W, 2.5 * sc),
        Paint()..color = const Color(0xFFF5C518));

    // Branding pojok kanan atas (dalam foto, atas panel)
    _t(canvas, 'Termullog', 16 * sc, panelY - 60 * sc,
        const Color(0xFFF5C518), bold: true, x: W - 130 * sc);
    _t(canvas, 'Foto 100% akurat', 9 * sc, panelY - 40 * sc,
        Colors.white70, x: W - 130 * sc);

    // ─── Jam besar ───
    _t(canvas, DateFormat('HH:mm').format(timestamp),
        46 * sc, panelY + 12 * sc, Colors.white, bold: true, x: padL);

    // Separator vertikal
    final double sepX = padL + 115 * sc;
    canvas.drawLine(
      Offset(sepX, panelY + 14 * sc),
      Offset(sepX, panelY + 70 * sc),
      Paint()..color = Colors.white38..strokeWidth = 1.5 * sc,
    );

    // Tanggal + hari
    final double dateX = sepX + 12 * sc;
    _t(canvas, DateFormat('dd MMMM yyyy').format(timestamp),
        13 * sc, panelY + 20 * sc, Colors.white, x: dateX);
    _t(canvas, DateFormat('EEEE', 'id_ID').format(timestamp),
        12 * sc, panelY + 42 * sc, Colors.white60, x: dateX);

    double infoY = panelY + 80 * sc;

    // Alamat
    if (showAddress && address.isNotEmpty) {
      _t(canvas, address, 12 * sc, infoY, Colors.white,
          x: padL, maxW: W - padL * 2);
      infoY += 20 * sc;
    }

    // Koordinat
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final coord =
          '${lat!.abs().toStringAsFixed(6)}°${lat! < 0 ? 'S' : 'N'}, '
          '${lon!.abs().toStringAsFixed(6)}°${lon! < 0 ? 'W' : 'E'}';
      _t(canvas, coord, 10 * sc, infoY, Colors.white54, x: padL);
      infoY += 16 * sc;
    }

    if (showWeather && weather.isNotEmpty) {
      _t(canvas, weather, 10 * sc, infoY, const Color(0xFF80CBC4), x: padL);
    }

    // Footer kode
    final String kode = _previewCode();
    final double ftY = H - 26 * sc;
    canvas.drawRect(Rect.fromLTWH(0, ftY, W, 1 * sc),
        Paint()..color = Colors.white12);
    _t(canvas, '🛡 Kode Foto: ', 8 * sc, ftY + 6 * sc, Colors.white38, x: padL);
    _t(canvas, kode, 8 * sc, ftY + 6 * sc, Colors.white,
        bold: true, x: padL + 80 * sc);
  }

  double _darkPanelHeight(double sc) {
    double h = 80 * sc;
    if (showAddress && address.isNotEmpty) h += 20 * sc;
    if (showCoordinates && hasPosition) h += 16 * sc;
    if (showWeather && weather.isNotEmpty) h += 16 * sc;
    h += 26 * sc; // footer
    return h.clamp(110 * sc, 200 * sc);
  }

  // ─────────────────────────────────────────────────────────────
  // LAYOUT 3 — Timemark Clean (branding atas + panel gelap bawah)
  // ─────────────────────────────────────────────────────────────
  void _drawTimemarkClean(Canvas canvas, double W, double H, double sc) {
    final double panelH = _cleanPanelHeight(sc);
    final double panelY = H - panelH;
    final double padL = 16 * sc;

    // Panel gelap
    canvas.drawRect(
      Rect.fromLTWH(0, panelY, W, panelH),
      Paint()..color = Color.fromRGBO(10, 10, 20, opacity.clamp(0.78, 0.94)),
    );

    // Branding kanan atas foto
    _t(canvas, 'Termullog', 15 * sc, 24 * sc,
        const Color(0xFFF5C518), bold: true, x: W - 130 * sc);
    _t(canvas, 'Camera', 10 * sc, 44 * sc, Colors.white60, x: W - 130 * sc);

    // Jam besar
    _t(canvas, DateFormat('HH:mm').format(timestamp),
        40 * sc, panelY + 12 * sc, Colors.white, bold: true, x: padL);

    // Bar vertikal kuning
    canvas.drawRect(
      Rect.fromLTWH(padL + 100 * sc, panelY + 12 * sc, 2.5 * sc, 52 * sc),
      Paint()..color = const Color(0xFFF5C518),
    );

    final double dateX = padL + 110 * sc;
    _t(canvas, DateFormat('dd MMMM yyyy').format(timestamp),
        12 * sc, panelY + 18 * sc, Colors.white70, x: dateX);
    _t(canvas, DateFormat('EEEE', 'id_ID').format(timestamp),
        11 * sc, panelY + 36 * sc, Colors.white38, x: dateX);

    // Divider
    canvas.drawRect(Rect.fromLTWH(padL, panelY + 70 * sc, W - padL * 2, 1 * sc),
        Paint()..color = Colors.white12);

    double infoY = panelY + 78 * sc;

    if (showAddress && address.isNotEmpty) {
      _t(canvas, _trunc(address, 55), 11 * sc, infoY, Colors.white70,
          x: padL, maxW: W - padL * 2);
      infoY += 18 * sc;
    }

    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final coord =
          '${lat!.abs().toStringAsFixed(6)}°${lat! < 0 ? 'S' : 'N'}, '
          '${lon!.abs().toStringAsFixed(6)}°${lon! < 0 ? 'W' : 'E'}';
      _t(canvas, coord, 10 * sc, infoY, Colors.white38, x: padL);
      infoY += 16 * sc;
    }

    if (showWeather && weather.isNotEmpty) {
      _t(canvas, weather, 10 * sc, infoY, const Color(0xFF80CBC4), x: padL);
    }

    // Footer
    final double ftY = H - 24 * sc;
    canvas.drawRect(Rect.fromLTWH(0, ftY, W, 1 * sc),
        Paint()..color = Colors.white12);
    _t(canvas, '🛡 Kode: ${_previewCode()}', 7 * sc, ftY + 5 * sc,
        Colors.white24, x: padL);

    if (showBorder) {
      canvas.drawRect(Rect.fromLTWH(0, panelY, W, 2.5 * sc),
          Paint()..color = const Color(0xFFF5C518));
    }
  }

  double _cleanPanelHeight(double sc) {
    double h = 70 * sc + 8 * sc;
    if (showAddress && address.isNotEmpty) h += 18 * sc;
    if (showCoordinates && hasPosition) h += 16 * sc;
    if (showWeather && weather.isNotEmpty) h += 16 * sc;
    h += 24 * sc;
    return h.clamp(100 * sc, 180 * sc);
  }

  // ─────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────
  void _t(
    Canvas canvas,
    String text,
    double size,
    double y,
    Color color, {
    bool bold = false,
    double letterSpacing = 0,
    double x = 14,
    double? maxW,
    bool centerX = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: letterSpacing,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    );
    tp.layout(maxWidth: maxW ?? 9999);
    final double px = centerX ? x - tp.width / 2 : x;
    tp.paint(canvas, Offset(px, y));
  }

  String _trunc(String s, int maxLen) =>
      s.length <= maxLen ? s : '${s.substring(0, maxLen - 1)}…';

  String _previewCode() {
    int h = 0x811C9DC5;
    for (final ch in timestamp.millisecondsSinceEpoch.toString().codeUnits) {
      h ^= ch;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(36).toUpperCase().padLeft(12, '0').substring(0, 12);
  }

  @override
  bool shouldRepaint(WatermarkPreviewPainter old) =>
      old.timestamp != timestamp ||
      old.hasPosition != hasPosition ||
      old.layout != layout ||
      old.address != address ||
      old.opacity != opacity;
}
