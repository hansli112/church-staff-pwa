import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/design/components.dart';
import '../../domain/family.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import 'no_account_picker.dart';

/// 「設定 → 家人」: my family in this church. 加入家人 picks anyone in the
/// church: one without an account is in at once, one with an account is
/// asked and shows 等對方接受 until they accept (收回 takes it back). 移出
/// one without an account can be undone; one with an account is asked
/// first, as they would have to accept again.
class FamilyScreen extends ConsumerWidget {
  const FamilyScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final l10n = L10n.of(context);
    final List<FamilyCandidate> people;
    try {
      people = await ref.read(familyAddableProvider.future);
    } catch (e) {
      if (context.mounted) showToast(context, errorText(l10n, e));
      return;
    }
    if (!context.mounted) return;
    final family = {for (final p in ref.read(familyProvider)) p.id};
    final left = [
      for (final p in people)
        if (!family.contains(p.id)) p,
    ];
    final picked = await showAppSheet<FamilyCandidate>(
      context,
      expand: left.length > 6,
      builder: (context) => NoAccountPicker<FamilyCandidate>(
        title: l10n.familyAdd,
        name: '',
        people: left,
        nameOf: (p) => p.name,
        details: (p) => p.account ? '' : l10n.noAccount,
        searched: (p) => [p.name],
      ),
    );
    if (picked == null || !context.mounted) return;
    await _run(context, () => ref.churchData.addFamily(picked.id));
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, FamilyPerson p) async {
    final l10n = L10n.of(context);
    if (p.asked) {
      await _run(context, () => ref.churchData.removeFamily(p.id));
      return;
    }
    if (p.account) {
      final ok = await askChoice(
        context,
        title: l10n.familyMoveOutAsk(p.name),
        yes: l10n.moveOutShort,
        no: l10n.cancel,
      );
      if (ok != true || !context.mounted) return;
      await _run(context, () => ref.churchData.removeFamily(p.id));
      return;
    }
    final data = ref.churchData;
    if (await _run(context, () => data.removeFamily(p.id)) && context.mounted) {
      showToast(context, l10n.familyMovedOut(p.name), onUndo: () => data.addFamily(p.id));
    }
  }

  /// Runs [write], saying why when it is refused. Whether it went through.
  Future<bool> _run(BuildContext context, Future<void> Function() write) async {
    final l10n = L10n.of(context);
    try {
      await write();
      return true;
    } catch (e) {
      if (context.mounted) showToast(context, errorText(l10n, e));
      return false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final me = ref.watch(meProvider).value;
    final family = ref.watch(familyProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.family)),
      body: ListView(
        children: [
          ListSection(
            children: [
              ListRow(
                leading: const Icon(Symbols.add_rounded),
                title: l10n.familyAdd,
                chevron: false,
                onTap: () => _add(context, ref),
              ),
            ],
          ),
          if (family.isNotEmpty)
            ListSection(
              footer: l10n.familyFooter,
              children: [
                ListRow(title: l10n.familyMe(me?.name ?? '')),
                for (final p in family)
                  ListRow(
                    title: p.name,
                    subtitle: p.asked
                        ? l10n.familyWaiting
                        : p.account
                        ? null
                        : l10n.noAccount,
                    trailing: RowButton(
                      label: p.asked ? l10n.swapWithdraw : l10n.moveOutShort,
                      semanticsLabel: p.asked ? l10n.familyWithdrawLabel(p.name) : l10n.familyMoveOutLabel(p.name),
                      onPressed: () => _remove(context, ref, p),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
