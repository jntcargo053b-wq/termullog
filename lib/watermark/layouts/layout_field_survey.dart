// lib/watermark/layouts/layout_field_survey.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

/// Layout profesional ala form survei lapangan.
/// - Tabel dengan header biru, baris zebra.
/// - Posisi tetap di bawah, tidak tergantung pengaturan global.
/// - Teks otomatis wrap (alamat), tinggi tabel dinamis.
/// - Mendukung ukuran font (small/normal/large) dan scaling proporsional.
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
    // ── Scaling adaptif ──────────────────────────────────────────
    final double scale = (src.width / 1080).clamp(0.7, 2.0);
    final int headerH = (28 * scale).round();
    final int rowH = WatermarkLayoutBase.getLineHeight(fontSize, scale, small: false);
    final int padX = (14 * scale).round();
    final int colW = (60 * scale).round();

    // ── Pilih font ────────────────────────────────────────────────
    final img.BitmapFont fontRow = fontSize == 'small' ? img.arial14 : img.arial24;
    final img.BitmapFont fontHeader = fontSize == 'small' ? img.arial14 : img.arial24;

    // ── Bangun baris data (label, value) ─────────────────────────
    final List<Map<String, String>> rows = [];

    // Tanggal & waktu
    rows.add({
      'label': 'DATE',
      'value': DateFormat('yyyy-MM-dd').format(timestamp),
    });
    rows.add({
      'label': 'TIME',
      'value': DateFormat('HH:mm:ss').format(timestamp),
    });

    // Koordinat & akurasi
    if (showCoordinates && hasPosition && lat != null && lon != null) {
      rows.add({'label': 'LAT', 'value': lat.toStringAsFixed(6)});
      rows.add({'label': 'LON', 'value': lon.toStringAsFixed(6)});
      if (showAccuracy && acc != null) {
        rows.add({'label': 'ACC', 'value': '±${acc.toStringAsFixed(0)} m'});
      }
    }

    // Alamat (di‑wrap dengan indentasi untuk baris ke‑2,3)
    if (showAddress && address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      final int maxChars = WatermarkLayoutBase.safeMaxChars(src.width, 12);
      final String wrapped = WatermarkLayoutBase.wrapText(address, maxChars);
      final List<String> lines = wrapped.split('\n');
      for (int i = 0; i < lines.length; i++) {
        final String displayLine = i == 0 ? lines[i] : '   ${lines[i]}'; // indentasi 3 spasi
        rows.add({
          'label': i == 0 ? 'ADDR' : '',
          'value': displayLine,
        });
      }
    }

    // Cuaca
    if (showWeather && weather.isNotEmpty) {
      rows.add({'label': 'WX', 'value': weather});
    }

    // ── Hitung tinggi total panel ────────────────────────────────
    final int totalH = headerH + rows.length * rowH + 8;
    final int y0 = src.height - totalH; // posisi BOTTOM (isTop dihapus)
    if (y0 < 0) return WatermarkLayoutBase.encodeJpg(src); // aman jika overflow

    // ── Background panel (solid dengan opacity) ──────────────────
    final int bgColor = img.ColorRgba8(0, 0, 0, (200 * opacity).toInt());
    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + totalH, color: bgColor);

    // ── Header (biru profesional) ─────────────────────────────────
    img.fillRect(src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + headerH,
        color: WatermarkLayoutBase.blue);
    // Teks header dengan shadow
    WatermarkLayoutBase.drawTextWithShadow(
      src, 'FIELD SURVEY', padX, y0 + 6,
      font: fontHeader, color: WatermarkLayoutBase.white,
    );

    // ── Isi tabel (baris) ────────────────────────────────────────
    int cy = y0 + headerH;
    for (int i = 0; i < rows.length; i++) {
      final Map<String, String> row = rows[i];
      final bool isEven = i.isEven;

      // Zebra stripe
      final int stripeColor = isEven
          ? img.ColorRgba8(255, 255, 255, 12)
          : img.ColorRgba8(0, 0, 0, 0);
      img.fillRect(src, x1: 0, y1: cy, x2: src.width - 1, y2: cy + rowH, color: stripeColor);

      // Label (hanya jika tidak kosong)
      final String label = row['label']!;
      if (label.isNotEmpty) {
        img.drawString(src, label, font: fontRow, x: padX, y: cy + (rowH ~/ 2 - 8),
            color: WatermarkLayoutBase.grey);
      }

      // Value (selalu ada)
      img.drawString(src, row['value']!, font: fontRow,
          x: padX + colW, y: cy + (rowH ~/ 2 - 8),
          color: WatermarkLayoutBase.white);

      // Garis pemisah (tipis) antar baris
      if (i < rows.length - 1) {
        img.fillRect(src,
            x1: padX, y1: cy + rowH - 1,
            x2: src.width - padX, y2: cy + rowH,
            color: img.ColorRgba8(255, 255, 255, 8));
      }
      cy += rowH;
    }

    // ── Border opsional ──────────────────────────────────────────
    if (showBorder) {
      img.drawRect(src,
          x1: 0, y1: y0,
          x2: src.width - 1, y2: y0 + totalH - 1,
          color: img.ColorRgba8(30, 144, 255, 60), thickness: 1);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }
}
