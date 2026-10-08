import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/core/fonts.dart';

/// An asset bundle with nothing in it.
class _EmptyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => Future.error(FlutterError('no $key'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the app’s own text comes from its strings, shipped with it', () async {
    final text = uiText(await rootBundle.loadString(uiStringsAsset));
    expect(text, contains('馬大別忙'));
    expect(text, contains('切換教會'));
    expect(text, isNot(contains('placeholders')), reason: 'not the strings’ notes');
  });

  test('the fonts are in once the engine says its fonts changed', () {
    fakeAsync((async) {
      final fonts = ChangeNotifier();
      var done = false;
      warmUpFonts(bundle: rootBundle, systemFonts: fonts).then((_) => done = true);
      async.elapse(const Duration(milliseconds: 500));
      expect(done, isFalse);
      fonts.notifyListeners();
      async.flushMicrotasks();
      expect(done, isTrue);
    });
  });

  test('fonts that never come stop holding things up after a while', () {
    fakeAsync((async) {
      var done = false;
      warmUpFonts(bundle: rootBundle, systemFonts: ChangeNotifier()).then((_) => done = true);
      async.elapse(fontsWaitLimit - const Duration(milliseconds: 1));
      expect(done, isFalse);
      async.elapse(const Duration(milliseconds: 1));
      expect(done, isTrue);
    });
  });

  test('without the strings, it still waits for the fonts the first page asks for', () {
    fakeAsync((async) {
      final fonts = ChangeNotifier();
      Object? error;
      var done = false;
      warmUpFonts(
        bundle: _EmptyBundle(),
        systemFonts: fonts,
      ).then((_) => done = true, onError: (Object e) => error = e);
      async.elapse(const Duration(milliseconds: 100));
      expect(done, isFalse);
      fonts.notifyListeners();
      async.flushMicrotasks();
      expect(done, isTrue);
      expect(error, isNull);
    });
  });
}
