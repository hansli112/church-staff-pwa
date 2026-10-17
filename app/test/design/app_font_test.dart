import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/core/design/theme.dart';
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
}
