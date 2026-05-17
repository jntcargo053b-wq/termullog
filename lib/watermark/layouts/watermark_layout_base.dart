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
  
  /// Konstanta warna yang digunakan oleh semua layout (img package)
  static final white    = img.ColorRgba8(255, 255, 255, 255);
  static final offWhite = img.ColorRgba8(230, 230, 230, 255);
  static final blue     = img.ColorRgba8(30, 144, 255, 255);
  static final grey     = img.ColorRgba8(150, 150, 150, 255);
  
  /// Flag untuk menandai apakah font sudah diload
  static bool _fontLoaded = false;

  /// Load font Roboto dari assets (dipanggil sekali)
  static Future<void> loadFont() async {
    if (_fontLoaded) return;
    try {
      final fontLoader = FontLoader('Roboto')
        ..addFont(await rootBundle.load('fonts/Roboto-Regular.ttf'))
        ..addFont(await rootBundle.load('fonts/Roboto-Bold.ttf'));
      await fontLoader.load();
      _fontLoaded = true;
    } catch (e) {
      // Font tidak ditemukan — fallback ke font sistem
      _fontLoaded = true; // jangan coba lagi
    }
  }

  // ────────────────────────────────────────────────────────────────
  // SYNC VERSION — untuk pipeline img package (wajib diimplementasikan)
  // ────────────────────────────────────────────────────────────────
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
  });

  // ────────────────────────────────────────────────────────────────
  // ASYNC VERSION — untuk pipeline dart:ui Canvas (opsional)
  // Default: panggil sync version untuk backward compatibility
  // ────────────────────────────────────────────────────────────────
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
    required String watermarkPosition,
    required bool showMiniMap,
    Uint8List? mapBytes,
  }) async {
    return apply(
      src: src,
      timestamp: timestamp,
      hasPosition: hasPosition,
      lat: lat,
      lon: lon,
      acc: acc,
      address: address,
      weather: weather,
      showWeather: showWeather,
      showAccuracy: showAccuracy,
      watermarkPosition: watermarkPosition,
      showMiniMap: showMiniMap,
      mapBytes: mapBytes,
    );
  }

  // ────────────────────────────────────────────────────────────────
  // HELPERS — untuk dart:ui Canvas rendering
  // ────────────────────────────────────────────────────────────────

  /// Gambar teks dengan TextPainter (font Roboto)
  static void drawText(
    Canvas canvas,
    String text, {
    required double x,
    required double y,
    Color color = Colors.white,
    bool bold = false,
    double size = 14,
    double letterSpacing = 1.0,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontFamily: 'Roboto',
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          letterSpacing: letterSpacing,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(x, y));
  }

  /// Gambar teks dengan shadow
  static void drawTextWithShadow(
    Canvas canvas,
    String text, {
    required double x,
    required double y,
    Color color = Colors.white,
    Color shadowColor = Colors.black54,
    bool bold = false,
    double size = 14,
    double shadowOffset = 1.0,
  }) {
    drawText(canvas, text, x: x + shadowOffset, y: y + shadowOffset, color: shadowColor, bold: bold, size: size);
    drawText(canvas, text, x: x, y: y, color: color, bold: bold, size: size);
  }

  /// Konversi img.Image → ui.Image
  static Future<ui.Image> imgToUiImage(img.Image src) async {
    final pngBytes = Uint8List.fromList(img.encodePng(src));
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Konversi ui.Image → img.Image
  static Future<img.Image> uiImageToImg(ui.Image src) async {
    final byteData = await src.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();
    return img.decodePng(pngBytes)!;
  }

  /// Render Canvas → img.Image
  static Future<img.Image> canvasToImg(ui.PictureRecorder recorder, ui.Image uiImage) async {
    final picture = recorder.endRecording();
    final newUiImage = await picture.toImage(uiImage.width, uiImage.height);
    return uiImageToImg(newUiImage);
  }

  // ────────────────────────────────────────────────────────────────
  // HELPERS — untuk img package (sync)
  // ────────────────────────────────────────────────────────────────

  /// Helper untuk decode gambar dengan validasi
  static img.Image decodeOrThrow(Uint8List bytes) {
    if (bytes.isEmpty) throw Exception('Data gambar kosong');
    if (bytes.length < 100) throw Exception('Data gambar terlalu kecil, mungkin corrupt');
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Format gambar tidak didukung');
    return decoded;
  }
  
  /// Encode ke JPEG dengan quality standar
  static Uint8List encodeJpg(img.Image src, {int quality = 90}) {
    return Uint8List.fromList(img.encodeJpg(src, quality: quality));
  }
}
