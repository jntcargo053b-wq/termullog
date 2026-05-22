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
  // WARNA STANDAR (img package)
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
  // LOAD FONT (aman + debug)
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
  // METODE UTAMA (wajib diimplementasikan)
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

  // Versi async (opsional)
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
  // SMART TEXT RENDERING
  // ==========================================================================
  static void drawSmartText(
    img.Image dst,
    String text,
    int x,
    int y, {
    required int maxWidth,
    required img.BitmapFont baseFont,
    required img.Color color,
    bool withShadow = true,
    bool autoEllipsis = true,
    bool autoWrap = false,
    bool adaptiveFont = false,
    int maxLines = 3,
    int lineHeight = 24,
  }) {
    if (text.isEmpty) return;

    img.BitmapFont finalFont = baseFont;
    if (adaptiveFont) {
      finalFont = _getAdaptiveFont(baseFont, text, maxWidth);
    }

    if (!autoWrap && autoEllipsis && _getTextWidth(finalFont, text) > maxWidth) {
      final displayText = _ellipsisText(finalFont, text, maxWidth);
      _drawSingleLine(dst, displayText, finalFont, x, y, color, withShadow);
      return;
    }

    if (autoWrap) {
      final lines = _wrapTextByWidth(finalFont, text, maxWidth, maxLines);
      int currentY = y;
      for (int i = 0; i < lines.length && i < maxLines; i++) {
        _drawSingleLine(dst, lines[i], finalFont, x, currentY, color, withShadow);
        currentY += lineHeight;
      }
      return;
    }

    _drawSingleLine(dst, text, finalFont, x, y, color, withShadow);
  }

  static void _drawSingleLine(img.Image dst, String text, img.BitmapFont font, int x, int y, img.Color color, bool withShadow) {
    if (withShadow) {
      img.drawString(dst, text, font: font, x: x + 1, y: y + 1,
          color: img.ColorRgba8(0, 0, 0, 160));
    }
    img.drawString(dst, text, font: font, x: x, y: y, color: color);
  }

  static img.BitmapFont _getAdaptiveFont(img.BitmapFont base, String text, int maxWidth) {
    if (_getTextWidth(base, text) <= maxWidth) return base;
    if (_getTextWidth(img.arial14, text) <= maxWidth) return img.arial14;
    if (_getTextWidth(img.arial12, text) <= maxWidth) return img.arial12;
    return img.arial12;
  }

  static String _ellipsisText(img.BitmapFont font, String text, int maxWidth) {
    if (_getTextWidth(font, text) <= maxWidth) return text;
    for (int i = text.length - 1; i > 3; i--) {
      final truncated = '${text.substring(0, i)}…';
      if (_getTextWidth(font, truncated) <= maxWidth) return truncated;
    }
    return '…';
  }

  static List<String> _wrapTextByWidth(img.BitmapFont font, String text, int maxWidth, int maxLines) {
    final words = text.split(' ');
    final lines = <String>[];
    String currentLine = '';
    for (final word in words) {
      final testLine = currentLine.isEmpty ? word : '$currentLine $word';
      if (_getTextWidth(font, testLine) > maxWidth) {
        if (currentLine.isNotEmpty) {
          lines.add(currentLine);
          currentLine = word;
          if (lines.length >= maxLines) break;
        } else {
          final trimmed = _ellipsisText(font, word, maxWidth);
          lines.add(trimmed);
          currentLine = '';
          if (lines.length >= maxLines) break;
        }
      } else {
        currentLine = testLine;
      }
    }
    if (currentLine.isNotEmpty && lines.length < maxLines) lines.add(currentLine);
    return lines;
  }

  static int _getTextWidth(img.BitmapFont font, String text) {
    // Approximate width: average character width based on font size
    final int approxCharWidth = font == img.arial24 ? 12 : font == img.arial14 ? 8 : 6;
    return text.length * approxCharWidth;
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
    // Extra for notch / dynamic island (simple heuristic)
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

  static Rect getSafeLayoutRect(img.Image src, {
    double widthFactor = 0.9,
    double heightFactor = 0.85,
    Alignment alignment = Alignment.bottomLeft,
  }) {
    final padding = getSafePadding(src);
    final usableWidth = src.width - padding.left - padding.right;
    final usableHeight = src.height - padding.top - padding.bottom;
    final rectWidth = (usableWidth * widthFactor).toInt();
    final rectHeight = (usableHeight * heightFactor).toInt();
    int x, y;
    switch (alignment) {
      case Alignment.bottomLeft:
        x = padding.left.toInt();
        y = src.height - padding.bottom.toInt() - rectHeight;
        break;
      case Alignment.bottomRight:
        x = src.width - padding.right.toInt() - rectWidth;
        y = src.height - padding.bottom.toInt() - rectHeight;
        break;
      case Alignment.topLeft:
        x = padding.left.toInt();
        y = padding.top.toInt();
        break;
      case Alignment.topRight:
        x = src.width - padding.right.toInt() - rectWidth;
        y = padding.top.toInt();
        break;
      default:
        x = padding.left.toInt();
        y = src.height - padding.bottom.toInt() - rectHeight;
    }
    return Rect.fromLTWH(x.toDouble(), y.toDouble(), rectWidth.toDouble(), rectHeight.toDouble());
  }

  // ==========================================================================
  // HELPER DASAR
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

  static void drawLabelValue(
    img.Image dst,
    String label,
    String value,
    int x,
    int y,
    int colW,
    int rowH,
    img.BitmapFont font, {
    required img.Color labelColor,
    required img.Color valueColor,
  }) {
    img.drawString(dst, label, font: font, x: x, y: y + (rowH ~/ 2 - 8),
        color: labelColor);
    img.drawString(dst, value, font: font, x: x + colW, y: y + (rowH ~/ 2 - 8),
        color: valueColor);
  }

  static String formatDate(DateTime dt, {String pattern = 'dd MMM yyyy'}) {
    return DateFormat(pattern).format(dt);
  }
  static String formatTime(DateTime dt, {String pattern = 'HH:mm:ss'}) {
    return DateFormat(pattern).format(dt);
  }
  static Color adaptiveTextColor(bool darkBackground) => darkBackground ? Colors.white : Colors.black;

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
