import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/design/components.dart';
import 'core/design/theme.dart';
import 'core/fonts.dart';
import 'core/builtin_localizations.dart';
import 'core/languages.dart';
import 'deep_link.dart';
import 'deferred_pages.dart';
import 'features/common/update_required.dart';
import 'l10n/app_localizations.dart';
import 'router.dart';
import 'state/fonts.dart';
import 'state/calendar.dart';
import 'state/providers.dart';
import 'state/push.dart';
import 'state/saved_read.dart';
import 'state/session.dart';
import 'state/support.dart';
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
    ref.watch(calendarCacheLifecycleProvider);
    ref.watch(savedReadsProvider);
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
            content: Text(n.title.isEmpty ? n.body : L10n.of(messenger.context).labelValue(n.title, n.body)),
            duration: const Duration(seconds: 8),
            persist: false,
            action: link == null
                ? null
                : SnackBarAction(label: L10n.of(messenger.context).pushView, onPressed: () => router.go(link)),
          ),
        );
    });
    // A church's own icon, put on the home screen on its own: say so, with
    // the way back.
    ref.listen(churchIconChangedProvider, (_, icon) {
      final context = router.routerDelegate.navigatorKey.currentContext;
      if (icon == null || context == null) return;
      showToast(
        context,
        L10n.of(context).churchIconChanged(icon.name),
        duration: const Duration(seconds: 8),
        onUndo: () => ref.read(currentAppIconProvider.notifier).set(null),
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
      // The one chosen, else the device's (AppLanguage.resolve).
      locale: AppLanguage.fromTag(locale)?.locale,
      supportedLocales: [for (final l in AppLanguage.values) l.locale],
      localizationsDelegates: const [
        L10n.delegate,
        ...builtinLocalizationsDelegates,
      ],
      localeListResolutionCallback: (device, _) => AppLanguage.resolve(device ?? const []).locale,
      routerConfig: router,
      scaffoldMessengerKey: _messenger,
      builder: (context, child) => _LanguageShown(
        child: _Column(child: UpdateRequiredGate(child: child!)),
      ),
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

/// Keeps users/{uid}.appLocale on the language shown, chosen or the
/// device's, for the server's pushes; written only when it changes. Kept on
/// this device too ([shownLanguagePref]).
class _LanguageShown extends ConsumerStatefulWidget {
  const _LanguageShown({required this.child});

  final Widget child;

  @override
  ConsumerState<_LanguageShown> createState() => _LanguageShownState();
}

class _LanguageShownState extends ConsumerState<_LanguageShown> {
  (String, String)? _sent;

  @override
  Widget build(BuildContext context) {
    final tag = AppLanguage.shownIn(context).tag;
    final prefs = ref.read(prefsProvider);
    if (prefs.getString(shownLanguagePref) != tag) unawaited(prefs.setString(shownLanguagePref, tag));
    final profile = ref.watch(profileProvider).value;
    if (profile != null && profile.appLocale != tag && _sent != (profile.uid, tag)) {
      _sent = (profile.uid, tag);
      final profiles = ref.read(backendProvider).profiles;
      // Best effort: on failure (offline), the next change of profile or
      // language tries again.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(profiles.setAppLocale(profile.uid, tag).catchError((_) => _sent = null)),
      );
    }
    return widget.child;
  }
}
