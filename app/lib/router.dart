import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'deep_link.dart';
import 'env.dart';
import 'features/admin/admin_screens.dart';
import 'features/auth/login_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/calendar/calendar_settings_screen.dart';
import 'features/church/church_entry_screen.dart';
import 'features/church/closed_screen.dart';
import 'features/church/join_screen.dart';
import 'features/church/move_screen.dart';
import 'features/church/welcome_screen.dart';
import 'features/dev/component_gallery.dart';
import 'features/home/home_screen.dart';
import 'features/me/account_screen.dart';
import 'features/me/church_info_screen.dart';
import 'features/me/church_link_screen.dart';
import 'features/me/invites_screen.dart';
import 'features/me/me_screen.dart';
import 'features/me/member_editor_screen.dart';
import 'features/me/members_screen.dart';
import 'features/me/notifications_screen.dart';
import 'features/me/profile_screen.dart';
import 'features/me/services_screen.dart';
import 'features/me/support_screen.dart';
import 'features/me/webhook_screen.dart';
import 'features/rosters/event_roster_screen.dart';
import 'features/rosters/import_screen.dart';
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
    redirect: (context, state) {
      // Done here, before any page is built, so the shell is never pushed
      // twice when a church URL switches church.
      final target = resolveLink(
        ref.read(appStageProvider),
        ref.read(membershipsProvider).value ?? const [],
        state.uri,
      );
      final church = target.church;
      if (church != null) {
        // After this redirect: changing the church now would rebuild the
        // app stage twice in one frame.
        scheduleMicrotask(() => ref.read(selectedChurchProvider.notifier).select(church));
      }
      return target.location;
    },
    routes: [
      page('/loading', (_) => const LoadingScreen()),
      page('/login', (s) => LoginScreen(from: s.uri.queryParameters['from'])),
      page(
        '/welcome',
        (_) => const WelcomeScreen(),
        routes: [
          page(
            'join',
            (_) => const EnterCodeScreen(),
            routes: [page(':code', (s) => JoinScreen(code: s.pathParameters['code']!))],
          ),
          page('create', (_) => const CreateChurchScreen()),
          page('move', (_) => const MoveScreen()),
        ],
      ),
      page(
        '/c/:churchId',
        (s) => ChurchEntryScreen(churchId: s.pathParameters['churchId']!),
        // An invite link. The code decides the church, not the URL.
        routes: [page('join/:code', (s) => JoinScreen(code: s.pathParameters['code']!))],
      ),
      page('/closed', (_) => const ClosedScreen()),
      page('/account', (_) => const AccountScreen()),
      page(
        '/admin',
        (_) => const AdminScreen(),
        routes: [
          page('stats', (_) => const AdminStatsScreen()),
          page('funding', (_) => const AdminFundingScreen()),
        ],
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
                  page('import/:type', (s) => ImportScreen(serviceType: s.pathParameters['type']!)),
                  // Before :type/:day, which would take it for a service.
                  page('event/:id', (s) => EventRosterScreen(eventId: s.pathParameters['id']!)),
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
                  // Store apps only: the web build has no support page at all.
                  if (!ref.read(isWebProvider)) page('support', (_) => const SupportScreen()),
                  page('language', (_) => const LanguageScreen()),
                  page('church', (_) => const ChurchInfoScreen()),
                  page('link', (_) => const ChurchLinkScreen()),
                  page('webhook', (_) => const WebhookScreen()),
                  page('calendar', (s) => CalendarSettingsScreen(result: s.uri.queryParameters['result'])),
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

/// Shown for the moment before the first auth state arrives. Just the
/// background: no full-screen spinner.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}
