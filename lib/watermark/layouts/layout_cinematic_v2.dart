// lib/watermark/layouts/layout_cinematic_v2.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'watermark_layout_base.dart';

class LayoutCinematicV2 extends WatermarkLayoutBase {
  @override
  String get name => 'Cinematic V2';

  static const int gradH = 180;
  static const int padX = 36;
  static const int lineH = 28;

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
    final int gradY0 = isTop ? 0 : src.height - gradH;
    _applyGradientImg(src, gradY0, isTop);

    final int divY = isTop ? gradH - 40 : gradY0 + 36;
    img.fillRect(src, x1: padX, y1: divY, x2: src.width - padX, y2: divY + 2,
        color: WatermarkLayoutBase.imgBlue);

    final font = img.arial24;
    int cy = isTop ? 16 : gradY0 + 12;
    img.drawString(src, DateFormat('HH:mm:ss').format(timestamp), font: font, x: padX, y: cy, color: WatermarkLayoutBase.imgWhite);
    cy += lineH;
    img.drawString(src, DateFormat('dd MMMM yyyy').format(timestamp), font: font, x: padX, y: cy, color: WatermarkLayoutBase.imgBlue);
    cy += lineH + 8;

    if (hasPosition) {
      img.drawString(src, '${lat!.toStringAsFixed(5)}°N  ${lon!.toStringAsFixed(5)}°E',
          font: font, x: padX, y: cy, color: WatermarkLayoutBase.imgOffWhite);
      cy += lineH;
      if (showAccuracy) {
        img.drawString(src, '±${acc?.toStringAsFixed(0) ?? '?'}m',
            font: font, x: padX, y: cy, color: WatermarkLayoutBase.imgGrey);
      }
    }
    return WatermarkLayoutBase.encodeJpg(src);
  }

  @override
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
    await WatermarkLayoutBase.loadFont();

    final uiImage = await WatermarkLayoutBase.toUiImage(src);
    final w = uiImage.width.toDouble();
    final h = uiImage.height.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
    canvas.drawImage(uiImage, Offset.zero, Paint());

    final bool isTop = watermarkPosition == 'top';
    final double gradY0 = isTop ? 0.0 : h - gradH;

    WatermarkLayoutBase.canvasDrawGradient(
      canvas, x: 0, y: gradY0, width: w, height: gradH.toDouble(),
      color: Colors.black, startOpacity: 0.85, endOpacity: 0.0, topToBottom: isTop,
    );

    final double divY = isTop ? gradH - 40 : gradY0 + 36;
    canvas.drawLine(Offset(padX.toDouble(), divY), Offset(w - padX, divY),
        Paint()..color = WatermarkLayoutBase.uiBlue..strokeWidth = 2);

    double cy = isTop ? 16.0 : gradY0 + 12;

    WatermarkLayoutBase.canvasDrawTextShadow(canvas, DateFormat('HH : mm : ss').format(timestamp),
        x: padX.toDouble(), y: cy, color: WatermarkLayoutBase.uiWhite, bold: true, size: 18);
    cy += lineH;
    WatermarkLayoutBase.canvasDrawText(canvas, DateFormat('dd  MMMM  yyyy').format(timestamp),
        x: padX.toDouble(), y: cy, color: WatermarkLayoutBase.uiBlue, bold: false, size: 15);
    cy += lineH + 8;

    if (hasPosition) {
      WatermarkLayoutBase.canvasDrawText(canvas, '${lat!.toStringAsFixed(5)}°N   ${lon!.toStringAsFixed(5)}°E',
          x: padX.toDouble(), y: cy, color: WatermarkLayoutBase.uiOffWhite, bold: false, size: 13);
      cy += lineH;
      if (showAccuracy) {
        WatermarkLayoutBase.canvasDrawText(canvas, 'ACCURACY  ±${acc?.toStringAsFixed(0) ?? '?'} M',
            x: padX.toDouble(), y: cy, color: WatermarkLayoutBase.uiGrey, bold: false, size: 12);
      }
    }

    final resultImg = await WatermarkLayoutBase.recorderToImg(recorder, uiImage.width, uiImage.height);
    return WatermarkLayoutBase.encodeJpg(resultImg);
  }

  void _applyGradientImg(img.Image src, int gradY0, bool isTop) {
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
