import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/design/components.dart';
import 'l10n/app_localizations.dart';

import 'page_code_native.dart' if (dart.library.js_interop) 'page_code_web.dart' as code;

/// Screen code fetched only when its page is opened: on the web a separate
/// script; native builds have it in the app (page_code_native.dart says why
/// they don't defer it).
enum PageLibrary {
  admin,
  calendarSettings,
  churchInfo,
  move,
  rosterImport
  ;

  Future<void> load() => switch (this) {
    admin => code.loadAdmin(),
    calendarSettings => code.loadCalendarSettings(),
    churchInfo => code.loadChurchInfo(),
    move => code.loadMove(),
    rosterImport => code.loadRosterImport(),
  };

  /// The cold-link destinations registered in router.dart. Keep new
  /// deferred routes here too, so the splash waits for their actual page.
  static PageLibrary? forLocation(Uri location) {
    final path = location.path;
    if (const {'/admin', '/admin/stats', '/admin/funding'}.contains(path)) return admin;
    if (path == '/me/church') return churchInfo;
    if (path == '/me/calendar') return calendarSettings;
    if (path == '/welcome/move') return move;
    if (path.startsWith('/rosters/import/')) return rosterImport;
    return null;
  }
}

/// The browser's code download, separate from the page's data reads.
final loadPageLibraryProvider = Provider<Future<void> Function(PageLibrary)>(
  (_) =>
      (library) => library.load(),
);

final pageLibraryProvider = FutureProvider.family<void, PageLibrary>(
  (ref, library) => ref.watch(loadPageLibraryProvider)(library).timeout(const Duration(seconds: 15)),
);

/// Keeps the route and its back button available while its code downloads.
class DeferredPage extends ConsumerWidget {
  const DeferredPage.admin({super.key}) : library = PageLibrary.admin, _builder = _admin;
  const DeferredPage.adminStats({super.key}) : library = PageLibrary.admin, _builder = _adminStats;
  const DeferredPage.adminFunding({super.key}) : library = PageLibrary.admin, _builder = _adminFunding;
  const DeferredPage.churchInfo({super.key}) : library = PageLibrary.churchInfo, _builder = _churchInfo;
  const DeferredPage.move({super.key}) : library = PageLibrary.move, _builder = _move;

  factory DeferredPage.calendarSettings({Key? key, String? result}) => DeferredPage._(
    key: key,
    library: PageLibrary.calendarSettings,
    builder: (_) => code.calendarSettingsScreen(result),
  );

  factory DeferredPage.rosterImport({Key? key, required String serviceType}) => DeferredPage._(
    key: key,
    library: PageLibrary.rosterImport,
    builder: (_) => code.importScreen(serviceType),
  );

  const DeferredPage._({super.key, required this.library, required WidgetBuilder builder}) : _builder = builder;

  final PageLibrary library;
  final WidgetBuilder _builder;

  static Widget _admin(BuildContext context) => code.adminScreen();
  static Widget _adminStats(BuildContext context) => code.adminStatsScreen();
  static Widget _adminFunding(BuildContext context) => code.adminFundingScreen();
  static Widget _churchInfo(BuildContext context) => code.churchInfoScreen();
  static Widget _move(BuildContext context) => code.moveScreen();

  AppBar _appBar(BuildContext context) {
    final l10n = L10n.of(context);
    return AppBar(
      title: Text(switch (library) {
        PageLibrary.admin => l10n.operatorConsole,
        PageLibrary.calendarSettings => l10n.calendarSetting,
        PageLibrary.churchInfo => l10n.churchInfo,
        PageLibrary.move => l10n.moveFromSelfHost,
        PageLibrary.rosterImport => l10n.photoImport,
      }),
      leading: context.canPop()
          ? null
          : IconButton(
              tooltip: l10n.goHome,
              icon: const Icon(Symbols.home_rounded),
              onPressed: () => context.go('/home'),
            ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(pageLibraryProvider(library))
      .when(
        skipLoadingOnRefresh: false,
        data: (_) => _builder(context),
        error: (_, _) => Scaffold(
          appBar: _appBar(context),
          body: ErrorRetry(
            message: L10n.of(context).loadFailed,
            onRetry: () => ref.invalidate(pageLibraryProvider(library)),
          ),
        ),
        loading: () => Scaffold(
          appBar: _appBar(context),
          body: const Align(alignment: Alignment.topCenter, child: LinearProgressIndicator()),
        ),
      );
}
