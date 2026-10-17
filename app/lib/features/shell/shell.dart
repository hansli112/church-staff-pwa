import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/balanced_text.dart';
import '../../core/design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../state/connectivity.dart';

enum AppTab { home, rosters, calendar, me }

/// The bottom tab bar around the four top-level tabs. Each tab keeps its
/// own navigation stack.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final online = ref.watch(onlineProvider);
    return Scaffold(
      body: SafeArea(
        top: !online,
        bottom: false,
        child: Column(
          children: [
            if (!online)
              Semantics(
                liveRegion: true,
                child: Container(
                  width: double.infinity,
                  color: AppColors.of(context).fill,
                  padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
                  child: BalancedText(l10n.offlineReadOnlyBanner, textAlign: TextAlign.start, style: AppText.callout),
                ),
              ),
            Expanded(child: shell),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.tabHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.view_agenda_outlined),
            selectedIcon: const Icon(Icons.view_agenda),
            label: l10n.tabRosters,
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_month_outlined),
            selectedIcon: const Icon(Icons.calendar_month),
            label: l10n.tabCalendar,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: l10n.tabMe,
          ),
        ],
      ),
    );
  }
}

String tabLabel(L10n l10n, AppTab tab) => switch (tab) {
  AppTab.home => l10n.tabHome,
  AppTab.rosters => l10n.tabRosters,
  AppTab.calendar => l10n.tabCalendar,
  AppTab.me => l10n.tabMe,
};
