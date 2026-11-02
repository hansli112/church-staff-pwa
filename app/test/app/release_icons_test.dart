import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a patch uses only icons the store release has: its fonts keep only the glyphs it used', () {
    final released = File(
      'tool/release_icons.txt',
    ).readAsLinesSync().where((l) => l.isNotEmpty && !l.startsWith('#')).toSet();
    final icon = RegExp(r'(?<![A-Za-z])(Symbols|Icons|CupertinoIcons)\.[a-z_0-9]+');
    final missing = {
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart'))
          for (final m in icon.allMatches(f.readAsStringSync()))
            if (!released.contains(m[0])) '${m[0]} (${f.path})',
    };
    expect(
      missing,
      isEmpty,
      reason:
          'on phones it shows as a question mark until the next store release; '
          'use one of tool/release_icons.txt, or list it there when releasing',
    );
  });
}
