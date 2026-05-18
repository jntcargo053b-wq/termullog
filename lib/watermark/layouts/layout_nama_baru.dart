// lib/watermark/layouts/layout_nama_baru.dart
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutNamaBaru extends WatermarkLayoutBase {
  @override
  String get name => 'Modern Clean Card';

  static const int _padX = 16;
  static const int _padY = 14;
  static const int _lineH = 26;
  static const int _lineS = 20;
  static const int _accentW = 4;
  static const int _accentGap = 12;
  static const int _maxAddr = 50;

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

    // ---- adaptive panel height ----
    final int panelH = (address.length > 70) ? 165 : 140;

    final int y0 = isTop ? 0 : src.height - panelH;
    if (y0 < 0 || y0 >= src.height) return WatermarkLayoutBase.encodeJpg(src);

    final int w = src.width;

    // adaptive font scale
    final double scale = (src.width / 1080).clamp(0.85, 1.3);
    final int mapSz = (_mapSz(showMiniMap, mapBytes) * scale).round();

    _gradientBg(src, y0: y0, w: w, panelH: panelH, isTop: isTop);

    // accent bar (lebih pendek, minimalis)
    final int barY1 = y0 + 24;
    final int barY2 = y0 + math.min(108, panelH - 30);
    _drawAccent(src, x: _padX, y1: barY1, y2: barY2);

    final int textX = _padX + _accentW + _accentGap;
    final bool hasMap = showMiniMap && mapBytes != null && mapBytes.isNotEmpty;
    final int mapReserve = hasMap ? (mapSz + 24) : 0;
    final int textEndX = w - _padX - mapReserve;

    int cy = y0 + _padY;

    // ---- baris 1: jam + tanggal ----
    final String timeStr = DateFormat('HH:mm').format(timestamp);   // tanpa detik
    final String dateStr = DateFormat('EEE, dd MMM yyyy').format(timestamp);

    _txt(src, dateStr,
        font: img.arial14, x: textX, y: cy + 5,
        color: img.ColorRgba8(160, 175, 195, 255));

    final int timeX = (textEndX - timeStr.length * 8).clamp(textX + 100, textEndX - 10);
    _txt(src, timeStr,
        font: img.arial24, x: timeX, y: cy,
        color: img.ColorRgba8(245, 248, 255, 255),
        shadow: true);
    cy += _lineH;

    // divider tipis
    img.fillRect(src, x1: textX, y1: cy, x2: textEndX - 8, y2: cy + 1,
        color: img.ColorRgba8(255, 255, 255, 20));
    cy += 7;

    // ---- baris 2: koordinat dengan ikon GPS ----
    if (hasPosition && lat != null && lon != null) {
      // titik marker kecil
      img.fillCircle(src, x: textX - 7, y: cy + 6, radius: 3,
          color: img.ColorRgba8(0, 212, 170, 255));

      final String coord =
          '${_fmtLat(lat)}   ${_fmtLon(lon)}';
      _txt(src, '📍 $coord',    // ikon GPS kecil
          font: img.arial14, x: textX, y: cy,
          color: img.ColorRgba8(0, 184, 212, 255),
          shadow: true);
      cy += _lineS;

      if (showAccuracy && acc != null) {
        _txt(src, 'Akurasi  ±${acc.toStringAsFixed(0)} m',
            font: img.arial14, x: textX, y: cy,
            color: img.ColorRgba8(130, 150, 170, 255));
        cy += _lineS;
      }
    }

    // ---- baris 3: alamat (smart cleanup) ----
    final cleanAddr = _cleanAddress(address);
    if (cleanAddr.isNotEmpty) {
      for (final line in _wrapAddr(cleanAddr, _maxAddr).take(2)) {
        if (cy > y0 + panelH - 14) break;
        _txt(src, line,
            font: img.arial14, x: textX, y: cy,
            color: img.ColorRgba8(160, 175, 195, 255));
        cy += 18;
      }
    }

    // ---- baris 4: cuaca ----
    if (showWeather && weather.isNotEmpty && cy < y0 + panelH - 12) {
      img.fillRect(src,
          x1: textX - 3, y1: cy - 2,
          x2: textX + weather.length * 7 + 6, y2: cy + 16,
          color: img.ColorRgba8(0, 184, 212, 22));
      _txt(src, weather,
          font: img.arial14, x: textX, y: cy,
          color: img.ColorRgba8(0, 184, 212, 255));
    }

    // ---- mini map dengan glassmorphism ----
    if (hasMap) {
      _glassMiniMap(src, mapBytes: mapBytes!, y0: y0, panelH: panelH, w: w, mapSz: mapSz);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  // ─── helpers ──────────────────────────────────────────────────────

  void _gradientBg(img.Image src,
      {required int y0, required int w, required int panelH, required bool isTop}) {
    for (int row = y0; row < y0 + panelH; row++) {
      if (row < 0 || row >= src.height) continue;
      final double t = isTop
          ? (row - y0) / panelH
          : 1.0 - (row - y0) / panelH;
      final int r = _lerp(8, 20, t);
      final int g = _lerp(12, 30, t);
      final int b = _lerp(20, 46, t);
      final int a = _lerp(235, 185, t);
      img.fillRect(src,
          x1: 0, y1: row, x2: w - 1, y2: row + 1,
          color: img.ColorRgba8(r, g, b, a));
    }
  }

  void _drawAccent(img.Image src, {required int x, required int y1, required int y2}) {
    // glow lembut
    img.fillRect(src,
        x1: x - 1, y1: y1 + 4,
        x2: x + _accentW + 2, y2: y2 - 4,
        color: img.ColorRgba8(0, 212, 170, 40));
    // bar utama
    img.fillRect(src,
        x1: x, y1: y1,
        x2: x + _accentW - 1, y2: y2,
        color: img.ColorRgba8(0, 212, 170, 255));
  }

  void _txt(img.Image src, String text, {
    required img.BitmapFont font,
    required int x, required int y,
    required img.Color color,
    bool shadow = false,
  }) {
    if (shadow) {
      img.drawString(src, text, font: font,
          x: x + 1, y: y + 1,
          color: img.ColorRgba8(0, 0, 0, 100));
    }
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  void _glassMiniMap(img.Image src, {
    required Uint8List mapBytes, required int y0, required int panelH, required int w, required int mapSz,
  }) {
    try {
      final m = img.decodeImage(mapBytes);
      if (m == null) return;

      // overlay gelap tipis agar map menyatu dengan UI
      img.fillRect(m, x1: 0, y1: 0, x2: m.width - 1, y2: m.height - 1,
          color: img.ColorRgba8(0, 0, 0, 35));

      final resized = img.copyResize(m, width: mapSz, height: mapSz);
      final int mx = w - mapSz - _padX;
      final int my = y0 + (panelH - mapSz) ~/ 2;
      if (mx < 0 || my < 0) return;

      // translucent frame (glassmorphism)
      img.fillRect(src,
          x1: mx - 4, y1: my - 4,
          x2: mx + mapSz + 3, y2: my + mapSz + 3,
          color: img.ColorRgba8(255, 255, 255, 35));

      img.compositeImage(src, resized,
          dstX: mx, dstY: my, blend: img.BlendMode.alpha);

      // inner border
      img.drawRect(src,
          x1: mx, y1: my,
          x2: mx + mapSz - 1, y2: my + mapSz - 1,
          color: img.ColorRgba8(255, 255, 255, 18), thickness: 1);
    } catch (_) {}
  }

  int _mapSz(bool showMiniMap, Uint8List? mapBytes) {
    if (!showMiniMap || mapBytes == null || mapBytes.isEmpty) return 0;
    return 100; // default
  }

  String _fmtLat(double v) =>
      '${v.abs().toStringAsFixed(5)}° ${v >= 0 ? "N" : "S"}';

  String _fmtLon(double v) =>
      '${v.abs().toStringAsFixed(5)}° ${v >= 0 ? "E" : "W"}';

  List<String> _wrapAddr(String text, int max) {
    if (text.length <= max) return [text];
    final parts = text.split(',');
    if (parts.length >= 2) {
      final l1   = parts.take(2).join(',').trim();
      final rest = parts.skip(2).join(',').trim();
      final l2   = rest.length > max ? '${rest.substring(0, max - 1)}…' : rest;
      return [l1, if (l2.isNotEmpty) l2];
    }
    return ['${text.substring(0, max - 1)}…'];
  }

  String _cleanAddress(String raw) {
    if (raw.isEmpty || raw == 'Tidak ada lokasi' || raw.startsWith('GPS:')) return '';

    // hapus plus code
    final plusCodePattern = RegExp(r'[23456789CFGHJMPQRVWX]{4,8}\+[23456789CFGHJMPQRVWX]{2,3}');
    String s = raw.replaceAll(plusCodePattern, '');

    // hapus "Unnamed Road"
    s = s.replaceAll('Unnamed Road,', '').replaceAll('Unnamed Road', '');

    // hapus duplikat berturut-turut (contoh: "Klojen, Klojen")
    final parts = s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final result = <String>[];
    for (final p in parts) {
      if (result.isEmpty || result.last.toLowerCase() != p.toLowerCase()) {
        result.add(p);
      }
    }

    // buang bagian akhir yang terlalu panjang (opsional)
    if (result.length > 3) {
      result.removeRange(3, result.length);
    }

    return result.join(', ');
  }

  int _lerp(int a, int b, double t) =>
      (a + (b - a) * t).round().clamp(0, 255);
}
