import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'deep_link.dart';
import 'deferred_pages.dart';
import 'domain/models.dart';
import 'env.dart';
import 'features/auth/login_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/church/add_to_home.dart';
import 'features/church/church_entry_screen.dart';
import 'features/church/closed_screen.dart';
import 'features/church/join_screen.dart';
import 'features/church/welcome_screen.dart';
import 'features/dev/component_gallery.dart';
import 'features/home/home_screen.dart';
import 'features/home/notification_list_screen.dart';
import 'features/me/about_screen.dart';
import 'features/me/account_screen.dart';
import 'features/me/church_link_screen.dart';
import 'features/me/groups_screen.dart';
import 'features/me/invites_screen.dart';
import 'features/me/me_screen.dart';
import 'features/me/member_editor_screen.dart';
import 'features/me/members_screen.dart';
import 'features/me/notifications_screen.dart';
import 'features/me/profile_screen.dart';
import 'features/me/services_screen.dart';
import 'features/me/sign_in_methods_screen.dart';
import 'features/me/support_screen.dart';
import 'features/me/time_zone_screen.dart';
import 'features/me/turn_on_notifications.dart';
import 'features/me/webhook_screen.dart';
import 'features/rosters/event_roster_screen.dart';
import 'features/rosters/plan_weeks_screen.dart';
import 'features/rosters/roster_day_screen.dart';
import 'features/rosters/rosters_screen.dart';
import 'data/backend.dart' show WarmUp;
import 'features/common/warm_up.dart';
import 'features/shell/shell.dart';
import 'state/notifications.dart';
import 'state/providers.dart';
import 'state/app_update.dart';

