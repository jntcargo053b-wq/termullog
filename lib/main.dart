// ════════════════════════════════════════════════════════════════════════════
//  TermulLog — main.dart (WATERMARK ENGINE V5 + MINI MAP)
// ════════════════════════════════════════════════════════════════════════════
//
//  Watermark Engine Fixes (V4 → V5):
//  ✔ [FIX] _clamp manual diganti .clamp() bawaan Dart
//  ✔ [FIX] _wrapText menangani kata lebih panjang dari maxChars (anti infinite-loop)
//  ✔ [FIX] Layout2 boxH proporsional (bukan hardcode 230)
//  ✔ [FIX] Layout2 yy relatif terhadap boxY (bukan hardcode 35)
//  ✔ [FIX] Logo ditampilkan di Layout2 & Layout3
//  ✔ [FIX] Field 'id' konsisten tampil di semua layout
//  ✔ [FIX] Semua layout pakai _wrapText untuk address
//  ✔ [FIX] Magic numbers diganti konstanta bernama
//  ✔ [FIX] Export PNG jika input PNG (alpha channel terjaga)
//  ✔ [FIX] _processWatermark diperbaiki — tidak lagi orphan function fragment
//  ✔ [FIX] Konflik konstanta kMaxOutputWidth & kJpegQuality diselesaikan
//         (engine pakai nilai lebih tinggi: 1080→1600, quality 78→90)
//
//  Mini Map Update:
//  ✔ [NEW] Realtime GPS mini map overlay di CameraPage
//  ✔ [NEW] Tap mini map untuk toggle ukuran kecil ↔ besar
//  ✔ [NEW] Indikator akurasi GPS (hijau < 30m, kuning ≥ 30m)
//  ✔ [NEW] Loading state saat GPS belum tersedia
//  ✔ [NEW] Tombol refresh GPS manual
//
//  Dependency tambahan di pubspec.yaml:
//    flutter_map: ^7.0.2
//    latlong2: ^0.9.1
//
// ════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// ─── Global cameras list ─────────────────────────────────────────────────────
List<CameraDescription> _cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _cameras = await availableCameras();
  } catch (e) {
    debugPrint('Camera initialization failed: $e');
  }
  await WatermarkLayout.load();
  runApp(const App());
}

// ════════════════════════════════════════════════════════════════════════════
//  CONSTANTS
// ════════════════════════════════════════════════════════════════════════════

const int kMaxOutputWidth = 1600;
const int kJpegQuality    = 90;
const int kSigMaxWidth    = 260;
const int kLogoMaxWidth   = 90;

const int kPanelPaddingX  = 25;
const int kSidebarPadX    = 18;
const int kAccentBarWidth = 10;
const int kCornerMargin   = 20;
const int kTextLineSmall  = 18;
const int kTextLineLarge  = 28;
const int kSectionGap     = 12;

final img.Color kColorWhite     = img.ColorRgb8(255, 255, 255);
final img.Color kColorCyan      = img.ColorRgb8(0, 184, 148);
final img.Color kColorGrey      = img.ColorRgb8(210, 210, 210);
final img.Color kColorDarkBg    = img.ColorRgba8(15, 23, 42, 230);
final img.Color kColorDarkBgMed = img.ColorRgba8(15, 23, 42, 210);
final img.Color kColorBlackCard = img.ColorRgba8(0, 0, 0, 170);
final img.Color kColorGlassBg   = img.ColorRgba8(0, 0, 0, 120);
final img.Color kColorShadow    = img.ColorRgb8(0, 0, 0);

// ════════════════════════════════════════════════════════════════════════════
//  LAYOUT REGISTRY
// ════════════════════════════════════════════════════════════════════════════

class LayoutInfo {
  final String id, label, description;
  final IconData icon;
  final Color accentColor;
  const LayoutInfo({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.accentColor,
  });
}

const List<LayoutInfo> kLayouts = [
  LayoutInfo(
    id: 'layout1',
    label: 'Professional Report',
    description: 'Overlay navy transparan di bawah foto. Info lengkap: teknisi, ID, waktu, lokasi, cuaca + TTD.',
    icon: Icons.article_outlined,
    accentColor: Color(0xFF1B4F72),
  ),
  LayoutInfo(
    id: 'layout2',
    label: 'Compact Field',
    description: 'Card pojok kanan atas. Info ringkas: nama, ID, waktu, lokasi. Cocok laporan cepat.',
    icon: Icons.assignment_turned_in_outlined,
    accentColor: Color(0xFF00897B),
  ),
  LayoutInfo(
    id: 'layout3',
    label: 'Dark Minimal',
    description: 'Overlay gelap transparan + aksen cyan. Teks putih & cyan. Kesan premium modern.',
    icon: Icons.dark_mode_outlined,
    accentColor: Color(0xFF00B894),
  ),
  LayoutInfo(
    id: 'layout4',
    label: 'Vertical Sidebar',
    description: 'Sidebar kiri dengan logo, teknisi, ID, waktu, lokasi & TTD. Ideal untuk foto portrait.',
    icon: Icons.layers_outlined,
    accentColor: Color(0xFF7B1FA2),
  ),
];

// ════════════════════════════════════════════════════════════════════════════
//  WATERMARK ENGINE V5 — HELPERS
// ════════════════════════════════════════════════════════════════════════════

String _trunc(String s, int maxLen) {
  if (s.length <= maxLen) return s;
  return '${s.substring(0, maxLen - 3)}...';
}

