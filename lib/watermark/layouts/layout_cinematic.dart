import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'watermark_layout_base.dart';
import '../../core/constants.dart';

class LayoutCinematic extends WatermarkLayoutBase {
  @override
  String get name => 'Cinematic';

  @override
  Uint8List apply({...}) {
    // ... sama seperti sebelumnya, hanya ubah di _drawTextCentered
  }

  void _drawTextCentered(img.Image image, String text, int centerX, int y, int size, img.Color color) {
    int approxWidth = text.length * (size ~/ 2);
    int x = centerX - (approxWidth ~/ 2);
    if (size <= 14) {
      img.drawString(image, text, font: img.arial14, x: x, y: y, color: color);
    } else if (size <= 24) {
      img.drawString(image, text, font: img.arial24, x: x, y: y, color: color);
    } else {
      img.drawString(image, text, font: img.arial36, x: x, y: y, color: color);
    }
  }
}
