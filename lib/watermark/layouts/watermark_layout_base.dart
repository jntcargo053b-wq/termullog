// lib/watermark/layouts/watermark_layout_base.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

abstract class WatermarkLayoutBase {
  String get name;

  // ==========================================================================
  // WARNA STANDAR
  // ==========================================================================
  static final img.Color white    = img.ColorRgba8(255, 255, 255, 255);
  static final img.Color offWhite = img.ColorRgba8(230, 230, 230, 255);
  static final img.Color blue     = img.ColorRgba8(30, 144, 255, 255);
  static final img.Color grey     = img.ColorRgba8(150, 150, 150, 255);

  static final img.Color imgWhite    = white;
  static final img.Color imgOffWhite = offWhite;
  static final img.Color imgBlue     = blue;
  static final img.Color imgGrey     = grey;

  static const Color uiWhite    = Color(0xFFFFFFFF);
  static const Color uiBlue     = Color(0xFF1E90FF);
  static const Color uiGrey     = Color(0xFF969696);
  static const Color uiOffWhite = Color(0xFFE6E6E6);

  // ==========================================================================
  // LOAD FONT (opsional untuk canvas)
  // ==========================================================================
  static bool _fontLoaded = false;
  static Future<void> loadFont() async {
    if (_fontLoaded) return;
    try {
      final fontLoader = FontLoader('Roboto')
        ..addFont(rootBundle.load('fonts/Roboto-Regular.ttf'))
        ..addFont(rootBundle.load('fonts/Roboto-Bold.ttf'));
      await fontLoader.load();
      _fontLoaded = true;
    } catch (e) {
      debugPrint('⚠️ Font load failed: $e');
      _fontLoaded = true;
    }
  }

  // ==========================================================================
  // METODE UTAMA
  // ==========================================================================
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
      showMiniMap: showMiniMap,
      mapBytes: mapBytes,
      showAddress: showAddress,
      showCoordinates: showCoordinates,
      opacity: opacity,
      showBorder: showBorder,
      fontSize: fontSize,
    );
  }

  // ==========================================================================
  // ADAPTIVE LAYOUT ENGINE
  // ==========================================================================
  static bool isPortrait(img.Image src) => src.height > src.width;

  static double getAdaptiveScale(img.Image src, {double baseWidth = 1080}) {
    return (src.width / baseWidth).clamp(0.6, 1.8);
  }

  static EdgeInsets getSafePadding(img.Image src, {double minPadding = 12}) {
    final bool isPortrait = src.height > src.width;
    final double scale = getAdaptiveScale(src);
    final double basePadding = minPadding * scale;
    final double horizontal = isPortrait ? basePadding : basePadding * 0.8;
    final double vertical = basePadding;
    final double notchExtra = (src.width / src.height > 2.0) ? 20.0 : 0.0;
    return EdgeInsets.fromLTRB(
      horizontal + notchExtra,
      vertical,
      horizontal + notchExtra,
      vertical,
    );
  }

  static int getAdaptiveLineHeight(String fontSize, double scale, {bool tight = false}) {
    final double fsMultiplier = fontSize == 'small' ? 0.75 : fontSize == 'large' ? 1.4 : 1.0;
    final int base = tight ? 22 : 28;
    return (base * scale * fsMultiplier).round();
  }

  static int getLineHeight(String fontSize, double scale, {bool small = false}) {
    return getAdaptiveLineHeight(fontSize, scale, tight: small);
  }

  static int getAdaptiveSpacing(double scale, {int base = 8}) {
    return (base * scale).round();
  }

  static int clampY(int y, int elementHeight, img.Image src, {int bottomMargin = 20}) {
    final maxY = src.height - elementHeight - bottomMargin;
    return y.clamp(0, maxY);
  }

  static int clampX(int x, int elementWidth, img.Image src, {int horizontalMargin = 20}) {
    final maxX = src.width - elementWidth - horizontalMargin;
    return x.clamp(horizontalMargin, maxX);
  }

  // ==========================================================================
  // HELPER DASAR (tanpa smart text yang bermasalah)
  // ==========================================================================
  static String wrapText(String text, int maxChars) {
    final words = text.split(' ');
    String result = '';
    String line = '';
    for (final word in words) {
      if ((line + word).length > maxChars) {
        result += '$line\n';
        line = '$word ';
      } else {
        line += '$word ';
      }
    }
    result += line;
    return result.trim();
  }

  static int safeMaxChars(int panelWidth, int fontSizePx) {
    final int charWidth = (fontSizePx * 0.6).toInt();
    if (charWidth <= 0) return 30;
    return ((panelWidth - 20) / charWidth).toInt().clamp(20, 60);
  }

  static int clampWidth(int value, img.Image src) {
    return value.clamp(100, src.width - 40);
  }

  static void drawTextWithShadow(
    img.Image dst,
    String text,
    int x,
    int y, {
    required img.BitmapFont font,
    required img.Color color,
    bool withShadow = true,
  }) {
    if (withShadow) {
      img.drawString(dst, text, font: font, x: x + 1, y: y + 1,
          color: img.ColorRgba8(0, 0, 0, 120));
    }
    img.drawString(dst, text, font: font, x: x, y: y, color: color);
  }

  static String formatDate(DateTime dt, {String pattern = 'dd MMM yyyy'}) {
    return DateFormat(pattern).format(dt);
  }

  static String formatTime(DateTime dt, {String pattern = 'HH:mm:ss'}) {
    return DateFormat(pattern).format(dt);
  }

  // ==========================================================================
  // FLUTTER CANVAS HELPERS
  // ==========================================================================
  static void canvasDrawText(
    Canvas canvas,
    String text, {
    required double x,
    required double y,
    Color color = uiWhite,
    bool bold = false,
    double size = 14,
    double letterSpacing = 1.0,
  }) {
    final tp = TextPainter(
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
      textDirection: ui.TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x, y));
  }

  static void canvasDrawTextShadow(
    Canvas canvas,
    String text, {
    required double x,
    required double y,
    Color color = uiWhite,
    bool bold = false,
    double size = 14,
    Color shadowColor = Colors.black54,
  }) {
    canvasDrawText(canvas, text,
        x: x + 1, y: y + 1, color: shadowColor, bold: bold, size: size);
    canvasDrawText(canvas, text,
        x: x, y: y, color: color, bold: bold, size: size);
  }

  static void canvasDrawGradient(
    Canvas canvas, {
    required double x,
    required double y,
    required double width,
    required double height,
    Color color = Colors.black,
    double startOpacity = 0.8,
    double endOpacity = 0.0,
    bool topToBottom = true,
  }) {
    final colors = [
      color.withOpacity(startOpacity),
      color.withOpacity(startOpacity * 0.5),
      color.withOpacity(endOpacity),
    ];
    final startOffset = Offset(x, topToBottom ? y : y + height);
    final endOffset = Offset(x, topToBottom ? y + height : y);
    canvas.drawRect(
      Rect.fromLTWH(x, y, width, height),
      Paint()..shader = ui.Gradient.linear(startOffset, endOffset, colors),
    );
  }

  // ==========================================================================
  // KONVERSI GAMBAR
  // ==========================================================================
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

  static img.Image decodeOrThrow(Uint8List bytes) {
    if (bytes.isEmpty) throw Exception('Data gambar kosong');
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Format gambar tidak didukung');
    return decoded;
  }

  static Uint8List encodeJpg(img.Image src, {int quality = 90}) {
    return Uint8List.fromList(img.encodeJpg(src, quality: quality));
  }
}
