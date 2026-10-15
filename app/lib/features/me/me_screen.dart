import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// 我的: my profile, my church, settings. Admin tools sit under 教會資訊 so
/// staff see a short page.
class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

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
      appBar: AppBar(title: Text(l10n.tabMe)),
      body: ListView(
        children: [
          ListSection(
            children: [
              ListRow(
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
          ListSection(
            children: [
              ListRow(
                title: l10n.churchInfo,
                value: church?.name,
                onTap: () => context.push('/me/church'),
              ),
              // Also with one church: joining or starting another starts here.
              ListRow(
                title: l10n.switchChurch,
                onTap: () => showChurchSwitcher(context, ref),
              ),
              ListRow(
                title: l10n.notifications,
                onTap: () => context.push('/me/notifications'),
              ),
            ],
          ),
          ListSection(
            children: [
              ListRow(
                title: l10n.language,
                value: AppLanguage.fromTag(ref.watch(profileProvider).value?.locale)?.label ?? l10n.languageSystem,
                onTap: () => context.push('/me/language'),
              ),
              if (store.available)
                ListRow(title: l10n.support, onTap: () => context.push('/me/support'))
              // The stores forbid sending people to pay outside them; the
              // web app is in no store.
              else if (ref.watch(isWebProvider) && ref.watch(sitePaymentsProvider))
                ListRow(title: l10n.support, onTap: () => openSitePage(context, ref, '/support')),
            ],
          ),
          const _UpdatesSection(),
          if (isOperator || Env.current.isDevelopment)
            ListSection(
              header: l10n.developer,
              children: [
                if (isOperator)
                  ListRow(
                    title: l10n.operatorConsole,
                    onTap: () => context.push('/admin'),
                  ),
                if (Env.current.isDevelopment)
                  ListRow(
                    title: l10n.components,
                    onTap: () => context.push('/dev/components'),
                  ),
                // Crashlytics has no web SDK.
                if (Env.current.isDevelopment && !kIsWeb)
                  ListRow(
                    title: l10n.testCrash,
                    onTap: () => ref.read(telemetryProvider).testCrash(),
                  ),
              ],
            ),
          ListSection(
            children: [
              ListRow(title: l10n.privacyPolicy, onTap: () => openSitePage(context, ref, '/privacy')),
              ListRow(title: l10n.termsOfService, onTap: () => openSitePage(context, ref, '/terms')),
            ],
          ),
          ListSection(
            header: l10n.account,
            children: [
              ListRow(title: l10n.signOut, onTap: () => signOut(ref)),
              ListRow(
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
          children: [ListRow(title: l10n.appRunningVersion, subtitle: l10n.appVersionDevelopment)],
        );
      }
      final build = ref.watch(appBuildProvider);
      return ListSection(
        children: [
          if (build != null)
            ListRow(
              title: l10n.appRunningVersion,
              subtitle: switch (build.patch) {
                null => build.label,
                final fix => l10n.appVersionWithFix(build.label, fix),
              },
            ),
          if (AppStore.current case final store?)
            ListRow(title: l10n.appUpdateNativeTitle, subtitle: l10n.appUpdateNativeNote(store.label)),
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
        ListRow(title: l10n.appRunningVersion, subtitle: update.runningVersion, chevron: false),
        ListRow(
          title: update.phase == AppUpdatePhase.checking ? l10n.appUpdateChecking : l10n.appUpdateCheck,
          chevron: false,
          onTap: update.busy ? null : () => run(ref.read(appUpdateProvider.notifier).check),
        ),
        if (update.availableVersion != null)
          ListRow(
            title: update.phase == AppUpdatePhase.applying ? l10n.appUpdateApplying : l10n.appUpdateApply,
            subtitle: blocked ? l10n.appUpdateFinishEditingNote : null,
            chevron: false,
            onTap: update.busy || blocked ? null : () => run(ref.read(appUpdateProvider.notifier).apply),
          ),
      ],
    );
  }
}
