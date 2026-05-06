// ════════════════════════════════════════════════════════════════════════════
//  watermark/wm_helpers.dart
//  Fungsi-fungsi helper internal Watermark Engine V5
// ════════════════════════════════════════════════════════════════════════════

import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../core/constants.dart';

// ─── Teks ────────────────────────────────────────────────────────────────────

String wmTrunc(String s, int maxLen) {
  if (s.length <= maxLen) return s;
  return '${s.substring(0, maxLen - 3)}...';
}

List<String> wmWrapText(String text, int maxChars) {
  assert(maxChars > 0, 'maxChars harus > 0');
  final words   = text.split(' ');
  final lines   = <String>[];
  var   current = '';

  for (var word in words) {
    while (word.length > maxChars) {
      if (current.isNotEmpty) { lines.add(current.trim()); current = ''; }
      lines.add(word.substring(0, maxChars));
      word = word.substring(maxChars);
    }
    if (word.isEmpty) continue;
    final candidate = current.isEmpty ? word : '$current $word';
    if (candidate.length > maxChars) {
      lines.add(current.trim());
      current = '$word ';
    } else {
      current = '$candidate ';
    }
  }
  if (current.trim().isNotEmpty) lines.add(current.trim());
  return lines;
}

// ─── Gambar ──────────────────────────────────────────────────────────────────

void wmDrawTextShadow(
  img.Image image,
  String text, {
  required img.BitmapFont font,
  required int x,
  required int y,
  required img.Color color,
}) {
  img.drawString(image, text, font: font, x: x + 2, y: y + 2, color: kColorShadow);
  img.drawString(image, text, font: font, x: x,     y: y,     color: color);
}

img.Image? wmResizeSignature(img.Image? sig, int maxWidth, int maxHeight) {
  if (sig == null) return null;
  if (sig.width  > maxWidth)  sig = img.copyResize(sig, width:  maxWidth,  interpolation: img.Interpolation.linear);
  if (sig.height > maxHeight) sig = img.copyResize(sig, height: maxHeight, interpolation: img.Interpolation.linear);
  return sig;
}

img.Image? wmResizeLogo(img.Image? logo) {
  if (logo == null) return null;
  if (logo.width > kLogoMaxWidth) {
    logo = img.copyResize(logo, width: kLogoMaxWidth, interpolation: img.Interpolation.linear);
  }
  return logo;
}

bool wmImageHasAlpha(img.Image image) => image.numChannels == 4;

Uint8List wmExport(img.Image image, {bool hasAlpha = false}) {
  if (hasAlpha) return Uint8List.fromList(img.encodePng(image));
  return Uint8List.fromList(
    img.encodeJpg(image, quality: kJpegQuality, chroma: img.JpegChroma.yuv420),
  );
}
