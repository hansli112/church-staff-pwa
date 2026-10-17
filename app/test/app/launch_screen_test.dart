import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Android launch screen is the icon's paper, which tool/generate_icons.dart
/// keeps in its `paper`; a launch screen of another beige shows an edge.
void main() {
  test("the launch screen's beige is the icon's paper", () {
    final paper = RegExp(
      r'const paper = \((\d+), (\d+), (\d+)\);',
    ).firstMatch(File('tool/generate_icons.dart').readAsStringSync())!;
    final hex = [
      for (var i = 1; i <= 3; i++) int.parse(paper[i]!).toRadixString(16).padLeft(2, '0'),
    ].join().toUpperCase();
    final colors = File('android/app/src/main/res/values/colors.xml').readAsStringSync();
    expect(colors, contains('<color name="splash">#$hex</color>'));
  });

  test('every Android version and both themes start on it, with the splash icon', () {
    for (final theme in ['values-v31', 'values-night-v31']) {
      final styles = File('android/app/src/main/res/$theme/styles.xml').readAsStringSync();
      expect(styles, contains('<item name="android:windowSplashScreenBackground">@color/splash</item>'), reason: theme);
      expect(
        styles,
        contains('<item name="android:windowSplashScreenAnimatedIcon">@drawable/splash_icon</item>'),
        reason: theme,
      );
    }
    final older = File('android/app/src/main/res/drawable/launch_background.xml').readAsStringSync();
    expect(older, contains('@color/splash'));
    expect(older, contains('@drawable/splash_icon'));
  });
}
