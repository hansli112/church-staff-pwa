import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/design/components.dart';
import 'l10n/app_localizations.dart';

import 'features/admin/admin_screens.dart' deferred as admin_screens;
import 'features/calendar/calendar_settings_screen.dart' deferred as calendar_settings;
import 'features/church/move_screen.dart' deferred as move_screen;
import 'features/me/church_info_screen.dart' deferred as church_info;
import 'features/rosters/import_screen.dart' deferred as roster_import;

/// Screen code fetched only when its page is opened. Native builds keep it
/// in the app; the web build downloads a separate script.
enum PageLibrary {
  admin,
  calendarSettings,
  churchInfo,
  move,
  rosterImport
  ;

  Future<void> load() => switch (this) {
    admin => admin_screens.loadLibrary(),
    calendarSettings => calendar_settings.loadLibrary(),
    churchInfo => church_info.loadLibrary(),
    move => move_screen.loadLibrary(),
    rosterImport => roster_import.loadLibrary(),
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
    builder: (_) => calendar_settings.CalendarSettingsScreen(result: result),
  );

  factory DeferredPage.rosterImport({Key? key, required String serviceType}) => DeferredPage._(
    key: key,
    library: PageLibrary.rosterImport,
    builder: (_) => roster_import.ImportScreen(serviceType: serviceType),
  );

  const DeferredPage._({super.key, required this.library, required WidgetBuilder builder}) : _builder = builder;

  final PageLibrary library;
  final WidgetBuilder _builder;

  static Widget _admin(BuildContext context) => admin_screens.AdminScreen();
  static Widget _adminStats(BuildContext context) => admin_screens.AdminStatsScreen();
  static Widget _adminFunding(BuildContext context) => admin_screens.AdminFundingScreen();
  static Widget _churchInfo(BuildContext context) => church_info.ChurchInfoScreen();
  static Widget _move(BuildContext context) => move_screen.MoveScreen();

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
              icon: const Icon(Icons.home_outlined),
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
