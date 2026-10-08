import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../state/support.dart';
import '../../env.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
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
                value: l10n.languageZhHant,
                onTap: () => context.push('/me/language'),
              ),
              if (store.available) ListRow(title: l10n.support, onTap: () => context.push('/me/support')),
            ],
          ),
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
