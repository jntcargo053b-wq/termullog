// lib/watermark/layouts/layout_cinematic_v2.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'watermark_layout_base.dart';

class LayoutCinematicV2 extends WatermarkLayoutBase {
  @override
  String get name => 'Cinematic V2';

  static const int gradH = 180;
  static const int padX = 36;
  static const int lineH = 28;
  static const int maxAddressLen = 55;
  static bool _fontLoaded = false;

  static Future<void> loadFont() async {
    if (_fontLoaded) return;
    final fontLoader = FontLoader('Roboto')
      ..addFont(await rootBundle.load('fonts/Roboto-Regular.ttf'))
      ..addFont(await rootBundle.load('fonts/Roboto-Bold.ttf'));
    await fontLoader.load();
    _fontLoaded = true;
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
    required String watermarkPosition,
    required bool showMiniMap,
    Uint8List? mapBytes,
  }) {
    // Fallback sync dengan img.arial24
    final bool isTop = watermarkPosition == 'top';
    final int gradY0 = isTop ? 0 : src.height - gradH;
    _applyGradient(src, gradY0, isTop);

    final int divY = isTop ? gradH - 40 : gradY0 + 36;
    img.fillRect(src, x1: padX, y1: divY, x2: src.width - padX, y2: divY + 2,
        color: img.ColorRgba8(30, 144, 255, 200));

    final font = img.arial24;
    int cy = isTop ? 16 : gradY0 + 12;
    img.drawString(src, DateFormat('HH : mm : ss').format(timestamp), font: font, x: padX, y: cy, color: white);
    cy += lineH;
    img.drawString(src, DateFormat('dd  MMMM  yyyy').format(timestamp), font: font, x: padX, y: cy, color: blue);
    cy += lineH + 8;

    if (hasPosition) {
      img.drawString(src, '${lat!.toStringAsFixed(5)}°N   ${lon!.toStringAsFixed(5)}°E',
          font: font, x: padX, y: cy, color: offWhite);
      cy += lineH;
      if (showAccuracy) {
        img.drawString(src, 'ACCURACY  ±${acc?.toStringAsFixed(0) ?? '?'} M',
            font: font, x: padX, y: cy, color: grey);
      }
    }
    return WatermarkLayoutBase.encodeJpg(src);
  }

  @override
  Future<Uint8List> applyAsync({
    required img.Image srcImg,
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
    await loadFont();

    final pngBytes = Uint8List.fromList(img.encodePng(srcImg));
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    final uiImage = frame.image;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, uiImage.width.toDouble(), uiImage.height.toDouble()));
    canvas.drawImage(uiImage, Offset.zero, Paint());

    final bool isTop = watermarkPosition == 'top';
    final int gradY0 = isTop ? 0 : srcImg.height - gradH;

    // Gradient overlay
    final gradientPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, gradY0.toDouble()),
        Offset(0, (gradY0 + gradH).toDouble()),
        [const Color(0xCC000000), const Color(0x00000000)],
        isTop ? [0.0, 1.0] : [1.0, 0.0],
      );
    canvas.drawRect(Rect.fromLTWH(0, gradY0.toDouble(), uiImage.width.toDouble(), gradH.toDouble()), gradientPaint);

    // Divider
    final int divY = isTop ? gradH - 40 : gradY0 + 36;
    canvas.drawLine(
      Offset(padX.toDouble(), divY.toDouble()),
      Offset((uiImage.width - padX).toDouble(), divY.toDouble()),
      Paint()..color = const Color(0xFF1E90FF)..strokeWidth = 2,
    );

    double cy = isTop ? 16.0 : (gradY0 + 12).toDouble();

    _drawText(canvas, DateFormat('HH : mm : ss').format(timestamp),
        x: padX.toDouble(), y: cy, color: Colors.white, bold: true, size: 18);
    cy += lineH;
    _drawText(canvas, DateFormat('dd  MMMM  yyyy').format(timestamp),
        x: padX.toDouble(), y: cy, color: const Color(0xFF1E90FF), bold: false, size: 16);
    cy += lineH + 8;

    if (hasPosition) {
      _drawText(canvas, '${lat!.toStringAsFixed(5)}°N   ${lon!.toStringAsFixed(5)}°E',
          x: padX.toDouble(), y: cy, color: const Color(0xFFDCE1EB), bold: false, size: 14);
      cy += lineH;
      if (showAccuracy) {
        _drawText(canvas, 'ACCURACY  ±${acc?.toStringAsFixed(0) ?? '?'} M',
            x: padX.toDouble(), y: cy, color: Colors.grey, bold: false, size: 12);
      }
    }

    final picture = recorder.endRecording();
    final newUiImage = await picture.toImage(uiImage.width, uiImage.height);
    final byteData = await newUiImage.toByteData(format: ui.ImageByteFormat.png);
    final pngResult = byteData!.buffer.asUint8List();
    final resultImg = img.decodePng(pngResult)!;
    return WatermarkLayoutBase.encodeJpg(resultImg);
  }

  void _drawText(Canvas canvas, String text, {required double x, required double y, required Color color, bool bold = false, double size = 14}) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontFamily: 'Roboto',
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(x, y));
  }

  void _applyGradient(img.Image src, int gradY0, bool isTop) {
    for (int y = gradY0; y < gradY0 + gradH; y++) {
      if (y < 0 || y >= src.height) continue;
      final t = isTop ? 1.0 - (y - gradY0) / gradH : (y - gradY0) / gradH;
      final alpha = (t * 220).toInt().clamp(0, 220);
      for (int x = 0; x < src.width; x++) {
        final px = src.getPixel(x, y);
        src.setPixel(x, y, img.ColorRgba8(
          ((px.r * (255 - alpha)) ~/ 255),
          ((px.g * (255 - alpha)) ~/ 255),
          ((px.b * (255 - alpha)) ~/ 255), 255));
      }
    }
  }
}
