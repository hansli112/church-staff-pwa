import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/family.dart';
import '../../domain/limits.dart';
import '../../domain/models.dart';
import '../../domain/text.dart' show nameKey;
import '../../l10n/app_localizations.dart';
import '../../state/church_writes.dart';
import '../../state/providers.dart';
import '../../state/shown_changes.dart';
import '../common/errors.dart';
import '../common/saving_indicator.dart';
import 'identity_section.dart';
import 'no_account_picker.dart';
import 'service_staff.dart';
import '../rosters/future_changes.dart';

/// An admin editing one member: their name here (tapped in the title),
/// their 身分 (#82), and each service they are one of the 同工 of, with the
/// duties they serve there and their 小組 in it (#94); 加入聚會 for
/// another; whose family they are in (家人). Every change saves at once.
///
/// 行政 edit anyone but an admin the same, through the backend, but give no
/// 身分, merge nobody, remove nobody and see nobody's 家人 (2026-11-23).
///
/// An admin cannot demote or remove themself (the rules forbid it too), so
/// those controls do not appear on their own page.
class MemberEditorScreen extends ConsumerWidget {
  const MemberEditorScreen({super.key, required this.uid});

  final String uid;

  /// Writes [next] over [member] as shown; false, and says so, when it
  /// failed (someone else changed the member meanwhile, say).
  Future<bool> _save(BuildContext context, WidgetRef ref, Member member, Member next) async {
    try {
      await ref.read(churchWritesProvider).member(member, next).done;
      return true;
    } catch (e) {
      if (context.mounted) showToast(context, saveErrorText(L10n.of(context), e));
      return false;
    }
  }

  /// Takes [member] out of [service]'s 同工, which clears its duties too,
  /// and offers 「復原」, refused once someone has changed the member since.
  Future<void> _leaveZone(BuildContext context, WidgetRef ref, Member member, Service service) async {
    final index = member.zones.indexWhere((z) => z.serviceType == service.id);
    if (index < 0) return;
    final l10n = L10n.of(context);
    final write = ref
        .read(churchWritesProvider)
        .member(member, member.copyWith(zones: [...member.zones]..removeAt(index)));
    try {
      await write.done;
    } catch (e) {
      if (context.mounted) showToast(context, saveErrorText(l10n, e));
      return;
    }
    if (context.mounted) showToast(context, l10n.zoneLeft(service.name), onUndo: write.undo);
  }

  /// Picks one of the 同工 without an account, those named like [member]
  /// first, and merges them into [member] once confirmed.
  Future<void> _mergePending(BuildContext context, WidgetRef ref, Member member, List<PendingMember> pending) async {
    final services = ref.read(servicesProvider).value;
    final smallGroups = ref.read(smallGroupsProvider).value ?? const <SmallGroupDetails>[];
    final picked = await showAppSheet<PendingMember>(
      context,
      expand: pending.length > 6,
      builder: (context) => NoAccountPicker<PendingMember>(
        title: L10n.of(context).mergePendingPick,
        name: member.name,
        people: pending,
        nameOf: (p) => p.name.isEmpty ? p.email : p.name,
        details: (p) => [
          noAccountDetails(L10n.of(context), p, services, smallGroups),
          if (p.name.isNotEmpty) p.email,
        ].where((t) => t.isNotEmpty).join('\n'),
        searched: (p) => [p.name, p.email],
      ),
    );
    if (picked == null || !context.mounted) return;
    await mergePendingInto(context, ref, picked, member);
  }

