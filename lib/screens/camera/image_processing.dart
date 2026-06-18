import 'package:image/image.dart' as img;

@immutable
class ResizeParams {
  final Uint8List rawBytes;
  final int quality;
  const ResizeParams(this.rawBytes, this.quality);
}

Future<Uint8List> resizeImageIsolate(ResizeParams params) async {
  final originalImg = img.decodeImage(params.rawBytes);
  if (originalImg == null) return params.rawBytes;
  const int targetWidth = 1920;
  if (originalImg.width <= targetWidth) {
    return Uint8List.fromList(img.encodeJpg(originalImg, quality: params.quality));
  }
  final ratio = originalImg.height / originalImg.width;
  final h = (targetWidth * ratio).round();
  final resized = img.copyResize(originalImg, width: targetWidth, height: h);
  return Uint8List.fromList(img.encodeJpg(resized, quality: params.quality));
}

Future<Uint8List> resizeImageSync(Uint8List rawBytes, int quality) async {
  final originalImg = img.decodeImage(rawBytes);
  if (originalImg == null) return rawBytes;
  const int targetWidth = 1920;
  if (originalImg.width <= targetWidth) {
    return Uint8List.fromList(img.encodeJpg(originalImg, quality: quality));
  }
  final ratio = originalImg.height / originalImg.width;
  final h = (targetWidth * ratio).round();
  final resized = img.copyResize(originalImg, width: targetWidth, height: h);
  return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
}
