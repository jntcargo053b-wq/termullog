// lib/watermark/watermark_preview_painter.dart
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'watermark_layout.dart';

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
  final WatermarkLayout layout; // tidak dipakai, tapi dipertahankan untuk kompatibilitas

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
    final W = size.width;
    final H = size.height;
    final sc = (W / 390.0).clamp(0.7, 2.0); // untuk preview, skala berdasarkan lebar layar
    _drawReferenceLayout(canvas, W, H, sc);
  }

  /// Layout yang sama dengan watermark_engine.dart (tanpa logo dinamis)
  void _drawReferenceLayout(Canvas c, double W, double H, double sc) {
    // Hitung tinggi panel (versi sederhana untuk preview)
    final double panelH = _calculatePreviewPanelHeight(sc);
    final double panelX = 20 * sc;
    final double targetY = H - panelH - 120 * sc;
    final double panelY = targetY.clamp(20 * sc, H - panelH - 20 * sc);
    final double panelW = 560 * sc;

    // Panel background
    final RRect panelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(panelX, panelY, panelW, panelH),
      Radius.circular(12 * sc),
    );
    c.drawRRect(panelRect, Paint()..color = Colors.white.withOpacity(opacity.clamp(0.7, 1.0)));

    if (showBorder) {
      c.drawRRect(panelRect, Paint()
        ..color = Colors.orange
        ..strokeWidth = 2 * sc
        ..style = PaintingStyle.stroke);
    }

    double currentX = panelX + 16 * sc;
    double currentY = panelY + 16 * sc;

    // Badge nama (hardcoded "termullog" untuk preview)
    final double badgeW = 150 * sc;
    final double badgeH = 80 * sc;
    final RRect badgeRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(currentX, currentY, badgeW, badgeH), Radius.circular(8 * sc));
    c.drawRRect(badgeRRect, Paint()..color = const Color(0xFFFFC107));
    _t(c, 'termullog', 32 * sc, currentY + 18 * sc, Colors.black87,
        bold: true, x: currentX + badgeW / 2, centerX: true, maxW: badgeW);

    // Jam besar
    final String timeStr = DateFormat('HH:mm').format(timestamp);
    _t(c, timeStr, 80 * sc, currentY - 4 * sc, const Color(0xFF1A237E),
        bold: true, x: currentX + badgeW + 16 * sc);

    // Logo NEXT (sederhana, tidak perlu digambar terlalu detail, cukup teks saja)
    _drawSimpleLogo(c, currentX + badgeW + 260 * sc, currentY + 15 * sc, sc);

    currentY += 100 * sc;

    // Divider
    c.drawLine(Offset(currentX, currentY), Offset(panelX + panelW - 16 * sc, currentY),
        Paint()..color = Colors.grey.withOpacity(0.3)..strokeWidth = 2 * sc);
    currentY += 25 * sc;

    // Tanggal
    final String dateStr = DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(timestamp);
    _t(c, dateStr, 28 * sc, currentY, Colors.black87, bold: true, x: currentX);
    currentY += 50 * sc;

    // Koordinat
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final String latDir = lat! >= 0 ? 'N' : 'S';
      final String lonDir = lon! >= 0 ? 'E' : 'W';
      final String coord = '${lat!.abs().toStringAsFixed(6)}°$latDir, ${lon!.abs().toStringAsFixed(6)}°$lonDir';
      _t(c, coord, 24 * sc, currentY, Colors.grey[700]!, x: currentX);
      currentY += 45 * sc;
    }

    // Akurasi
    if (showAccuracy && acc != null) {
      _t(c, 'Accuracy: ±${acc!.toStringAsFixed(1)} m', 20 * sc, currentY, Colors.grey[600]!, x: currentX);
      currentY += 40 * sc;
    }

    // Alamat
    if (showAddress && address.isNotEmpty) {
      _t(c, address, 20 * sc, currentY, Colors.grey[700]!, x: currentX, maxW: panelW - 32 * sc, maxLines: 3);
      final tp = TextPainter(
        text: TextSpan(text: address, style: TextStyle(fontSize: 20 * sc)),
        textDirection: ui.TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: panelW - 32 * sc);
      currentY += tp.height + 15 * sc;
    }

    // Cuaca
    if (showWeather && weather.isNotEmpty) {
      _t(c, weather, 20 * sc, currentY, const Color(0xFF00796B), x: currentX);
      currentY += 35 * sc;
    }

    // Footer
    _t(c, '🛡 Timemark menjamin keaslian waktu', 20 * sc, currentY, Colors.grey[600]!, x: currentX);

    // Kode verifikasi vertikal (di kanan)
    final String verCode = _previewVerCode();
    final double verCenterY = panelY + panelH / 2;
    _drawVerticalText(c, '© $verCode Timemark Verified', 18 * sc, W - 45 * sc, verCenterY, Colors.white.withOpacity(0.8));

    // Branding pojok kanan bawah
    _t(c, 'Timemark', 28 * sc, H - 100 * sc, Colors.white, bold: true, x: W - 240 * sc);
    _t(c, 'Camera', 22 * sc, H - 65 * sc, Colors.white70, x: W - 240 * sc);
  }

  double _calculatePreviewPanelHeight(double sc) {
    // Perhitungan sederhana untuk preview (tanpa fontScale)
    double h = 16 * sc + 100 * sc + 25 * sc + 50 * sc;
    if (showCoordinates && hasPosition && lat != null) h += 45 * sc;
    if (showAccuracy && acc != null) h += 40 * sc;
    if (showAddress && address.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(text: address, style: TextStyle(fontSize: 20 * sc)),
        textDirection: ui.TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: (560 - 32) * sc);
      h += tp.height + 15 * sc;
    }
    if (showWeather && weather.isNotEmpty) h += 35 * sc;
    h += 45 * sc + 16 * sc;
    return h.clamp(120 * sc, 300 * sc);
  }

  void _drawSimpleLogo(Canvas c, double x, double y, double sc) {
    // Versi sederhana untuk preview: hanya kotak putih + teks "NEXT"
    final Paint p = Paint()..color = Colors.white;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, 140 * sc, 60 * sc), Radius.circular(8 * sc)), p);
    _t(c, 'NEXT', 20 * sc, y + 20 * sc, Colors.black, bold: true, x: x + 50 * sc, centerX: true);
  }

  void _drawVerticalText(Canvas c, String text, double size, double x, double centerY, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, letterSpacing: 1.2, fontWeight: FontWeight.w500)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    c.save();
    c.translate(x, centerY + tp.width / 2);
    c.rotate(-pi / 2);
    tp.paint(c, Offset.zero);
    c.restore();
  }

  void _t(Canvas canvas, String text, double size, double y, Color color,
      {bool bold = false, double x = 16, double? maxW, bool centerX = false, int maxLines = 2}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: maxW ?? 9999);
    final double paintX = centerX ? x - tp.width / 2 : x;
    tp.paint(canvas, Offset(paintX, y));
  }

  String _previewVerCode() {
    int h = 0x811C9DC5;
    for (final ch in timestamp.millisecondsSinceEpoch.toString().codeUnits) {
      h ^= ch;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(36).toUpperCase().padLeft(12, '0').substring(0, 12);
  }

  @override
  bool shouldRepaint(WatermarkPreviewPainter old) {
    return old.timestamp != timestamp ||
        old.hasPosition != hasPosition ||
        old.lat != lat ||
        old.lon != lon ||
        old.acc != acc ||
        old.address != address ||
        old.weather != weather ||
        old.showWeather != showWeather ||
        old.showAccuracy != showAccuracy ||
        old.showAddress != showAddress ||
        old.showCoordinates != showCoordinates ||
        old.opacity != opacity ||
        old.showBorder != showBorder;
  }
}
