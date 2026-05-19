// lib/watermark/layouts/layout_cinematic.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutCinematic extends WatermarkLayoutBase {
  @override
  String get name => 'GPS Timestamp';

  static const int _padX = 20;
  static const int _padY = 16;
  static const int _mapH = 100;

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
    bool showAddress = true,
    bool showCoordinates = true,
    double opacity = 0.85,
    bool showBorder = true,
    String fontSize = 'normal',
  }) {
    final font = fontSize == 'small' ? img.arial14 : fontSize == 'large' ? img.arial24 : img.arial24;
    final smallFont = fontSize == 'small' ? img.arial14 : fontSize == 'large' ? img.arial24 : img.arial14;

    // Hitung tinggi panel
    int rowCount = 0;
    rowCount += 1; // mini map
    rowCount += 2; // jam + tanggal
    rowCount += 1; // divider
    if (showCoordinates && hasPosition) rowCount += 2;
    if (showAddress && address.isNotEmpty) rowCount += 2;
    if (showWeather && weather.isNotEmpty) rowCount += 1;

    final int panelH = _mapH + _padY * 2 + rowCount * 24 + 20;
    final int y0 = src.height - panelH;
    if (y0 < 0 || y0 >= src.height) return WatermarkLayoutBase.encodeJpg(src);

    const m = 12;
    final int cardW = src.width - m * 2;
    final int cardX = m;

    // Card background
    img.fillRect(src,
        x1: cardX, y1: y0 + m,
        x2: cardX + cardW, y2: y0 + panelH - m,
        color: img.ColorRgba8(19, 19, 19, (255 * opacity).toInt()));

    // Border rounded
    if (showBorder) {
      img.drawRect(src,
          x1: cardX, y1: y0 + m,
          x2: cardX + cardW, y2: y0 + panelH - m,
          color: img.ColorRgba8(255, 255, 255, 20), thickness: 1);
    }

    int cy = y0 + m + _padY;

    // Mini map di atas
    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) {
      try {
        final map = img.decodeImage(mapBytes);
        if (map != null) {
          final resized = img.copyResize(map, width: cardW, height: _mapH);
          final mapX = cardX;
          final mapY = cy;
          img.fillRect(src,
              x1: mapX, y1: mapY,
              x2: mapX + cardW, y2: mapY + _mapH,
              color: img.ColorRgba8(0, 0, 0, 60));
          img.compositeImage(src, resized,
              dstX: mapX, dstY: mapY, blend: img.BlendMode.alpha);
          final pinX = mapX + cardW ~/ 2;
          final pinY = mapY + _mapH ~/ 2;
          img.fillCircle(src, x: pinX, y: pinY, radius: 8,
              color: img.ColorRgba8(255, 50, 50, 255));
          img.fillCircle(src, x: pinX, y: pinY, radius: 3,
              color: WatermarkLayoutBase.white);
        }
      } catch (_) {}
      cy += _mapH + _padY;
    }

    // Tanggal
    img.drawString(src,
        DateFormat('EEE, dd MMM yyyy').format(timestamp),
        font: font, x: cardX + _padX, y: cy,
        color: WatermarkLayoutBase.white);
    cy += 24;

    // Jam
    img.drawString(src,
        DateFormat('HH:mm:ss').format(timestamp),
        font: font, x: cardX + _padX, y: cy,
        color: WatermarkLayoutBase.white);
    cy += 24;

    // Divider
    img.fillRect(src,
        x1: cardX + _padX, y1: cy,
        x2: cardX + cardW - _padX, y2: cy + 1,
        color: img.ColorRgba8(255, 255, 255, 20));
    cy += 12;

    // Alamat
    if (showAddress && address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      final lines = _splitAddress(address);
      for (final line in lines.take(2)) {
        img.drawString(src, line,
            font: smallFont, x: cardX + _padX, y: cy,
            color: WatermarkLayoutBase.white);
        cy += 20;
      }
    }

    // Koordinat
    if (showCoordinates && hasPosition) {
      img.drawString(src,
          '${lat!.toStringAsFixed(2)}°, ${lon!.toStringAsFixed(2)}°',
          font: smallFont, x: cardX + _padX, y: cy,
          color: WatermarkLayoutBase.blue);
      cy += 20;
    }

    // Cuaca
    if (showWeather && weather.isNotEmpty) {
      img.drawString(src, weather,
          font: smallFont, x: cardX + _padX, y: cy,
          color: WatermarkLayoutBase.blue);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  List<String> _splitAddress(String address) {
    const maxLen = 42;
    final parts = address.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return [address.length > maxLen ? '${address.substring(0, maxLen - 1)}…' : address];
    final l1 = parts.first;
    final rest = parts.skip(1).join(', ');
    return [
      l1.length > maxLen ? '${l1.substring(0, maxLen - 1)}…' : l1,
      if (rest.isNotEmpty)
        rest.length > maxLen ? '${rest.substring(0, maxLen - 1)}…' : rest,
    ];
  }
}
