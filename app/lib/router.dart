import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/shell/shell.dart';
import 'features/shell/placeholder_tab.dart';
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
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) =>
        redirectFor(ref.read(appStageProvider), state.matchedLocation),
    routes: [
      GoRoute(path: '/loading', builder: (_, _) => const LoadingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, _) => const PlaceholderTab(tab: AppTab.home),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/rosters',
                builder: (_, _) => const PlaceholderTab(tab: AppTab.rosters),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/calendar',
                builder: (_, _) => const PlaceholderTab(tab: AppTab.calendar),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/me',
                builder: (_, _) => const PlaceholderTab(tab: AppTab.me),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Where to send someone at [location] given the app [stage]; null stays.
@visibleForTesting
String? redirectFor(AppStage stage, String location) {
  bool at(String prefix) =>
      location == prefix || location.startsWith('$prefix/');
  switch (stage) {
    case AppStage.loading:
      return location == '/loading' ? null : '/loading';
    case AppStage.signedOut:
    case AppStage.noChurch:
    case AppStage.churchClosed:
    case AppStage.ready:
      return at('/loading') ? '/home' : null;
  }
}

/// Shown for the moment before the first auth state arrives. Just the
/// background: no full-screen spinner.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}
