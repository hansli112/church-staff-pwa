import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_build.dart';
import '../../state/app_update.dart';
import '../../state/providers.dart';
import 'me_screen.dart' show openSitePage;

/// 關於馬大別忙: the version running and updating it, and the privacy
/// policy and the terms the stores require the app to link to.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.about)),
      body: ListView(
        children: [
          const _UpdatesSection(),
          ListSection(
            children: [
              ListRow(
                title: l10n.privacyPolicy,
                onTap: () => openSitePage(context, ref, '/privacy'),
              ),
              ListRow(
                title: l10n.termsOfService,
                onTap: () => openSitePage(context, ref, '/terms'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
              title: l10n.appRunningVersion,
              subtitle: l10n.appVersionDevelopment,
            ),
          ],
        );
      }
      final build = ref.watch(appBuildProvider);
      if (build == null) return const SizedBox.shrink();
      return ListSection(
        children: [
          ListRow(
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
          title: l10n.appRunningVersion,
          subtitle: update.runningVersion,
          chevron: false,
        ),
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
