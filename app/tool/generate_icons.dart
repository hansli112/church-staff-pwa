// Writes the app icon and the alternate icons supporters can pick, in every
// size Android, iOS and the web need.
//
//   cd app && dart run tool/generate_icons.dart
//
// For now every icon is the drawing in tool/icon.png (a full-bleed 1024
// square; each platform rounds its own corners), until the icon for launch
// is ready. The alternates repaint its paper (and, at night, its ink), so
// the app is still recognizable on the home screen.
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

/// The drawing, and the colour of its paper.
final picture = img.decodePng(File('tool/icon.png').readAsBytesSync())!;
const paper = (244, 237, 225);

typedef Rgb = (num, num, num);

class Variant {
  const Variant(this.id, this.paperTo, {this.inkTo, this.dim = 1});

  /// '' for the default icon.
  final String id;

  /// What the paper becomes.
  final Rgb paperTo;

  /// What black lines become; null keeps them.
  final Rgb? inkTo;

  /// How much the drawing's own colours keep their brightness, when the
  /// ink changes too.
  final double dim;
}

const variants = [
  Variant('', paper),
  Variant('Green', (214, 232, 214)),
  Variant('Purple', (226, 220, 240)),
  Variant('Night', (34, 40, 54), inkTo: (226, 218, 204), dim: 0.62),
];

/// [picture] repainted for [v]: pixels near the paper colour take the new
/// paper, near-black ones the new ink, blending at the edges.
img.Image paint(Variant v) {
  final out = img.Image(width: picture.width, height: picture.height);
  if (v.id.isEmpty) return picture.clone();
  final inkTo = v.inkTo;
  for (final p in out) {
    final s = picture.getPixel(p.x, p.y);
    final r = s.r.toDouble(), g = s.g.toDouble(), b = s.b.toDouble();
    final toPaper = (1 - sqrt(pow(r - paper.$1, 2) + pow(g - paper.$2, 2) + pow(b - paper.$3, 2)) / 60).clamp(0.0, 1.0);
    final toInk = inkTo == null ? 0.0 : (1 - (r + g + b) / 3 / 90).clamp(0.0, 1.0);
    double channel(double c, num paperC, num paperTo, num? inkC) {
      // Light paper keeps its grain, shifted; dark paper replaces it.
      var x = inkTo == null ? c + toPaper * (paperTo - paperC) : c * v.dim * (1 - toPaper) + toPaper * paperTo;
      if (inkC != null) x = x * (1 - toInk) + toInk * inkC;
      return x.clamp(0, 255).toDouble();
    }

    p
      ..r = channel(r, paper.$1, v.paperTo.$1, inkTo?.$1)
      ..g = channel(g, paper.$2, v.paperTo.$2, inkTo?.$2)
      ..b = channel(b, paper.$3, v.paperTo.$3, inkTo?.$3);
  }
  return out;
}

/// [square] with its corners cut, for Android and the web.
img.Image rounded(img.Image square) {
  final size = square.width;
  final mask = img.Image(width: size, height: size, numChannels: 4);
  img.fillRect(
    mask,
    x1: 0,
    y1: 0,
    x2: size - 1,
    y2: size - 1,
    color: img.ColorRgba8(255, 255, 255, 255),
    radius: size * 0.22,
  );
  final out = img.Image(width: size, height: size, numChannels: 4);
  for (final p in out) {
    final s = square.getPixel(p.x, p.y);
    p
      ..r = s.r
      ..g = s.g
      ..b = s.b
      ..a = mask.getPixel(p.x, p.y).a;
  }
  return out;
}

/// [square] inside the middle 80% on its paper: the safe zone of a maskable
/// icon.
img.Image padded(img.Image square, Variant v) {
  final out = img.Image(width: square.width, height: square.height);
  img.fill(out, color: img.ColorRgb8(v.paperTo.$1.round(), v.paperTo.$2.round(), v.paperTo.$3.round()));
  final inner = (square.width * 0.8).round();
  final at = (square.width - inner) ~/ 2;
  img.compositeImage(out, resized(square, inner), dstX: at, dstY: at);
  return out;
}

void write(String path, img.Image image) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(image));
}

img.Image resized(img.Image src, int size) =>
    img.copyResize(src, width: size, height: size, interpolation: img.Interpolation.average);

/// [round] in the middle of Android's 288dp splash icon, small enough for
/// the 192dp circle it is cut to: 132dp, a little under 192/√2, so its
/// corners stay inside. [px] is 6 times the launcher icon's (288dp / 48dp). On the splash's paper only the drawing
/// shows: no circle or edge around it.
img.Image splash(img.Image round, int px) {
  final out = img.Image(width: px, height: px, numChannels: 4);
  final inner = (px * 132 / 288).round();
  final at = (px - inner) ~/ 2;
  img.compositeImage(out, resized(round, inner), dstX: at, dstY: at);
  return out;
}

void main() {
  const android = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
  for (final v in variants) {
    final full = paint(v);
    final round = rounded(full);
    final name = v.id.isEmpty ? 'ic_launcher' : 'ic_launcher_${v.id.toLowerCase()}';
    android.forEach((density, px) {
      write('android/app/src/main/res/mipmap-$density/$name.png', resized(round, px));
      // Every icon starts the app on the default one's paper.
      if (v.id.isEmpty) write('android/app/src/main/res/drawable-$density/splash_icon.png', splash(round, px * 6));
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
      final maskable = padded(full, v);
      write('web/icons/Icon-maskable-192.png', resized(maskable, 192));
      write('web/icons/Icon-maskable-512.png', resized(maskable, 512));
      write('web/favicon.png', resized(round, 64));
      write('assets/icons/app.png', resized(round, 256));
    } else {
      write('assets/icons/${v.id.toLowerCase()}.png', resized(round, 256));
    }
  }
  stdout.writeln('Wrote ${variants.length} icons.');
}
