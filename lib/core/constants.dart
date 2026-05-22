import 'package:image/image.dart' as img;

// Warna sebagai img.Color
final img.Color kColorWhite = img.ColorRgb8(255, 255, 255);
final img.Color kColorBlack = img.ColorRgb8(0, 0, 0);
final img.Color kColorRed = img.ColorRgb8(255, 0, 0);
final img.Color kColorGreen = img.ColorRgb8(0, 255, 0);
final img.Color kColorBlue = img.ColorRgb8(0, 0, 255);
final img.Color kColorCyan = img.ColorRgb8(0, 255, 255);
final img.Color kColorYellow = img.ColorRgb8(255, 255, 0);
final img.Color kColorLightGrey = img.ColorRgb8(200, 200, 200);
final img.Color kColorDarkGrey = img.ColorRgb8(50, 50, 50);
final img.Color kColorIvory = img.ColorRgb8(255, 255, 240);
final img.Color kColorDarkText = img.ColorRgb8(30, 30, 30);
final img.Color kColorTransparent = img.ColorRgba8(0, 0, 0, 0);

img.Color getAccuracyColor(double? acc) {
  if (acc == null) return kColorLightGrey;
  if (acc < 5) return kColorGreen;
  if (acc < 15) return kColorYellow;
  return kColorRed;
}

// Theme colors (jika dibutuhkan)
final Map<String, dynamic> lightTheme = {
  'primaryColor': img.ColorRgb8(27, 42, 74),
  'primaryImgColor': img.getColor(27, 42, 74),
  // ...
};

final Map<String, dynamic> darkTheme = {
  'primaryColor': img.ColorRgb8(0, 184, 212),
  'primaryImgColor': img.getColor(0, 184, 212),
};

final Map<String, dynamic> sepiaTheme = {
  'primaryColor': img.ColorRgb8(248, 245, 235),
  'primaryImgColor': img.getColor(248, 245, 235),
};
