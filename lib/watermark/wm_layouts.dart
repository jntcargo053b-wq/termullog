// ════════════════════════════════════════════════════════════════════════════
//  watermark/wm_layouts.dart
//  Empat implementasi layout watermark (Layout 1-4)
// ════════════════════════════════════════════════════════════════════════════

import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../core/constants.dart';
import 'wm_helpers.dart';

// ════════════════════════════════════════════════════════════════════════════
//  LAYOUT 1 — PROFESSIONAL BOTTOM BANNER
// ════════════════════════════════════════════════════════════════════════════

Uint8List drawLayout1(
  img.Image base, img.Image? sig, img.Image? logo,
  String name, String id, String date, String time,
  String address, String weather, {bool hasAlpha = false}
) {
  final W = base.width;
  final H = base.height;

  final bannerH     = (H * 0.23).toInt().clamp(180, 380);
  final isSmall     = W < 700;
  final addrMaxChar = isSmall ? 38 : 65;

  sig = wmResizeSignature(sig, kSigMaxWidth, (bannerH * 0.45).toInt());

  img.fillRect(base, x1: 0, y1: H - bannerH, x2: W - 1, y2: H - 1, color: kColorDarkBg);
  img.fillRect(base, x1: 0, y1: H - bannerH, x2: kAccentBarWidth, y2: H - 1, color: kColorCyan);

  final titleFont = isSmall ? img.arial14 : img.arial24;
  int yy          = H - bannerH + kTextLineSmall;

  wmDrawTextShadow(base, 'LAPORAN TEKNIS',
      font: titleFont, x: kPanelPaddingX, y: yy, color: kColorCyan);
  yy += isSmall ? kTextLineSmall : kTextLineLarge + kSectionGap;

  wmDrawTextShadow(base, 'Teknisi : ${wmTrunc(name, 30)}',
      font: img.arial14, x: kPanelPaddingX, y: yy, color: kColorWhite);
  yy += kTextLineSmall + 4;

  wmDrawTextShadow(base, 'ID       : $id',
      font: img.arial14, x: kPanelPaddingX, y: yy, color: kColorWhite);
  yy += kTextLineSmall + 4;

  wmDrawTextShadow(base, '$date   |   $time',
      font: img.arial14, x: kPanelPaddingX, y: yy, color: kColorWhite);
  yy += kTextLineSmall + kSectionGap;

  if (address.isNotEmpty) {
    for (final line in wmWrapText(address, addrMaxChar).take(2)) {
      wmDrawTextShadow(base, line,
          font: img.arial14, x: kPanelPaddingX, y: yy, color: kColorWhite);
      yy += kTextLineSmall;
    }
  }

  if (weather.isNotEmpty) {
    yy += 4;
    wmDrawTextShadow(base, weather,
        font: img.arial14, x: kPanelPaddingX, y: yy, color: kColorCyan);
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

  return wmExport(base, hasAlpha: hasAlpha);
}

// ════════════════════════════════════════════════════════════════════════════
//  LAYOUT 2 — COMPACT CORNER CARD
// ════════════════════════════════════════════════════════════════════════════

Uint8List drawLayout2(
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

  sig = wmResizeSignature(sig, (boxW * 0.65).toInt(), 80);

  img.fillRect(base, x1: boxX, y1: boxY, x2: W - kCornerMargin, y2: boxY + boxH, color: kColorBlackCard);
  img.drawRect(base, x1: boxX, y1: boxY, x2: W - kCornerMargin, y2: boxY + boxH, color: kColorCyan);

  final textX = boxX + kTextLineSmall;
  int   yy    = boxY + 15;

  wmDrawTextShadow(base, wmTrunc(name, 28),  font: img.arial14, x: textX, y: yy, color: kColorWhite);
  yy += kTextLineLarge;
  wmDrawTextShadow(base, 'ID: $id',          font: img.arial14, x: textX, y: yy, color: kColorGrey);
  yy += kTextLineLarge;
  wmDrawTextShadow(base, '$date  $time',     font: img.arial14, x: textX, y: yy, color: kColorGrey);
  yy += kTextLineLarge;

  if (address.isNotEmpty) {
    for (final line in wmWrapText(address, 30).take(2)) {
      wmDrawTextShadow(base, line, font: img.arial14, x: textX, y: yy, color: kColorCyan);
      yy += kTextLineSmall;
    }
  }

  if (weather.isNotEmpty) {
    yy += kSectionGap ~/ 2;
    wmDrawTextShadow(base, weather, font: img.arial14, x: textX, y: yy, color: kColorWhite);
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

  return wmExport(base, hasAlpha: hasAlpha);
}

// ════════════════════════════════════════════════════════════════════════════
//  LAYOUT 3 — GLASS HUD
// ════════════════════════════════════════════════════════════════════════════

Uint8List drawLayout3(
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

  sig = wmResizeSignature(sig, 220, 80);

  img.fillRect(base,
    x1: panelX, y1: panelY, x2: panelX + panelW, y2: panelY + panelH,
    color: kColorGlassBg);
  img.fillRect(base,
    x1: panelX, y1: panelY, x2: panelX + kAccentBarWidth - 2, y2: panelY + panelH,
    color: kColorCyan);

  final textX = panelX + kTextLineLarge;
  int   yy    = panelY + kTextLineSmall;

  wmDrawTextShadow(base, wmTrunc(name.toUpperCase(), 28),
      font: img.arial24, x: textX, y: yy, color: kColorWhite);
  yy += kTextLineLarge + kSectionGap;

  wmDrawTextShadow(base, 'ID: $id', font: img.arial14, x: textX, y: yy, color: kColorGrey);
  yy += kTextLineSmall + 4;

  if (address.isNotEmpty) {
    final addrLine = wmWrapText(address, 60).take(1).join('');
    wmDrawTextShadow(base, addrLine, font: img.arial14, x: textX, y: yy, color: kColorCyan);
    yy += kTextLineSmall + 4;
  }

  wmDrawTextShadow(base, '$date   |   $time',
      font: img.arial14, x: textX, y: yy, color: kColorWhite);
  yy += kTextLineSmall + 4;

  if (weather.isNotEmpty) {
    wmDrawTextShadow(base, weather, font: img.arial14, x: textX, y: yy, color: kColorCyan);
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

  return wmExport(base, hasAlpha: hasAlpha);
}

// ════════════════════════════════════════════════════════════════════════════
//  LAYOUT 4 — VERTICAL SIDEBAR
// ════════════════════════════════════════════════════════════════════════════

Uint8List drawLayout4(
  img.Image base, img.Image? sig, img.Image? logo,
  String name, String id, String date, String time,
  String address, String weather, {bool hasAlpha = false}
) {
  final W = base.width;
  final H = base.height;

  final sideW = (W * 0.28).toInt().clamp(190, 340);
  sig = wmResizeSignature(sig, sideW - 40, 100);

  img.fillRect(base, x1: 0, y1: 0, x2: sideW, y2: H, color: kColorDarkBgMed);
  img.fillRect(base,
    x1: sideW - kAccentBarWidth + 2, y1: 0, x2: sideW, y2: H,
    color: kColorCyan);

  int yy = 35;

  if (logo != null) {
    img.compositeImage(base, logo,
      dstX: ((sideW - logo.width) ~/ 2).clamp(0, W - logo.width),
      dstY: yy,
    );
    yy += logo.height + 35;
  }

  wmDrawTextShadow(base, 'TEKNISI',        font: img.arial14, x: kSidebarPadX, y: yy, color: kColorCyan);
  yy += kTextLineLarge - 4;
  wmDrawTextShadow(base, wmTrunc(name, 18), font: img.arial14, x: kSidebarPadX, y: yy, color: kColorWhite);
  yy += kTextLineLarge + kSectionGap;

  wmDrawTextShadow(base, 'ID',             font: img.arial14, x: kSidebarPadX, y: yy, color: kColorCyan);
  yy += kTextLineLarge - 4;
  wmDrawTextShadow(base, wmTrunc(id, 18),  font: img.arial14, x: kSidebarPadX, y: yy, color: kColorWhite);
  yy += kTextLineLarge + kSectionGap;

  wmDrawTextShadow(base, 'WAKTU',          font: img.arial14, x: kSidebarPadX, y: yy, color: kColorCyan);
  yy += kTextLineLarge - 4;
  wmDrawTextShadow(base, date,             font: img.arial14, x: kSidebarPadX, y: yy, color: kColorWhite);
  yy += kTextLineSmall + 2;
  wmDrawTextShadow(base, time,             font: img.arial14, x: kSidebarPadX, y: yy, color: kColorWhite);
  yy += kTextLineLarge + kSectionGap;

  if (address.isNotEmpty) {
    wmDrawTextShadow(base, 'LOKASI',       font: img.arial14, x: kSidebarPadX, y: yy, color: kColorCyan);
    yy += kTextLineLarge - 4;
    for (final line in wmWrapText(address, 18).take(4)) {
      wmDrawTextShadow(base, line, font: img.arial14, x: kSidebarPadX, y: yy, color: kColorWhite);
      yy += kTextLineSmall;
    }
  }

  if (weather.isNotEmpty) {
    yy += kSectionGap;
    wmDrawTextShadow(base, weather, font: img.arial14, x: kSidebarPadX, y: yy, color: kColorCyan);
  }

  if (sig != null) {
    img.compositeImage(base, sig,
      dstX: ((sideW - sig.width) ~/ 2).clamp(0, W - sig.width),
      dstY: (H - sig.height - 35).clamp(0, H - sig.height),
    );
  }

  return wmExport(base, hasAlpha: hasAlpha);
}
