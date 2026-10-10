import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/core/fonts.dart';

import '../support/fonts.dart';
import '../support/harness.dart';

/// An asset bundle whose strings cannot be read.
class _BrokenBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(utf8.encode('not json'));
}

class _DelayedBundle extends CachingAssetBundle {
  final contents = Completer<ByteData>();

  @override
  Future<ByteData> load(String key) => contents.future;

  void complete(String json) => contents.complete(ByteData.sublistView(utf8.encode(json)));
}

class _SystemFonts extends ChangeNotifier {
  bool get waiting => hasListeners;
}

void main() {
  test('the app’s own text comes from its strings, shipped with it', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final text = arbText(await rootBundle.loadString(uiStringsAsset));
    expect(text, contains('馬大別忙'));
    expect(text, contains('切換教會'));
    expect(text, isNot(contains('placeholders')), reason: 'not the strings’ notes');
  }, skip: kIsWeb);

  testWidgets('startup warms the first pages without paying for admin or photo-import text', (tester) async {
    final laidOut = <String>[];
    unawaited(
      warmUpFonts(
        bundle: UiStringsBundle(),
        systemFonts: PaintingBinding.instance.systemFonts,
        startupOnly: true,
        layOut: laidOut.add,
      ),
    );
    await tester.pump();
    expect(laidOut.single, contains('馬大別忙'));
    expect(laidOut.single, contains('使用 Google 登入'));
    expect(laidOut.single, contains('我接下來的服事'));
    expect(laidOut.single, contains('切換教會'));
    expect(laidOut.single, isNot(contains('估計費用（USD）')));
    expect(laidOut.single, isNot(contains('辨識中，大約需要一分鐘')));
    await sendFontsChange(tester);
    await tester.pump();
  });

  testWidgets('the fonts are in once the engine says its fonts changed', (tester) async {
    final laidOut = <String>[];
    var done = false;
    unawaited(
      warmUpFonts(
        bundle: UiStringsBundle(),
        systemFonts: PaintingBinding.instance.systemFonts,
        layOut: laidOut.add,
      ).then((_) => done = true),
    );
    await tester.pump();
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
        bundle: UiStringsBundle(),
        systemFonts: PaintingBinding.instance.systemFonts,
        layOut: laidOut.add,
      ).then((_) => done = true),
    );
    await tester.pump();
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

  testWidgets('background character fonts wait until the first usable frame, not just startup fonts', (tester) async {
    final laidOut = <String>[];
    final firstFrame = Completer<void>();
    var done = false;
    unawaited(
      warmUpFonts(
        bundle: UiStringsBundle(),
        systemFonts: PaintingBinding.instance.systemFonts,
        afterFirstFrame: firstFrame.future,
        layOut: laidOut.add,
      ).then((_) => done = true),
    );
    await tester.pump();
    await sendFontsChange(tester);
    await tester.pump();
    expect(done, isTrue, reason: 'startup readiness does not wait for background fonts');
    expect(laidOut, hasLength(1));
    firstFrame.complete();
    await tester.pump();
    expect(laidOut.last, commonCharacters);
    await sendFontsChange(tester);
    await tester.pump();
    expect(laidOut, hasLength(2), reason: 'background warmup runs once');
  });

  testWidgets('an unrelated font change before the text is read does not release readiness', (tester) async {
    final bundle = _DelayedBundle();
    final fonts = ChangeNotifier();
    addTearDown(fonts.dispose);
    final laidOut = <String>[];
    var done = false;
    unawaited(warmUpFonts(bundle: bundle, systemFonts: fonts, layOut: laidOut.add).then((_) => done = true));
    fonts.notifyListeners();
    await tester.pump();
    expect(done, isFalse);
    expect(laidOut, isEmpty);
    bundle.complete('{"appName":"馬大別忙"}');
    await tester.pump();
    expect(laidOut, ['馬大別忙']);
    expect(done, isFalse);
    fonts.notifyListeners();
    await tester.pump();
    expect(done, isTrue);
  });

  testWidgets('the first drawn frame releases a timed-out warmup and ignores a late text read', (tester) async {
    final bundle = _DelayedBundle();
    final fonts = _SystemFonts();
    addTearDown(fonts.dispose);
    final firstFrame = Completer<void>();
    final laidOut = <String>[];
    var done = false;
    var timedOut = false;
    final ready = warmUpFonts(
      bundle: bundle,
      systemFonts: fonts,
      afterFirstFrame: firstFrame.future,
      layOut: laidOut.add,
    );
    unawaited(ready.then((_) => done = true));
    unawaited(ready.timeout(fontsWaitLimit, onTimeout: () => timedOut = true));
    await tester.pump(fontsWaitLimit);
    expect(timedOut, isTrue);
    expect(done, isFalse);
    firstFrame.complete();
    await tester.pump();
    expect(done, isTrue);
    expect(fonts.waiting, isFalse);
    expect(laidOut, [commonCharacters]);
    bundle.complete('{"appName":"馬大別忙"}');
    await tester.pump();
    expect(laidOut, [commonCharacters], reason: 'the visible page already requested its own text');
  });

  testWidgets('an asset without startup text leaves font fetching to the page instead of holding readiness', (
    tester,
  ) async {
    final bundle = _DelayedBundle();
    final fonts = _SystemFonts();
    addTearDown(fonts.dispose);
    final firstFrame = Completer<void>();
    final laidOut = <String>[];
    var done = false;
    unawaited(
      warmUpFonts(
        bundle: bundle,
        systemFonts: fonts,
        startupOnly: true,
        afterFirstFrame: firstFrame.future,
        layOut: laidOut.add,
      ).then((_) => done = true),
    );
    bundle.complete('{"photoRecognizing":"辨識中，大約需要一分鐘"}');
    await tester.pump();
    expect(done, isTrue);
    expect(laidOut, isEmpty);
    expect(fonts.waiting, isFalse);
    firstFrame.complete();
    await tester.pump();
    expect(laidOut, [commonCharacters]);
  });

  testWidgets('unreadable strings release readiness without waiting for a font download that cannot start', (
    tester,
  ) async {
    final fonts = _SystemFonts();
    addTearDown(fonts.dispose);
    final firstFrame = Completer<void>();
    Object? error;
    var done = false;
    unawaited(
      warmUpFonts(
        bundle: _BrokenBundle(),
        systemFonts: fonts,
        afterFirstFrame: firstFrame.future,
      ).then((_) => done = true, onError: (Object e) => error = e),
    );
    await tester.pump();
    expect(done, isTrue);
    expect(fonts.waiting, isFalse, reason: 'the first page will request its own fonts');
    expect(error, isNull);
    firstFrame.complete();
    await tester.pump();
  });
}