List<String> _wrapText(String text, int maxChars) {
  assert(maxChars > 0, 'maxChars harus lebih dari 0');
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

void _drawTextShadow(
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

img.Image? _resizeSignature(img.Image? sig, int maxWidth, int maxHeight) {
  if (sig == null) return null;
  if (sig.width  > maxWidth)  sig = img.copyResize(sig, width:  maxWidth,  interpolation: img.Interpolation.linear);
  if (sig.height > maxHeight) sig = img.copyResize(sig, height: maxHeight, interpolation: img.Interpolation.linear);
  return sig;
}

img.Image? _resizeLogo(img.Image? logo) {
  if (logo == null) return null;
  if (logo.width > kLogoMaxWidth) {
    logo = img.copyResize(logo, width: kLogoMaxWidth, interpolation: img.Interpolation.linear);
  }
  return logo;
}

Uint8List _export(img.Image image, {bool hasAlpha = false}) {
  if (hasAlpha) return Uint8List.fromList(img.encodePng(image));
  return Uint8List.fromList(
    img.encodeJpg(image, quality: kJpegQuality, chroma: img.JpegChroma.yuv420),
  );
}

bool _imageHasAlpha(img.Image image) => image.numChannels == 4;

// ════════════════════════════════════════════════════════════════════════════
//  WATERMARK ENGINE V5 — ENTRY POINT
// ════════════════════════════════════════════════════════════════════════════

Uint8List _processWatermark(Map<String, dynamic> p) {
  try {
    final imageBytes = p['imageBytes'] as Uint8List?;
    if (imageBytes == null || imageBytes.isEmpty) {
      throw Exception('Image bytes are empty or null');
    }

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) throw Exception('Unsupported image format');

    img.Image image = decoded;
    final hasAlpha  = _imageHasAlpha(image);

    if (image.width > kMaxOutputWidth) {
      image = img.copyResize(
        image, width: kMaxOutputWidth, interpolation: img.Interpolation.linear,
      );
    }

    img.Image? sig;
    final sigBytes = p['sigBytes'] as Uint8List?;
    if (sigBytes != null && sigBytes.isNotEmpty) {
      try { sig = img.decodeImage(sigBytes); } catch (e) { sig = null; }
    }

    img.Image? logo;
    final logoBytes = p['logoBytes'] as Uint8List?;
    if (logoBytes != null && logoBytes.isNotEmpty) {
      try {
        logo = img.decodeImage(logoBytes);
        if (logo != null && (logo.width <= 0 || logo.height <= 0)) logo = null;
      } catch (e) { logo = null; }
    }
    logo = _resizeLogo(logo);

    final layout     = p['layout']  as String? ?? 'layout1';
    final name       = p['name']    as String? ?? '-';
    final id         = p['id']      as String? ?? '-';
    final date       = p['date']    as String? ?? '-';
    final time       = p['time']    as String? ?? '-';
    final address    = p['address'] as String? ?? '';
    final weather    = p['weather'] as String? ?? '';
    final isPortrait = image.height > image.width;

    Uint8List draw(String l) {
      switch (l) {
        case 'layout2': return _drawLayout2(image, sig, logo, name, id, date, time, address, weather, hasAlpha: hasAlpha);
        case 'layout3': return _drawLayout3(image, sig, logo, name, id, date, time, address, weather, hasAlpha: hasAlpha);
        case 'layout4': return _drawLayout4(image, sig, logo, name, id, date, time, address, weather, hasAlpha: hasAlpha);
        default:        return _drawLayout1(image, sig, logo, name, id, date, time, address, weather, hasAlpha: hasAlpha);
      }
    }

    if (layout == 'auto') return draw(isPortrait ? 'layout4' : 'layout1');
    return draw(layout);
  } catch (e, stackTrace) {
    debugPrint('Watermark processing error: $e\n$stackTrace');
    final originalBytes = p['imageBytes'] as Uint8List?;
    if (originalBytes != null) return originalBytes;
    throw Exception('Failed to process watermark: $e');
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  LAYOUT 1 — PROFESSIONAL BOTTOM BANNER
// ════════════════════════════════════════════════════════════════════════════

Uint8List _drawLayout1(
  img.Image base, img.Image? sig, img.Image? logo,
  String name, String id, String date, String time,
  String address, String weather, {bool hasAlpha = false}
) {
  final W = base.width;
  final H = base.height;

  final bannerH     = (H * 0.23).toInt().clamp(180, 380);
  final isSmall     = W < 700;
  final addrMaxChar = isSmall ? 38 : 65;

  sig = _resizeSignature(sig, kSigMaxWidth, (bannerH * 0.45).toInt());

  img.fillRect(base, x1: 0, y1: H - bannerH, x2: W - 1, y2: H - 1, color: kColorDarkBg);
  img.fillRect(base, x1: 0, y1: H - bannerH, x2: kAccentBarWidth, y2: H - 1, color: kColorCyan);

  final titleFont = isSmall ? img.arial14 : img.arial24;
  int yy          = H - bannerH + kTextLineSmall;

  _drawTextShadow(base, 'LAPORAN TEKNIS',               font: titleFont,   x: kPanelPaddingX, y: yy, color: kColorCyan);
  yy += isSmall ? kTextLineSmall : kTextLineLarge + kSectionGap;

  _drawTextShadow(base, 'Teknisi : ${_trunc(name, 30)}', font: img.arial14, x: kPanelPaddingX, y: yy, color: kColorWhite);
  yy += kTextLineSmall + 4;

  _drawTextShadow(base, 'ID       : $id',               font: img.arial14, x: kPanelPaddingX, y: yy, color: kColorWhite);
  yy += kTextLineSmall + 4;

  _drawTextShadow(base, '$date   |   $time',            font: img.arial14, x: kPanelPaddingX, y: yy, color: kColorWhite);
  yy += kTextLineSmall + kSectionGap;

  for (final line in _wrapText(address, addrMaxChar).take(2)) {
    _drawTextShadow(base, line, font: img.arial14, x: kPanelPaddingX, y: yy, color: kColorWhite);
    yy += kTextLineSmall;
  }

  if (weather.isNotEmpty) {
    yy += 4;
    _drawTextShadow(base, weather, font: img.arial14, x: kPanelPaddingX, y: yy, color: kColorCyan);
  }

  if (logo != null) {
    img.compositeImage(base, logo,
      dstX: (W - logo.width - kPanelPaddingX).clamp(0, W - logo.width),
      dstY: (H - bannerH + kTextLineSmall).clamp(0, H - logo.height),
    );
  }

  if (sig != null) {
    img.compositeImage(base, sig,
      dstX: (W - sig.width - kPanelPaddingX).clamp(0, W - sig.width),
      dstY: (H - sig.height - kTextLineSmall).clamp(0, H - sig.height),
    );
  }

  return _export(base, hasAlpha: hasAlpha);
}

// ════════════════════════════════════════════════════════════════════════════
//  LAYOUT 2 — COMPACT CORNER CARD
// ════════════════════════════════════════════════════════════════════════════

Uint8List _drawLayout2(
  img.Image base, img.Image? sig, img.Image? logo,
  String name, String id, String date, String time,
  String address, String weather, {bool hasAlpha = false}
) {
  final W = base.width;
  final H = base.height;

  final boxW = (W * 0.42).toInt().clamp(300, 500);
  final boxH = (H * 0.32).toInt().clamp(200, 280);
  final boxX = W - boxW - kCornerMargin;
  const boxY = kCornerMargin;

  sig = _resizeSignature(sig, (boxW * 0.65).toInt(), 80);

  img.fillRect(base, x1: boxX, y1: boxY, x2: W - kCornerMargin, y2: boxY + boxH, color: kColorBlackCard);
  img.drawRect(base, x1: boxX, y1: boxY, x2: W - kCornerMargin, y2: boxY + boxH, color: kColorCyan);

  final textX = boxX + kTextLineSmall;
  int   yy    = boxY + 15;

  _drawTextShadow(base, _trunc(name, 28),   font: img.arial14, x: textX, y: yy, color: kColorWhite);
  yy += kTextLineLarge;
  _drawTextShadow(base, 'ID: $id',          font: img.arial14, x: textX, y: yy, color: kColorGrey);
  yy += kTextLineLarge;
  _drawTextShadow(base, '$date  $time',     font: img.arial14, x: textX, y: yy, color: kColorGrey);
  yy += kTextLineLarge;

  for (final line in _wrapText(address, 30).take(2)) {
    _drawTextShadow(base, line, font: img.arial14, x: textX, y: yy, color: kColorCyan);
    yy += kTextLineSmall;
  }

  if (weather.isNotEmpty) {
    yy += kSectionGap ~/ 2;
    _drawTextShadow(base, weather, font: img.arial14, x: textX, y: yy, color: kColorWhite);
  }

  if (logo != null) {
    img.compositeImage(base, logo,
      dstX: (boxX + kTextLineSmall).clamp(0, W - logo.width),
      dstY: (boxY + boxH - logo.height - 12).clamp(0, H - logo.height),
    );
  }

  if (sig != null) {
    img.compositeImage(base, sig,
      dstX: (W - sig.width - 35).clamp(0, W - sig.width),
      dstY: (boxY + boxH - sig.height - 12).clamp(0, H - sig.height),
    );
  }

  return _export(base, hasAlpha: hasAlpha);
}

// ════════════════════════════════════════════════════════════════════════════
//  LAYOUT 3 — GLASS HUD
// ════════════════════════════════════════════════════════════════════════════

Uint8List _drawLayout3(
  img.Image base, img.Image? sig, img.Image? logo,
  String name, String id, String date, String time,
  String address, String weather, {bool hasAlpha = false}
) {
  final W = base.width;
  final H = base.height;

  const panelX = 35;
  final panelW = W - 70;
  const panelH = 160;
  final panelY = (H - panelH - 30).clamp(0, H - panelH);

  sig = _resizeSignature(sig, 220, 80);

  img.fillRect(base, x1: panelX, y1: panelY, x2: panelX + panelW, y2: panelY + panelH, color: kColorGlassBg);
  img.fillRect(base, x1: panelX, y1: panelY, x2: panelX + kAccentBarWidth - 2, y2: panelY + panelH, color: kColorCyan);

  final textX = panelX + kTextLineLarge;
  int   yy    = panelY + kTextLineSmall;

  _drawTextShadow(base, _trunc(name.toUpperCase(), 28), font: img.arial24, x: textX, y: yy, color: kColorWhite);
  yy += kTextLineLarge + kSectionGap;

  _drawTextShadow(base, 'ID: $id', font: img.arial14, x: textX, y: yy, color: kColorGrey);
  yy += kTextLineSmall + 4;

  final addrLine = _wrapText(address, 60).take(1).join('');
  _drawTextShadow(base, addrLine,            font: img.arial14, x: textX, y: yy, color: kColorCyan);
  yy += kTextLineSmall + 4;

  _drawTextShadow(base, '$date   |   $time', font: img.arial14, x: textX, y: yy, color: kColorWhite);
  yy += kTextLineSmall + 4;

  if (weather.isNotEmpty) {
    _drawTextShadow(base, weather, font: img.arial14, x: textX, y: yy, color: kColorCyan);
  }

  if (logo != null) {
    img.compositeImage(base, logo,
      dstX: (panelX + panelW - logo.width - kPanelPaddingX).clamp(0, W - logo.width),
      dstY: (panelY + kTextLineSmall).clamp(0, H - logo.height),
    );
  }

  if (sig != null) {
    img.compositeImage(base, sig,
      dstX: (panelX + panelW - sig.width - kPanelPaddingX).clamp(0, W - sig.width),
      dstY: (panelY + panelH ~/ 2 - sig.height ~/ 2).clamp(0, H - sig.height),
    );
  }

  return _export(base, hasAlpha: hasAlpha);
}

// ════════════════════════════════════════════════════════════════════════════
//  LAYOUT 4 — VERTICAL SIDEBAR
// ════════════════════════════════════════════════════════════════════════════

Uint8List _drawLayout4(
  img.Image base, img.Image? sig, img.Image? logo,
  String name, String id, String date, String time,
  String address, String weather, {bool hasAlpha = false}
) {
  final W = base.width;
  final H = base.height;

  final sideW = (W * 0.28).toInt().clamp(190, 340);
  sig = _resizeSignature(sig, sideW - 40, 100);

  img.fillRect(base, x1: 0, y1: 0, x2: sideW, y2: H, color: kColorDarkBgMed);
  img.fillRect(base, x1: sideW - kAccentBarWidth + 2, y1: 0, x2: sideW, y2: H, color: kColorCyan);

  int yy = 35;

  if (logo != null) {
    img.compositeImage(base, logo,
      dstX: ((sideW - logo.width) ~/ 2).clamp(0, W - logo.width),
      dstY: yy,
    );
    yy += logo.height + 35;
  }

  _drawTextShadow(base, 'TEKNISI',          font: img.arial14, x: kSidebarPadX, y: yy, color: kColorCyan);
  yy += kTextLineLarge - 4;
  _drawTextShadow(base, _trunc(name, 18),   font: img.arial14, x: kSidebarPadX, y: yy, color: kColorWhite);
  yy += kTextLineLarge + kSectionGap;

  _drawTextShadow(base, 'ID',               font: img.arial14, x: kSidebarPadX, y: yy, color: kColorCyan);
  yy += kTextLineLarge - 4;
  _drawTextShadow(base, _trunc(id, 18),     font: img.arial14, x: kSidebarPadX, y: yy, color: kColorWhite);
  yy += kTextLineLarge + kSectionGap;

  _drawTextShadow(base, 'WAKTU',            font: img.arial14, x: kSidebarPadX, y: yy, color: kColorCyan);
  yy += kTextLineLarge - 4;
  _drawTextShadow(base, date,               font: img.arial14, x: kSidebarPadX, y: yy, color: kColorWhite);
  yy += kTextLineSmall + 2;
  _drawTextShadow(base, time,               font: img.arial14, x: kSidebarPadX, y: yy, color: kColorWhite);
  yy += kTextLineLarge + kSectionGap;

  _drawTextShadow(base, 'LOKASI',           font: img.arial14, x: kSidebarPadX, y: yy, color: kColorCyan);
  yy += kTextLineLarge - 4;

  for (final line in _wrapText(address, 18).take(4)) {
    _drawTextShadow(base, line, font: img.arial14, x: kSidebarPadX, y: yy, color: kColorWhite);
    yy += kTextLineSmall;
  }

  if (weather.isNotEmpty) {
    yy += kSectionGap;
    _drawTextShadow(base, weather, font: img.arial14, x: kSidebarPadX, y: yy, color: kColorCyan);
  }

  if (sig != null) {
    img.compositeImage(base, sig,
      dstX: ((sideW - sig.width) ~/ 2).clamp(0, W - sig.width),
      dstY: (H - sig.height - 35).clamp(0, H - sig.height),
    );
  }

  return _export(base, hasAlpha: hasAlpha);
}

// ════════════════════════════════════════════════════════════════════════════
//  APP
// ════════════════════════════════════════════════════════════════════════════

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B4F72)),
      useMaterial3: true,
      fontFamily: 'Roboto',
    ),
    home: const Login(),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  LOGIN
