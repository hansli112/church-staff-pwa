import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/app.dart';
import 'package:martha/core/design/theme.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/l10n/app_localizations.dart';
import 'package:martha/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thursday 2026-10-01: the "today" every widget test runs on.
final testToday = Day(2026, 10, 1);

Future<List<Override>> testOverrides(MemoryBackend backend) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    backendProvider.overrideWithValue(backend),
    prefsProvider.overrideWithValue(prefs),
    todayProvider.overrideWithValue(testToday),
  ];
}

/// Pumps the whole app on [backend], phone-sized.
Future<void> pumpApp(
  WidgetTester tester,
  MemoryBackend backend, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    ProviderScope(
      overrides: await testOverrides(backend),
      retry: (_, _) => null,
      child: const MarthaApp(),
    ),
  );
  await settle(tester);
}

/// Pumps a single widget inside the app theme and localizations.
Future<void> pumpWidgetInApp(
  WidgetTester tester,
  Widget child, {
  MemoryBackend? backend,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  TargetPlatform platform = TargetPlatform.iOS,
}) async {
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: await testOverrides(backend ?? MemoryBackend()),
      retry: (_, _) => null,
      child: MaterialApp(
        theme: buildTheme(brightness).copyWith(platform: platform),
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: Scaffold(body: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Lets streams deliver and animations finish, without waiting forever on
/// an indeterminate spinner.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// What the app shared through the system share sheet and copied to the
/// clipboard, recorded instead of reaching the platform.
class Outbox {
  final shared = <Map<String, Object?>>[];
  final copied = <String>[];

  List<String> get sharedTexts => [for (final s in shared) ?s['text'] as String?];
}

Outbox captureOutbox(WidgetTester tester) {
  final out = Outbox();
  final messenger = tester.binding.defaultBinaryMessenger;
  const share = MethodChannel('dev.fluttercommunity.plus/share');
  messenger.setMockMethodCallHandler(share, (call) async {
    out.shared.add(Map<String, Object?>.from(call.arguments as Map));
    return 'dev.fluttercommunity.plus/share/success';
  });
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') out.copied.add((call.arguments as Map)['text'] as String);
    return null;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(share, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });
  return out;
}
