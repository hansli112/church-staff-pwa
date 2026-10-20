import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../core/languages.dart';
import '../../state/support.dart';
import '../../env.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../church/church_switcher.dart';

/// The LINE OpenChat (馬大別忙 Martha, sit): help, and churches meeting each other.
final lineCommunity = Uri.parse('https://line.me/ti/g2/irPvG8tKHa9Iwf2hK7D9lcjdW5O-DUx4Coafcg');

/// 設定: my account, my church, settings. An admin's most used pages sit at
/// the top under 管理教會, the rest in 教會資訊, so staff see a short page.
/// What is rarely needed is a level down: signing in and out under my
/// name, the version and the fine print under 關於.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final profile = ref.watch(profileProvider).value;
    final church = ref.watch(churchProvider).value;
    final me = ref.watch(meProvider).value;
    final isOperator = ref.watch(isOperatorProvider).value ?? false;
    final store = ref.watch(supportStoreProvider);
    final supporter = store.available && ref.watch(supporterProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabSettings)),
      body: ListView(
        children: [
          ListSection(
            children: [
              ListRow(
                leading: Avatar(profile?.name ?? me?.name ?? ''),
                title: profile?.name ?? me?.name ?? '',
                subtitle: profile?.email,
                trailing: supporter
                    ? Tag(
                        label: l10n.supporterBadge,
                        background: AppColors.of(context).accentSoft,
                        foreground: AppColors.of(context).accent,
                      )
                    : null,
                chevron: true,
                onTap: () => context.push('/me/profile'),
              ),
            ],
          ),
          // Only the platform operator: near the top, one tap to each page.
          if (isOperator)
            ListSection(
              header: l10n.operatorConsole,
              children: [
                ListRow(
                  leading: const IconTile(Symbols.list_alt_rounded, color: TileColors.neutral),
                  title: l10n.adminChurches,
                  onTap: () => context.push('/admin'),
                ),
                ListRow(
                  leading: const IconTile(Symbols.insights_rounded, color: TileColors.neutral),
                  title: l10n.adminStats,
                  onTap: () => context.push('/admin/stats'),
                ),
                ListRow(
                  leading: const IconTile(Symbols.savings_rounded, color: TileColors.neutral),
                  title: l10n.fundingCosts,
                  onTap: () => context.push('/admin/funding'),
                ),
              ],
            ),
          // The pages an admin opens most, one tap away; the rest in 教會資訊.
          if (me?.isAdmin ?? false)
            ListSection(
              header: l10n.manageChurch,
              children: [
                ListRow(
                  leading: const IconTile(Symbols.group_rounded, color: TileColors.manage),
                  title: l10n.members,
                  onTap: () => context.push('/me/members'),
                ),
                ListRow(
                  leading: const IconTile(Symbols.person_add_rounded, color: TileColors.manage),
                  title: l10n.invites,
                  onTap: () => context.push('/me/invites'),
                ),
                ListRow(
                  leading: const IconTile(Symbols.tune_rounded, color: TileColors.manage),
                  title: l10n.serviceSettings,
                  onTap: () => context.push('/me/services'),
                ),
                ListRow(
                  leading: const IconTile(Symbols.diversity_3_rounded, color: TileColors.manage),
                  title: l10n.groupsTitle,
                  onTap: () => context.push('/me/groups'),
                ),
              ],
            ),
          // A lead's groups, one tap away (#82); admins have them all above.
          if (me != null && !me.isAdmin && me.leads) _LedGroups(me: me),
          ListSection(
            children: [
              // Most used first: everyone's notifications; the church's
              // details are rarely looked at.
              ListRow(
                leading: const IconTile(Symbols.notifications_rounded, color: TileColors.church),
                title: l10n.notifications,
                onTap: () => context.push('/me/notifications'),
              ),
              // Also with one church: joining or starting another starts here.
              ListRow(
                leading: const IconTile(Symbols.swap_horiz_rounded, color: TileColors.church),
                title: l10n.switchChurch,
                onTap: () => showChurchSwitcher(context, ref),
              ),
              ListRow(
                leading: const IconTile(Symbols.church_rounded, color: TileColors.church),
                title: l10n.churchInfo,
                value: church?.name,
                onTap: () => context.push('/me/church'),
              ),
            ],
          ),
          ListSection(
            children: [
              ListRow(
                leading: const IconTile(Symbols.language_rounded, color: TileColors.neutral),
                title: l10n.language,
                value: AppLanguage.fromTag(ref.watch(profileProvider).value?.locale)?.label ?? l10n.languageSystem,
                onTap: () => context.push('/me/language'),
              ),
              if (store.available)
                ListRow(
                  leading: const IconTile(Symbols.favorite_rounded, color: TileColors.support),
                  title: l10n.support,
                  onTap: () => context.push('/me/support'),
                )
              // The stores forbid sending people to pay outside them; the
              // web app is in no store.
              else if (ref.watch(isWebProvider) && ref.watch(sitePaymentsProvider))
                ListRow(
                  leading: const IconTile(Symbols.favorite_rounded, color: TileColors.support),
                  title: l10n.support,
                  onTap: () => openSitePage(context, ref, '/support'),
                ),
            ],
          ),
          ListSection(
            children: [
              // Where to ask.
              ListRow(
                leading: const IconTile(Symbols.forum_rounded, color: TileColors.line),
                title: l10n.lineCommunity,
                subtitle: l10n.lineCommunityNote,
                onTap: () => launchUrl(lineCommunity, mode: LaunchMode.externalApplication),
              ),
              ListRow(
                leading: const IconTile(Symbols.info_rounded, color: TileColors.neutral),
                title: l10n.about,
                onTap: () => context.push('/me/about'),
              ),
            ],
          ),
          if (Env.current.isDevelopment)
            ListSection(
              header: l10n.developer,
              children: [
                ListRow(
                  leading: const IconTile(Symbols.widgets_rounded, color: TileColors.neutral),
                  title: l10n.components,
                  onTap: () => context.push('/dev/components'),
                ),
                // Crashlytics has no web SDK.
                if (!kIsWeb)
                  ListRow(
                    leading: const IconTile(Symbols.bug_report_rounded, color: TileColors.neutral),
                    title: l10n.testCrash,
                    onTap: () => ref.read(telemetryProvider).testCrash(),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A page of the website: the privacy policy and the terms, which the stores
/// require the app to link to, and on the web the support page. The stores
/// forbid the iOS and Android apps to lead to paying elsewhere, so they
/// open it with `fromApp` (AppLanguage.sitePage).
void openSitePage(BuildContext context, WidgetRef ref, String page) => launchUrl(
  Uri.parse(
    '${Env.current.webOrigin}${AppLanguage.shownIn(context).sitePage(page, fromApp: !ref.read(isWebProvider))}',
  ),
);

/// 我負責的: the services and 事工 [me] leads, each opening its page.
class _LedGroups extends ConsumerWidget {
  const _LedGroups({required this.me});

  final Member me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final services = ref.watch(servicesProvider).value;
    final ministries = ref.watch(ministriesProvider).value;
    return ListSection(
      header: l10n.myGroups,
      children: [
        for (final id in me.leadTypes)
          if (services?.byId(id) case final s?)
            ListRow(
              leading: const IconTile(Symbols.diversity_3_rounded, color: TileColors.manage),
              title: s.name,
              onTap: () => context.push('/me/groups/service/$id'),
            ),
        for (final id in me.leadMinistries)
          if (ministries?.byId(id) case final m?)
            ListRow(
              leading: const IconTile(Symbols.diversity_3_rounded, color: TileColors.manage),
              title: m.name,
              onTap: () => context.push('/me/groups/ministry/$id'),
            ),
      ],
    );
  }
}
