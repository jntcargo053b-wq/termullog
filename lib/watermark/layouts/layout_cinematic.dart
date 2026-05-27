// lib/watermark/layouts/layout_cinematic.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutCinematic extends WatermarkLayoutBase {
  @override
  String get name => 'Cinematic Modern';

  // Warna tema (modern dark cinematic)
  static final _bgTop = img.ColorRgba8(18, 20, 28, 235);
  static final _bgBottom = img.ColorRgba8(8, 10, 16, 250);
  static final _borderLight = img.ColorRgba8(255, 255, 255, 45);
  static final _textWhite = img.ColorRgba8(245, 248, 255, 255);
  static final _textMuted = img.ColorRgba8(170, 180, 200, 255);
  static final _accentBlue = img.ColorRgba8(80, 170, 250, 255);
  static final _accentGreen = img.ColorRgba8(100, 220, 140, 255);
  static final _accentCyan = img.ColorRgba8(60, 210, 230, 255);
  static final _shadowColor = img.ColorRgba8(0, 0, 0, 80);

  // Hanya menggunakan font yang tersedia: arial14, arial24, arial48
  img.BitmapFont _getDateFont(String fontSize) {
    switch (fontSize) {
      case 'large': return img.arial24;
      case 'small': return img.arial14;
      default: return img.arial24; // normal
    }
  }

  img.BitmapFont _getTimeFont(String fontSize) {
    switch (fontSize) {
      case 'large': return img.arial48;
      case 'small': return img.arial24;
      default: return img.arial48; // normal juga pakai arial48 agar lebih tegas
    }
  }

  img.BitmapFont _getInfoFont(String fontSize) {
    switch (fontSize) {
      case 'large': return img.arial24;
      case 'small': return img.arial14;
      default: return img.arial24; // normal
    }
  }

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
    required bool showMiniMap,
    Uint8List? mapBytes,
    bool showAddress = true,
    bool showCoordinates = true,
    double opacity = 0.85,
    bool showBorder = true,
    String fontSize = 'normal',
    String mapSize = 'medium',
    String dateFormat = 'dd MMM yyyy',
    String timeFormat = 'HH:mm:ss',
  }) {
    final double scale = (src.width / 1080).clamp(0.7, 2.0);
    
    final fontDate = _getDateFont(fontSize);
    final fontTime = _getTimeFont(fontSize);
    final fontInfo = _getInfoFont(fontSize);
    
    final int padX = (24 * scale).round();
    final int padY = (20 * scale).round();
    final int margin = (16 * scale).round();
    final int shadowOffset = (6 * scale).round();
    
    // Hitung tinggi panel (tanpa emoji)
    int contentHeight = 0;
    contentHeight += fontDate.height + 8;
    contentHeight += fontTime.height + 12;
    contentHeight += 8; // separator
    
    List<String> addressLines = [];
    if (showAddress && address.isNotEmpty && !_isInvalidAddress(address)) {
      addressLines = _splitAddress(address, scale);
      contentHeight += addressLines.length * (fontInfo.height + 6);
    }
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      contentHeight += fontInfo.height + 6;
    }
    if (showAccuracy && hasPosition && acc != null) {
      contentHeight += fontInfo.height + 6;
    }
    if (showWeather && weather.isNotEmpty) {
      contentHeight += fontInfo.height + 6;
    }
    
    final int panelHeight = contentHeight + padY * 2;
    final int cardWidth = src.width - margin * 2;
    final int cardX = margin;
    int cardY = src.height - panelHeight - margin;
    
    // Safety bounds (jangan keluar gambar)
    if (cardY < margin) cardY = margin;
    if (cardY + panelHeight > src.height) {
      // fallback: simpan di posisi aman
      return WatermarkLayoutBase.encodeJpg(src);
    }
    
    // 1. Background gradien (loop aman, cepat)
    for (int y = cardY; y < cardY + panelHeight; y++) {
      final double t = (y - cardY) / panelHeight;
      final int r = _lerp(_bgTop.r, _bgBottom.r, t);
      final int g = _lerp(_bgTop.g, _bgBottom.g, t);
      final int b = _lerp(_bgTop.b, _bgBottom.b, t);
      final int a = (_lerp(_bgTop.a, _bgBottom.a, t) * opacity).toInt().clamp(0, 255);
      img.drawLine(src,
          x1: cardX, y1: y,
          x2: cardX + cardWidth, y2: y,
          color: img.ColorRgba8(r, g, b, a));
    }
    
    // 2. Border dengan radius (simulasi)
    if (showBorder) {
      _drawRoundedBorder(src, cardX, cardY, cardX + cardWidth, cardY + panelHeight, (16 * scale).round());
    }
    
    // 3. Shadow bawah (efek mengambang) dengan batas aman
    if (shadowOffset > 0 && cardY + panelHeight + shadowOffset <= src.height) {
      for (int i = 1; i <= shadowOffset; i++) {
        final int alpha = (40 * (1 - i / shadowOffset)).toInt().clamp(0, 40);
        img.drawLine(src,
            x1: cardX + 8, y1: cardY + panelHeight + i - 1,
            x2: cardX + cardWidth - 8, y2: cardY + panelHeight + i - 1,
            color: img.ColorRgba8(0, 0, 0, alpha));
      }
    }
    
    int cy = cardY + padY;
    
    // Tanggal
    final dateStr = DateFormat(dateFormat).format(timestamp);
    img.drawString(src, dateStr, font: fontDate, x: cardX + padX, y: cy, color: _textMuted);
    cy += fontDate.height + 8;
    
    // Waktu
    final timeStr = DateFormat(timeFormat).format(timestamp);
    img.drawString(src, timeStr, font: fontTime, x: cardX + padX, y: cy, color: _textWhite);
    cy += fontTime.height + 12;
    
    // Separator garis tipis (efisien)
    img.drawLine(src,
        x1: cardX + padX, y1: cy,
        x2: cardX + cardWidth - padX, y2: cy,
        color: img.ColorRgba8(255, 255, 255, 30),
        thickness: 1);
    cy += 8;
    
    // Alamat
    for (final line in addressLines) {
      img.drawString(src, line, font: fontInfo, x: cardX + padX, y: cy, color: _textMuted);
      cy += fontInfo.height + 6;
    }
    
    // Koordinat (tanpa emoji, pakai huruf N/S/E/W)
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      final latDir = lat >= 0 ? "N" : "S";
      final lonDir = lon >= 0 ? "E" : "W";
      final coordStr = "${lat.abs().toStringAsFixed(5)}° $latDir   ${lon.abs().toStringAsFixed(5)}° $lonDir";
      img.drawString(src, coordStr, font: fontInfo, x: cardX + padX, y: cy, color: _accentBlue);
      cy += fontInfo.height + 6;
    }
    
    // Akurasi (tanpa emoji)
    if (showAccuracy && hasPosition && acc != null) {
      final accStr = "Akurasi ± ${acc.toStringAsFixed(1)} m";
      img.drawString(src, accStr, font: fontInfo, x: cardX + padX, y: cy, color: _accentGreen);
      cy += fontInfo.height + 6;
    }
    
    // Cuaca (tanpa emoji, dengan background highlight)
    if (showWeather && weather.isNotEmpty) {
      // Background highlight transparan (opsional)
      img.fillRect(src,
          x1: cardX + padX - 4, y1: cy - 2,
          x2: cardX + padX + weather.length * (fontInfo.width ~/ 2) + 8,
          y2: cy + fontInfo.height + 2,
          color: img.ColorRgba8(80, 180, 255, 25));
      img.drawString(src, weather, font: fontInfo, x: cardX + padX, y: cy, color: _accentCyan);
    }
    
    return WatermarkLayoutBase.encodeJpg(src);
  }
  
  // Gambar border dengan sudut membulat (simulasi)
  void _drawRoundedBorder(img.Image src, int x1, int y1, int x2, int y2, int r) {
    final int thickness = 2;
    // Garis tepi
    img.drawLine(src,
        x1: x1 + r, y1: y1,
        x2: x2 - r, y2: y1,
        color: _borderLight, thickness: thickness);
    img.drawLine(src,
        x1: x1 + r, y1: y2,
        x2: x2 - r, y2: y2,
        color: _borderLight, thickness: thickness);
    img.drawLine(src,
        x1: x1, y1: y1 + r,
        x2: x1, y2: y2 - r,
        color: _borderLight, thickness: thickness);
    img.drawLine(src,
        x1: x2, y1: y1 + r,
        x2: x2, y2: y2 - r,
        color: _borderLight, thickness: thickness);
    // Gambar lengkungan sudut (lingkaran kecil)
    if (r > 4) {
      img.drawCircle(src, x: x1 + r, y: y1 + r, radius: r, color: _borderLight, thickness: thickness);
      img.drawCircle(src, x: x2 - r, y: y1 + r, radius: r, color: _borderLight, thickness: thickness);
      img.drawCircle(src, x: x1 + r, y: y2 - r, radius: r, color: _borderLight, thickness: thickness);
      img.drawCircle(src, x: x2 - r, y: y2 - r, radius: r, color: _borderLight, thickness: thickness);
    }
  }
  
  // Deteksi alamat invalid
  bool _isInvalidAddress(String addr) {
    return addr.isEmpty ||
        addr == 'Tidak ada lokasi' ||
        addr.startsWith('GPS:') ||
        addr.startsWith('Mencari');
  }
  
  // Pecah alamat menjadi maksimal 2 baris dengan panjang dinamis
  List<String> _splitAddress(String address, double scale) {
    final int maxLen = (38 + (scale * 6).round()).clamp(38, 55);
    final List<String> parts = address.split(',');
    if (parts.length == 1) {
      final List<String> words = address.split(' ');
      final List<String> lines = [];
      String current = '';
      for (final word in words) {
        if ((current + word).length > maxLen) {
          if (current.isNotEmpty) lines.add(current.trim());
          current = word;
        } else {
          current += (current.isEmpty ? word : ' $word');
        }
      }
      if (current.isNotEmpty) lines.add(current.trim());
      return lines.take(2).toList();
    } else {
      String first = parts.first.trim();
      String rest = parts.skip(1).join(',').trim();
      if (first.length > maxLen) first = first.substring(0, maxLen - 3) + '…';
      if (rest.length > maxLen) rest = rest.substring(0, maxLen - 3) + '…';
      return [first, rest];
    }
  }
  
  int _lerp(int a, int b, double t) => (a + (b - a) * t).round().clamp(0, 255);
}