// ════════════════════════════════════════════════════════════════════════════

class Login extends StatelessWidget {
  const Login({super.key});
  @override
  Widget build(BuildContext context) {
    final c = TextEditingController();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D2137), Color(0xFF1B4F72), Color(0xFF2980B9)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(Icons.photo_camera_rounded,
                        color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 24),
                  const Text('TermulLog',
                      style: TextStyle(
                        fontSize: 32, fontWeight: FontWeight.w800,
                        color: Colors.white, letterSpacing: -0.5,
                      )),
                  const SizedBox(height: 6),
                  Text('Laporan Lapangan Digital',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.7),
                        letterSpacing: 0.5,
                      )),
                  const SizedBox(height: 48),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: TextField(
                      controller: c,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Nama Teknisi',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                        prefixIcon: Icon(Icons.person_outline,
                            color: Colors.white.withOpacity(0.6)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity, height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1B4F72),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      onPressed: () {
                        if (c.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Mohon masukkan nama teknisi'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) => Dashboard(name: c.text.trim())),
                        );
                      },
                      child: const Text('Masuk',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ITEM MODEL
// ════════════════════════════════════════════════════════════════════════════

class Item {
  final String id, path, time;
  Item(this.id, this.path, this.time);
}

// ════════════════════════════════════════════════════════════════════════════
//  WATERMARK LAYOUT SETTING
// ════════════════════════════════════════════════════════════════════════════

class WatermarkLayout {
  static String _layout = 'layout1';

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _layout = p.getString('layout') ?? 'layout1';
    } catch (e) {
      debugPrint('Failed to load layout: $e');
    }
  }

  static Future<void> set(String v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('layout', v);
      _layout = v;
    } catch (e) {
      debugPrint('Failed to save layout: $e');
    }
  }

  static String get() => _layout;
}

