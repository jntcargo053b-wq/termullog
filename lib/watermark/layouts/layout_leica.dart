import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'watermark_layout_base.dart';
import '../../core/constants.dart';

class LayoutLeica extends WatermarkLayoutBase {
  @override
  String get name => 'Leica';

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
    final int margin = 20;
    final int panelW = 210; // sedikit lebih lebar untuk alamat
    int x = src.width - margin - panelW;

    // Hitung jumlah baris konten
    int rowCount = 2; // date + time
    if (hasPosition && showCoordinates) rowCount += 1;
    if (showAccuracy && acc != null) rowCount += 1;
    if (showAddress && address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      final maxChars = panelW ~/ 6; // ~35 karakter
      final wrapped = WatermarkLayoutBase.wrapText(address, maxChars);
      rowCount += wrapped.split('\n').length;
    }
    if (showWeather && weather.isNotEmpty) rowCount += 1;

    final int lineH = 24;
    final int panelH = 30 + rowCount * lineH;
    int y = src.height - margin - panelH + 10;

    // Lingkaran merah (indikator Leica)
    img.fillCircle(src, src.width - margin - 12, y + 12, 6, kColorRed);

    final String dateStr = DateFormat('yyyy-MM-dd').format(timestamp);
    final String timeStr = DateFormat('HH:mm:ss').format(timestamp);

    _drawText(src, dateStr, x, y, 14, kColorWhite);
    y += lineH;
    _drawText(src, timeStr, x, y, 14, kColorWhite);
    y += lineH;

    if (hasPosition && showCoordinates && lat != null && lon != null) {
      final String coordStr = '${lat.toStringAsFixed(4)}° ${lon.toStringAsFixed(4)}°';
      _drawText(src, coordStr, x, y, 11, kColorLightGrey);
      y += lineH - 4;
    }

    if (showAccuracy && acc != null) {
      final String accStr = '±${acc.toStringAsFixed(1)}m';
      _drawText(src, accStr, x, y, 11, getAccuracyColor(acc));
      y += lineH - 4;
    }

    // Address dengan wrap text
    if (showAddress && address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      final maxChars = panelW ~/ 6; // sekitar 35 karakter per baris
      final wrapped = WatermarkLayoutBase.wrapText(address, maxChars);
      final lines = wrapped.split('\n');
      for (final line in lines) {
        if (y + 14 > src.height - margin) break;
        _drawText(src, line, x, y, 11, kColorLightGrey);
        y += lineH - 4;
      }
    }

    // Weather (jika ada)
    if (showWeather && weather.isNotEmpty) {
      _drawText(src, weather, x, y, 11, kColorWhite);
    }

    return WatermarkLayoutBase.encodeJpg(src);
  }

  void _drawText(img.Image image, String text, int x, int y, int size, int color) {
    if (size <= 12) {
      img.drawString(image, img.arial12, x, y, text, color: color);
    } else if (size <= 14) {
      img.drawString(image, img.arial14, x, y, text, color: color);
    } else {
      img.drawString(image, img.arial24, x, y, text, color: color);
    }
  }
}
