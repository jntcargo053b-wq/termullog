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

  /// 🎨 PERSONALITY LAYOUT - setiap layout menentukan sendiri posisi defaultnya
  /// 
  /// Nilai yang mungkin:
  /// - 'topLeft', 'top', 'topRight'
  /// - 'left', 'center', 'right'
  /// - 'bottomLeft', 'bottom', 'bottomRight'
  /// - 'fullFrame' (khusus layout yang memenuhi seluruh frame)
  String get defaultPosition => 'bottom';
  
  /// 🎨 PERSONALITY LAYOUT - opacity default untuk layout ini
  double get defaultOpacity => 0.85;
  
  /// 🎨 PERSONALITY LAYOUT - apakah layout ini mendukung mini map?
  bool get supportsMiniMap => true;
  
  /// 🎨 PERSONALITY LAYOUT - apakah layout ini mendukung border?
  bool get supportsBorder => true;
  
  /// 🎨 PERSONALITY LAYOUT - ukuran font default ('small', 'normal', 'large')
  String get defaultFontSize => 'normal';
  
  /// 🎨 PERSONALITY LAYOUT - apakah layout ini menampilkan weather secara default?
  bool get defaultShowWeather => true;
  
  /// 🎨 PERSONALITY LAYOUT - apakah layout ini menampilkan akurasi GPS?
  bool get defaultShowAccuracy => true;
  
  /// 🎨 PERSONALITY LAYOUT - apakah layout ini menampilkan address?
  bool get defaultShowAddress => true;
  
  /// 🎨 PERSONALITY LAYOUT - apakah layout ini menampilkan koordinat?
  bool get defaultShowCoordinates => true;

  /// Konstanta warna (img.ColorRgba8 tidak bisa const — pakai static final)
  static final img.Color white    = img.getColor(255, 255, 255, 255);
  static final img.Color offWhite = img.getColor(230, 230, 230, 255);
  static final img.Color blue     = img.getColor(30, 144, 255, 255);
  static final img.Color grey     = img.getColor(150, 150, 150, 255);

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
    required String watermarkPosition,
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
    required String watermarkPosition,
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
      watermarkPosition: watermarkPosition, showMiniMap: showMiniMap, mapBytes: mapBytes,
      showAddress: showAddress,
      showCoordinates: showCoordinates,
      opacity: opacity,
      showBorder: showBorder,
      fontSize: fontSize,
    );
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

  // ─── POSISI HELPERS ──────────────────────────────────────────────
  /// Hitung Y posisi awal watermark bar.
  ///
  /// ✅ BENAR: logika posisi (TOP/BOTTOM) HANYA di sini.
  /// Layout TIDAK boleh melakukan `watermarkPosition == 'top'`
  /// langsung di dalam renderer mereka — panggil method ini saja.
  ///
  ///   final int y0 = WatermarkLayoutBase.resolveYStart(
  ///     watermarkPosition: watermarkPosition,
  ///     imageHeight: src.height,
  ///     contentHeight: barH,
  ///   );
  static int resolveYStart({
    required String watermarkPosition,
    required int imageHeight,
    required int contentHeight,
    int margin = 0,
  }) {
    switch (watermarkPosition) {
      case 'top':
      case 'topLeft':
      case 'topRight':
        return margin;
      case 'center':
        return (imageHeight - contentHeight) ~/ 2;
      case 'fullFrame':
        return 0;
      default: // 'bottom', 'bottomLeft', 'bottomRight', 'left', 'right'
        return imageHeight - contentHeight - margin;
    }
  }
  
  /// Hitung X posisi berdasarkan watermarkPosition
  static int resolveXStart({
    required String watermarkPosition,
    required int imageWidth,
    required int contentWidth,
    int margin = 0,
  }) {
    switch (watermarkPosition) {
      case 'topLeft':
      case 'bottomLeft':
      case 'left':
        return margin;
      case 'topRight':
      case 'bottomRight':
      case 'right':
        return imageWidth - contentWidth - margin;
      case 'center':
        return (imageWidth - contentWidth) ~/ 2;
      case 'fullFrame':
        return 0;
      default: // 'top', 'bottom'
        return margin;
    }
  }

  /// Apakah watermark berada di tepi atas gambar?
  /// Digunakan renderer untuk arah gradient (fade dari tepi image ke tengah).
  /// Ini adalah "position-aware rendering" — bukan perubahan jenis layout.
  static bool isAtTopEdge(int yStart, int imageHeight) {
    return yStart < imageHeight / 2;
  }
  
  /// Apakah watermark berada di tepi kiri gambar?
  static bool isAtLeftEdge(int xStart, int imageWidth) {
    return xStart < imageWidth / 2;
  }
  
  /// Dapatkan alignment berdasarkan watermarkPosition
  static Alignment getAlignment(String watermarkPosition) {
    switch (watermarkPosition) {
      case 'topLeft':
        return Alignment.topLeft;
      case 'top':
        return Alignment.topCenter;
      case 'topRight':
        return Alignment.topRight;
      case 'left':
        return Alignment.centerLeft;
      case 'center':
        return Alignment.center;
      case 'right':
        return Alignment.centerRight;
      case 'bottomLeft':
        return Alignment.bottomLeft;
      case 'bottom':
        return Alignment.bottomCenter;
      case 'bottomRight':
        return Alignment.bottomRight;
      default:
        return Alignment.bottomCenter;
    }
  }
}
