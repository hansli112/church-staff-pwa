import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/design/theme.dart';
import 'l10n/app_localizations.dart';
import 'router.dart';
import 'state/providers.dart';
import 'state/push.dart';
import 'state/session.dart';

/// Lets app-wide events (a notification arriving) show a toast without a
/// screen's context.
final _messenger = GlobalKey<ScaffoldMessengerState>();

class MarthaApp extends ConsumerWidget {
  const MarthaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(sessionEffectsProvider);
    final router = ref.watch(routerProvider);
    // A tapped notification opens the page it is about.
    ref.listen(pushLinksProvider, (_, link) {
      final l = link.value;
      if (l != null && l.startsWith('/')) router.go(l);
    });
    // In front, the system shows nothing: say it here, with a way to open it.
    ref.listen(pushNoticesProvider, (_, notice) {
      final n = notice.value;
      final messenger = _messenger.currentState;
      if (n == null || messenger == null) return;
      final link = n.link;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(n.title.isEmpty ? n.body : '${n.title}：${n.body}'),
            duration: const Duration(seconds: 8),
            persist: false,
            action: link == null || !link.startsWith('/')
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
