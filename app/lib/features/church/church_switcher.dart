import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';

/// The name of any church I belong to, for the switcher.
final churchByIdProvider = StreamProvider.autoDispose.family<Church?, String>(
  (ref, cid) => ref.watch(backendProvider).church(cid).church(),
);

/// Lists my churches; picking one switches every screen to it. Below them,
/// joining another church with a code, or starting one.
Future<void> showChurchSwitcher(BuildContext context, WidgetRef ref) {
  return showAppSheet<void>(
    context,
    builder: (context) => const _ChurchSwitcherSheet(),
  );
}

class _ChurchSwitcherSheet extends ConsumerWidget {
  const _ChurchSwitcherSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final memberships = ref.watch(membershipsProvider).value ?? const [];
    final current = ref.watch(currentChurchIdProvider);
    final router = GoRouter.of(context);
    // To join or start a church, away from the tabs rather than over them:
    // Riverpod pauses what a covered page watches, and joining or starting
    // a church changes it all.
    void open(String location) {
      Navigator.pop(context);
      router.go(location);
    }

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          children: [
            ListSection(
              header: l10n.switchChurch,
              children: [
                for (final m in memberships)
                  Consumer(
                    builder: (context, ref, _) {
                      final church = ref.watch(churchByIdProvider(m.churchId)).value;
                      return ListRow(
                        title: church?.name ?? '',
                        selected: m.churchId == current,
                        onTap: () {
                          Haptics.selection();
                          ref.read(selectedChurchProvider.notifier).select(m.churchId);
                          open('/home');
                        },
                      );
                    },
                  ),
              ],
            ),
            ListSection(
              children: [
                ListRow(
                  title: l10n.enterInviteCode,
                  leading: const Icon(Icons.group_add_outlined),
                  onTap: () => open('/welcome/join'),
                ),
                ListRow(
                  title: l10n.createChurch,
                  leading: const Icon(Icons.add),
                  onTap: () => open('/welcome/create'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
