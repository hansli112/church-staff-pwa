import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/app.dart';
import 'package:martha/core/design/balanced_text.dart';
import 'package:martha/core/design/theme.dart';
import 'package:martha/deferred_pages.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/l10n/app_localizations.dart';
import 'package:martha/state/providers.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Thursday 2026-10-01, 09:00: the time every widget test starts at.
final testNow = DateTime(2026, 10, 1, 9);
final testToday = Day.today(testNow);

/// The clock a test backend runs on unless the test moves time itself.
DateTime testClock() => testNow;

Future<List<Override>> testOverrides(MemoryBackend backend) async {
  // On the real clock, what a test sees would change from day to day.
  if (identical(backend.clock, DateTime.now)) {
    throw ArgumentError('Give the test backend a clock: MemoryBackend(clock: testClock)');
  }
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    backendProvider.overrideWithValue(backend),
    prefsProvider.overrideWithValue(prefs),
  ];
}

/// Pumps the whole app on [backend], phone-sized.
Future<void> pumpApp(
  WidgetTester tester,
  MemoryBackend backend, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
  List<Override> overrides = const [],
}) async {
  // VM deferred snapshots use real async work, not the widget test's fake
  // clock. Download delays/failures are injected at loadPageLibraryProvider;
  // actual web script delivery is checked by the browser smoke test.
  await tester.runAsync(() async {
    for (final library in PageLibrary.values) {
      await library.load();
    }
  });
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...await testOverrides(backend), ...overrides],
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
      overrides: await testOverrides(backend ?? MemoryBackend(clock: testClock)),
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
/// clipboard, recorded instead of reaching the platform. With [blocked], both
/// fail, as in a desktop browser that has no share sheet and refuses the
/// clipboard.
class Outbox {
  final shared = <Map<String, Object?>>[];
  final copied = <String>[];

  List<String> get sharedTexts => [for (final s in shared) ?s['text'] as String?];
}

Outbox captureOutbox(WidgetTester tester, {bool blocked = false}) {
  final out = Outbox();
  final messenger = tester.binding.defaultBinaryMessenger;
  const share = MethodChannel('dev.fluttercommunity.plus/share');
  messenger.setMockMethodCallHandler(share, (call) async {
    if (blocked) throw PlatformException(code: 'unavailable');
    out.shared.add(Map<String, Object?>.from(call.arguments as Map));
    return 'dev.fluttercommunity.plus/share/success';
  });
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData' && blocked) throw PlatformException(code: 'denied');
    if (call.method == 'Clipboard.setData') out.copied.add((call.arguments as Map)['text'] as String);
    return null;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(share, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });
  return out;
}

/// Records URLs the app opens instead of launching a browser.
class FakeUrlLauncher extends Fake with MockPlatformInterfaceMixin implements UrlLauncherPlatform {
  final opened = <String>[];

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return true;
  }
}

FakeUrlLauncher captureLaunches() {
  final previous = UrlLauncherPlatform.instance;
  final fake = FakeUrlLauncher();
  UrlLauncherPlatform.instance = fake;
  addTearDown(() => UrlLauncherPlatform.instance = previous);
  return fake;
}

/// What the web engine sends once a round of font downloads is done.
Future<void> sendFontsChange(WidgetTester tester) => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
  SystemChannels.system.name,
  SystemChannels.system.codec.encodeMessage({'type': 'fontsChange'}),
  (_) {},
);

/// [text] as shown, also by a [BalancedText], which joins the characters
/// inside 「」 with invisible joiners so the term stays on one line.
Finder findShown(String text) =>
    find.byWidgetPredicate((w) => (w is Text && w.data == text) || (w is BalancedText && w.text == text));

/// Text shown that contains [part], as [findShown].
Finder findShownContaining(String part) => find.byWidgetPredicate(
  (w) => (w is Text && (w.data?.contains(part) ?? false)) || (w is BalancedText && w.text.contains(part)),
);