// ════════════════════════════════════════════════════════════════════════════
//  LOCATION & WEATHER SERVICE
// ════════════════════════════════════════════════════════════════════════════

class LocationWeatherService {
  static Future<Map<String, String>> fetch() async {
    String address = 'Lokasi tidak tersedia';
    String weather  = 'Cuaca tidak tersedia';
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return {'address': address, 'weather': weather};

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return {'address': address, 'weather': weather};
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 12));

      final lat    = pos.latitude;
      final lon    = pos.longitude;
      final latStr = lat.toStringAsFixed(6);
      final lonStr = lon.toStringAsFixed(6);

      try {
        final geoUri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse'
          '?format=json&lat=$latStr&lon=$lonStr&zoom=16&addressdetails=1',
        );
        final geoRes = await http
            .get(geoUri, headers: {'User-Agent': 'TermulLog/1.0'})
            .timeout(const Duration(seconds: 8));
        if (geoRes.statusCode == 200) {
          final data = jsonDecode(geoRes.body) as Map<String, dynamic>;
          final addr = data['address'] as Map<String, dynamic>?;
          if (addr != null) {
            final parts  = <String>[];
            final road   = addr['road']   as String?;
            final suburb = addr['suburb'] as String? ?? addr['village'] as String?;
            final city   = addr['city']   as String?
                        ?? addr['town']   as String?
                        ?? addr['county'] as String?;
            if (road   != null && road.isNotEmpty)   parts.add(road);
            if (suburb != null && suburb.isNotEmpty) parts.add(suburb);
            if (city   != null && city.isNotEmpty)   parts.add(city);
            address = parts.take(3).join(', ');
            if (address.isEmpty) {
              address = ((data['display_name'] as String?) ?? '')
                  .split(',').take(2).join(',').trim();
            }
          }
        }
      } catch (e) {
        debugPrint('Geocoding error: $e');
        address = 'GPS: ${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';
      }

      try {
        final wUri = Uri.parse(
          'https://api.open-meteo.com/v1/forecast'
          '?latitude=$latStr&longitude=$lonStr'
          '&current=temperature_2m,weathercode&timezone=auto',
        );
        final wRes = await http.get(wUri).timeout(const Duration(seconds: 8));
        if (wRes.statusCode == 200) {
          final wData   = jsonDecode(wRes.body) as Map<String, dynamic>;
          final current = wData['current'] as Map<String, dynamic>?;
          if (current != null) {
            final temp = (current['temperature_2m'] as num?)
                    ?.toStringAsFixed(0) ?? '--';
            final code = (current['weathercode'] as num?)?.toInt() ?? 0;
            weather = '${_wmoDesc(code)} ${temp}°C';
          }
        }
      } catch (e) {
        debugPrint('Weather error: $e');
      }
    } catch (e) {
      debugPrint('Location error: $e');
    }
    return {'address': address, 'weather': weather};
  }

  static String _wmoDesc(int c) {
    if (c == 0)  return 'Cerah';
    if (c <= 3)  return 'Berawan';
    if (c <= 49) return 'Berkabut';
    if (c <= 59) return 'Gerimis';
    if (c <= 67) return 'Hujan';
    if (c <= 77) return 'Bersalju';
    if (c <= 82) return 'Hujan Lebat';
    if (c <= 86) return 'Salju Lebat';
    if (c == 95) return 'Badai Petir';
    if (c <= 99) return 'Badai+Hujan Es';
    return 'Tidak diketahui';
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  LOGO CACHE
// ════════════════════════════════════════════════════════════════════════════

class LogoCache {
  static Uint8List?  _bytes;
  static img.Image?  _decoded;
  static String?     _path;

  static Future<void> load(String path) async {
    if (_path == path) return;
    try {
      final file = File(path);
      if (!await file.exists()) { debugPrint('Logo file not found: $path'); return; }
      final raw = await file.readAsBytes();
      img.Image? decoded = img.decodeImage(raw);
      if (decoded == null) return;

      if (decoded.width > kLogoMaxWidth || decoded.height > kLogoMaxWidth) {
        decoded = img.copyResize(decoded,
            width: kLogoMaxWidth, interpolation: img.Interpolation.linear);
      }
      if (decoded.width <= 0 || decoded.height <= 0) return;

      _bytes   = Uint8List.fromList(img.encodePng(decoded));
      _decoded = decoded;
      _path    = path;
    } catch (e) {
      debugPrint('Failed to load logo: $e');
      _bytes = null; _decoded = null; _path = null;
    }
  }

  static Uint8List?  get bytes   => _bytes;
  static img.Image?  get decoded => _decoded;

  static void clear() { _bytes = null; _decoded = null; _path = null; }
}

// ════════════════════════════════════════════════════════════════════════════
//  DASHBOARD
// ════════════════════════════════════════════════════════════════════════════

class Dashboard extends StatefulWidget {
  final String name;
  const Dashboard({super.key, required this.name});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> with WidgetsBindingObserver {
  List<Item> list = [];
  String? _logoPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cleanupTempFiles();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _cleanupTempFiles() async {
    try {
      final dir   = await getApplicationDocumentsDirectory();
      final files = await dir.list().toList();
      if (files.length > 100) {
        files.sort((a, b) =>
            a.statSync().modified.compareTo(b.statSync().modified));
        for (int i = 0; i < files.length - 100; i++) {
          if (files[i] is File) await (files[i] as File).delete();
        }
      }
    } catch (e) {
      debugPrint('Cleanup error: $e');
    }
  }

  Future<void> _openCamera() async {
    if (_cameras.isEmpty) { await _captureFallback(); return; }
    final paths = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(builder: (_) => const CameraPage()),
    );
    if (!mounted || paths == null || paths.isEmpty) return;
    if (paths.length == 1) {
      _goToSignature(paths.first);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BurstSelectionPage(
            paths: paths,
            onSelect: _goToSignature,
          ),
        ),
      );
    }
  }

  Future<void> _captureFallback() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: kMaxOutputWidth.toDouble(),
      imageQuality: 90,
    );
    if (file == null || !mounted) return;
    _goToSignature(file.path);
  }

  void _goToSignature(String imagePath) {
    final now  = DateTime.now();
    final id   = 'TRM-${now.millisecondsSinceEpoch}';
    final time = DateFormat('dd/MM HH:mm').format(now);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SignaturePage(
          imagePath: imagePath,
          techName:  widget.name,
          itemId:    id,
          itemTime:  time,
          onDone: (path) {
            if (mounted) setState(() => list.add(Item(id, path, time)));
          },
        ),
      ),
    );
  }

  Future<void> _pickLogo() async {
    final file = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 200);
    if (file == null) return;
    setState(() => _logoPath = file.path);
    await LogoCache.load(file.path);
  }

  Future<void> _shareItem(Item item) async {
    try {
      await Share.shareXFiles(
        [XFile(item.path)],
        subject: 'Laporan ${item.id}',
        text: 'Laporan teknisi — ${item.id} — ${item.time}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal share: $e'),
              backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  Future<void> _saveToGallery(Item item) async {
    try {
      final bool? ok = await GallerySaver.saveImage(item.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok == true ? '✓ Tersimpan ke galeri' : '✗ Gagal menyimpan'),
            backgroundColor: ok == true ? Colors.green.shade700 : Colors.red.shade700,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'),
              backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  void _previewItem(Item item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreviewPage(
          item:    item,
          onShare: () => _shareItem(item),
          onSave:  () => _saveToGallery(item),
        ),
      ),
    );
  }

  void _deleteItem(Item item) {
    setState(() => list.removeWhere((e) => e.id == item.id));
    try {
      final file = File(item.path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Laporan dihapus'),
            backgroundColor: Colors.grey),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final today      = DateFormat('dd/MM').format(DateTime.now());
    final todayCount = list.where((e) => e.time.startsWith(today)).length;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: Column(
        children: [
          _DashboardHeader(
            name:       widget.name,
            total:      list.length,
            todayCount: todayCount,
            logoPath:   _logoPath,
            onPickLogo: _pickLogo,
            onClearLogo: () {
              setState(() => _logoPath = null);
              LogoCache.clear();
            },
            onSettings: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? _EmptyState(onCapture: _openCamera)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final item = list[list.length - 1 - i];
                      return _ItemCard(
                        item:     item,
                        onTap:    () => _previewItem(item),
                        onShare:  () => _shareItem(item),
                        onSave:   () => _saveToGallery(item),
                        onDelete: () => _deleteItem(item),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _CameraFAB(onTap: _openCamera),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

// ─── Dashboard Header ────────────────────────────────────────────────────────

class _DashboardHeader extends StatelessWidget {
  final String name;
  final int total, todayCount;
  final String? logoPath;
  final VoidCallback onPickLogo, onClearLogo, onSettings;

  const _DashboardHeader({
    required this.name,
    required this.total,
    required this.todayCount,
    required this.logoPath,
    required this.onPickLogo,
    required this.onClearLogo,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D2137), Color(0xFF1B4F72)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Selamat datang,',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.white.withOpacity(0.65),
                              letterSpacing: 0.3,
                            )),
                        const SizedBox(height: 2),
                        Text(name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  if (logoPath != null)
                    GestureDetector(
                      onTap: onClearLogo,
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.file(File(logoPath!),
                                height: 30,
                                errorBuilder: (_, __, ___) => const Icon(
                                    Icons.broken_image,
                                    color: Colors.white70,
                                    size: 30)),
                            const SizedBox(width: 4),
                            const Icon(Icons.close, size: 14, color: Colors.white70),
                          ],
                        ),
                      ),
                    ),
                  IconButton(
                    icon: Icon(Icons.image_outlined,
                        color: Colors.white.withOpacity(0.85), size: 22),
                    onPressed: onPickLogo,
                  ),
                  IconButton(
                    icon: Icon(Icons.tune_rounded,
                        color: Colors.white.withOpacity(0.85), size: 22),
                    onPressed: onSettings,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _StatChip(label: 'Semua',    value: '$total',      icon: Icons.photo_library_outlined),
                  const SizedBox(width: 10),
                  _StatChip(label: 'Hari ini', value: '$todayCount', icon: Icons.today_outlined),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _StatChip({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.13),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withOpacity(0.2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 7),
        Text('$value $label',
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCapture;
  const _EmptyState({required this.onCapture});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 100, height: 100,
          decoration: BoxDecoration(
            color: const Color(0xFF1B4F72).withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.add_a_photo_outlined,
              size: 44, color: Color(0xFF1B4F72)),
        ),
        const SizedBox(height: 20),
        const Text('Belum ada laporan',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF1B4F72))),
        const SizedBox(height: 6),
        Text('Ketuk tombol kamera untuk mulai',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        const SizedBox(height: 28),
        OutlinedButton.icon(
          onPressed: onCapture,
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('Ambil Foto'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF1B4F72),
            side: const BorderSide(color: Color(0xFF1B4F72)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    ),
  );
}

class _ItemCard extends StatelessWidget {
  final Item item;
  final VoidCallback onTap, onShare, onSave, onDelete;

  const _ItemCard({
    required this.item,
    required this.onTap,
    required this.onShare,
    required this.onSave,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: Colors.red.shade400, borderRadius: BorderRadius.circular(16)),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.white, size: 26),
            SizedBox(height: 4),
            Text('Hapus', style: TextStyle(color: Colors.white, fontSize: 11)),
          ],
        ),
      ),
      confirmDismiss: (_) async =>
          await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Hapus Laporan?'),
              content: Text('${item.id} akan dihapus permanen.'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Batal')),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Hapus', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ) ?? false,
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 3))
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Hero(
                  tag: 'thumb_${item.id}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      File(item.path),
                      width: 72, height: 72,
                      fit: BoxFit.cover,
                      cacheWidth: 144,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey.shade300, width: 72, height: 72,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B4F72).withOpacity(0.09),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(item.id,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1B4F72),
                            ),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.access_time_rounded,
                              size: 13, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(item.time,
                              style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _ActionBtn(
                            icon: Icons.visibility_outlined,
                            label: 'Preview',
                            color: const Color(0xFF1B4F72),
                            onTap: onTap,
                          ),
                          const SizedBox(width: 8),
                          _ActionBtn(
                            icon: Icons.share_outlined,
                            label: 'Bagikan',
                            color: Colors.teal,
                            onTap: onShare,
                          ),
                          const SizedBox(width: 8),
                          _ActionBtn(
                            icon: Icons.save_alt_rounded,
                            label: 'Simpan',
                            color: Colors.orange,
                            onTap: onSave,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    ),
  );
}

