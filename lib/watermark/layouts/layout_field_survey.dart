
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

/// Layout Professional - Field Survey
/// Menampilkan data dalam format tabel survey lapangan
class LayoutFieldSurvey extends WatermarkLayoutBase {
  @override
  String get name => 'Field Survey';
  
  // Konstanta layout
  static const int headerH = 32;
  static const int rowH = 28;
  static const int padX = 16;
  static const int colVal = 130;
  static const int maxAddressLen = 50;

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
    // Gambar tabel field survey
    final bool isTop = watermarkPosition == 'top';
    final wmHeight = _drawTable(
      src, timestamp, hasPosition, lat, lon, acc,
      address, weather, showWeather, showAccuracy, watermarkPosition,
    );
    
    // Tambahkan mini map jika tersedia
    if (showMiniMap && mapBytes != null && hasPosition && wmHeight > 0) {
      WatermarkLayoutBase.drawMiniMap(src, mapBytes,
          watermarkHeight: wmHeight, isTop: isTop);
    }
    
    return WatermarkLayoutBase.encodeJpg(src);
  }

  /// Menggambar tabel field survey dan mengembalikan tinggi watermark
  int _drawTable(
    img.Image src,
    DateTime timestamp,
    bool hasPosition,
    double? lat,
    double? lon,
    double? acc,
    String address,
    String weather,
    bool showWeather,
    bool showAccuracy,
    String watermarkPosition,
  ) {
    // Bangun baris data
    final rows = _buildRows(
      timestamp, hasPosition, lat, lon, acc,
      address, weather, showWeather, showAccuracy,
    );

    final int totalRows = rows.length;
    final int totalH = headerH + totalRows * rowH + 12 + 3;
    final bool isTop = watermarkPosition == 'top';
    final int y0 = isTop ? 0 : src.height - totalH;
    
    if (y0 < 0) return 0;

    // Gambar header
    _drawHeader(src, y0);
    
    // Gambar baris data
    _drawRows(src, y0, rows);
    
    // Garis penutup
    final int bottomY = y0 + headerH + totalRows * rowH;
    img.fillRect(
      src, x1: 0, y1: bottomY, x2: src.width - 1, y2: bottomY + 3,
      color: img.ColorRgba8(30, 144, 255, 200),
    );

    return totalH;
  }

  /// Membangun list baris data
  List<List<String>> _buildRows(
    DateTime timestamp,
    bool hasPosition,
    double? lat,
    double? lon,
    double? acc,
    String address,
    String weather,
    bool showWeather,
    bool showAccuracy,
  ) {
    final rows = <List<String>>[
      ['DATE', DateFormat('yyyy-MM-dd').format(timestamp)],
      ['TIME', DateFormat('HH:mm:ss').format(timestamp)],
    ];
    
    if (hasPosition) {
      rows.add(['LAT', '${lat!.toStringAsFixed(6)}°']);
      rows.add(['LON', '${lon!.toStringAsFixed(6)}°']);
      if (showAccuracy) {
        rows.add(['ACC', '±${acc?.toStringAsFixed(0) ?? '?'} m']);
      }
    }
    
    if (address.isNotEmpty && 
        address != 'Tidak ada lokasi' && 
        !address.startsWith('GPS:')) {
      final shortAddr = address.length > maxAddressLen 
          ? '${address.substring(0, maxAddressLen - 3)}…' 
          : address;
      rows.add(['ADDR', shortAddr]);
    }
    
    if (showWeather && weather.isNotEmpty) {
      rows.add(['WX', weather]);
    }
    
    return rows;
  }

  /// Menggambar header biru
  void _drawHeader(img.Image src, int y0) {
    img.fillRect(
      src, x1: 0, y1: y0, x2: src.width - 1, y2: y0 + headerH,
      color: WatermarkLayoutBase.blue,
    );
    img.drawString(
      src, 'TERMULOG  GEOTAGGED PHOTO',
      font: img.arial24, x: padX, y: y0 + 8,
      color: img.ColorRgba8(0, 0, 0, 255),
    );
  }

  /// Menggambar baris data dengan zebra stripe
  void _drawRows(img.Image src, int y0, List<List<String>> rows) {
    final font = img.arial24;
    int cy = y0 + headerH;
    
    for (int i = 0; i < rows.length; i++) {
      // Background zebra
      img.fillRect(
        src, x1: 0, y1: cy, x2: src.width - 1, y2: cy + rowH,
        color: i.isEven 
            ? img.ColorRgba8(0, 0, 12, 220) 
            : img.ColorRgba8(10, 10, 28, 220),
      );
      
      // Label
      img.drawString(src, rows[i][0], font: font, 
        x: padX, y: cy + 6, color: WatermarkLayoutBase.grey);
      
      // Value - warna putih untuk header, biru untuk data
      img.drawString(src, rows[i][1], font: font, 
        x: padX + colVal, y: cy + 6,
        color: i < 2 ? WatermarkLayoutBase.white : WatermarkLayoutBase.blue);
      
      cy += rowH;
    }
  }

}
