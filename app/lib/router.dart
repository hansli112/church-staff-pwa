import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'env.dart';
import 'features/admin/admin_screens.dart';
import 'features/auth/login_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/church/closed_screen.dart';
import 'features/church/join_screen.dart';
import 'features/church/welcome_screen.dart';
import 'features/dev/component_gallery.dart';
import 'features/home/home_screen.dart';
import 'features/me/account_screen.dart';
import 'features/me/church_info_screen.dart';
import 'features/me/invites_screen.dart';
import 'features/me/me_screen.dart';
import 'features/me/member_editor_screen.dart';
import 'features/me/members_screen.dart';
import 'features/me/notifications_screen.dart';
import 'features/me/profile_screen.dart';
import 'features/me/services_screen.dart';
import 'features/rosters/roster_day_screen.dart';
import 'features/rosters/rosters_screen.dart';
import 'features/shell/shell.dart';
import 'state/providers.dart';

/// Re-runs the router's redirect whenever the app stage changes.
class _StageListenable extends ChangeNotifier {
  _StageListenable(Ref ref) {
    ref.listen(appStageProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _StageListenable(ref);
  ref.onDispose(refresh.dispose);
  GoRoute page(
    String path,
    Widget Function(GoRouterState s) build, {
    List<RouteBase> routes = const [],
  }) => GoRoute(path: path, builder: (_, s) => build(s), routes: routes);
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) => redirectFor(ref.read(appStageProvider), state.uri),
    routes: [
      page('/loading', (_) => const LoadingScreen()),
      page('/login', (_) => const LoginScreen()),
      page(
        '/welcome',
        (_) => const WelcomeScreen(),
        routes: [
          page('join', (_) => const EnterCodeScreen()),
          page('create', (_) => const CreateChurchScreen()),
        ],
      ),
      page('/join/:code', (s) => JoinScreen(code: s.pathParameters['code']!)),
      page('/closed', (_) => const ClosedScreen()),
      page('/account', (_) => const AccountScreen()),
      page(
        '/admin',
        (_) => const AdminScreen(),
        routes: [page('stats', (_) => const AdminStatsScreen())],
      ),
      if (Env.current.isDevelopment) page('/dev/components', (_) => const ComponentGallery()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [page('/home', (_) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [
              page(
                '/rosters',
                (_) => const RostersScreen(),
                routes: [
                  page(
                    ':type/:day',
                    (s) => RosterDayScreen(
                      serviceType: s.pathParameters['type']!,
                      dayKey: s.pathParameters['day']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [page('/calendar', (_) => const CalendarScreen())],
          ),
          StatefulShellBranch(
            routes: [
              page(
                '/me',
                (_) => const MeScreen(),
                routes: [
                  page('profile', (_) => const ProfileScreen()),
                  page('language', (_) => const LanguageScreen()),
                  page('church', (_) => const ChurchInfoScreen()),
                  page('notifications', (_) => const NotificationsScreen()),
                  page('invites', (_) => const InvitesScreen()),
                  page(
                    'members',
                    (_) => const MembersScreen(),
                    routes: [
                      page(
                        ':uid',
                        (s) => MemberEditorScreen(uid: s.pathParameters['uid']!),
                      ),
                    ],
                  ),
                  page(
                    'services',
                    (_) => const ServicesScreen(),
                    routes: [
                      page(
                        ':id',
                        (s) => ServiceEditorScreen(
                          serviceId: s.pathParameters['id']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Where to send someone at [uri] given the app [stage]; null stays.
///
/// A redirect away from the page someone asked for (an invite link, a deep
/// link) carries it in `from`, so they land there once signed in.
@visibleForTesting
String? redirectFor(AppStage stage, Uri uri) {
  final path = uri.path;
  bool at(String prefix) => path == prefix || path.startsWith('$prefix/');
  final from = uri.queryParameters['from'];

  String withFrom(String target) {
    final keep = from ?? (at('/loading') || at('/login') ? null : uri.toString());
    return keep == null ? target : '$target?from=${Uri.encodeComponent(keep)}';
  }

  /// Leaves a waiting page for [from] if this stage allows it.
  String? resume(String fallback) {
    if (from != null) {
      final target = Uri.parse(from);
      final again = redirectFor(stage, target);
      return again ?? target.toString();
    }
    return fallback;
  }

  switch (stage) {
    case AppStage.loading:
      return at('/loading') ? null : withFrom('/loading');
    case AppStage.signedOut:
      if (at('/login')) return null;
      if (at('/loading')) {
        return from == null ? '/login' : '/login?from=${Uri.encodeComponent(from)}';
      }
      return withFrom('/login');
    case AppStage.noChurch:
      if (at('/welcome') || at('/join') || at('/account') || at('/dev')) {
        return null;
      }
      if (at('/loading') || at('/login')) return resume('/welcome');
      return '/welcome';
    case AppStage.churchClosed:
      if (at('/closed') || at('/join') || at('/account') || at('/welcome') || at('/dev')) {
        return null;
      }
      if (at('/loading') || at('/login')) return resume('/closed');
      return '/closed';
    case AppStage.ready:
      if (at('/loading') || at('/login') || at('/welcome') || at('/closed')) {
        return resume('/home');
      }
      return null;
  }
}

/// Shown for the moment before the first auth state arrives. Just the
/// background: no full-screen spinner.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}
