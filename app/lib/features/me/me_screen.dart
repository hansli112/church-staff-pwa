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
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/app_build.dart';
import '../../state/app_update.dart';
import '../../state/session.dart';
import '../church/church_switcher.dart';

/// The LINE OpenChat (馬大別忙 Martha, sit): help, and churches meeting each other.
final lineCommunity = Uri.parse('https://line.me/ti/g2/irPvG8tKHa9Iwf2hK7D9lcjdW5O-DUx4Coafcg');

/// 設定: my profile, my church, settings. An admin's most used pages sit at
/// the top under 管理教會, the rest in 教會資訊, so staff see a short page.
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
              ],
            ),
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
          // Where to ask, above the version and the fine print.
          ListSection(
            children: [
              ListRow(
                leading: const IconTile(Symbols.forum_rounded, color: TileColors.line),
                title: l10n.lineCommunity,
                subtitle: l10n.lineCommunityNote,
                onTap: () => launchUrl(lineCommunity, mode: LaunchMode.externalApplication),
              ),
            ],
          ),
          const _UpdatesSection(),
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
          ListSection(
            children: [
              ListRow(
                leading: const IconTile(Symbols.shield_rounded, color: TileColors.neutral),
                title: l10n.privacyPolicy,
                onTap: () => openSitePage(context, ref, '/privacy'),
              ),
              ListRow(
                leading: const IconTile(Symbols.description_rounded, color: TileColors.neutral),
                title: l10n.termsOfService,
                onTap: () => openSitePage(context, ref, '/terms'),
              ),
            ],
          ),
          ListSection(
            header: l10n.account,
            children: [
              ListRow(
                leading: const IconTile(Symbols.key_rounded, color: TileColors.neutral),
                title: l10n.signInMethods,
                onTap: () => context.push('/account/sign-in'),
              ),
              ListRow(
                leading: const IconTile(Symbols.logout_rounded, color: TileColors.neutral),
                title: l10n.signOut,
                onTap: () => signOut(ref),
              ),
              ListRow(
                leading: const IconTile(Symbols.delete_rounded, color: TileColors.destructive),
                title: l10n.deleteAccount,
                destructive: true,
                onTap: () => context.push('/account'),
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

class _UpdatesSection extends ConsumerWidget {
  const _UpdatesSection();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final update = ref.watch(appUpdateProvider);
    final blocked = ref.watch(updateBlockedProvider);
    final error = update.error;
    final footer = error is UpdateRejected
        ? switch (error.reason) {
            UpdateRejection.editing => l10n.appUpdateFinishEditing,
            UpdateRejection.scopeChanged => l10n.appUpdateScopeChanged,
            UpdateRejection.unsafeRoute => l10n.appUpdateBackToMe,
            UpdateRejection.noUpdate => l10n.appUpdateCheckFirst,
          }
        : error != null
        ? l10n.appUpdateFailed
        : update.phase == AppUpdatePhase.current
        ? l10n.appUpdateCurrent
        : update.availableVersion != null
        ? l10n.appUpdateReady
        : null;
    if (!update.supported) {
      if (ref.watch(isWebProvider)) {
        return ListSection(
          children: [
            ListRow(
              leading: _versionTile,
              title: l10n.appRunningVersion,
              subtitle: l10n.appVersionDevelopment,
            ),
          ],
        );
      }
      final build = ref.watch(appBuildProvider);
      return ListSection(
        children: [
          if (build != null)
            ListRow(
              leading: _versionTile,
              title: l10n.appRunningVersion,
              subtitle: switch (build.patch) {
                null => build.label,
                final fix => l10n.appVersionWithFix(build.label, fix),
              },
            ),
        ],
      );
    }
    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } catch (_) {
        /* The controller renders the explicit inline error above. */
      }
    }

    return ListSection(
      footer: footer,
      children: [
        ListRow(
          leading: _versionTile,
          title: l10n.appRunningVersion,
          subtitle: update.runningVersion,
          chevron: false,
        ),
        ListRow(
          leading: const IconTile(Symbols.refresh_rounded, color: TileColors.neutral),
          title: update.phase == AppUpdatePhase.checking ? l10n.appUpdateChecking : l10n.appUpdateCheck,
          chevron: false,
          onTap: update.busy ? null : () => run(ref.read(appUpdateProvider.notifier).check),
        ),
        if (update.availableVersion != null)
          ListRow(
            leading: const IconTile(Symbols.system_update_rounded, color: TileColors.neutral),
            title: update.phase == AppUpdatePhase.applying ? l10n.appUpdateApplying : l10n.appUpdateApply,
            subtitle: blocked ? l10n.appUpdateFinishEditingNote : null,
            chevron: false,
            onTap: update.busy || blocked ? null : () => run(ref.read(appUpdateProvider.notifier).apply),
          ),
      ],
    );
  }
}

const _versionTile = IconTile(Symbols.info_rounded, color: TileColors.neutral);
