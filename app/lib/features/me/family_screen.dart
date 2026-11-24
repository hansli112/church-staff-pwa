import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/design/components.dart';
import '../../domain/family.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/shown_changes.dart';
import '../common/errors.dart';
import '../common/saving_indicator.dart';
import 'no_account_picker.dart';

/// 家人 added or taken out (null) here, by ID, shown before the backend has it.
final _familyShown = NotifierProvider<ShownChanges<FamilyPerson?>, Map<String, FamilyPerson?>>(ShownChanges.new);

/// 「設定 → 家人」: my family in this church. 加入家人 picks anyone in the
/// church: one without an account is in at once, one with an account is
/// asked and shows 等對方接受 until they accept (收回 takes it back). 移出
/// one without an account can be undone; one with an account is asked
/// first, as they would have to accept again. Each shows at once, the
/// backend taking seconds (2026-11-23).
class FamilyScreen extends ConsumerWidget {
  const FamilyScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final l10n = L10n.of(context);
    final List<FamilyCandidate> people;
    try {
      people = await ref.read(familyAddableProvider.future);
    } catch (e) {
      // Asked again on the next tap, not this failure kept.
      ref.invalidate(familyAddableProvider);
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
    final shown = FamilyPerson(id: picked.id, name: picked.name, account: picked.account, asked: picked.account);
    await _run(context, ref, picked.id, shown, () => ref.churchData.addFamily(picked.id));
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, FamilyPerson p) async {
    final l10n = L10n.of(context);
    if (p.asked) {
      await _run(context, ref, p.id, null, () => ref.churchData.removeFamily(p.id));
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
      await _run(context, ref, p.id, null, () => ref.churchData.removeFamily(p.id));
      return;
    }
    final data = ref.churchData;
    final shown = ref.read(_familyShown.notifier);
    if (await _run(context, ref, p.id, null, () => data.removeFamily(p.id)) && context.mounted) {
      showToast(context, l10n.familyMovedOut(p.name), onUndo: () => shown.show(p.id, p, () => data.addFamily(p.id)));
    }
  }

  /// Runs [write], [id] shown as [person] (null: out) meanwhile, saying
  /// why when it is refused. Whether it went through.
  Future<bool> _run(
    BuildContext context,
    WidgetRef ref,
    String id,
    FamilyPerson? person,
    Future<void> Function() write,
  ) async {
    final l10n = L10n.of(context);
    try {
      await ref.read(_familyShown.notifier).show(id, person, write);
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
    // Asked for now, so 加入家人 opens its list at once rather than waiting
    // on the backend then.
    ref.watch(familyAddableProvider);
    final changed = ref.watch(_familyShown);
    final had = ref.watch(familyProvider);
    final family = [
      for (final p in had)
        if (!changed.containsKey(p.id)) p else ?changed[p.id],
      for (final MapEntry(key: id, value: p) in changed.entries)
        if (p != null && !had.any((h) => h.id == id)) p,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.family), actions: const [SavingIndicator()]),
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
