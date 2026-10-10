import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/design/theme.dart';
import 'core/fonts.dart';
import 'deep_link.dart';
import 'deferred_pages.dart';
import 'l10n/app_localizations.dart';
import 'router.dart';
import 'state/fonts.dart';
import 'state/providers.dart';
import 'state/push.dart';
import 'state/session.dart';
import 'state/web_page.dart';

/// Lets app-wide events (a notification arriving) show a toast without a
/// screen's context.
final _messenger = GlobalKey<ScaffoldMessengerState>();

class MarthaApp extends ConsumerStatefulWidget {
  const MarthaApp({super.key});

  @override
  ConsumerState<MarthaApp> createState() => _MarthaAppState();
}

class _MarthaAppState extends ConsumerState<MarthaApp> {
  GoRouter? _router;
  bool _splashHidden = false;
  Future<void>? _fontsSettled;
  int _drawAttempt = 0;

  void _routeChanged() => unawaited(_hideSplashOnceDrawn());

  // Fonts and the current destination's code load together. A download
  // error is a usable page too: dismiss the splash so retry can be reached.
  Future<void> _hideSplashOnceDrawn() async {
    if (_splashHidden) return;
    final attempt = ++_drawAttempt;
    if (ref.read(appStageProvider) == AppStage.loading) return;
    await (_fontsSettled ??= ref.read(fontsReadyProvider).timeout(fontsWaitLimit, onTimeout: () {}));
    if (!mounted || attempt != _drawAttempt) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || attempt != _drawAttempt) return;
    final router = _router!;
    final location = router.routerDelegate.currentConfiguration.uri;
    if (location.path == '/loading') return;
    final library = PageLibrary.forLocation(location);
    if (library != null) {
      try {
        await ref.read(pageLibraryProvider(library).future);
      } catch (_) {
        // DeferredPage shows the download error with a retry button.
      }
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        attempt != _drawAttempt ||
        ref.read(appStageProvider) == AppStage.loading ||
        router.routerDelegate.currentConfiguration.uri != location) {
      return;
    }
    _splashHidden = true;
    ref.read(hideSplashProvider)();
    ref.read(onFirstPageDrawnProvider)();
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_routeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sessionEffectsProvider);
    final router = ref.watch(routerProvider);
    if (_router != router) {
      _router?.routerDelegate.removeListener(_routeChanged);
      _router = router;
      router.routerDelegate.addListener(_routeChanged);
    }
    ref.listen(appStageProvider, (_, _) => _routeChanged());
    _routeChanged();
    // A tapped notification opens the page it is about.
    ref.listen(pushLinksProvider, (_, link) {
      final l = appLocation(link.value);
      if (l != null) router.go(l);
    });
    // In front, the system shows nothing: say it here, with a way to open it.
    ref.listen(pushNoticesProvider, (_, notice) {
      final n = notice.value;
      final messenger = _messenger.currentState;
      if (n == null || messenger == null) return;
      final link = appLocation(n.link);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(n.title.isEmpty ? n.body : '${n.title}：${n.body}'),
            duration: const Duration(seconds: 8),
            persist: false,
            action: link == null
                ? null
                : SnackBarAction(label: L10n.of(messenger.context).pushView, onPressed: () => router.go(link)),
          ),
        );
    });
    final locale = ref.watch(profileProvider.select((p) => p.value?.locale));
    return MaterialApp.router(
      onGenerateTitle: (context) => L10n.of(context).appName,
      debugShowCheckedModeBanner: false,
      // --dart-define=PERF_HUD=true shows frame timings (raster and UI threads).
      showPerformanceOverlay: const bool.fromEnvironment('PERF_HUD'),
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      locale: localeFromTag(locale),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      // Only Traditional Chinese for now; every device gets it until other
      // ARB files are added. With the script and region, not plain `zh`,
      // which gives Flutter's own labels (close, date picker) in Simplified.
      localeResolutionCallback: (device, supported) =>
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
      routerConfig: router,
      scaffoldMessengerKey: _messenger,
      builder: (context, child) => _Column(child: child!),
    );
  }
}

/// On a wide window (a desktop browser) the app keeps a phone-to-tablet
/// width in the middle instead of stretching rows and toasts edge to edge.
/// Dialogs and sheets open inside it too.
class _Column extends StatelessWidget {
  const _Column({required this.child});

  static const maxWidth = 640.0;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.width <= maxWidth) return child;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: SizedBox(
          width: maxWidth,
          child: MediaQuery(
            data: mq.copyWith(size: Size(maxWidth, mq.size.height)),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// `zh-Hant` → Locale('zh', 'Hant' script). Null follows the device.
Locale? localeFromTag(String? tag) {
  if (tag == null || tag.isEmpty) return null;
  final parts = tag.split('-');
  return parts.length > 1 ? Locale.fromSubtags(languageCode: parts[0], scriptCode: parts[1]) : Locale(parts[0]);
}