class _CameraFAB extends StatelessWidget {
  final VoidCallback onTap;
  const _CameraFAB({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF1B4F72), Color(0xFF2980B9)]),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B4F72).withOpacity(0.45),
            blurRadius: 18,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.camera_alt_rounded, color: Colors.white, size: 22),
          SizedBox(width: 10),
          Text('Ambil Foto',
              style: TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  PREVIEW PAGE
// ════════════════════════════════════════════════════════════════════════════

class PreviewPage extends StatelessWidget {
  final Item item;
  final VoidCallback onShare, onSave;

  const PreviewPage({
    super.key,
    required this.item,
    required this.onShare,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(item.id, style: const TextStyle(fontSize: 14)),
        actions: [
          IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: onShare,
              tooltip: 'Bagikan'),
          IconButton(
              icon: const Icon(Icons.save_alt_rounded),
              onPressed: onSave,
              tooltip: 'Simpan ke galeri'),
        ],
      ),
      body: Center(
        child: Hero(
          tag: 'thumb_${item.id}',
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Image.file(
              File(item.path),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              const Icon(Icons.access_time_rounded, size: 14, color: Colors.white54),
              const SizedBox(width: 6),
              Text(item.time,
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SIGNATURE PAGE
// ════════════════════════════════════════════════════════════════════════════

class SignaturePage extends StatefulWidget {
  final String imagePath, techName, itemId, itemTime;
  final Function(String) onDone;

  const SignaturePage({
    super.key,
    required this.imagePath,
    required this.techName,
    required this.itemId,
    required this.itemTime,
    required this.onDone,
  });

  @override
  State<SignaturePage> createState() => _SignaturePageState();
}

class _SignaturePageState extends State<SignaturePage> {
  final SignatureController _signature = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
  );

  bool   _saving          = false;
  String _address         = 'Mengambil lokasi...';
  String _weather         = 'Mengambil cuaca...';
  bool   _locationLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchLocationWeather();
  }

  Future<void> _fetchLocationWeather() async {
    final result = await LocationWeatherService.fetch();
    if (!mounted) return;
    setState(() {
      _address         = result['address'] ?? 'Lokasi tidak tersedia';
      _weather         = result['weather'] ?? 'Cuaca tidak tersedia';
      _locationLoading = false;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final imageBytes = await File(widget.imagePath).readAsBytes();

      Uint8List? sigBytes;
      if (_signature.isNotEmpty) {
        try {
          sigBytes = await _signature.toPngBytes();
        } catch (e) {
          debugPrint('Signature conversion error: $e');
          sigBytes = null;
        }
      }

      final result = await compute(_processWatermark, {
        'imageBytes': imageBytes,
        'sigBytes':   sigBytes,
        'logoBytes':  LogoCache.bytes,
        'layout':     WatermarkLayout.get(),
        'name':       widget.techName,
        'id':         widget.itemId,
        'date':       DateFormat('dd/MM/yyyy').format(DateTime.now()),
        'time':       DateFormat('HH:mm:ss').format(DateTime.now()),
        'address':    _address,
        'weather':    _weather,
      });

      final dir  = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${widget.itemId}.jpg');
      await file.writeAsBytes(result);

      widget.onDone(file.path);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Laporan berhasil dibuat'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✗ Gagal save: ${e.toString().substring(0, e.toString().length.clamp(0, 100))}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _signature.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(title: const Text('Tambah Tanda Tangan')),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              child: Image.file(
                File(widget.imagePath),
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            color: const Color(0xFF0D2137),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _locationLoading
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: Colors.white54),
                      ),
                      SizedBox(width: 10),
                      Text('Mengambil lokasi & cuaca...',
                          style: TextStyle(color: Colors.white54, fontSize: 11)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 13, color: Colors.amber),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(_address,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.wb_sunny_outlined,
                              size: 13, color: Colors.amber),
                          const SizedBox(width: 6),
                          Text(_weather,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tanda Tangan Teknisi',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Signature(
                      controller: _signature,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _signature.clear(),
                        icon: const Icon(Icons.clear),
                        label: const Text('Hapus'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save_alt_rounded),
                        label: Text(_saving ? 'Menyimpan...' : 'Simpan'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B4F72),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  CAMERA PAGE  ← MINI MAP TERINTEGRASI
// ════════════════════════════════════════════════════════════════════════════

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _ctrl;
  int  _camIdx      = 0;
  bool _initialized = false;
  bool _busy        = false;

  FlashMode _flash = FlashMode.off;

  double _zoom = 1.0, _baseZoom = 1.0, _minZoom = 1.0, _maxZoom = 8.0;

  Offset? _focusPoint;
  bool    _showFocus = false;

  bool         _burstMode    = false;
  bool         _burstRunning = false;
  Timer?       _burstTimer;
  List<String> _burstPaths   = [];

  late AnimationController _shutterAnim;
  late Animation<double>   _shutterOpacity;

  // ── MINI MAP STATE ────────────────────────────────────────────────────────
  Position? _position;
  bool      _mapExpanded    = false;
  bool      _gpsLoading     = true;
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shutterAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _shutterOpacity = Tween<double>(begin: 0.0, end: 0.7).animate(
      CurvedAnimation(parent: _shutterAnim, curve: Curves.easeOut),
    );
    _initCamera(_camIdx);
    _fetchGps(); // ← ambil GPS untuk mini map
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _burstTimer?.cancel();
    _shutterAnim.dispose();
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(_camIdx);
    }
  }

  Future<void> _initCamera(int idx) async {
    if (_cameras.isEmpty) return;
    await _ctrl?.dispose();
    final controller = CameraController(
      _cameras[idx],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _ctrl = controller;
    try {
      await controller.initialize();
      await controller.setFlashMode(_flash);
      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = await controller.getMaxZoomLevel();
      _zoom    = _minZoom;
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error kamera: $e'),
              backgroundColor: Colors.red.shade700),
        );
      }
    }
    if (mounted) setState(() => _initialized = true);
  }

  // ── MINI MAP: Fetch GPS ──────────────────────────────────────────────────
  Future<void> _fetchGps() async {
    setState(() => _gpsLoading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) { setState(() => _gpsLoading = false); return; }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _gpsLoading = false);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 12));

      if (mounted) setState(() { _position = pos; _gpsLoading = false; });
    } catch (e) {
      debugPrint('MiniMap GPS error: $e');
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  // ── MINI MAP: Widget ─────────────────────────────────────────────────────
  Widget _buildMiniMap() {
    // Loading state
    if (_gpsLoading) {
      return Positioned(
        left: 14, top: 14,
        child: Container(
          width: 160, height: 80,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24),
          ),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: Colors.white54),
                ),
                SizedBox(height: 6),
                Text('GPS…',
                    style: TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),
          ),
        ),
      );
    }

    // GPS tidak tersedia
    if (_position == null) {
      return Positioned(
        left: 14, top: 14,
        child: GestureDetector(
          onTap: _fetchGps,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.65),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.red.shade400.withOpacity(0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_off, size: 14, color: Colors.red.shade300),
                const SizedBox(width: 6),
                const Text('GPS off — Coba lagi',
                    style: TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
          ),
        ),
      );
    }

    final lat = _position!.latitude;
    final lon = _position!.longitude;
    final acc = _position!.accuracy;
    final accColor = acc < 30 ? Colors.greenAccent : Colors.amber;
    final mapSize  = _mapExpanded ? 260.0 : 150.0;

    return Positioned(
      left: 14, top: 14,
      child: GestureDetector(
        onTap: () => setState(() => _mapExpanded = !_mapExpanded),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOut,
          width: mapSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white70, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 12, offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Peta OSM ──────────────────────────────────────────────
              SizedBox(
                height: mapSize,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(lat, lon),
                    initialZoom: 17,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.termullog.app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(lat, lon),
                          width: 36, height: 36,
                          child: const Icon(
                            Icons.location_pin,
                            color: Colors.red,
                            size: 36,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Info GPS di bawah peta ────────────────────────────────
              Container(
                width: double.infinity,
                color: Colors.black.withOpacity(0.80),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _GpsRow('LAT', lat.toStringAsFixed(5)),
                    _GpsRow('LNG', lon.toStringAsFixed(5)),
                    _GpsRow('±',   '${acc.toStringAsFixed(0)} m', color: accColor),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Tombol refresh
                        GestureDetector(
                          onTap: _fetchGps,
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.refresh, size: 11, color: Colors.white38),
                              SizedBox(width: 3),
                              Text('Refresh',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 9)),
                            ],
                          ),
                        ),
                        Text(
                          _mapExpanded ? 'Tutup ▲' : 'Buka ▼',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 9),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    setState(() => _initialized = false);
    _camIdx = (_camIdx + 1) % _cameras.length;
    await _initCamera(_camIdx);
  }

  Future<void> _cycleFlash() async {
    final next = _flash == FlashMode.off
        ? FlashMode.auto
        : _flash == FlashMode.auto
            ? FlashMode.always
            : FlashMode.off;
    setState(() => _flash = next);
    await _ctrl?.setFlashMode(next);
  }

  Future<void> _onTapFocus(TapDownDetails d, BoxConstraints c) async {
    if (_ctrl == null || !_initialized) return;
    final x = (d.localPosition.dx / c.biggest.width).clamp(0.0, 1.0);
    final y = (d.localPosition.dy / c.biggest.height).clamp(0.0, 1.0);
    setState(() { _focusPoint = d.localPosition; _showFocus = true; });
    try {
      await _ctrl!.setFocusPoint(Offset(x, y));
      await _ctrl!.setExposurePoint(Offset(x, y));
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _showFocus = false);
  }

  void _onScaleStart(ScaleStartDetails _) => _baseZoom = _zoom;

  Future<void> _onScaleUpdate(ScaleUpdateDetails d) async {
    if (_ctrl == null) return;
    final z = (_baseZoom * d.scale).clamp(_minZoom, _maxZoom);
    setState(() => _zoom = z);
    await _ctrl!.setZoomLevel(z);
  }

  Future<void> _flashShutter() async {
    await _shutterAnim.forward();
    await _shutterAnim.reverse();
  }

  Future<void> _capture() async {
    if (_ctrl == null || !_initialized || _busy) return;
    setState(() => _busy = true);
    unawaited(_flashShutter());
    try {
      final file = await _ctrl!.takePicture();
      if (!mounted) return;
      Navigator.pop(context, [file.path]);
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error kamera: ${e.toString().substring(
                0, e.toString().length.clamp(0, 100))}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
        setState(() => _busy = false);
      }
    }
  }

  void _startBurst() {
    setState(() { _burstRunning = true; _burstPaths = []; });
    _burstTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) async {
      if (!mounted || _ctrl == null || !_initialized) return;
      try {
        unawaited(_flashShutter());
        final file = await _ctrl!.takePicture();
        if (mounted) setState(() => _burstPaths.add(file.path));
      } catch (e) {
        debugPrint('Burst capture error: $e');
      }
    });
  }

  void _stopBurst() {
    _burstTimer?.cancel();
    _burstTimer = null;
    setState(() => _burstRunning = false);
    if (_burstPaths.isNotEmpty && mounted) {
      Navigator.pop(context, List<String>.from(_burstPaths));
    } else if (mounted) {
      setState(() => _burstMode = false);
    }
  }

  Future<void> _pickFromGallery() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    Navigator.pop(context, [file.path]);
  }

  IconData get _flashIcon => _flash == FlashMode.always
      ? Icons.flash_on_rounded
      : _flash == FlashMode.auto
          ? Icons.flash_auto_rounded
          : Icons.flash_off_rounded;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_burstRunning,
    onPopInvoked: (didPop) {
      if (_burstRunning && !didPop) _stopBurst();
    },
    child: Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildPreview()),
            if (_burstPaths.isNotEmpty) _buildBurstStrip(),
            _buildBottomBar(),
          ],
        ),
      ),
    ),
  );

  Widget _buildTopBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    color: Colors.black,
    child: Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () {
            if (_burstRunning) { _stopBurst(); } else { Navigator.pop(context); }
          },
        ),
        const Spacer(),
        _CamBtn(
          icon: _flashIcon,
          label: _flash == FlashMode.off ? 'Off' : _flash == FlashMode.auto ? 'Auto' : 'On',
          onTap: _cycleFlash,
        ),
        const SizedBox(width: 4),
        _CamBtn(
          icon: Icons.burst_mode_rounded,
          label: 'Burst',
          active: _burstMode,
          onTap: () => setState(() {
            _burstMode = !_burstMode;
            if (!_burstMode && _burstRunning) _stopBurst();
          }),
        ),
        const SizedBox(width: 4),
        _CamBtn(icon: Icons.flip_camera_ios_rounded, label: 'Balik', onTap: _switchCamera),
      ],
    ),
  );

  Widget _buildPreview() {
    if (!_initialized || _ctrl == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white54),
            SizedBox(height: 16),
            Text('Memuat kamera…',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (_, constraints) => GestureDetector(
        onTapDown: (d) => _onTapFocus(d, constraints),
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Camera preview ──────────────────────────────────────────
            ClipRect(
              child: OverflowBox(
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width:  _ctrl!.value.previewSize!.height,
                    height: _ctrl!.value.previewSize!.width,
                    child: CameraPreview(_ctrl!),
                  ),
                ),
              ),
            ),

            // ── Shutter flash ───────────────────────────────────────────
            AnimatedBuilder(
              animation: _shutterOpacity,
              builder: (_, __) => Opacity(
                opacity: _shutterOpacity.value,
                child: Container(color: Colors.white),
              ),
            ),

            // ── Focus indicator ─────────────────────────────────────────
            if (_showFocus && _focusPoint != null)
              Positioned(
                left: _focusPoint!.dx - 28,
                top:  _focusPoint!.dy - 28,
                child: _FocusBox(),
              ),

            // ── Zoom badge ──────────────────────────────────────────────
            if (_zoom > _minZoom + 0.05)
              Positioned(
                top: 14, left: 0, right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${_zoom.toStringAsFixed(1)}×',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ),

            // ── Burst counter ───────────────────────────────────────────
            if (_burstRunning)
              Positioned(
                top: 14, right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.red.shade600,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.fiber_manual_record,
                          color: Colors.white, size: 10),
                      const SizedBox(width: 5),
                      Text('${_burstPaths.length}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),

            // ── MINI MAP OVERLAY ────────────────────────────────────────
            _buildMiniMap(),
            // ────────────────────────────────────────────────────────────
          ],
        ),
      ),
    );
  }

  Widget _buildBurstStrip() => Container(
    height: 72,
    color: Colors.black87,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      itemCount: _burstPaths.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(
            File(_burstPaths[i]),
            width: 56, height: 56, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Container(color: Colors.grey, width: 56, height: 56),
          ),
        ),
      ),
    ),
  );

  Widget _buildBottomBar() => Container(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
    color: Colors.black,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _CircleBtn(icon: Icons.photo_library_outlined, size: 48, onTap: _pickFromGallery),
        GestureDetector(
          onTap: _burstMode
              ? (_burstRunning ? _stopBurst : _startBurst)
              : _capture,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 72, height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _burstRunning ? Colors.red.shade400 : Colors.white,
                width: 4,
              ),
            ),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width:  _burstRunning ? 24 : 54,
                height: _burstRunning ? 24 : 54,
                decoration: BoxDecoration(
                  color: _burstRunning ? Colors.red.shade500 : Colors.white,
                  borderRadius: BorderRadius.circular(_burstRunning ? 6 : 27),
                ),
              ),
            ),
          ),
        ),
        _CircleBtn(icon: Icons.info_outline_rounded, size: 48, onTap: _showInfoSheet),
      ],
    ),
  );

  void _showInfoSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Petunjuk Kamera',
                style: TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            SizedBox(height: 14),
            _InfoRow(icon: Icons.touch_app_rounded,      text: 'Ketuk layar untuk fokus'),
            _InfoRow(icon: Icons.zoom_in_rounded,         text: 'Jepit/rentang untuk zoom'),
            _InfoRow(icon: Icons.burst_mode_rounded,      text: 'Burst: aktifkan toggle → tekan shutter mulai, tekan lagi berhenti'),
            _InfoRow(icon: Icons.flash_auto_rounded,      text: 'Ikon kilat: Off → Auto → On'),
            _InfoRow(icon: Icons.flip_camera_ios_rounded, text: 'Ikon flip: ganti kamera depan/belakang'),
            _InfoRow(icon: Icons.map_outlined,            text: 'Mini map pojok kiri: tap untuk perbesar/perkecil, tap Refresh untuk perbarui GPS'),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  BURST SELECTION PAGE
