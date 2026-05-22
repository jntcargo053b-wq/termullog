// lib/watermark/layouts/layout_field_survey.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutFieldSurvey extends WatermarkLayoutBase {
  @override
  String get name => 'Field Survey';

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
    required bool showMiniMap,
    Uint8List? mapBytes,
    bool showAddress = true,
    bool showCoordinates = true,
    double opacity = 0.85,
    bool showBorder = true,
    String fontSize = 'normal',
  }) {
    // ── Adaptive scaling ──────────────────────────────────────────
    final double scale = (src.width / 1080).clamp(0.7, 2.0);
    final double fsMultiplier = fontSize == 'small' ? 0.75 : fontSize == 'large' ? 1.4 : 1.0;

    final int headerH = (28 * scale).round();
    final int rowH = (24 * scale * fsMultiplier).round();
    final int padX = (12 * scale).round();
    final int colW = (60 * scale).round();

    // ── Pilih font ────────────────────────────────────────────────
    final font = fontSize == 'small' ? img.arial14 : img.arial24;

    // ── Bangun rows dinamis ──────────────────────────────────────
    final List<Map<String, String>> rows = [
      {'label': 'DATE', 'value': DateFormat('yyyy-MM-dd').format(timestamp)},
      {'label': 'TIME', 'value': DateFormat('HH:mm:ss').format(timestamp)},
    ];

    if (showCoordinates && hasPosition && lat != null && lon != null) {
      rows.add({'label': 'LAT', 'value': lat.toStringAsFixed(6)});
      rows.add({'label': 'LON', 'value': lon.toStringAsFixed(6)});
      if (showAccuracy && acc != null) {
        rows.add({'label': 'ACC', 'value': '±${acc.toStringAsFixed(0)} m'});
      }
    }

    // Address dengan wrapText (multi‑line)
    if (showAddress && address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      final maxChars = (src.width / 6).toInt().clamp(30, 50);
      final wrapped = WatermarkLayoutBase.wrapText(address, maxChars);
      final lines = wrapped.split('\n');
      for (int i = 0; i < lines.length; i++) {
        rows.add({
          'label': i == 0 ? 'ADDR' : '',
          'value': lines[i],
        });
      }
    }

    if (showWeather && weather.isNotEmpty) {
      rows.add({'label': 'WX', 'value': weather});
    }

    final int totalH = headerH + rows.length * rowH + 8;
    final int y0 = src.height - totalH; // posisi bottom (isTop dihapus)
    if (y0 < 0) return WatermarkLayoutBase.encodeJpg(src);

    // ── Background table ──────────────────────────────────────────
    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + totalH,
        color: img.ColorRgba8(0, 0, 0, (200 * opacity).toInt()));

    // ── Header dengan shadow ─────────────────────────────────────
    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + headerH,
        color: WatermarkLayoutBase.blue);
    img.drawString(src, 'FIELD SURVEY',
        font: font, x: padX + 1, y: y0 + 6 + 1,
        color: img.ColorRgba8(0, 0, 0, 80));
    img.drawString(src, 'FIELD SURVEY',
        font: font, x: padX, y: y0 + 6,
        color: WatermarkLayoutBase.white);

    // ── Rows ─────────────────────────────────────────────────────
    int cy = y0 + headerH;
    for (int i = 0; i < rows.length; i++) {
      // Zebra stripe
      final bgColor = i.isEven
          ? img.ColorRgba8(255, 255, 255, 12)
          : img.ColorRgba8(0, 0, 0, 0);
      img.fillRect(src, x1: 0, y1: cy, x2: src.width - 1, y2: cy + rowH, color: bgColor);

      // Label (abu-abu) - hanya jika tidak kosong
      final label = rows[i]['label']!;
      if (label.isNotEmpty) {
        img.drawString(src, label,
            font: font, x: padX, y: cy + (rowH / 2 - 10).round(),
            color: WatermarkLayoutBase.grey);
      }

      // Value (putih)
      img.drawString(src, rows[i]['value']!,
          font: font, x: padX + colW, y: cy + (rowH / 2 - 10).round(),
          color: WatermarkLayoutBase.white);

      // Separator tipis antar baris
      if (i < rows.length - 1) {
        img.fillRect(src, x1: padX, y1: cy + rowH - 1,
            x2: src.width - padX, y2: cy + rowH,
            color: img.ColorRgba8(255, 255, 255, 8));
      }
      cy += rowH;
    }

    // ── Border jika aktif ────────────────────────────────────────
    if (showBorder) {
      img.drawRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + totalH - 1,
          color: img.ColorRgba8(30, 144, 255, 60), thickness: 1);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }
}
