import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutCinematic extends WatermarkLayoutBase {
  @override
  String get name => 'Cinematic';

  // ── Dimensi area gradient ───────────────────────────────────────────────
  static const int gradH    = 220;   // lebih tinggi agar teks tidak terpotong
  static const int padX     = 28;
  static const int padY     = 14;    // jarak dari tepi atas/bawah
  static const int lineH    = 30;    // tinggi baris normal
  static const int lineHSm  = 24;    // tinggi baris kecil (accuracy, address)

  // ── Mini-map ────────────────────────────────────────────────────────────
  static const int mapW     = 110;
  static const int mapH     = 82;
  static const int mapMar   = 14;
  static const int mapBorder = 2;

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

    // Hitung berapa baris yang akan ditampilkan untuk menentukan gradH dinamis
    int rowCount = 2; // jam + tanggal selalu ada
    if (hasPosition) {
      rowCount += 1;
      if (showAccuracy) rowCount += 1;
    }
    final bool showAddr = address.isNotEmpty &&
        address != 'Tidak ada lokasi' &&
        !address.startsWith('GPS:');
    if (showAddr) rowCount += _addressLineCount(src.width, address);
    if (showWeather && weather.isNotEmpty) rowCount += 1;

    // Tinggi area = padding atas + baris + spacer divider + padding bawah
    final int dynGradH = (padY + lineH + lineH + 10 + // jam + tanggal + spasi
        (rowCount - 2) * lineHSm +                    // baris sisanya
        padY + 10)                                     // padding bawah
        .clamp(gradH, gradH + 60);                    // clamp supaya tidak terlalu besar

    final int gradY0 = isTop ? 0 : src.height - dynGradH;

    // 1. Gradient overlay
    _applyGradient(src, gradY0, dynGradH, isTop);

    // 2. Garis aksen biru
    final int divY = isTop ? dynGradH - 38 : gradY0 + 34;
    img.fillRect(src,
        x1: padX, y1: divY,
        x2: src.width - padX - (showMiniMap && mapBytes != null ? mapW + mapMar * 2 + 8 : 0),
        y2: divY + 2,
        color: img.ColorRgba8(30, 144, 255, 220));

    // 3. Area tulis teks (kiri, hindari mini-map di kanan)
    final int textMaxX = src.width - padX -
        (showMiniMap && mapBytes != null ? mapW + mapMar * 2 + 8 : 0);
    final int textW = textMaxX - padX;

    final fontLg = img.arial24;   // jam, tanggal
    final fontSm = img.arial14;   // koordinat, address, weather

    int cy = isTop ? padY : gradY0 + padY;

    // Jam
    _drawOutlined(src, DateFormat('HH : mm : ss').format(timestamp),
        fontLg, padX, cy, WatermarkLayoutBase.white);
    cy += lineH;

    // Tanggal
    _drawOutlined(src, DateFormat('dd  MMMM  yyyy').format(timestamp),
        fontLg, padX, cy, WatermarkLayoutBase.blue);
    cy += lineH + 8;

    // Koordinat
    if (hasPosition) {
      _drawOutlined(src,
          '${lat!.toStringAsFixed(6)}°N   ${lon!.toStringAsFixed(6)}°E',
          fontSm, padX, cy, WatermarkLayoutBase.offWhite);
      cy += lineHSm;

      if (showAccuracy) {
        _drawOutlined(src,
            'ACCURACY  ±${acc?.toStringAsFixed(1) ?? '?'} m',
            fontSm, padX, cy, WatermarkLayoutBase.grey);
        cy += lineHSm;
      }
    }

    // Alamat – wrap otomatis supaya tidak terpotong
    if (showAddr) {
      final lines = _wrapText(address, textW, fontSm);
      for (final line in lines) {
        _drawOutlined(src, line, fontSm, padX, cy, WatermarkLayoutBase.grey);
        cy += lineHSm;
      }
    }

    // Cuaca
    if (showWeather && weather.isNotEmpty) {
      _drawOutlined(src, weather, fontSm, padX, cy, WatermarkLayoutBase.blue);
    }

    // 4. Mini-map
    if (showMiniMap && mapBytes != null && mapBytes.isNotEmpty) {
      _drawMiniMap(src, mapBytes, isTop, dynGradH, gradY0);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  // ── Gradient ─────────────────────────────────────────────────────────────
  void _applyGradient(img.Image src, int gradY0, int dynGradH, bool isTop) {
    for (int y = gradY0; y < gradY0 + dynGradH; y++) {
      if (y < 0 || y >= src.height) continue;
      final t = isTop
          ? 1.0 - (y - gradY0) / dynGradH
          : (y - gradY0) / dynGradH;
      // Lebih gelap di tepi, lebih transparan di tengah
      final alpha = (t * 210).toInt().clamp(0, 210);
      for (int x = 0; x < src.width; x++) {
        final px = src.getPixel(x, y);
        src.setPixel(x, y, img.ColorRgba8(
          ((px.r * (255 - alpha)) ~/ 255),
          ((px.g * (255 - alpha)) ~/ 255),
          ((px.b * (255 - alpha)) ~/ 255),
          255,
        ));
      }
    }
  }

  // ── Teks dengan outline tipis agar terbaca di semua background ───────────
  void _drawOutlined(
    img.Image src, String text, img.BitmapFont font,
    int x, int y, img.Color color,
  ) {
    final shadow = img.ColorRgba8(0, 0, 0, 160);
    for (int dx = -1; dx <= 1; dx++) {
      for (int dy = -1; dy <= 1; dy++) {
        if (dx == 0 && dy == 0) continue;
        img.drawString(src, text, font: font,
            x: x + dx, y: y + dy, color: shadow);
      }
    }
    img.drawString(src, text, font: font, x: x, y: y, color: color);
  }

  // ── Word-wrap sederhana berdasarkan perkiraan lebar karakter ────────────
  List<String> _wrapText(String text, int maxWidth, img.BitmapFont font) {
    // Estimasi lebar: arial14 ≈ 8px/char, arial24 ≈ 14px/char
    final charW = (font == img.arial24) ? 14 : 8;
    final maxChars = (maxWidth / charW).floor().clamp(20, 200);

    final words = text.split(' ');
    final lines = <String>[];
    var current = '';

    for (final word in words) {
      final candidate = current.isEmpty ? word : '$current $word';
      if (candidate.length <= maxChars) {
        current = candidate;
      } else {
        if (current.isNotEmpty) lines.add(current);
        current = word.length > maxChars
            ? '${word.substring(0, maxChars - 1)}…'
            : word;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines.take(3).toList(); // maks 3 baris address
  }

  int _addressLineCount(int imageWidth, String address) {
    final textW = imageWidth - padX * 2 - mapW - mapMar * 2 - 8;
    return _wrapText(address, textW, img.arial14).length;
  }

  // ── Mini-map dengan border ────────────────────────────────────────────────
  void _drawMiniMap(
    img.Image src, Uint8List mapBytes,
    bool isTop, int dynGradH, int gradY0,
  ) {
    img.Image? mapImage;
    try { mapImage = img.decodeImage(mapBytes); } catch (_) {}
    if (mapImage == null) return;

    try {
      final resized = img.copyResize(mapImage,
          width: mapW, height: mapH,
          interpolation: img.Interpolation.average);

      final int mapX = src.width - mapW - mapMar;
      final int mapY = isTop
          ? mapMar + padY
          : src.height - mapH - mapMar - padY;

      if (mapX < 0 || mapY < 0 ||
          mapX + mapW > src.width || mapY + mapH > src.height) return;

      // Border gelap
      img.fillRect(src,
          x1: mapX - mapBorder, y1: mapY - mapBorder,
          x2: mapX + mapW + mapBorder, y2: mapY + mapH + mapBorder,
          color: img.ColorRgba8(0, 0, 0, 200));

      // Aksen biru tipis
      img.drawRect(src,
          x1: mapX - mapBorder, y1: mapY - mapBorder,
          x2: mapX + mapW + mapBorder, y2: mapY + mapH + mapBorder,
          color: img.ColorRgba8(30, 144, 255, 180),
          thickness: 1);

      img.compositeImage(src, resized,
          dstX: mapX, dstY: mapY, blend: img.BlendMode.alpha);
    } catch (_) {}
  }
}
