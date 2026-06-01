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
    final double pr = (W / 390).clamp(0.7, 1.5);

    switch (layout) {
      case WatermarkLayout.timemarkClassic:
        _drawClassic(canvas, W, H, pr);
        break;
      case WatermarkLayout.timemarkMinimal:
        _drawMinimal(canvas, W, H, pr);
        break;
      case WatermarkLayout.timemarkCard:
        _drawCard(canvas, W, H, pr);
        break;
      case WatermarkLayout.timemarkHUD:
        _drawHUD(canvas, W, H, pr);
        break;
      case WatermarkLayout.timemarkFilm:
        _drawFilm(canvas, W, H, pr);
        break;
    }
  }

  void _drawClassic(Canvas canvas, double W, double H, double pr) {
    final double stripH = 70 * pr;
    final double sy = H - stripH;

    canvas.drawRect(
      Rect.fromLTWH(0, sy, W, stripH),
      Paint()..color = Color.fromRGBO(0, 0, 0, opacity * 0.85),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, sy, W, 2.5 * pr),
      Paint()..color = const Color(0xFFE63946),
    );

    _drawText(canvas, DateFormat('HH:mm:ss').format(timestamp),
        size: 26 * pr, color: Colors.white, x: 12 * pr, y: sy + 8 * pr, bold: true);
    _drawText(canvas, DateFormat('EEE, dd MMM yyyy').format(timestamp),
        size: 11 * pr, color: const Color(0xFF888888), x: 12 * pr, y: sy + 38 * pr);

    double rx = W * 0.52;
    double ry = sy + 10 * pr;

    if (showCoordinates && lat != null && lon != null) {
      _drawText(canvas,
          '${lat!.abs().toStringAsFixed(4)}°${lat! >= 0 ? "N" : "S"} ${lon!.abs().toStringAsFixed(4)}°${lon! >= 0 ? "E" : "W"}',
          size: 10 * pr, color: const Color(0xFF1E90FF), x: rx, y: ry);
      ry += 14 * pr;
    }
    if (showAccuracy && acc != null) {
      final c = acc! <= 5
          ? const Color(0xFF3CB86A)
          : acc! <= 20
              ? const Color(0xFFFFB820)
              : const Color(0xFFE63946);
      _drawText(canvas, '± ${acc!.toStringAsFixed(0)} m',
          size: 10 * pr, color: c, x: rx, y: ry);
      ry += 14 * pr;
    }
    if (showAddress && address.isNotEmpty) {
      _drawText(canvas, _trunc(address, 38),
          size: 10 * pr, color: const Color(0xFF777777), x: rx, y: ry);
      ry += 14 * pr;
    }
    if (showWeather && weather.isNotEmpty) {
      _drawText(canvas, weather,
          size: 10 * pr, color: const Color(0xFF1E90FF), x: rx, y: ry);
    }
  }

  void _drawMinimal(Canvas canvas, double W, double H, double pr) {
    const double mR = 12, mB = 12;
    final double cardW = 160 * pr;
    final double cardH = 50 * pr;
    final double cx = W - cardW - mR * pr;
    final double cy = H - cardH - mB * pr;

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx, cy, cardW, cardH), Radius.circular(7 * pr)),
      Paint()..color = Color.fromRGBO(0, 0, 0, opacity * 0.82),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx, cy, 3 * pr, cardH), Radius.circular(2 * pr)),
      Paint()..color = const Color(0xFFE63946),
    );
    _drawText(canvas, DateFormat('HH:mm:ss').format(timestamp),
        size: 17 * pr, color: Colors.white, x: cx + 8 * pr, y: cy + 7 * pr, bold: true);
    _drawText(canvas, DateFormat('dd/MM/yyyy').format(timestamp),
        size: 10 * pr, color: const Color(0xFF777777), x: cx + 8 * pr, y: cy + 30 * pr);
  }

  void _drawCard(Canvas canvas, double W, double H, double pr) {
    final double cardW = (W * 0.42).clamp(160.0, 280.0);
    final double margin = 12 * pr;
    final double cx = W - cardW - margin;

    int lines = 3;
    if (showCoordinates && lat != null) lines++;
    if (showAccuracy && acc != null) lines++;
    if (showAddress && address.isNotEmpty) lines++;
    if (showWeather && weather.isNotEmpty) lines++;

    final double cardH = 14 * pr + lines * 16 * pr + 10 * pr;
    final double cy = H - cardH - margin;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(cx, cy, cardW, cardH), Radius.circular(8 * pr)),
      Paint()..color = Color.fromRGBO(8, 12, 24, opacity * 0.92),
    );
    if (showBorder) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(cx, cy, cardW, cardH), Radius.circular(8 * pr)),
        Paint()
          ..color = const Color(0x401E90FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 * pr,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(cx, cy + 10 * pr, 3 * pr, cardH - 20 * pr), Radius.circular(2 * pr)),
      Paint()..color = const Color(0xFF1E90FF),
    );

    final double tx = cx + 12 * pr;
    double ty = cy + 10 * pr;
    _drawText(canvas, DateFormat('HH:mm:ss').format(timestamp),
        size: 18 * pr, color: Colors.white, x: tx, y: ty, bold: true);
    ty += 20 * pr;
    _drawText(canvas, DateFormat('EEE, dd MMM yyyy').format(timestamp),
        size: 10 * pr, color: const Color(0xFF666E7A), x: tx, y: ty);
    ty += 16 * pr;

    canvas.drawLine(
      Offset(tx, ty), Offset(cx + cardW - 12 * pr, ty),
      Paint()..color = const Color(0x201E90FF)..strokeWidth = 1,
    );
    ty += 5 * pr;

    if (showCoordinates && lat != null && lon != null) {
      _drawText(canvas,
          '${lat!.abs().toStringAsFixed(4)}°${lat! >= 0 ? "N" : "S"} ${lon!.abs().toStringAsFixed(4)}°${lon! >= 0 ? "E" : "W"}',
          size: 10 * pr, color: const Color(0xFF1E90FF), x: tx, y: ty);
      ty += 15 * pr;
    }
    if (showAccuracy && acc != null) {
      final c = acc! <= 5
          ? const Color(0xFF3CB86A)
          : acc! <= 20 ? const Color(0xFFFFB820) : const Color(0xFFE63946);
      _drawText(canvas, '± ${acc!.toStringAsFixed(0)} m', size: 10 * pr, color: c, x: tx, y: ty);
      ty += 15 * pr;
    }
    if (showAddress && address.isNotEmpty) {
      _drawText(canvas, _trunc(address, 40),
          size: 9.5 * pr, color: const Color(0xFF555D6A), x: tx, y: ty);
      ty += 15 * pr;
    }
    if (showWeather && weather.isNotEmpty) {
      _drawText(canvas, weather, size: 10 * pr, color: const Color(0xFF1E90FF), x: tx, y: ty);
    }
  }

  void _drawHUD(Canvas canvas, double W, double H, double pr) {
    final cx = W / 2;
    final cy = H / 2;
    final rp = Paint()
      ..color = const Color(0x401E90FF)
      ..strokeWidth = 1.2 * pr
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(cx, cy), 22 * pr, rp);
    canvas.drawLine(Offset(cx - 32 * pr, cy), Offset(cx - 24 * pr, cy), rp);
    canvas.drawLine(Offset(cx + 24 * pr, cy), Offset(cx + 32 * pr, cy), rp);
    canvas.drawLine(Offset(cx, cy - 32 * pr), Offset(cx, cy - 24 * pr), rp);
    canvas.drawLine(Offset(cx, cy + 24 * pr), Offset(cx, cy + 32 * pr), rp);

    _drawText(canvas, DateFormat('HH:mm:ss').format(timestamp),
        size: 15 * pr, color: const Color(0xFF00E5FF),
        x: W - 130 * pr, y: 30 * pr, bold: true);
    _drawText(canvas, DateFormat('dd/MM/yyyy').format(timestamp),
        size: 9.5 * pr, color: const Color(0xFF006070), x: W - 130 * pr, y: 50 * pr);
  }

  void _drawFilm(Canvas canvas, double W, double H, double pr) {
    final double bh = 22 * pr;
    canvas.drawRect(Rect.fromLTWH(0, 0, W, bh), Paint()..color = const Color(0xFF1A1000));
    canvas.drawRect(Rect.fromLTWH(0, H - bh, W, bh), Paint()..color = const Color(0xFF1A1000));

    final hp = Paint()..color = const Color(0xFFFF9500);
    for (double hx = 10 * pr; hx < W; hx += 18 * pr) {
      canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(hx, bh * 0.2, 8 * pr, bh * 0.6), Radius.circular(1.5 * pr)), hp);
      canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(hx, H - bh + bh * 0.2, 8 * pr, bh * 0.6), Radius.circular(1.5 * pr)), hp);
    }

    final double cardW = (W * 0.38).clamp(140.0, 240.0);
    final double cardH = 60 * pr;
    final double cxc = W - cardW - 8 * pr;
    final double cyc = H - bh - cardH - 8 * pr;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cxc, cyc, cardW, cardH), Radius.circular(5 * pr)),
      Paint()..color = Color.fromRGBO(0, 0, 0, opacity * 0.8),
    );
    canvas.drawRect(
      Rect.fromLTWH(cxc, cyc, cardW, 2 * pr),
      Paint()..color = const Color(0xFFFF9500),
    );
    _drawText(canvas, DateFormat('HH:mm:ss').format(timestamp),
        size: 16 * pr, color: const Color(0xFFFFD95A),
        x: cxc + 8 * pr, y: cyc + 7 * pr, bold: true);
    _drawText(canvas, DateFormat('EEE, dd MMM yyyy').format(timestamp),
        size: 9.5 * pr, color: const Color(0xFFB89040),
        x: cxc + 8 * pr, y: cyc + 28 * pr);
    if (showCoordinates && lat != null) {
      _drawText(canvas, '${lat!.toStringAsFixed(4)}, ${lon!.toStringAsFixed(4)}',
          size: 9 * pr, color: const Color(0xFF6A4A10), x: cxc + 8 * pr, y: cyc + 45 * pr);
    }
  }

  void _drawText(Canvas canvas, String text,
      {required double size,
      required Color color,
      required double x,
      required double y,
      bool bold = false,
      double letterSpacing = 0.0}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          letterSpacing: letterSpacing,
          shadows: const [Shadow(blurRadius: 3, color: Color(0x88000000), offset: Offset(1, 1))],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
    tp.layout(maxWidth: 400);
    tp.paint(canvas, Offset(x, y));
  }

  String _trunc(String s, int n) => s.length > n ? '${s.substring(0, n - 1)}…' : s;

  @override
  bool shouldRepaint(WatermarkPreviewPainter old) =>
      old.timestamp != timestamp ||
      old.lat != lat ||
      old.lon != lon ||
      old.acc != acc ||
      old.address != address ||
      old.weather != weather ||
      old.layout != layout;
}
