// Draws the app icon and the alternate icons supporters can pick, and writes
// every size Android, iOS and the web need.
//
//   cd app && dart run tool/generate_icons.dart
//
// The mark: a short roster (three lines, the last one ticked) on a solid
// colour. No text: icons are read at 29pt. The variants change only the
// colour, so the app is still recognizable on the home screen.
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

class Variant {
  const Variant(this.id, this.background, this.foreground);

  /// '' for the default icon.
  final String id;
  final img.ColorRgb8 background;
  final img.ColorRgb8 foreground;
}

final variants = [
  Variant('', img.ColorRgb8(0x1F, 0x5F, 0xD1), img.ColorRgb8(0xFF, 0xFF, 0xFF)),
  Variant('Green', img.ColorRgb8(0x1E, 0x7B, 0x4C), img.ColorRgb8(0xFF, 0xFF, 0xFF)),
  Variant('Purple', img.ColorRgb8(0x5B, 0x3E, 0xA8), img.ColorRgb8(0xFF, 0xFF, 0xFF)),
  Variant('Night', img.ColorRgb8(0x16, 0x1B, 0x26), img.ColorRgb8(0x9F, 0xC2, 0xFF)),
];

img.Image draw(Variant v, {int size = 1024, bool padForMaskable = false, bool rounded = false}) {
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
  if (rounded) {
    img.fillRect(canvas, x1: 0, y1: 0, x2: size - 1, y2: size - 1, color: v.background, radius: size * 0.22);
  } else {
    img.fill(canvas, color: v.background);
  }
  // Content area: the middle 56% (maskable icons need a safe zone of 80%,
  // and the mark sits well inside it either way).
  final scale = padForMaskable ? 0.48 : 0.56;
  final box = size * scale;
  final left = (size - box) / 2;
  final top = (size - box) / 2;
  final row = box / 3;
  final bar = row * 0.30;
  final dot = bar * 0.75;
  for (var i = 0; i < 3; i++) {
    final cy = top + row * i + row / 2;
    final last = i == 2;
    // Leading dot, or a tick on the last line.
    if (last) {
      final t = bar * 0.85;
      final x0 = left - dot * 0.3, y0 = cy - dot * 0.05;
      final x1 = left + dot * 0.75, y1 = cy + dot * 1.0;
      final x2 = left + dot * 2.4, y2 = cy - dot * 1.2;
      stroke(canvas, x0, y0, x1, y1, t, v.foreground);
      stroke(canvas, x1, y1, x2, y2, t, v.foreground);
    } else {
      img.fillCircle(canvas, x: (left + dot).round(), y: cy.round(), radius: dot.round(), color: v.foreground, antialias: true);
    }
    final x1 = left + dot * 3.2;
    final x2 = left + box - (last ? box * 0.22 : 0);
    img.fillRect(
      canvas,
      x1: x1.round(),
      y1: (cy - bar / 2).round(),
      x2: x2.round(),
      y2: (cy + bar / 2).round(),
      color: v.foreground,
      radius: bar / 2,
    );
  }
  return canvas;
}

/// A line with round caps, drawn as overlapping discs.
void stroke(img.Image c, double x0, double y0, double x1, double y1, double width, img.Color color) {
  final steps = (sqrt(pow(x1 - x0, 2) + pow(y1 - y0, 2)) / 2).ceil();
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    img.fillCircle(c, x: (x0 + (x1 - x0) * t).round(), y: (y0 + (y1 - y0) * t).round(), radius: (width / 2).round(), color: color, antialias: true);
  }
}

void write(String path, img.Image image) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(image));
}

img.Image resized(img.Image src, int size) =>
    img.copyResize(src, width: size, height: size, interpolation: img.Interpolation.average);

void main() {
  const android = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
  for (final v in variants) {
    final full = draw(v);
    final name = v.id.isEmpty ? 'ic_launcher' : 'ic_launcher_${v.id.toLowerCase()}';
    final round = draw(v, rounded: true);
    android.forEach((density, px) {
      write('android/app/src/main/res/mipmap-$density/$name.png', resized(round, px));
    });
    final set = v.id.isEmpty ? 'AppIcon' : 'AppIcon-${v.id}';
    final dir = 'ios/Runner/Assets.xcassets/$set.appiconset';
    if (Directory(dir).existsSync()) {
      for (final f in Directory(dir).listSync()) {
        f.deleteSync();
      }
    }
    // iOS masks the corners itself; the icon must be square and opaque.
    write('$dir/icon-1024.png', full);
    File('$dir/Contents.json').writeAsStringSync('''
{
  "images" : [
    { "filename" : "icon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
''');
    if (v.id.isEmpty) {
      write('web/icons/Icon-192.png', resized(round, 192));
      write('web/icons/Icon-512.png', resized(round, 512));
      final maskable = draw(v, padForMaskable: true);
      write('web/icons/Icon-maskable-192.png', resized(maskable, 192));
      write('web/icons/Icon-maskable-512.png', resized(maskable, 512));
      write('web/favicon.png', resized(round, 64));
      write('assets/icons/app.png', resized(round, 256));
    } else {
      write('assets/icons/${v.id.toLowerCase()}.png', resized(round, 256));
    }
  }
  stdout.writeln('Wrote ${variants.length} icons (${max(1, variants.length)} variants).');
}
