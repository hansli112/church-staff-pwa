import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
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
    final multiple = (ref.watch(membershipsProvider).value?.length ?? 0) > 1;
    final isOperator = ref.watch(isOperatorProvider).value ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabMe)),
      body: ListView(
        children: [
          ListSection(
            children: [
              ListRow(
                title: profile?.name ?? me?.name ?? '',
                subtitle: profile?.email,
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
              if (multiple)
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
