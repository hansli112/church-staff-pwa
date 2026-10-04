import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/perf.dart';
import '../../core/design/tokens.dart';
import '../../domain/church_link.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../church/church_logo.dart';
import 'church_link_card.dart';
import '../rosters/format.dart';
import '../rosters/rosters_screen.dart';

/// 首頁: the days I serve next. That is what most people open the app for.
/// Above them, the church link when the admin has set one.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final church = ref.watch(churchProvider).value;
    final mine = ref.watch(myServicesProvider);
    final services = ref.watch(servicesProvider).value;
    final today = ref.watch(todayProvider);
    final fixedLink = ref.watch(churchLinkProvider).value;
    final content = ref.watch(linkContentProvider).value;
    final link = fixedLink == null ? null : shownChurchLink(fixedLink, content, DateTime.now());
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: Space.m,
        title: church == null ? null : ChurchTitle(church: church),
      ),
      body: mine.when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (_, _) => ErrorRetry(
          message: l10n.loadFailed,
          onRetry: () => ref.invalidate(savedRostersProvider),
        ),
        data: (list) {
          perfMark('home-visible');
          if (list.isEmpty && link == null) {
            return EmptyState(
              message: l10n.noUpcomingServices,
              actionLabel: l10n.viewRosters,
              onAction: () => context.go('/rosters'),
            );
          }
          return ListView(
            children: [
              if (link != null) ChurchLinkCard(title: link.title, body: link.body, url: link.url),
              if (list.isEmpty)
                EmptyState(
                  message: l10n.noUpcomingServices,
                  actionLabel: l10n.viewRosters,
                  onAction: () => context.go('/rosters'),
                )
              else
                ListSection(
                  header: l10n.myServicesTitle,
                  children: [
                    for (final s in list.take(20))
                      ListRow(
                        title: dayLabel(l10n, s.roster.day, today),
                        subtitle: [
                          services?.byId(s.roster.type)?.name ?? '',
                          s.duties.join('、'),
                        ].where((t) => t.isNotEmpty).join(' · '),
                        onTap: () {
                          ref.read(selectedServiceProvider.notifier).select(s.roster.type);
                          context.push(
                            '/rosters/${s.roster.type}/${s.roster.day.key}',
                          );
                        },
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
