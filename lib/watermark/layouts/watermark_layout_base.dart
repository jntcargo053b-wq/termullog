// lib/watermark/layouts/watermark_layout_base.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

/// Base class untuk semua layout watermark
abstract class WatermarkLayoutBase {
  /// Nama layout untuk debugging
  String get name;

  /// Konstanta warna (img.ColorRgba8 tidak bisa const — pakai static final)
  static final img.Color white    = img.ColorRgba8(255, 255, 255, 255);
  static final img.Color offWhite = img.ColorRgba8(230, 230, 230, 255);
  static final img.Color blue     = img.ColorRgba8(30, 144, 255, 255);
  static final img.Color grey     = img.ColorRgba8(150, 150, 150, 255);

  /// Alias untuk layout baru
  static final img.Color imgWhite    = white;
  static final img.Color imgOffWhite = offWhite;
  static final img.Color imgBlue     = blue;
  static final img.Color imgGrey     = grey;

  /// Warna untuk dart:ui Canvas
  static const Color uiWhite    = Color(0xFFFFFFFF);
  static const Color uiBlue     = Color(0xFF1E90FF);
  static const Color uiGrey     = Color(0xFF969696);
  static const Color uiOffWhite = Color(0xFFE6E6E6);

  /// Flag font sudah diload
  static bool _fontLoaded = false;

  /// Load font Roboto dari assets (panggil sekali)
  static Future<void> loadFont() async {
    if (_fontLoaded) return;
    try {
      final fontLoader = FontLoader('Roboto')
        ..addFont(rootBundle.load('fonts/Roboto-Regular.ttf'))
        ..addFont(rootBundle.load('fonts/Roboto-Bold.ttf'));
      await fontLoader.load();
      _fontLoaded = true;
    } catch (e) {
      _fontLoaded = true;
    }
  }