// ════════════════════════════════════════════════════════════════════════════

class BurstSelectionPage extends StatelessWidget {
  final List<String> paths;
  final Function(String) onSelect;

  const BurstSelectionPage({super.key, required this.paths, required this.onSelect});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text('Pilih Foto (${paths.length})',
          style: const TextStyle(fontSize: 16)),
    ),
    body: GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4,
      ),
      itemCount: paths.length,
      itemBuilder: (_, i) => GestureDetector(
        onTap: () { Navigator.pop(context); onSelect(paths[i]); },
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(File(paths[i]),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Container(color: Colors.grey.shade800)),
            ),
            Positioned(
              bottom: 4, right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                child: Text('${i + 1}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  SETTINGS PAGE
// ════════════════════════════════════════════════════════════════════════════

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String selected = WatermarkLayout.get();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pilih Layout')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: kLayouts.length,
        itemBuilder: (_, i) {
          final l      = kLayouts[i];
          final active = selected == l.id;
          return Card(
            elevation: active ? 4 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                  color: active ? l.accentColor : Colors.transparent, width: 2),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: l.accentColor.withOpacity(0.15),
                child: Icon(l.icon, color: l.accentColor),
              ),
              title: Text(l.label,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(l.description),
              trailing: active ? Icon(Icons.check_circle, color: l.accentColor) : null,
              onTap: () async {
                setState(() => selected = l.id);
                await WatermarkLayout.set(l.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('✓ ${l.label} dipilih')),
                  );
                }
              },
            ),
          );
        },
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  CAMERA HELPER WIDGETS
// ════════════════════════════════════════════════════════════════════════════

class _CamBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  const _CamBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? Colors.amber.withOpacity(0.25)
            : Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? Colors.amber : Colors.white24, width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: active ? Colors.amber : Colors.white, size: 20),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                color: active ? Colors.amber : Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    ),
  );
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  const _CircleBtn({required this.icon, required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.12),
        border: Border.all(color: Colors.white30, width: 1),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.45),
    ),
  );
}

class _FocusBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 1.3, end: 1.0),
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
    builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
    child: Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.amber, width: 1.8),
        borderRadius: BorderRadius.circular(6),
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.amber, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13.5, height: 1.4)),
        ),
      ],
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  GPS ROW WIDGET  ← helper untuk info di bawah mini map
// ════════════════════════════════════════════════════════════════════════════

class _GpsRow extends StatelessWidget {
  final String label, value;
  final Color color;

  const _GpsRow(this.label, this.value, {this.color = Colors.white70});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(
      children: [
        SizedBox(
          width: 26,
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 9,
                  fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}
