import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:martha/domain/logo.dart';

void main() {
  test('crops to a square and shrinks to 512px PNG', () {
    final source = img.encodeJpg(img.Image(width: 1600, height: 900));
    final out = img.decodePng(prepareLogo(source))!;
    expect((out.width, out.height), (512, 512));
  });

  test('keeps small images at their size', () {
    final source = img.encodePng(img.Image(width: 200, height: 300));
    final out = img.decodePng(prepareLogo(source))!;
    expect((out.width, out.height), (200, 200));
  });

  test('rejects files over 1MB and files that are not images', () {
    expect(
      () => prepareLogo(Uint8List(maxLogoBytes + 1)),
      throwsA(
        isA<LogoException>().having(
          (e) => e.error,
          'error',
          LogoError.tooLarge,
        ),
      ),
    );
    expect(
      () => prepareLogo(Uint8List.fromList('<html>'.codeUnits)),
      throwsA(
        isA<LogoException>().having(
          (e) => e.error,
          'error',
          LogoError.notImage,
        ),
      ),
    );
  });
}
