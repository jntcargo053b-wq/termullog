// lib/watermark/watermark_preview_painter.dart
// ============================================================
// WATERMARK PREVIEW PAINTER — Timemark Style Edition + Akurasi GPS
// ============================================================

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart'; // sesuaikan dengan path Anda

class WatermarkPreviewPainter extends CustomPainter {
  final DateTime timestamp;
  final bool hasPosition;
  final double? lat;
  final double? lon;
  final double? acc;          // ✅ akurasi GPS
  final String address;
  final String weather;
  final bool showWeather;
  final bool showAccuracy;    // ✅ toggle akurasi
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
  // LAYOUT 1 — Light (tambah akurasi)
  // ─────────────────────────────────────────────────────────────
  void _drawTimemarkLight(Canvas canvas, double W, double H, double sc) {
    // ... (gambar panel, badge, jam, tanggal, divider) ...
    // Saya asumsikan variabel padL, row2Y sudah didefinisikan seperti di kode asli.
    double ry = row2Y + 44 * sc; // setelah tanggal

    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final coord = '${lat!.abs().toStringAsFixed(6)}°${lat! < 0 ? 'S' : 'N'}, '
                    '${lon!.abs().toStringAsFixed(6)}°${lon! < 0 ? 'W' : 'E'}';
      _t(canvas, coord, 11 * sc, ry, const Color(0xFF555555), x: padL);
      ry += 18 * sc;

      // ✅ Tampilkan akurasi
      if (showAccuracy && acc != null) {
        _t(canvas, '±${acc!.toStringAsFixed(1)} m', 9 * sc, ry, const Color(0xFF888888), x: padL);
        ry += 14 * sc;
      }
    }

    if (showAddress && address.isNotEmpty) {
      _t(canvas, _trunc(address, 52), 10 * sc, ry, const Color(0xFF777777), x: padL, maxW: W - padL * 2 - 40 * sc);
      ry += 16 * sc;
    }

    if (showWeather && weather.isNotEmpty) {
      _t(canvas, weather, 10 * sc, ry, const Color(0xFF006064), x: padL);
    }
    // footer ...
  }

  // ─────────────────────────────────────────────────────────────
  // LAYOUT 2 — Dark (tambah akurasi)
  // ─────────────────────────────────────────────────────────────
  void _drawTimemarkDark(Canvas canvas, double W, double H, double sc) {
    // ... panel, jam, separator, tanggal ...
    double infoY = panelY + 80 * sc;

    if (showAddress && address.isNotEmpty) {
      _t(canvas, address, 12 * sc, infoY, Colors.white, x: padL, maxW: W - padL * 2);
      infoY += 20 * sc;
    }

    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final coord = '${lat!.abs().toStringAsFixed(6)}°${lat! < 0 ? 'S' : 'N'}, '
                    '${lon!.abs().toStringAsFixed(6)}°${lon! < 0 ? 'W' : 'E'}';
      _t(canvas, coord, 10 * sc, infoY, Colors.white54, x: padL);
      infoY += 16 * sc;

      // ✅ Akurasi
      if (showAccuracy && acc != null) {
        _t(canvas, '±${acc!.toStringAsFixed(1)} m', 9 * sc, infoY, Colors.white38, x: padL);
        infoY += 14 * sc;
      }
    }

    if (showWeather && weather.isNotEmpty) {
      _t(canvas, weather, 10 * sc, infoY, const Color(0xFF80CBC4), x: padL);
    }
    // footer ...
  }

  // ─────────────────────────────────────────────────────────────
  // LAYOUT 3 — Clean (tambah akurasi)
  // ─────────────────────────────────────────────────────────────
  void _drawTimemarkClean(Canvas canvas, double W, double H, double sc) {
    // ... panel, jam, bar, tanggal ...
    double infoY = panelY + 78 * sc;

    if (showAddress && address.isNotEmpty) {
      _t(canvas, _trunc(address, 55), 11 * sc, infoY, Colors.white70, x: padL, maxW: W - padL * 2);
      infoY += 18 * sc;
    }

    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final coord = '${lat!.abs().toStringAsFixed(6)}°${lat! < 0 ? 'S' : 'N'}, '
                    '${lon!.abs().toStringAsFixed(6)}°${lon! < 0 ? 'W' : 'E'}';
      _t(canvas, coord, 10 * sc, infoY, Colors.white38, x: padL);
      infoY += 16 * sc;

      // ✅ Akurasi
      if (showAccuracy && acc != null) {
        _t(canvas, '±${acc!.toStringAsFixed(1)} m', 9 * sc, infoY, Colors.white24, x: padL);
        infoY += 14 * sc;
      }
    }

    if (showWeather && weather.isNotEmpty) {
      _t(canvas, weather, 10 * sc, infoY, const Color(0xFF80CBC4), x: padL);
    }
    // footer ...
  }

  // ─────────────────────────────────────────────────────────────
  // UPDATE HEIGHT CALCULATORS untuk preview (agar panel tidak kelebihan)
  // ─────────────────────────────────────────────────────────────
  double _lightPanelHeight(double sc) {
    double h = 68 * sc + 8 * sc; // header + divider
    h += 20 * sc; // tanggal
    if (showCoordinates && hasPosition) {
      h += 18 * sc;
      if (showAccuracy && acc != null) h += 14 * sc;
    }
    if (showAddress && address.isNotEmpty) h += 16 * sc;
    if (showWeather && weather.isNotEmpty) h += 16 * sc;
    h += 28 * sc; // footer
    return h.clamp(120 * sc, 220 * sc);
  }

  double _darkPanelHeight(double sc) {
    double h = 80 * sc;
    if (showAddress && address.isNotEmpty) h += 20 * sc;
    if (showCoordinates && hasPosition) {
      h += 16 * sc;
      if (showAccuracy && acc != null) h += 14 * sc;
    }
    if (showWeather && weather.isNotEmpty) h += 16 * sc;
    h += 26 * sc;
    return h.clamp(110 * sc, 200 * sc);
  }

  double _cleanPanelHeight(double sc) {
    double h = 70 * sc + 8 * sc;
    if (showAddress && address.isNotEmpty) h += 18 * sc;
    if (showCoordinates && hasPosition) {
      h += 16 * sc;
      if (showAccuracy && acc != null) h += 14 * sc;
    }
    if (showWeather && weather.isNotEmpty) h += 16 * sc;
    h += 24 * sc;
    return h.clamp(100 * sc, 180 * sc);
  }

  // Helper _t, _trunc, _previewCode, shouldRepaint tetap sama
  // Pastikan _previewCode menggunakan acc juga jika ingin konsisten dengan engine? Tidak perlu karena hanya preview.
}
