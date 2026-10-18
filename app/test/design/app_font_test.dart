import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/core/design/theme.dart';
import 'package:martha/core/design/tokens.dart';
import 'package:flutter/material.dart';

void main() {
  ThemeData themeOn(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    try {
      return buildTheme(Brightness.light);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  test('on Android every text, components too, is in Martha Latin', () {
    final theme = themeOn(TargetPlatform.android);
    expect(theme.textTheme.bodyLarge!.fontFamily, 'Martha Latin');
    expect(theme.appBarTheme.titleTextStyle!.fontFamily, 'Martha Latin');
    expect(theme.listTileTheme.titleTextStyle!.fontFamily, 'Martha Latin');
    expect(theme.inputDecorationTheme.hintStyle!.fontFamily, 'Martha Latin');
  });

  test("on iOS the system's font", () {
    final theme = themeOn(TargetPlatform.iOS);
    expect(theme.textTheme.bodyLarge!.fontFamily, isNot('Martha Latin'));
    expect(theme.appBarTheme.titleTextStyle!.fontFamily, isNull);
  });

  test('an app without the font file (patched over an older release) still starts', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await loadAppFont(bundle: _NoFiles());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

class _NoFiles extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => Future.error(FlutterError('Unable to load asset: $key'));
}
