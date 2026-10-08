import 'dart:async';
import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/core/fonts.dart';

import '../support/harness.dart';

/// An asset bundle whose strings cannot be read.
class _BrokenBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(utf8.encode('not json'));
}

void main() {
  test('the app’s own text comes from its strings, shipped with it', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final text = arbText(await rootBundle.loadString(uiStringsAsset));
    expect(text, contains('馬大別忙'));
    expect(text, contains('切換教會'));
    expect(text, isNot(contains('placeholders')), reason: 'not the strings’ notes');
  });

  testWidgets('the fonts are in once the engine says its fonts changed', (tester) async {
    var done = false;
    unawaited(
      warmUpFonts(bundle: rootBundle, systemFonts: PaintingBinding.instance.systemFonts).then((_) => done = true),
    );
    await tester.pump(const Duration(seconds: 10));
    expect(done, isFalse, reason: 'no limit of its own: the loading screen sets one');
    await sendFontsChange(tester);
    await tester.pump();
    expect(done, isTrue);
  });

  testWidgets('the most used characters come after the app’s own, which the loading screen waits for', (tester) async {
    final laidOut = <String>[];
    var done = false;
    unawaited(
      warmUpFonts(
        bundle: rootBundle,
        systemFonts: PaintingBinding.instance.systemFonts,
        layOut: laidOut.add,
      ).then((_) => done = true),
    );
    // Reading the strings is real I/O.
    await tester.runAsync(() async {
      while (laidOut.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(laidOut, hasLength(1));
    expect(laidOut.single, contains('切換教會'));
    expect(laidOut.single, isNot(contains(commonCharacters)), reason: 'not held up by them');

    await sendFontsChange(tester);
    await tester.pump();
    expect(done, isTrue);
    expect(laidOut.last, commonCharacters);

    await sendFontsChange(tester);
    await tester.pump();
    expect(laidOut, hasLength(2), reason: 'once');
  });

  testWidgets('strings that cannot be read leave the fonts to the first page', (tester) async {
    Object? error;
    var done = false;
    unawaited(
      warmUpFonts(
        bundle: _BrokenBundle(),
        systemFonts: PaintingBinding.instance.systemFonts,
      ).then((_) => done = true, onError: (Object e) => error = e),
    );
    await tester.pump();
    expect(done, isFalse);
    await sendFontsChange(tester);
    await tester.pump();
    expect(done, isTrue);
    expect(error, isNull);
  });
}
