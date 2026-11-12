import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../domain/text.dart';
import '../../l10n/app_localizations.dart';
import '../../state/church_writes.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import '../common/saving_indicator.dart';
import 'identity_section.dart';
import 'service_staff.dart';
import '../rosters/future_changes.dart';

/// An admin editing one member: their 身分 (#82), and each service they
/// are one of the 同工 of, with the duties they serve there and their
/// 小組 in it (#94); 加入聚會 for another. Every change saves at once.
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

  /// Picks a pending member, the same name first, and merges it into
  /// [member] once confirmed.
  Future<void> _mergePending(BuildContext context, WidgetRef ref, Member member, List<PendingMember> pending) async {
    final l10n = L10n.of(context);
    final same = nameKey(member.name);
    final ordered = [
      ...pending.where((p) => nameKey(p.name) == same),
      ...pending.where((p) => nameKey(p.name) != same),
    ];
    final picked = await showAppSheet<PendingMember>(
      context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: ListSection(
            header: l10n.mergePendingPick,
            children: [
              for (final p in ordered)
                ListRow(
                  title: p.name.isEmpty ? p.email : p.name,
                  subtitle: p.name.isEmpty || p.email.isEmpty ? null : p.email,
                  onTap: () => Navigator.pop(context, p),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    await mergePendingInto(context, ref, picked, member);
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

    final zoneTypes = member.zoneTypes.toSet();
    final joinable = [
      for (final s in services.services)
        if (s.enabled && !zoneTypes.contains(s.id)) s,
    ];
    Future<bool> save(Member next) => _save(context, ref, member, next);

    return Scaffold(
      appBar: AppBar(title: Text(member.name), actions: const [SavingIndicator()]),
      body: ListView(
        children: [
          IdentitySection(member: member, self: self),
          for (final s in services.services)
            if (zoneTypes.contains(s.id))
              ServiceStaffSection(
                person: member,
                service: s,
                header: s.name,
                smallGroups: [...smallGroups.where((g) => g.service == s.id)],
                onDuty: (duty, on) => save(on ? member.withDuty(s.id, duty) : member.withoutDuty(s.id, duty)),
                onSmallGroup: (g, on) => save(member.inGroupAs(g.group, member: on)),
                onLeave: () => _leaveZone(context, ref, member, s),
              ),
          if (joinable.isNotEmpty)
            ListSection(
              children: [
                MenuRow<Service>(
                  title: l10n.joinService,
                  leading: const Icon(Symbols.add_rounded),
                  options: joinable,
                  label: (s) => s.name,
                  onPicked: (s) => save(
                    member.copyWith(
                      zones: [
                        ...member.zones,
                        Zone(serviceType: s.id),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          if (pending.isNotEmpty)
            ListSection(
              footer: l10n.mergePendingFooter,
              children: [
                ListRow(title: l10n.mergePending, onTap: () => _mergePending(context, ref, member, pending)),
              ],
            ),
          if (!self)
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

/// Merges [pending] into [member] once the admin says so: 「合併還沒登入的
/// 「黃鎮台」？」, which reads the same when both have one name.
Future<void> mergePendingInto(BuildContext context, WidgetRef ref, PendingMember pending, Member member) async {
  final l10n = L10n.of(context);
  final name = pending.name.isEmpty ? pending.email : pending.name;
  final ok = await askChoice(
    context,
    title: l10n.mergePendingTitle(name),
    message: l10n.mergePendingBody(name, member.name),
    yes: l10n.mergePendingAction,
    no: l10n.cancel,
  );
  if (ok != true || !context.mounted) return;
  try {
    await ref.churchData.mergePending(pending.id, member.uid);
    Haptics.success();
    if (context.mounted) showToast(context, l10n.merged);
  } catch (e) {
    if (context.mounted) showToast(context, errorText(l10n, e));
  }
}

/// One of the 同工 without an account yet (moved, or added by name), for
/// an admin: as a member's page, but no 身分 (not using the app, they lead
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
    final person = pending.asMember(smallGroups);
    final name = pending.name.isEmpty ? pending.email : pending.name;
    final writes = ref.read(churchWritesProvider);
    Future<bool> saved(Future<void> write) => savedOrSaid(context, write);

    final zoneTypes = person.zoneTypes.toSet();
    final joinable = [
      for (final s in services.services)
        if (s.enabled && !zoneTypes.contains(s.id)) s,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(
        children: [
          // Whoever arranges them tells them: said once, at the top.
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
            child: Text(
              l10n.getsNoNotice,
              style: AppText.footnote.copyWith(color: AppColors.of(context).secondaryLabel),
            ),
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
