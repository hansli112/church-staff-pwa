import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/limits.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/church_writes.dart';
import '../../state/providers.dart';
import '../rosters/future_changes.dart';
import 'services_screen.dart' show promptText;

/// 聚會與事工 (#82), for admins: every service and 事工, each opening its
/// page; a new 事工 is added here.
class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final services = ref.watch(servicesProvider).value?.enabled ?? const <Service>[];
    final ministries = ref.watch(ministriesProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.groupsTitle)),
      body: ListView(
        children: [
          ListSection(
            header: l10n.serviceSettings,
            children: [
              for (final s in services) ListRow(title: s.name, onTap: () => context.push('/me/groups/service/${s.id}')),
            ],
          ),
          ListSection(
            header: l10n.ministries,
            footer: (ministries?.ministries.isEmpty ?? true) ? l10n.noMinistries : null,
            children: [
              for (final m in ministries?.ministries ?? const <Ministry>[])
                ListRow(title: m.name, onTap: () => context.push('/me/groups/ministry/${m.id}')),
              ListRow(
                title: l10n.addMinistry,
                leading: const Icon(Symbols.add_rounded),
                chevron: false,
                onTap: ministries == null ? null : () => _add(context, ref, ministries),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref, MinistrySettings settings) async {
    final l10n = L10n.of(context);
    final name = await promptText(
      context,
      title: l10n.addMinistry,
      hint: l10n.ministryName,
      maxLength: TextLimits.profileName,
    );
    if (name == null || !context.mounted) return;
    final id = _newId(settings.ids);
    final before = settings.ministries;
    final ok = await runWithUndo(
      context,
      l10n.saved,
      () => ref.read(churchWritesProvider).ministries(before, [...before, Ministry(id: id, name: name)]),
    );
    if (ok && context.mounted) unawaited(context.push('/me/groups/ministry/$id'));
  }

  static String _newId(List<String> taken) {
    final rng = Random();
    while (true) {
      final id = 'm${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${rng.nextInt(1296).toRadixString(36)}';
      if (!taken.contains(id)) return id;
    }
  }
}

/// Every roster saved, read once when a group's page opens: who served
/// what, for 排過…的服事.
final _allRostersProvider = FutureProvider.autoDispose<List<Roster>>((ref) => ref.churchData.allRosters());

/// Someone who served [group]'s duties without being one of its 同工: each
/// duty and how many times.
typedef Candidate = ({Member member, Map<String, int> served});

/// Who served [group] on [rosters] and is not one of its 同工, most served
/// first. A service's duties are its days'; a 事工's, the duties it links,
/// on services' days and, by name, on events'.
List<Candidate> groupCandidates(ChurchGroup group, List<Roster> rosters, List<Member> members, Ministry? ministry) {
  final byUid = {for (final m in members) m.uid: m};
  final served = <String, Map<String, int>>{};
  for (final r in rosters) {
    if (r.forEvent?.cancelled ?? false) continue;
    for (final d in r.duties) {
      final counts = switch (group) {
        ServiceGroup(:final id) => !r.isEvent && r.type == id,
        MinistryGroup() => ministry != null && ministry.dutiesIn(r.isEvent ? null : r.type).contains(d.role),
      };
      if (!counts) continue;
      for (final uid in {for (final name in d.people) ?d.uids[name]}) {
        final m = byUid[uid];
        if (m == null || m.isIn(group)) continue;
        final mine = served[uid] ??= {};
        mine[d.role] = (mine[d.role] ?? 0) + 1;
      }
    }
  }
  int total(Map<String, int> s) => s.values.fold(0, (a, b) => a + b);
  return [
    for (final e in served.entries) (member: byUid[e.key]!, served: e.value),
  ]..sort((a, b) {
    final t = total(b.served).compareTo(total(a.served));
    return t != 0 ? t : a.member.name.compareTo(b.member.name);
  });
}

/// One group's page (#82): its 負責人, its 同工 and those who served it
/// without being one. Its 負責人 and admins add and take out 同工; admins
/// also name a 事工, link its duties, assign its 負責人 and delete it.
class GroupScreen extends ConsumerWidget {
  const GroupScreen({super.key, required this.group});

  final ChurchGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final me = ref.watch(meProvider).value;
    final services = ref.watch(servicesProvider).value;
    final ministries = ref.watch(ministriesProvider).value;
    final members = ref.watch(membersProvider).value;
    final ministry = switch (group) {
      MinistryGroup(:final id) => ministries?.byId(id),
      ServiceGroup() => null,
    };
    final name = switch (group) {
      ServiceGroup(:final id) => services?.byId(id)?.name,
      MinistryGroup() => ministry?.name,
    };
    final admin = me?.isAdmin ?? false;
    final leads = switch (group) {
      ServiceGroup(:final id) => me?.leadTypes.contains(id) ?? false,
      MinistryGroup(:final id) => me?.leadMinistries.contains(id) ?? false,
    };
    if (name == null || members == null || !(admin || leads)) return Scaffold(appBar: AppBar());
    bool isLead(Member m) => switch (group) {
      ServiceGroup(:final id) => m.leadTypes.contains(id),
      MinistryGroup(:final id) => m.leadMinistries.contains(id),
    };
    final leaders = [...members.where(isLead)]..sort((a, b) => a.name.compareTo(b.name));
    final staff = [...members.where((m) => m.isIn(group))]..sort((a, b) => a.name.compareTo(b.name));
    final candidates = groupCandidates(group, ref.watch(_allRostersProvider).value ?? const [], members, ministry);
    final c = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          if (admin && ministry != null)
            ListSection(
              footer: l10n.ministryDutiesFooter,
              children: [
                ListRow(title: l10n.ministryName, value: ministry.name, onTap: () => _rename(context, ref, ministry)),
                ListRow(
                  title: l10n.ministryDuties,
                  value: ministry.duties.isEmpty
                      ? l10n.ministryDutiesNone
                      : ministry.duties.map((d) => d.duty).toSet().join(l10n.listSeparator),
                  onTap: () => _linkDuties(context, ref, ministry),
                ),
              ],
            ),
          ListSection(
            header: l10n.leads,
            footer: leaders.isEmpty ? l10n.noLeads : null,
            children: [
              for (final m in leaders) ListRow(title: m.name, chevron: false),
              if (admin)
                ListRow(
                  title: l10n.assignLead,
                  leading: const Icon(Symbols.add_rounded),
                  chevron: false,
                  onTap: () => _assignLead(context, ref, members.where((m) => !isLead(m)).toList(), name),
                ),
            ],
          ),
          ListSection(
            header: l10n.groupStaff,
            footer: staff.isEmpty ? l10n.noGroupStaff : null,
            children: [
              for (final m in staff)
                ListRow(
                  title: m.name,
                  subtitle: switch (group) {
                    ServiceGroup(:final id) => switch (m.zones.where((z) => z.serviceType == id).firstOrNull?.duties) {
                      final duties? when duties.isNotEmpty => duties.join(l10n.listSeparator),
                      _ => null,
                    },
                    MinistryGroup() => null,
                  },
                  chevron: false,
                  onTap: () => _takeOut(context, ref, m, name),
                ),
            ],
          ),
          if (candidates.isNotEmpty)
            ListSection(
              header: l10n.groupCandidates(name),
              children: [
                for (final cand in candidates)
                  ListRow(
                    title: cand.member.name,
                    subtitle: [
                      for (final e in cand.served.entries) l10n.groupCandidateServed(e.key, e.value),
                    ].join(l10n.listSeparator),
                    trailing: TextButton(
                      onPressed: () => runWithUndo(
                        context,
                        l10n.addedToGroup(cand.member.name, name),
                        () => ref
                            .read(churchWritesProvider)
                            .groupMember(cand.member, group, member: true, duties: cand.served.keys.toList()),
                      ),
                      // Read out whole: who, and to which group.
                      child: Semantics(
                        label: l10n.addAsStaffLabel(cand.member.name, name),
                        excludeSemantics: true,
                        child: Text(l10n.addAsStaff, style: AppText.body.copyWith(color: c.accent)),
                      ),
                    ),
                  ),
              ],
            ),
          if (admin && ministry != null)
            ListSection(
              children: [
                ListRow(
                  title: l10n.deleteMinistry,
                  destructive: true,
                  chevron: false,
                  onTap: () => _delete(context, ref, ministry),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _takeOut(BuildContext context, WidgetRef ref, Member m, String name) async {
    final l10n = L10n.of(context);
    final go = await showAppSheet<bool>(
      context,
      builder: (context) => SafeArea(
        child: ListSection(
          header: m.name,
          children: [
            ListRow(title: l10n.removeFromGroup(name), destructive: true, onTap: () => Navigator.pop(context, true)),
          ],
        ),
      ),
    );
    if (go != true || !context.mounted) return;
    await runWithUndo(
      context,
      l10n.removedFromGroup(m.name, name),
      () => ref.read(churchWritesProvider).groupMember(m, group, member: false),
    );
  }

  Future<void> _assignLead(BuildContext context, WidgetRef ref, List<Member> others, String name) async {
    final l10n = L10n.of(context);
    others.sort((a, b) => a.name.compareTo(b.name));
    final picked = await showAppSheet<Member>(
      context,
      expand: others.length > 8,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: ListSection(
            header: l10n.assignLead,
            children: [for (final m in others) ListRow(title: m.name, onTap: () => Navigator.pop(context, m))],
          ),
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    final identity = switch (group) {
      ServiceGroup(:final id) => ServiceLead(id) as Identity,
      MinistryGroup(:final id) => MinistryLead(id),
    };
    await runWithUndo(
      context,
      l10n.identityAdded(l10n.identityLeadOf(name)),
      () => ref.read(churchWritesProvider).member(picked, picked.withIdentities([...picked.identities, identity])),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, Ministry ministry) async {
    final l10n = L10n.of(context);
    final name = await promptText(
      context,
      title: l10n.ministryName,
      hint: l10n.ministryName,
      initial: ministry.name,
      maxLength: TextLimits.profileName,
    );
    if (name == null || name == ministry.name || !context.mounted) return;
    await _replace(context, ref, ministry, ministry.copyWith(name: name), l10n.saved);
  }

  Future<void> _linkDuties(BuildContext context, WidgetRef ref, Ministry ministry) async {
    final services = ref.read(servicesProvider).value?.enabled ?? const <Service>[];
    final picked = await showAppSheet<List<MinistryDuty>>(
      context,
      expand: true,
      builder: (_) => _DutyPicker(services: services, initial: ministry.duties),
    );
    if (picked == null || !context.mounted) return;
    await _replace(context, ref, ministry, ministry.copyWith(duties: picked), L10n.of(context).saved);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Ministry ministry) async {
    final before = ref.read(ministriesProvider).value?.ministries;
    if (before == null) return;
    final ok = await runWithUndo(
      context,
      L10n.of(context).ministryDeleted(ministry.name),
      () => ref.read(churchWritesProvider).ministries(before, [
        for (final m in before)
          if (m.id != ministry.id) m,
      ]),
    );
    if (ok && context.mounted) context.pop();
  }

  Future<void> _replace(BuildContext context, WidgetRef ref, Ministry was, Ministry next, String done) async {
    final before = ref.read(ministriesProvider).value?.ministries;
    if (before == null) return;
    await runWithUndo(
      context,
      done,
      () => ref.read(churchWritesProvider).ministries(before, [
        for (final m in before) m.id == was.id ? next : m,
      ]),
    );
  }
}

/// The duties a 事工 links, ticked per service.
class _DutyPicker extends StatefulWidget {
  const _DutyPicker({required this.services, required this.initial});

  final List<Service> services;
  final List<MinistryDuty> initial;

  @override
  State<_DutyPicker> createState() => _DutyPickerState();
}

class _DutyPickerState extends State<_DutyPicker> {
  late final _picked = [...widget.initial];

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ministryDuties),
        automaticallyImplyLeading: false,
        actions: [TextButton(onPressed: () => Navigator.pop(context, _picked), child: Text(l10n.done))],
      ),
      body: ListView(
        children: [
          for (final s in widget.services)
            ListSection(
              header: s.name,
              children: [
                for (final d in s.duties)
                  ListRow(
                    title: d,
                    selected: _picked.contains(MinistryDuty(s.id, d)),
                    onTap: () => setState(() {
                      final duty = MinistryDuty(s.id, d);
                      if (!_picked.remove(duty)) _picked.add(duty);
                    }),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
