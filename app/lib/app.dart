import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/design/theme.dart';
import 'l10n/app_localizations.dart';
import 'router.dart';
import 'state/providers.dart';
import 'state/session.dart';

class MarthaApp extends ConsumerWidget {
  const MarthaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(profileBootstrapProvider);
    final router = ref.watch(routerProvider);
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
      // ARB files are added.
      localeResolutionCallback: (device, supported) => supported.first,
      routerConfig: router,
    );
  }
}

/// `zh-Hant` → Locale('zh', 'Hant' script). Null follows the device.
Locale? localeFromTag(String? tag) {
  if (tag == null || tag.isEmpty) return null;
  final parts = tag.split('-');
  return parts.length > 1 ? Locale.fromSubtags(languageCode: parts[0], scriptCode: parts[1]) : Locale(parts[0]);
}