  // ─── SYNC: wajib diimplementasikan dengan parameter opsional ─────
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
  });

  // ─── ASYNC: opsional ─────────────────────────────────────────────
  Future<Uint8List> applyAsync({
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
  }) async {
    return apply(
      src: src, timestamp: timestamp, hasPosition: hasPosition,
      lat: lat, lon: lon, acc: acc, address: address, weather: weather,
      showWeather: showWeather, showAccuracy: showAccuracy,
      showMiniMap: showMiniMap, mapBytes: mapBytes,
      showAddress: showAddress,
      showCoordinates: showCoordinates,
      opacity: opacity,
      showBorder: showBorder,
      fontSize: fontSize,
    );
  }

  // ==========================================================================
  // FUNGSI-FUNGSI BARU: Safe Area, Auto Font Scale, Wrap, Shadow, Anti Overflow
  // ==========================================================================

  /// Mendapatkan rect aman berdasarkan orientasi gambar
  /// (notch area untuk portrait/landscape)
  static Rect getSafeArea(img.Image src, Orientation orientation) {
    final width = src.width;
    final height = src.height;
    if (orientation == Orientation.portrait) {
      // Contoh: sisakan 44 pixel di atas untuk notch, 34 di bawah untuk home indicator
      return Rect.fromLTRB(0, 44, width.toDouble(), (height - 34).toDouble());
    } else {
      // Landscape: sisakan 44 pixel di kiri/kanan untuk notch
      return Rect.fromLTRB(44, 0, (width - 44).toDouble(), height.toDouble());
    }
  }

  /// Menyesuaikan opacity secara adaptif berdasarkan kecerahan area
  /// (implementasi sederhana: ambil sampel area, jika cerah -> opacity lebih rendah)
  static double getAdaptiveOpacity(img.Image src, int x, int y, int w, int h, double baseOpacity) {
    // Hitung rata-rata kecerahan area yang akan ditimpa watermark
    int total = 0;
    int count = 0;
    final step = (w * h) ~/ 100; // sampel 1% piksel
    for (int i = 0; i < w; i += (w ~/ 20) + 1) {
      for (int j = 0; j < h; j += (h ~/ 20) + 1) {
        final px = src.getPixel(x + i, y + j);
        final brightness = (px.r + px.g + px.b) ~/ 3;
        total += brightness;
        count++;
      }
    }
    final avgBrightness = total / count;
    if (avgBrightness > 200) return baseOpacity * 0.6; // area terang -> lebih transparan
    if (avgBrightness > 150) return baseOpacity * 0.8;
    return baseOpacity;
  }

  /// Menggambar teks dengan fitur lengkap: shadow, auto scale, wrap, anti overflow
  /// Parameter:
  /// - dst: gambar tujuan
  /// - text: teks
  /// - x, y: posisi (koordinat piksel)
  /// - font: font yang digunakan (img.BitmapFont)
  /// - color: warna
  /// - enableShadow: true untuk shadow hitam di bawah
  /// - autoScale: true untuk mengecilkan font jika melebihi maxWidth
  /// - maxWidth: lebar maksimum (0 = ambil dari lebar gambar - x - 20)
  /// - maxLines: maksimal baris (jika wrap=true, akan dibatasi)
  /// - wrap: true untuk memecah teks menjadi beberapa baris berdasarkan maxWidth
  /// - lineHeight: tinggi antar baris (default font.height + 4)
  /// - overflowAction: jika teks masih overflow, bisa 'ellipsis' atau 'clip'
  void drawSafeText(
    img.Image dst,
    String text,
    int x, int y, {
    required img.BitmapFont font,
    required int color,
    bool enableShadow = true,
    bool autoScale = true,
    int maxWidth = 0,
    int maxLines = 1,
    bool wrap = false,
    int? lineHeight,
    String overflowAction = 'ellipsis',
  }) {
    if (text.isEmpty) return;

    // Tentukan lebar maksimum
    final effectiveMaxWidth = maxWidth > 0 ? maxWidth : dst.width - x - 20;
    if (effectiveMaxWidth <= 0) return;

    // Jika wrap=true, pecah teks menjadi baris
    List<String> lines = wrap ? _wrapText(text, font, effectiveMaxWidth) : [text];

    // Jika perlu auto scale dan baris pertama overflow, coba turunkan font
    img.BitmapFont currentFont = font;
    if (autoScale && lines.isNotEmpty && _isTextOverflow(lines.first, currentFont, effectiveMaxWidth)) {
      currentFont = _getScaledFont(font, effectiveMaxWidth, lines.first);
      // setelah scaling, ulang wrap jika perlu
      if (wrap) {
        lines = _wrapText(text, currentFont, effectiveMaxWidth);
      }
    }

    // Potong jika melebihi maxLines
    if (lines.length > maxLines) {
      if (overflowAction == 'ellipsis') {
        lines = lines.sublist(0, maxLines - 1);
        lines.add('...');
      } else {
        lines = lines.sublist(0, maxLines);
      }
    }

    // Hitung tinggi baris
    final lineH = lineHeight ?? (currentFont.height + 4);
    int currentY = y;

    for (final line in lines) {
      // Cek overflow vertikal
      if (currentY + currentFont.height > dst.height) break;

      // Gambar shadow jika diperlukan
      if (enableShadow) {
        img.drawString(dst, line, font: currentFont, x: x + 1, y: currentY + 1,
            color: (color & 0x00FFFFFF) | 0x44000000); // shadow semi transparan
      }
      // Gambar teks utama
      img.drawString(dst, line, font: currentFont, x: x, y: currentY, color: color);
      currentY += lineH;
    }
  }

  /// Memecah teks menjadi baris-baris berdasarkan lebar maksimum
  List<String> _wrapText(String text, img.BitmapFont font, int maxWidth) {
    final words = text.split(' ');
    final lines = <String>[];
    String currentLine = '';
    for (final word in words) {
      final testLine = currentLine.isEmpty ? word : '$currentLine $word';
      if (font.getWidth(testLine) <= maxWidth) {
        currentLine = testLine;
      } else {
        if (currentLine.isNotEmpty) lines.add(currentLine);
        currentLine = word;
      }
    }
    if (currentLine.isNotEmpty) lines.add(currentLine);
    return lines;
  }

  /// Cek apakah teks melebihi lebar maksimum
  bool _isTextOverflow(String text, img.BitmapFont font, int maxWidth) {
    return font.getWidth(text) > maxWidth;
  }

  /// Mendapatkan font dengan ukuran lebih kecil (hardcoded fallback)
  img.BitmapFont _getScaledFont(img.BitmapFont original, int maxWidth, String text) {
    // Coba ukuran font yang lebih kecil
    if (original == img.arial24) {
      if (img.arial14.getWidth(text) <= maxWidth) return img.arial14;
      return img.arial12;
    } else if (original == img.arial14) {
      if (img.arial12.getWidth(text) <= maxWidth) return img.arial12;
    }
    // Fallback: tetap pakai original (tidak ada ukuran lebih kecil)
    return original;
  }

  // ─── CANVAS HELPERS ──────────────────────────────────────────────
  static void canvasDrawText(Canvas canvas, String text, {required double x, required double y, Color color = uiWhite, bool bold = false, double size = 14, double letterSpacing = 1.0}) {
    final tp = TextPainter(text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontFamily: 'Roboto', fontWeight: bold ? FontWeight.w700 : FontWeight.w400, letterSpacing: letterSpacing)), textDirection: TextDirection.ltr);
    tp.layout(); tp.paint(canvas, Offset(x, y));
  }

  static void canvasDrawTextShadow(Canvas canvas, String text, {required double x, required double y, Color color = uiWhite, bool bold = false, double size = 14}) {
    canvasDrawText(canvas, text, x: x + 1, y: y + 1, color: Colors.black54, bold: bold, size: size);
    canvasDrawText(canvas, text, x: x, y: y, color: color, bold: bold, size: size);
  }

  static void canvasDrawChip(Canvas canvas, {required double x, required double y, required double width, required double height, Color color = uiBlue, double opacity = 0.15}) {
    canvas.drawRRect(RRect.fromLTRBR(x, y, x + width, y + height, const Radius.circular(4)), Paint()..color = color.withOpacity(opacity));
  }

  static void canvasDrawGradient(Canvas canvas, {required double x, required double y, required double width, required double height, Color color = Colors.black, double startOpacity = 0.8, double endOpacity = 0.0, bool topToBottom = true}) {
    canvas.drawRect(Rect.fromLTWH(x, y, width, height), Paint()..shader = ui.Gradient.linear(Offset(x, topToBottom ? y : y + height), Offset(x, topToBottom ? y + height : y), [color.withOpacity(startOpacity), color.withOpacity(endOpacity)]));
  }

  // ─── KONVERSI IMAGE ──────────────────────────────────────────────
  static Future<ui.Image> toUiImage(img.Image src) async {
    final pngBytes = Uint8List.fromList(img.encodePng(src));
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  static Future<img.Image> recorderToImg(ui.PictureRecorder recorder, int width, int height) async {
    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(width, height);
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    return img.decodePng(byteData!.buffer.asUint8List())!;
  }

  // ─── IMG PACKAGE HELPERS ─────────────────────────────────────────
  static img.Image decodeOrThrow(Uint8List bytes) {
    if (bytes.isEmpty) throw Exception('Data gambar kosong');
    if (bytes.length < 100) throw Exception('Data gambar terlalu kecil');
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Format tidak didukung');
    return decoded;
  }

  /// Encode ke JPEG
  static Uint8List encodeJpg(img.Image src, {int quality = 90}) {
    return Uint8List.fromList(img.encodeJpg(src, quality: quality));
  }
}
