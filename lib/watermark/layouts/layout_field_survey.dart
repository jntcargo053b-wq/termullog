import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'watermark_layout_base.dart';

class LayoutFieldSurvey extends WatermarkLayoutBase {
  @override
  String get name => 'Field Survey';
  
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
    final wmHeight = _drawTable(src, timestamp, hasPosition, lat, lon, acc,
        address, weather, showWeather, showAccuracy, watermarkPosition);
    
    if (showMiniMap && mapBytes != null && hasPosition && wmHeight > 0) {
      _addMiniMapTopRight(src, mapBytes, watermarkHeight: wmHeight);
    }
    
    return WatermarkLayoutBase.encodeJpg(src);
  }

  int _drawTable(img.Image src, DateTime timestamp, bool hasPosition,
      double? lat, double? lon, double? acc, String address, String weather,
      bool showWeather, bool showAccuracy, String watermarkPosition) {
    final rows = _buildRows(timestamp, hasPosition, lat, lon, acc, address, weather, showWeather, showAccuracy);
    final int totalRows = rows.length;
    final int totalH = headerH + totalRows * rowH + 12 + 3;
    final bool isTop = watermarkPosition == 'top';
    final int y0 = isTop ? 0 : src.height - totalH;
    if (y0 < 0) return 0;

    _drawHeader(src, y0);
    _drawRows(src, y0, rows);
    
    // Garis penutup dengan glow
    final int bottomY = y0 + headerH + totalRows * rowH;
    img.fillRect(src, x1: 0, y1: bottomY - 1, x2: src.width - 1, y2: bottomY + 1,
        color: img.ColorRgba8(30, 144, 255, 40));
    img.fillRect(src, x1: 0, y1: bottomY, x2: src.width - 1, y2: bottomY + 3,
        color: img.ColorRgba8(30, 144, 255, 200));

    return totalH;
  }

  List<List<String>> _buildRows(DateTime timestamp, bool hasPosition,
      double? lat, double? lon, double? acc, String address, String weather,
      bool showWeather, bool showAccuracy) {
    final rows = <List<String>>[
      ['DATE', DateFormat('yyyy-MM-dd').format(timestamp)],
      ['TIME', DateFormat('HH:mm:ss').format(timestamp)],
    ];
    if (hasPosition) {
      rows.add(['LAT', '${lat!.toStringAsFixed(6)}°']);
      rows.add(['LON', '${lon!.toStringAsFixed(6)}°']);
      if (showAccuracy) rows.add(['ACC', '±${acc?.toStringAsFixed(0) ?? '?'} m']);
    }
    if (address.isNotEmpty && address != 'Tidak ada lokasi' && !address.startsWith('GPS:')) {
      final shortAddr = address.length > maxAddressLen ? '${address.substring(0, maxAddressLen - 3)}…' : address;
      rows.add(['ADDR', shortAddr]);
    }
    if (showWeather && weather.isNotEmpty) rows.add(['WX', weather]);
    return rows;
  }

  void _drawHeader(img.Image src, int y0) {
    // Gradient header
    for (int y = y0; y < y0 + headerH; y++) {
      final t = (y - y0) / headerH;
      final r = 20 + (t * 20).toInt();
      final g = 100 + (t * 40).toInt();
      final b = 180 + (t * 50).toInt();
      img.fillRect(src, x1: 0, y1: y, x2: src.width - 1, y2: y + 1,
          color: img.ColorRgba8(r, g, b, 255));
    }
    // Shadow text
    img.drawString(src, 'TERMULOG  GEOTAGGED PHOTO',
        font: img.arial24, x: padX + 1, y: y0 + 9,
        color: img.ColorRgba8(0, 0, 0, 60));
    img.drawString(src, 'TERMULOG  GEOTAGGED PHOTO',
        font: img.arial24, x: padX, y: y0 + 8,
        color: img.ColorRgba8(255, 255, 255, 255));
  }

  void _drawRows(img.Image src, int y0, List<List<String>> rows) {
    final font = img.arial24;
    int cy = y0 + headerH;
    for (int i = 0; i < rows.length; i++) {
      // Background zebra dengan subtle gradient
      final baseColor = i.isEven
          ? img.ColorRgba8(0, 0, 12, 220)
          : img.ColorRgba8(10, 10, 28, 220);
      img.fillRect(src, x1: 0, y1: cy, x2: src.width - 1, y2: cy + rowH, color: baseColor);
      
      // Label
      img.drawString(src, rows[i][0], font: font, x: padX, y: cy + 6, color: WatermarkLayoutBase.grey);
      // Value
      img.drawString(src, rows[i][1], font: font, x: padX + colVal, y: cy + 6,
          color: i < 2 ? WatermarkLayoutBase.white : WatermarkLayoutBase.blue);
      
      // Separator halus antar baris
      if (i < rows.length - 1) {
        img.fillRect(src, x1: padX, y1: cy + rowH - 1, x2: src.width - padX, y2: cy + rowH,
            color: img.ColorRgba8(255, 255, 255, 15));
      }
      cy += rowH;
    }
  }

  void _addMiniMapTopRight(img.Image src, Uint8List? mapBytes, {int watermarkHeight = 0}) {
    if (mapBytes == null || mapBytes.isEmpty) return;
    try {
      final mapImage = img.decodeImage(mapBytes);
      if (mapImage == null) return;
      
      const int mapWidth = 220;
      const int mapHeight = 140;
      const int margin = 16;
      
      final resizedMap = (mapImage.width != mapWidth || mapImage.height != mapHeight)
          ? img.copyResize(mapImage, width: mapWidth, height: mapHeight)
          : mapImage;
      
      final mapX = src.width - mapWidth - margin;
      final mapY = src.height - watermarkHeight - mapHeight - margin;
      if (mapX < 0 || mapY < 0) return;
      
      // Border glow
      img.fillRect(src, x1: mapX - 2, y1: mapY - 2, x2: mapX + mapWidth + 2, y2: mapY + mapHeight + 2,
          color: img.ColorRgba8(30, 144, 255, 50));
      img.compositeImage(src, resizedMap, dstX: mapX, dstY: mapY, blend: img.BlendMode.alpha);
      img.drawRect(src, x1: mapX - 1, y1: mapY - 1, x2: mapX + mapWidth, y2: mapY + mapHeight,
          color: WatermarkLayoutBase.blue, thickness: 2);
      
      // Pin lokasi dengan shadow
      final int cx = mapX + mapWidth ~/ 2;
      final int cy = mapY + mapHeight ~/ 2;
      img.fillCircle(src, x: cx + 1, y: cy + 1, radius: 6, color: img.ColorRgba8(0, 0, 0, 80));
      img.fillCircle(src, x: cx, y: cy, radius: 6, color: img.ColorRgba8(255, 50, 50, 255));
      img.fillCircle(src, x: cx, y: cy, radius: 2, color: WatermarkLayoutBase.white);
    } catch (_) {}
  }
}
