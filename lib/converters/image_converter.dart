import 'dart:typed_data';

import 'package:image/image.dart' as img;

enum ImageFormatOption { png, jpg, bmp, gif }

extension ImageFormatOptionX on ImageFormatOption {
  String get extension {
    switch (this) {
      case ImageFormatOption.png:
        return 'png';
      case ImageFormatOption.jpg:
        return 'jpg';
      case ImageFormatOption.bmp:
        return 'bmp';
      case ImageFormatOption.gif:
        return 'gif';
    }
  }

  String get label => extension.toUpperCase();
}

class UnsupportedImageException implements Exception {
  final String message;
  UnsupportedImageException(this.message);

  @override
  String toString() => message;
}

class ImageConverter {
  static Uint8List convert(Uint8List bytes, ImageFormatOption target) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw UnsupportedImageException('لم أستطع قراءة هذا الملف كصورة صالحة');
    }

    switch (target) {
      case ImageFormatOption.png:
        return Uint8List.fromList(img.encodePng(decoded));
      case ImageFormatOption.jpg:
        img.Image toEncode = decoded;
        if (decoded.hasAlpha) {
          final background = img.Image(
            width: decoded.width,
            height: decoded.height,
            numChannels: 3,
          );
          img.fill(background, color: img.ColorRgb8(255, 255, 255));
          img.compositeImage(background, decoded);
          toEncode = background;
        }
        return Uint8List.fromList(img.encodeJpg(toEncode, quality: 92));
      case ImageFormatOption.bmp:
        return Uint8List.fromList(img.encodeBmp(decoded));
      case ImageFormatOption.gif:
        return Uint8List.fromList(img.encodeGif(decoded));
    }
  }

  static List<ImageFormatOption> targetsExcluding(String sourceExt) {
    final all = ImageFormatOption.values;
    return all
        .where((format) => format.extension != sourceExt.toLowerCase())
        .toList(growable: false);
  }

  static const supportedSourceExtensions = [
    'png',
    'jpg',
    'jpeg',
    'bmp',
    'gif',
    'webp',
    'tga',
    'pvr',
  ];
}
