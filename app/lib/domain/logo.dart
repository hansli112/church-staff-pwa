import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// The largest logo file accepted, before resizing.
const maxLogoBytes = 1024 * 1024;

/// The logo is stored as a [logoSize] × [logoSize] PNG.
const logoSize = 512;

enum LogoError { tooLarge, notImage }

class LogoException implements Exception {
  const LogoException(this.error);

  final LogoError error;
}

/// Turns a picked file into the stored logo: centre-cropped square,
/// [logoSize] px, PNG. Throws [LogoException] for files over 1MB or that
/// are not images. The storage rules enforce the same limit.
Uint8List prepareLogo(Uint8List bytes) {
  if (bytes.length > maxLogoBytes) {
    throw const LogoException(LogoError.tooLarge);
  }
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const LogoException(LogoError.notImage);
  final side = decoded.width < decoded.height ? decoded.width : decoded.height;
  final square = img.copyCrop(
    decoded,
    x: (decoded.width - side) ~/ 2,
    y: (decoded.height - side) ~/ 2,
    width: side,
    height: side,
  );
  final sized = side > logoSize
      ? img.copyResize(
          square,
          width: logoSize,
          height: logoSize,
          interpolation: img.Interpolation.average,
        )
      : square;
  return img.encodePng(sized);
}
