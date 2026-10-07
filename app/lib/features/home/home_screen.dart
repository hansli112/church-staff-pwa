import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/perf.dart';
import '../../core/design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../church/church_logo.dart';
import '../church/claims.dart';
import 'church_link_card.dart';
import '../rosters/format.dart';
import '../rosters/rosters_screen.dart';

/// Whether to show 開始使用: I am an admin and still the church's only
/// member (just made it, nobody invited yet).
final _gettingStartedProvider = Provider.autoDispose<bool>((ref) {
  if (!(ref.watch(meProvider).value?.isAdmin ?? false)) return false;
  final members = ref.watch(membersProvider).value;
  final pending = ref.watch(pendingMembersProvider).value;
  return members != null && members.length <= 1 && pending != null && pending.isEmpty;
});

/// What to do first in a new church, where the screens for it are three
/// levels down under 我的. Shown while [_gettingStartedProvider] holds.
class _GettingStarted extends StatelessWidget {
  const _GettingStarted();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ListSection(
      header: l10n.gettingStarted,
      children: [
        ListRow(
          title: l10n.gettingStartedInvite,
          subtitle: l10n.gettingStartedInviteBody,
          leading: const Icon(Icons.person_add_alt),
          onTap: () => context.push('/me/invites'),
        ),
        ListRow(
          title: l10n.gettingStartedServices,
          subtitle: l10n.gettingStartedServicesBody,
          leading: const Icon(Icons.tune),
          onTap: () => context.push('/me/services'),
        ),
      ],
    );
  }
}

/// 首頁: the days I serve next. That is what most people open the app for.
/// Above them, the church link when the admin has set one, and 開始使用 for
/// the admin of a church nobody else has joined yet.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final church = ref.watch(churchProvider).value;
    final mine = ref.watch(myServicesProvider);
    final services = ref.watch(servicesProvider).value;
    final today = ref.watch(todayProvider);
    final link = ref.watch(shownChurchLinkProvider);
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
          final claims = ref.watch(pendingClaimsProvider).value ?? const [];
          final gettingStarted = ref.watch(_gettingStartedProvider);
          if (list.isEmpty && link == null && claims.isEmpty && !gettingStarted) {
            return EmptyState(
              message: l10n.noUpcomingServices,
              actionLabel: l10n.viewRosters,
              onAction: () => context.go('/rosters'),
            );
          }
          return ListView(
            children: [
              const PendingClaimsCard(),
              if (gettingStarted) const _GettingStarted(),
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
