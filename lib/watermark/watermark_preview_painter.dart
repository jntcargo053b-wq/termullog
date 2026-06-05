// lib/watermark/watermark_preview_painter.dart
// Preview overlay di viewfinder kamera (Flutter Canvas, bukan image package)
// Harus CEPAT – dipanggil setiap frame clock (1 detik)

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
    // referensi 390px (layar phone normal)
    final double pr = (W / 390).clamp(0.6, 1.6);

    switch (layout) {
      case WatermarkLayout.podCorporate:
        _drawCorporate(canvas, W, H, pr);
        break;
      case WatermarkLayout.podDarkField:
        _drawDarkField(canvas, W, H, pr);
        break;
      case WatermarkLayout.podGovern:
        _drawGovernment(canvas, W, H, pr);
        break;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // CORPORATE preview
  // ─────────────────────────────────────────────────────────────
  void _drawCorporate(Canvas canvas, double W, double H, double pr) {
    final double headerH = 36 * pr;
    final double rowH    = 18 * pr;
    int rowCount = 2; // timestamp + date selalu ada
    if (showCoordinates && hasPosition) rowCount += 2;
    if (showAccuracy && acc != null)    rowCount++;
    if (showAddress && address.isNotEmpty) rowCount++;
    if (showWeather && weather.isNotEmpty) rowCount++;

    final double panelH = headerH + 8 * pr + rowCount * rowH + 8 * pr + 22 * pr;
    final double panelY = H - panelH;

    // Panel background
    canvas.drawRect(
      Rect.fromLTWH(0, panelY, W, panelH),
      Paint()..color = const Color(0xFFF8FAFF),
    );

    // Header
    canvas.drawRect(
      Rect.fromLTWH(0, panelY, W, headerH),
      Paint()..color = const Color(0xFF0D2B5E),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, panelY, 4 * pr, headerH),
      Paint()..color = const Color(0xFF4A90E2),
    );

    _text(canvas, 'TERMULLOG', 14 * pr, panelY + 7 * pr, const Color(0xFFFFFFFF),
        bold: true, letterSpacing: 2.0);
    _textRight(canvas, W, 'PROOF OF DELIVERY', 8 * pr, panelY + 12 * pr,
        const Color(0xFF90B4E8), W * 0.5);

    // Divider
    canvas.drawRect(
      Rect.fromLTWH(0, panelY + headerH, W, 1 * pr),
      Paint()..color = const Color(0xFFDDE4F0),
    );

    // Rows
    final double padL = 12 * pr;
    double ry = panelY + headerH + 8 * pr;

    _labelValue(canvas, 'TIME', DateFormat('HH:mm:ss').format(timestamp),
        padL, ry, pr, valueColor: const Color(0xFF1A2B4A), bold: true);
    ry += rowH;
    _labelValue(canvas, 'DATE', DateFormat('dd MMMM yyyy').format(timestamp),
        padL, ry, pr);
    ry += rowH;

    if (showCoordinates && hasPosition && lat != null && lon != null) {
      _labelValue(canvas, 'LAT',
          '${lat!.abs().toStringAsFixed(5)}° ${lat! >= 0 ? 'N' : 'S'}',
          padL, ry, pr, valueColor: const Color(0xFF1565C0), bold: true);
      ry += rowH;
      _labelValue(canvas, 'LON',
          '${lon!.abs().toStringAsFixed(5)}° ${lon! >= 0 ? 'E' : 'W'}',
          padL, ry, pr, valueColor: const Color(0xFF1565C0), bold: true);
      ry += rowH;
    }

    if (showAccuracy && acc != null) {
      final Color ac = acc! <= 5
          ? const Color(0xFF2E7D32)
          : acc! <= 20
              ? const Color(0xFFE65100)
              : const Color(0xFFC62828);
      _labelValue(canvas, 'ACC', '± ${acc!.toStringAsFixed(1)} m', padL, ry, pr,
          valueColor: ac);
      ry += rowH;
    }

    if (showAddress && address.isNotEmpty) {
      _labelValue(canvas, 'ADDR', _trunc(address, 38), padL, ry, pr);
      ry += rowH;
    }

    if (showWeather && weather.isNotEmpty) {
      _labelValue(canvas, 'WX', weather, padL, ry, pr,
          valueColor: const Color(0xFF006064));
      ry += rowH;
    }

    // Footer hash preview
    final double footerY = H - 22 * pr;
    canvas.drawRect(
      Rect.fromLTWH(0, footerY, W, 1 * pr),
      Paint()..color = const Color(0xFFDDE4F0),
    );
    _text(canvas, '# ${_previewHash()}', 7 * pr, footerY + 5 * pr,
        const Color(0xFFAAAFBF), letterSpacing: 1.0);

    // Border atas
    if (showBorder) {
      canvas.drawRect(
        Rect.fromLTWH(0, panelY, W, 2.5 * pr),
        Paint()..color = const Color(0xFF4A90E2),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // DARK FIELD preview
  // ─────────────────────────────────────────────────────────────
  void _drawDarkField(Canvas canvas, double W, double H, double pr) {
    final double cardW = (W * 0.55).clamp(200.0, 320.0);
    final double rowH  = 18 * pr;
    int rowCount = 1; // koordinat/address
    if (showCoordinates && hasPosition) rowCount++;
    if (showAccuracy && acc != null)    rowCount++;
    if (showAddress && address.isNotEmpty) rowCount++;
    if (showWeather && weather.isNotEmpty) rowCount++;

    final double cardH = 48 * pr + 12 * pr + rowCount * rowH + 12 * pr + 14 * pr;
    final double margin = 14 * pr;
    final double cx = margin;
    final double cy = H - cardH - margin;
    final double bgAlpha = opacity.clamp(0.65, 0.94);

    // Background card
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx, cy, cardW, cardH),
        Radius.circular(12 * pr),
      ),
      Paint()..color = Color.fromRGBO(6, 14, 28, bgAlpha),
    );

    // Accent strip kiri
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx, cy + 12 * pr, 3 * pr, cardH - 24 * pr),
        Radius.circular(2 * pr),
      ),
      Paint()..color = const Color(0xFF00D4FF),
    );

    if (showBorder) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx, cy, cardW, cardH),
          Radius.circular(12 * pr),
        ),
        Paint()
          ..color = const Color(0x3500D4FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 * pr,
      );
    }

    final double tx = cx + 14 * pr;
    double ty = cy + 8 * pr;

    // Waktu besar
    _text(canvas, DateFormat('HH:mm:ss').format(timestamp), 22 * pr, ty,
        Colors.white, bold: true);
    ty += 30 * pr;

    // Tanggal cyan
    _text(canvas, DateFormat('dd MMMM yyyy').format(timestamp), 10 * pr, ty,
        const Color(0xFF00D4FF));
    ty += 14 * pr;

    // Divider
    canvas.drawLine(
      Offset(tx, ty), Offset(cx + cardW - 12 * pr, ty),
      Paint()..color = const Color(0x2500D4FF)..strokeWidth = 1.0 * pr,
    );
    ty += 10 * pr;

    if (showCoordinates && hasPosition && lat != null && lon != null) {
      _text(canvas,
          '${lat!.abs().toStringAsFixed(5)}° ${lat! >= 0 ? 'N' : 'S'}  '
          '${lon!.abs().toStringAsFixed(5)}° ${lon! >= 0 ? 'E' : 'W'}',
          9.5 * pr, ty, const Color(0xFF4AC8FF));
      ty += rowH;
    }

    if (showAccuracy && acc != null) {
      final Color ac = acc! <= 5
          ? const Color(0xFF66BB6A)
          : acc! <= 20
              ? const Color(0xFFFF9800)
              : const Color(0xFFEF5350);
      _text(canvas, '± ${acc!.toStringAsFixed(1)} m', 9.5 * pr, ty, ac);
      ty += rowH;
    }

    if (showAddress && address.isNotEmpty) {
      _text(canvas, _trunc(address, 32), 9 * pr, ty, const Color(0xFF8ABADF));
      ty += rowH;
    }

    if (showWeather && weather.isNotEmpty) {
      _text(canvas, weather, 9 * pr, ty, const Color(0xFF00B8A0));
    }
  }

  // ─────────────────────────────────────────────────────────────
  // GOVERNMENT preview
  // ─────────────────────────────────────────────────────────────
  void _drawGovernment(Canvas canvas, double W, double H, double pr) {
    final double headerH = 38 * pr;
    final double rowH    = 18 * pr;
    int rowCount = 2;
    if (showCoordinates && hasPosition) rowCount += 2;
    if (showAccuracy && acc != null)    rowCount++;
    if (showAddress && address.isNotEmpty) rowCount++;
    if (showWeather && weather.isNotEmpty) rowCount++;

    // 2 kolom: hitung tinggi berdasarkan setengah rows
    final int half = (rowCount / 2).ceil();
    final double panelH = headerH + 8 * pr + half * rowH + 8 * pr + 24 * pr;
    final double panelY = H - panelH;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, panelY, W, panelH),
      Paint()..color = const Color(0xFFF5F7FC),
    );

    // Header biru tua
    canvas.drawRect(
      Rect.fromLTWH(0, panelY, W, headerH),
      Paint()..color = const Color(0xFF1A237E),
    );

    // Gold strip kiri
    canvas.drawRect(
      Rect.fromLTWH(0, panelY, 5 * pr, headerH),
      Paint()..color = const Color(0xFFFFD700),
    );

    _text(canvas, 'TERMULLOG', 13 * pr, panelY + 7 * pr, Colors.white,
        bold: true, letterSpacing: 3.0);
    _textRight(canvas, W, '✓ VERIFIED DOCUMENT', 8 * pr, panelY + 13 * pr,
        const Color(0xFFFFD700), W * 0.5);

    canvas.drawRect(
      Rect.fromLTWH(0, panelY + headerH, W, 1 * pr),
      Paint()..color = const Color(0xFFCDD4E8),
    );

    // Kolom kiri
    final double padL = 12 * pr;
    double ry = panelY + headerH + 8 * pr;

    _labelValue(canvas, 'TIME', DateFormat('HH:mm:ss').format(timestamp),
        padL, ry, pr, valueColor: const Color(0xFF1A2050), bold: true);
    ry += rowH;
    _labelValue(canvas, 'DATE', DateFormat('dd MMMM yyyy').format(timestamp),
        padL, ry, pr);
    ry += rowH;

    if (showCoordinates && hasPosition && lat != null && lon != null) {
      _labelValue(canvas, 'LAT',
          '${lat!.abs().toStringAsFixed(5)}° ${lat! >= 0 ? 'N' : 'S'}',
          padL, ry, pr, valueColor: const Color(0xFF1565C0));
      ry += rowH;
    }

    // Kolom kanan
    double ry2 = panelY + headerH + 8 * pr;
    final double colX = W / 2 + padL;

    if (showCoordinates && hasPosition && lon != null) {
      _labelValue(canvas, 'LON',
          '${lon!.abs().toStringAsFixed(5)}° ${lon! >= 0 ? 'E' : 'W'}',
          colX, ry2, pr, valueColor: const Color(0xFF1565C0));
      ry2 += rowH;
    }

    if (showAccuracy && acc != null) {
      final Color ac = acc! <= 5
          ? const Color(0xFF2E7D32)
          : acc! <= 20
              ? const Color(0xFFE65100)
              : const Color(0xFFC62828);
      _labelValue(canvas, 'ACC', '± ${acc!.toStringAsFixed(1)} m', colX, ry2, pr,
          valueColor: ac);
      ry2 += rowH;
    }

    if (showAddress && address.isNotEmpty) {
      _labelValue(canvas, 'ADDR', _trunc(address, 22), colX, ry2, pr);
      ry2 += rowH;
    }

    if (showWeather && weather.isNotEmpty) {
      _labelValue(canvas, 'WX', weather, colX, ry2, pr,
          valueColor: const Color(0xFF006064));
    }

    // Garis pemisah kolom
    canvas.drawLine(
      Offset(W / 2, panelY + headerH + 6 * pr),
      Offset(W / 2, H - 24 * pr - 6 * pr),
      Paint()..color = const Color(0xFFCDD4E8)..strokeWidth = 0.8 * pr,
    );

    // Footer
    final double footerY = H - 24 * pr;
    canvas.drawRect(
      Rect.fromLTWH(0, footerY, W, 1 * pr),
      Paint()..color = const Color(0xFFCDD4E8),
    );
    _text(canvas, 'REF: ${_previewHash()}', 7 * pr, footerY + 6 * pr,
        const Color(0xFF8090B8), letterSpacing: 1.0);

    if (showBorder) {
      canvas.drawRect(
        Rect.fromLTWH(0, panelY, W, 3 * pr),
        Paint()..color = const Color(0xFFFFD700),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Shared helpers
  // ─────────────────────────────────────────────────────────────
  void _text(
    Canvas canvas,
    String text,
    double size,
    double y,
    Color color, {
    bool bold = false,
    double letterSpacing = 0.0,
    double x = 14.0,
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
      maxLines: 1,
      ellipsis: '…',
    );
    tp.layout(maxWidth: 10000);
    tp.paint(canvas, Offset(x, y));
  }

  void _textRight(Canvas canvas, double W, String text, double size, double y,
      Color color, double maxW) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
    tp.layout(maxWidth: maxW);
    tp.paint(canvas, Offset(W - tp.width - 14, y));
  }

  void _labelValue(
    Canvas canvas,
    String label,
    String value,
    double x,
    double y,
    double pr, {
    Color? valueColor,
    bool bold = false,
  }) {
    // Label kecil abu
    final lp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: const Color(0xFF8090B0),
          fontSize: 7 * pr,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    lp.layout();
    lp.paint(canvas, Offset(x, y));

    // Value
    final vp = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: valueColor ?? const Color(0xFF1A2050),
          fontSize: 9.5 * pr,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
    vp.layout(maxWidth: 200 * pr);
    vp.paint(canvas, Offset(x + 52 * pr, y));
  }

  String _trunc(String s, int maxLen) {
    if (s.length <= maxLen) return s;
    return '${s.substring(0, maxLen - 1)}…';
  }

  String _previewHash() {
    int h = 0x811C9DC5;
    for (final c in timestamp.millisecondsSinceEpoch.toString().codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).toUpperCase().padLeft(8, '0');
  }

  @override
  bool shouldRepaint(WatermarkPreviewPainter old) =>
      old.timestamp != timestamp ||
      old.hasPosition != hasPosition ||
      old.layout != layout ||
      old.address != address ||
      old.opacity != opacity;
}