  /// 改名: [member]'s name in this church, on the rosters too, with 復原,
  /// shown at once while the backend renames them (2026-11-23). A name one
  /// of the others has is said as it is typed; an admin giving the name of
  /// one without an account is asked whether they are one person, and
  /// merges them.
  Future<void> _rename(BuildContext context, WidgetRef ref, Member member) async {
    final l10n = L10n.of(context);
    final admin = ref.read(meProvider).value?.isAdmin ?? false;
    final others = _OtherNames(ref, self: member.uid);
    final data = ref.churchData;
    var typed = member.name;
    while (true) {
      if (!context.mounted) return;
      final next = await promptText(
        context,
        title: l10n.rename,
        label: l10n.name,
        initial: typed,
        maxLength: TextLimits.profileName,
        // Merging is an admin's: to 行政, one without an account is a name taken.
        error: (t) => others.taken(t, merging: admin) ? l10n.nameTaken(t.trim()) : null,
        helper: (t) => switch (others.pending(t)) {
          final p? when admin => l10n.renameNoAccount(p.name),
          _ => null,
        },
      );
      if (next == null || next == member.name || !context.mounted) return;
      final p = admin ? others.pending(next) : null;
      if (p == null) {
        await runWithUndo(
          context,
          l10n.pendingRenamed,
          () => (done: data.renameMember(member.uid, next), undo: () => data.renameMember(member.uid, member.name)),
        );
        return;
      }
      // Not one person after all: the name typed, asked again.
      if (!await confirmMerge(context, ref, p, member.name)) {
        typed = next;
        continue;
      }
      try {
        await data.mergePending(p.id, member.uid);
      } catch (e) {
        if (context.mounted) showToast(context, errorText(l10n, e));
        return;
      }
      try {
        await data.renameMember(member.uid, next);
        Haptics.success();
        if (context.mounted) showToast(context, l10n.merged);
      } catch (e) {
        // Merged, which stays, but still called what they were.
        if (context.mounted) showToast(context, nameErrorText(l10n, e, next));
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final pending = ref.watch(pendingMembersProvider).value ?? const <PendingMember>[];
    final member = ref.watch(
      membersProvider.select(
        (v) => v.value?.where((m) => m.uid == uid).firstOrNull,
      ),
    );
    final services = ref.watch(servicesProvider).value;
    final smallGroups = ref.watch(smallGroupsProvider).value ?? const <SmallGroupDetails>[];
    final self = ref.watch(uidProvider) == uid;
    if (member == null && pending.any((p) => p.id == uid)) return _NoAccountScreen(id: uid);
    if (member == null || services == null) return Scaffold(appBar: AppBar());
    final me = ref.watch(meProvider).value;
    final admin = me?.isAdmin ?? false;
    if (!admin && !(me?.inGroup(Group.rosterEditors) ?? false) || member.isAdmin && !admin) {
      return Scaffold(appBar: AppBar(title: Text(member.name)));
    }
    final writes = ref.read(churchWritesProvider);
    // 行政's changes go through the backend, as a 負責人's do.
    Future<bool> backend(ChurchWrite write) => savedOrSaid(context, write.done);

    final zoneTypes = member.zoneTypes.toSet();
    final joinable = [
      for (final s in services.services)
        if (!zoneTypes.contains(s.id)) s,
    ];
    Future<bool> save(Member next) => _save(context, ref, member, next);
    final mergeFirst = admin && member.waitsForZone(services.services);
    // Just joined, in no service: likely someone the rosters already have,
    // so first. In a service already, last (2026-11-19): nothing says who
    // was merged, but one put on a duty before being merged still can be.
    final merge = pending.isEmpty || !admin
        ? null
        : ListSection(
            footer: l10n.mergePendingFooter,
            children: [
              ListRow(title: l10n.mergePending, onTap: () => _mergePending(context, ref, member, pending)),
            ],
          );

    return Scaffold(
      appBar: AppBar(
        title: NameTitle(name: member.name, onTap: () => _rename(context, ref, member)),
        actions: const [SavingIndicator()],
      ),
      body: ListView(
        children: [
          if (mergeFirst) ?merge,
          if (admin) IdentitySection(member: member, self: self),
          for (final s in services.services)
            if (zoneTypes.contains(s.id))
              ServiceStaffSection(
                person: member,
                service: s,
                header: s.name,
                smallGroups: [...smallGroups.where((g) => g.service == s.id)],
                onDuty: (duty, on) => admin
                    ? save(on ? member.withDuty(s.id, duty) : member.withoutDuty(s.id, duty))
                    : savedOrSaid(
                        context,
                        (on ? ref.churchData.grantDuty : ref.churchData.revokeDuty)(uid, s.id, duty),
                      ),
                onSmallGroup: (g, on) => admin
                    ? save(member.inGroupAs(g.group, member: on))
                    : backend(writes.groupMember(member, g.group, member: on)),
                onLeave: () => admin
                    ? _leaveZone(context, ref, member, s)
                    : runWithUndo(
                        context,
                        l10n.zoneLeft(s.name),
                        () => writes.groupMember(member, ServiceGroup(s.id), member: false),
                      ),
              ),
          if (joinable.isNotEmpty)
            ListSection(
              children: [
                MenuRow<Service>(
                  title: l10n.joinService,
                  leading: const Icon(Symbols.add_rounded),
                  options: joinable,
                  label: (s) => s.name,
                  onPicked: (s) => admin
                      ? save(
                          member.copyWith(
                            zones: [
                              ...member.zones,
                              Zone(serviceType: s.id),
                            ],
                          ),
                        )
                      : backend(writes.groupMember(member, ServiceGroup(s.id), member: true)),
                ),
              ],
            ),
          if (admin) _FamiliesSection(id: uid, name: member.name),
          if (!mergeFirst) ?merge,
          if (admin && !self)
            ListSection(
              children: [
                ListRow(
                  title: l10n.removeMember,
                  destructive: true,
                  onTap: () => Navigator.of(context).pop('remove'),
                ),
              ],
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// Merges [pending] into [member] once the admin says so.
Future<void> mergePendingInto(BuildContext context, WidgetRef ref, PendingMember pending, Member member) async {
  if (!await confirmMerge(context, ref, pending, member.name) || !context.mounted) return;
  final l10n = L10n.of(context);
  try {
    await ref.churchData.mergePending(pending.id, member.uid);
    Haptics.success();
    if (context.mounted) showToast(context, l10n.merged);
  } catch (e) {
    if (context.mounted) showToast(context, errorText(l10n, e));
  }
}

/// 「王小明和小明是同一個人？」 (「這兩位黃鎮台…」 for one name), with their
/// 小組 and what they serve to be sure it is them, and that a merge is not
/// undone; true for 合併.
Future<bool> confirmMerge(BuildContext context, WidgetRef ref, PendingMember pending, String memberName) async {
  final l10n = L10n.of(context);
  final name = pending.name.isEmpty ? pending.email : pending.name;
  final details = noAccountDetails(
    l10n,
    pending,
    ref.read(servicesProvider).value,
    ref.read(smallGroupsProvider).value ?? const [],
  );
  final ok = await askChoice(
    context,
    title: name == memberName ? l10n.mergePendingSameName(name) : l10n.mergePendingTitle(name, memberName),
    message: [if (details.isNotEmpty) details, l10n.mergePendingBody].join('\n\n'),
    yes: l10n.mergePendingAction,
    no: l10n.cancel,
  );
  return ok == true;
}

/// One of the 同工 without an account yet (moved, or added by name), for
/// an admin or 行政 (who deletes nobody, and changes no admin): as a
/// member's page, but no 身分 (not using the app, they lead
/// nothing), each change through the backend, and 刪除 at the end.
class _NoAccountScreen extends ConsumerWidget {
  const _NoAccountScreen({required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final pending = ref.watch(
      pendingMembersProvider.select((v) => v.value?.where((p) => p.id == id).firstOrNull),
    );
    final services = ref.watch(servicesProvider).value;
    final smallGroups = ref.watch(smallGroupsProvider).value ?? const <SmallGroupDetails>[];
    if (pending == null || services == null) return Scaffold(appBar: AppBar());
    final name = pending.name.isEmpty ? pending.email : pending.name;
    final admin = ref.watch(meProvider).value?.isAdmin ?? false;
    // 行政 change anyone but an admin (one moved from self-host).
    if (!admin && pending.role == Role.admin) return Scaffold(appBar: AppBar(title: Text(name)));
    final person = pending.asMember(smallGroups);
    final writes = ref.read(churchWritesProvider);
    Future<bool> saved(Future<void> write) => savedOrSaid(context, write);

    final zoneTypes = person.zoneTypes.toSet();
    final joinable = [
      for (final s in services.services)
        if (!zoneTypes.contains(s.id)) s,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(name), actions: const [SavingIndicator()]),
      body: ListView(
        children: [
          // Whoever arranges them tells them: said once, at the top.
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
            child: Text(
              l10n.noAccount,
              style: AppText.footnote.copyWith(color: AppColors.of(context).secondaryLabel),
            ),
          ),
          if (pending.name.isNotEmpty)
            ListSection(
              children: [
                ListRow(title: l10n.name, value: pending.name, onTap: () => _rename(context, ref, pending.name)),
              ],
            ),
          for (final s in services.services)
            if (zoneTypes.contains(s.id))
              ServiceStaffSection(
                person: person,
                service: s,
                header: s.name,
                smallGroups: [...smallGroups.where((g) => g.service == s.id)],
                onDuty: (duty, on) =>
                    saved((on ? ref.churchData.grantDuty : ref.churchData.revokeDuty)(id, s.id, duty)),
                onSmallGroup: (g, on) => saved(writes.groupMember(person, g.group, member: on).done),
                onLeave: () => runWithUndo(
                  context,
                  l10n.zoneLeft(s.name),
                  () => writes.groupMember(person, ServiceGroup(s.id), member: false),
                ),
              ),
          if (joinable.isNotEmpty)
            ListSection(
              children: [
                MenuRow<Service>(
                  title: l10n.joinService,
                  leading: const Icon(Symbols.add_rounded),
                  options: joinable,
                  label: (s) => s.name,
                  onPicked: (s) => saved(writes.groupMember(person, ServiceGroup(s.id), member: true).done),
                ),
              ],
            ),
          if (admin) _FamiliesSection(id: id, name: name),
          if (admin)
            ListSection(
              children: [
                ListRow(title: l10n.pendingDelete, destructive: true, onTap: () => _delete(context, ref, name)),
              ],
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// A typo fixed: their name here and on the rosters they are on, shown
  /// at once while the backend renames them. A name one of the others has
  /// is said as it is typed.
  Future<void> _rename(BuildContext context, WidgetRef ref, String name) async {
    final l10n = L10n.of(context);
    final others = _OtherNames(ref, self: id);
    final next = await promptText(
      context,
      title: l10n.rename,
      label: l10n.name,
      initial: name,
      maxLength: TextLimits.profileName,
      error: (t) => others.taken(t, merging: false) ? l10n.nameTaken(t.trim()) : null,
    );
    if (next == null || next == name || !context.mounted) return;
    final data = ref.churchData;
    await runWithUndo(
      context,
      l10n.pendingRenamed,
      () => (done: data.renamePending(id, next), undo: () => data.renamePending(id, name)),
    );
  }

  /// Deleted once confirmed; their name stays on the rosters.
  Future<void> _delete(BuildContext context, WidgetRef ref, String name) async {
    final l10n = L10n.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.pendingDeleteTitle(name),
      message: l10n.pendingDeleteBody,
      action: l10n.delete,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.churchData.deletePendingMember(id);
      if (!context.mounted) return;
      showToast(context, l10n.pendingDeleted);
      Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) showToast(context, errorText(l10n, e));
    }
  }
}

/// Those taken out of a family here, by `<family>/<person>`, before the
/// backend has it.
final _takenOut = NotifierProvider<ShownChanges<bool>, Map<String, bool>>(ShownChanges.new);

/// 家人, for an admin on [id]'s page: each family they are in, by the
/// others' names, with 移出 (a parent who added someone not theirs, say).
class _FamiliesSection extends ConsumerWidget {
  const _FamiliesSection({required this.id, required this.name});

  final String id;
  final String name;

  Future<void> _takeOut(BuildContext context, WidgetRef ref, Household h, String others) async {
    final l10n = L10n.of(context);
    final ok = await askChoice(
      context,
      title: l10n.familyTakeOutAsk(name, others),
      yes: l10n.moveOutShort,
      no: l10n.cancel,
    );
    if (ok != true || !context.mounted) return;
    final data = ref.churchData;
    // Out at once, the backend taking seconds (2026-11-23).
    await savedOrSaid(
      context,
      ref.read(_takenOut.notifier).show('${h.id}/$id', true, () => data.removeFromHousehold(h.id, id)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    // One who only asked someone has no family yet.
    final out = ref.watch(_takenOut);
    final families = [
      for (final h in ref.watch(householdsOfProvider(id)).value ?? const <Household>[])
        if (h.people.any((p) => p != id) && !out.containsKey('${h.id}/$id')) h,
    ];
    if (families.isEmpty) return const SizedBox.shrink();
    return ListSection(
      header: l10n.family,
      children: [
        for (final h in families) _row(context, ref, h),
      ],
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, Household h) {
    final l10n = L10n.of(context);
    final others = [
      for (final p in h.people)
        if (p != id && (h.names[p] ?? '').isNotEmpty) h.names[p]!,
    ].join(l10n.listSeparator);
    return ListRow(
      title: others,
      trailing: RowButton(
        label: l10n.moveOutShort,
        semanticsLabel: l10n.familyTakeOutLabel(name, others),
        onPressed: () => _takeOut(context, ref, h, others),
      ),
    );
  }
}

/// A member's name as a page's title, tapped to rename them: a small pencil
/// after it, which, where titles are centred, the name is centred without.
class NameTitle extends StatelessWidget {
  const NameTitle({super.key, required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  static const _icon = 16.0;
  static const _gap = 4.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final centred =
        theme.appBarTheme.centerTitle ??
        switch (theme.platform) {
          TargetPlatform.iOS || TargetPlatform.macOS => true,
          _ => false,
        };
    return Semantics(
      button: true,
      hint: L10n.of(context).rename,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (centred) const SizedBox(width: _icon + _gap),
              Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: _gap),
              ExcludeSemantics(
                child: Icon(Symbols.edit_rounded, size: _icon, color: AppColors.of(context).tertiaryLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Who else in the church goes by a name, however written ([nameKey]), as
/// the backend tells them apart: a member, or one without an account; read
/// as they are each time, the lists loading while a name is typed.
class _OtherNames {
  _OtherNames(this._ref, {required this.self});

  final WidgetRef _ref;

  /// The one being renamed: a member's uid, or the ID of one without an
  /// account.
  final String self;

  Member? member(String name) => _named(_ref.read(membersProvider).value, name, (m) => m.uid, (m) => m.name);

  PendingMember? pending(String name) =>
      _named(_ref.read(pendingMembersProvider).value, name, (p) => p.id, (p) => p.name);

  /// Whether [name] is someone else's; one without an account is only
  /// when not [merging] into them.
  bool taken(String name, {required bool merging}) => member(name) != null || !merging && pending(name) != null;

  T? _named<T>(List<T>? people, String name, String Function(T) id, String Function(T) nameOf) {
    final key = nameKey(name);
    if (key.isEmpty) return null;
    return people?.where((p) => id(p) != self && nameKey(nameOf(p)) == key).firstOrNull;
  }
}