/// Re-runs the router's redirect whenever the app stage changes.
class _StageListenable extends ChangeNotifier {
  _StageListenable(Ref ref) {
    ref.listen(appStageProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _StageListenable(ref);
  ref.onDispose(refresh.dispose);

  /// [fade]: a stage of the app (loading, signing in, the tabs), which
  /// fades in instead of sliding in like a page opened from another.
  GoRoute page(
    String path,
    Widget Function(GoRouterState s) build, {
    List<RouteBase> routes = const [],
    bool fade = false,
  }) {
    Widget guarded(GoRouterState s) {
      final child = build(s);
      return isUpdateEditorRoute(s.matchedLocation) ? UpdateEditGuard(child: child) : child;
    }

    return GoRoute(
      path: path,
      builder: fade ? null : (_, s) => guarded(s),
      pageBuilder: fade ? (_, s) => fadeInPage(s, guarded(s)) : null,
      routes: routes,
    );
  }

  return GoRouter(
    initialLocation: Env.current.startRoute,
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
        final notification = target.notification;
        if (notification != null) unawaited(markTappedSeen(ref, church, notification));
      }
      return target.location;
    },
    routes: [
      page('/loading', (_) => const LoadingScreen(), fade: true),
      page('/login', (s) => LoginScreen(from: s.uri.queryParameters['from']), fade: true),
      page(
        '/welcome',
        (_) => const WelcomeScreen(),
        fade: true,
        routes: [
          page(
            'join',
            (_) => const WarmUpOnOpen(WarmUp.joinChurch, child: EnterCodeScreen()),
            routes: [
              page(':code', (s) => WarmUpOnOpen(WarmUp.joinChurch, child: JoinScreen(code: s.pathParameters['code']!))),
            ],
          ),
          page('create', (_) => const WarmUpOnOpen(WarmUp.createChurch, child: CreateChurchScreen())),
          page('move', (_) => const DeferredPage.move()),
        ],
      ),
      page(
        '/c/:churchId',
        (s) => WarmUpOnOpen(WarmUp.askToJoin, child: ChurchEntryScreen(churchId: s.pathParameters['churchId']!)),
        fade: true,
        // An invite link. The code decides the church, not the URL.
        routes: [
          // Opened from the link itself, not from a page here.
          page(
            'join/:code',
            (s) => WarmUpOnOpen(WarmUp.joinChurch, child: JoinScreen(code: s.pathParameters['code']!)),
            fade: true,
          ),
        ],
      ),
      page('/closed', (_) => const ClosedScreen(), fade: true),
      page('/add-to-home', (_) => const AddToHomeScreen()),
      page('/turn-on-notifications', (_) => const TurnOnNotificationsScreen(), fade: true),
      page('/account', (_) => const AccountScreen(), routes: [page('sign-in', (_) => const SignInMethodsScreen())]),
      page(
        '/admin',
        (_) => const WarmUpOnOpen(WarmUp.backOffice, child: DeferredPage.admin()),
        routes: [
          page('stats', (_) => const DeferredPage.adminStats()),
          page('funding', (_) => const DeferredPage.adminFunding()),
        ],
      ),
      if (Env.current.isDevelopment) page('/dev/components', (_) => const ComponentGallery()),
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, shell) => fadeInPage(state, AppShell(shell: shell)),
        branches: [
          StatefulShellBranch(
            routes: [
              page(
                '/home',
                (_) => const HomeScreen(),
                routes: [page('notifications', (_) => const NotificationListScreen())],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              page(
                '/rosters',
                (_) => const RostersScreen(),
                routes: [
                  page(
                    'import/:type',
                    (s) => WarmUpOnOpen(
                      WarmUp.photoImport,
                      child: DeferredPage.rosterImport(serviceType: s.pathParameters['type']!),
                    ),
                  ),
                  // These two before :type/:day, which would take them for a service.
                  page('plan/:type', (s) => PlanWeeksScreen(serviceType: s.pathParameters['type']!)),
                  page(
                    'event/:id',
                    (s) => EventRosterScreen(eventId: s.pathParameters['id']!, event: s.extra as CalendarEvent?),
                  ),
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
                (_) => const SettingsScreen(),
                routes: [
                  page('profile', (_) => const ProfileScreen(), routes: [page('name', (_) => const NameScreen())]),
                  page('about', (_) => const AboutScreen()),
                  // Store apps only: the web build has no support page at all.
                  if (!ref.read(isWebProvider))
                    page('support', (_) => const SupportScreen(), routes: [page('icon', (_) => const AppIconScreen())]),
                  page('language', (_) => const LanguageScreen()),
                  page(
                    'church',
                    (_) => const DeferredPage.churchInfo(),
                    routes: [page('icon', (_) => const AppIconScreen(back: '/me/church'))],
                  ),
                  page('timezone', (_) => const WarmUpOnOpen(WarmUp.timeZone, child: TimeZoneScreen())),
                  page('link', (_) => const ChurchLinkScreen()),
                  page('webhook', (_) => const WebhookScreen()),
                  page('calendar', (s) => DeferredPage.calendarSettings(result: s.uri.queryParameters['result'])),
                  page('notifications', (_) => const NotificationsScreen()),
                  page('invites', (_) => const InvitesScreen()),
                  page(
                    'groups',
                    (_) => const GroupsScreen(),
                    routes: [
                      page('service/:id', (s) => GroupScreen(group: ServiceGroup(s.pathParameters['id']!))),
                      page('ministry/:id', (s) => GroupScreen(group: MinistryGroup(s.pathParameters['id']!))),
                      page('small/:id', (s) => GroupScreen(group: SmallGroup(s.pathParameters['id']!))),
                    ],
                  ),
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
                        (s) => WarmUpOnOpen(
                          WarmUp.serviceEdit,
                          child: ServiceEditorScreen(serviceId: s.pathParameters['id']!),
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

/// [child] fading in over what showed before, as a launch screen gives way
/// to the app; at once when the phone asks for less motion. A page opened
/// over it moves it aside as the platform does (iOS slides it left).
Page<void> fadeInPage(GoRouterState state, Widget child) => CustomTransitionPage<void>(
  key: state.pageKey,
  child: child,
  transitionDuration: const Duration(milliseconds: 250),
  reverseTransitionDuration: const Duration(milliseconds: 200),
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    final route = ModalRoute.of(context);
    final covered = route is PageRoute<void>
        ? Theme.of(context).pageTransitionsTheme.buildTransitions(
            route,
            context,
            kAlwaysCompleteAnimation,
            secondaryAnimation,
            child,
          )
        : child;
    if (MediaQuery.disableAnimationsOf(context)) return covered;
    return FadeTransition(
      opacity: CurveTween(curve: Curves.easeOut).animate(animation),
      child: covered,
    );
  },
);
