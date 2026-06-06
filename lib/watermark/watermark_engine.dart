// lib/watermark/watermark_engine.dart
// ============================================================
// WATERMARK ENGINE — Timemark Style Edition + Akurasi GPS
// ============================================================

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import 'watermark_params.dart';
import 'watermark_layout.dart';

class WatermarkEngine {
  static Future<Uint8List> process(WatermarkParams params) async {
    // ... (kode proses sama seperti sebelumnya, tidak berubah) ...
    // Hanya pastikan signature method _draw* menyertakan params dan sc/fontScale
    // Saya asumsikan kode sebelumnya sudah benar. Di sini saya hanya menampilkan
    // bagian yang ditambahkan untuk akurasi.
  }

  // ═══════════════════════════════════════════════════════════════
  // LAYOUT 1 — Timemark Light (tambahan akurasi)
  // ═══════════════════════════════════════════════════════════════
  static void _drawTimemarkLight(Canvas c, double W, double H, double sc, double fontScale, WatermarkParams p) {
    // ... (kode panel, badge, jam, tanggal, dll sama) ...
    double row3Y = row2Y + 44 * sc;
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final String coord = '${p.lat!.abs().toStringAsFixed(6)}°${p.lat! < 0 ? 'S' : 'N'}, '
                           '${p.lon!.abs().toStringAsFixed(6)}°${p.lon! < 0 ? 'W' : 'E'}';
      _tp(coord, 18 * sc * fontScale, row3Y, const Color(0xFF444444), x: padL).paint(c);
      row3Y += 30 * sc;

      // 🔹 TAMPILKAN AKURASI (jika aktif dan ada)
      if (p.showAccuracy && p.acc != null) {
        final String accText = '±${p.acc!.toStringAsFixed(1)} m';
        _tp(accText, 14 * sc * fontScale, row3Y, const Color(0xFF888888), x: padL).paint(c);
        row3Y += 24 * sc; // tambah tinggi
      }
    }

    // Alamat dan weather tetap...
    // Pastikan row3Y digunakan untuk menempatkan alamat setelah koordinat+akurasi
  }

  // ═══════════════════════════════════════════════════════════════
  // LAYOUT 2 — Timemark Dark
  // ═══════════════════════════════════════════════════════════════
  static void _drawTimemarkDark(Canvas c, double W, double H, double sc, double fontScale, WatermarkParams p) {
    // ... (bagian atas panel, jam, tanggal, separator) ...
    double addrY = panelY + 126 * sc;
    if (p.showAddress && p.address.isNotEmpty) {
      _tp(p.address, 18 * sc * fontScale, addrY, Colors.white, x: padL, maxW: W - padL * 2, maxLines: 3).paint(c);
      addrY += 30 * sc;
    }

    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final String coord = '${p.lat!.abs().toStringAsFixed(6)}°${p.lat! < 0 ? 'S' : 'N'}, '
                           '${p.lon!.abs().toStringAsFixed(6)}°${p.lon! < 0 ? 'W' : 'E'}';
      _tp(coord, 15 * sc * fontScale, addrY, Colors.white54, x: padL).paint(c);
      addrY += 24 * sc;

      // 🔹 AKURASI
      if (p.showAccuracy && p.acc != null) {
        final String accText = '±${p.acc!.toStringAsFixed(1)} m';
        _tp(accText, 13 * sc * fontScale, addrY, Colors.white38, x: padL).paint(c);
        addrY += 20 * sc;
      }
    }

    if (p.showWeather && p.weather.isNotEmpty) {
      _tp(p.weather, 15 * sc * fontScale, addrY, const Color(0xFF80CBC4), x: padL).paint(c);
    }
    // footer...
  }

  // ═══════════════════════════════════════════════════════════════
  // LAYOUT 3 — Timemark Clean
  // ═══════════════════════════════════════════════════════════════
  static void _drawTimemarkClean(Canvas c, double W, double H, double sc, double fontScale, WatermarkParams p) {
    // ... (panel, jam, branding) ...
    double infoY = panelY + 104 * sc;
    if (p.showAddress && p.address.isNotEmpty) {
      _tp(p.address, 16 * sc * fontScale, infoY, Colors.white70, x: padL, maxW: W - padL * 2, maxLines: 3).paint(c);
      infoY += 26 * sc;
    }

    if (p.showCoordinates && p.lat != null && p.lon != null) {
      final String coord = '${p.lat!.abs().toStringAsFixed(6)}°${p.lat! < 0 ? 'S' : 'N'}, '
                           '${p.lon!.abs().toStringAsFixed(6)}°${p.lon! < 0 ? 'W' : 'E'}';
      _tp(coord, 14 * sc * fontScale, infoY, Colors.white54, x: padL).paint(c);
      infoY += 22 * sc;

      // 🔹 AKURASI
      if (p.showAccuracy && p.acc != null) {
        final String accText = '±${p.acc!.toStringAsFixed(1)} m';
        _tp(accText, 12 * sc * fontScale, infoY, Colors.white38, x: padL).paint(c);
        infoY += 18 * sc;
      }
    }

    if (p.showWeather && p.weather.isNotEmpty) {
      _tp(p.weather, 14 * sc * fontScale, infoY, const Color(0xFF80CBC4), x: padL).paint(c);
    }
    // footer...
  }

  // ═══════════════════════════════════════════════════════════════
  // UPDATE HEIGHT CALCULATORS (tambahan akurasi)
  // ═══════════════════════════════════════════════════════════════
  static double _lightPanelHeight(double sc, WatermarkParams p) {
    double h = 90 * sc + 44 * sc;
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      h += 30 * sc;
      if (p.showAccuracy && p.acc != null) h += 24 * sc; // tambahan akurasi
    }
    if (p.showAddress && p.address.isNotEmpty) h += 24 * sc;
    if (p.showWeather && p.weather.isNotEmpty) h += 20 * sc;
    h += 40 * sc;
    return h.clamp(140 * sc, 220 * sc);
  }

  static double _darkPanelHeight(double sc, WatermarkParams p) {
    double h = 126 * sc;
    if (p.showAddress && p.address.isNotEmpty) h += 30 * sc;
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      h += 24 * sc;
      if (p.showAccuracy && p.acc != null) h += 20 * sc;
    }
    if (p.showWeather && p.weather.isNotEmpty) h += 20 * sc;
    h += 42 * sc;
    return h.clamp(160 * sc, 260 * sc);
  }

  static double _cleanPanelHeight(double sc, WatermarkParams p) {
    double h = 92 * sc + 12 * sc;
    if (p.showAddress && p.address.isNotEmpty) h += 26 * sc;
    if (p.showCoordinates && p.lat != null && p.lon != null) {
      h += 22 * sc;
      if (p.showAccuracy && p.acc != null) h += 18 * sc;
    }
    if (p.showWeather && p.weather.isNotEmpty) h += 20 * sc;
    h += 38 * sc;
    return h.clamp(120 * sc, 200 * sc);
  }

  // Helper lainnya (_tp, _verCode, dll) tetap sama
}
