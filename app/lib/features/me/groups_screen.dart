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
import '../../state/attendance.dart';
import '../../state/church_writes.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import '../rosters/future_changes.dart';
import 'attendance.dart';
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
        SmallGroup() => false,
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
/// also name a 事工, link its duties, assign its 負責人 and delete it. A
/// service's page lists its 小組 (#85), which its 負責人 open; a 小組's,
/// managed also by its service's 負責人, says when it meets and has its
/// 小組長. With 回報人數 on, a service's and a 小組's 人數 follow.
class GroupScreen extends ConsumerWidget {
  const GroupScreen({super.key, required this.group});

  final ChurchGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final me = ref.watch(meProvider).value;
    final services = ref.watch(servicesProvider).value;
    final ministries = ref.watch(ministriesProvider).value;
    final smallGroups = ref.watch(smallGroupsProvider).value ?? const <SmallGroupDetails>[];
    final members = ref.watch(membersProvider).value;
    final attendanceOn = ref.watch(churchProvider.select((c) => c.value?.attendanceSince != null));
    final ministry = switch (group) {
      MinistryGroup(:final id) => ministries?.byId(id),
      _ => null,
    };
    final small = switch (group) {
      SmallGroup(:final id) => smallGroups.byId(id),
      _ => null,
    };
    final name = switch (group) {
      ServiceGroup(:final id) => services?.byId(id)?.name,
      MinistryGroup() => ministry?.name,
      SmallGroup() => small?.name,
    };
    final service = small?.service;
    // 行政 sees a service's 人數 here too, and changes nothing.
    final sees =
        me != null &&
        (me.managesGroup(group, service: service) || (group is ServiceGroup && me.readsAttendance(group.key)));
    if (me == null || name == null || members == null || !sees) {
      return Scaffold(appBar: AppBar());
    }
    final admin = me.isAdmin;
    // A 小組's service's 負責人 open, change and close it, and name its 小組長.
    final editsSmall = small != null && me.mayEditSmallGroup(small.service, small.service);
    bool isLead(Member m) => m.leadsGroup(group);
    final leaders = [...members.where(isLead)]..sort((a, b) => a.name.compareTo(b.name));
    final addable = [
      for (final m in members)
        if (!m.isIn(group) && me.mayMove(m, group, service: service)) m,
    ]..sort((a, b) => a.name.compareTo(b.name));
    final staff = [...members.where((m) => m.isIn(group))]..sort((a, b) => a.name.compareTo(b.name));
    final candidates = group is SmallGroup
        ? const <Candidate>[]
        : groupCandidates(group, ref.watch(_allRostersProvider).value ?? const [], members, ministry);
    final serviceSmallGroups = switch (group) {
      ServiceGroup(:final id) => [...smallGroups.where((g) => g.service == id)],
      _ => const <SmallGroupDetails>[],
    };
    final opensSmall = switch (group) {
      ServiceGroup(:final id) => me.mayEditSmallGroup(null, id),
      _ => false,
    };
    final attendance = attendanceOn && group is! MinistryGroup
        ? ref.watch(attendanceGroupsProvider).where((g) => g.key == group.key).firstOrNull
        : null;
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
          if (small != null)
            ListSection(
              children: [
                ListRow(
                  title: l10n.smallGroupName,
                  value: small.name,
                  chevron: editsSmall,
                  onTap: editsSmall ? () => _renameSmall(context, ref, small) : null,
                ),
                ListRow(title: l10n.smallGroupService, value: services?.byId(small.service)?.name, chevron: false),
                // When it meets matters only to 回報人數; its 小組長 set it too.
                if (attendanceOn)
                  ListRow(
                    title: l10n.smallGroupMeets,
                    value: smallGroupMeetsLabel(l10n, small),
                    onTap: () => _meets(context, ref, small),
                  ),
              ],
            ),
          ListSection(
            header: group is SmallGroup ? l10n.identitySmallGroupLead : l10n.leads,
            footer: leaders.isEmpty ? (group is SmallGroup ? l10n.noSmallGroupLeads : l10n.noLeads) : null,
            children: [
              for (final m in leaders)
                ListRow(
                  title: m.name,
                  chevron: false,
                  trailing: editsSmall
                      ? RowButton(
                          label: l10n.removeShort,
                          semanticsLabel: l10n.removeIdentityLabel(l10n.identitySmallGroupLeadOf(name)),
                          onPressed: () => _setSmallLeads(
                            context,
                            ref,
                            small,
                            [
                              for (final l in leaders)
                                if (l.uid != m.uid) l.uid,
                            ],
                            was: [for (final l in leaders) l.uid],
                            done: l10n.identityRemoved(l10n.identitySmallGroupLeadOf(name)),
                          ),
                        )
                      : null,
                ),
              if (admin && group is! SmallGroup)
                ListRow(
                  title: l10n.assignLead,
                  leading: const Icon(Symbols.add_rounded),
                  chevron: false,
                  onTap: () => _assignLead(context, ref, members.where((m) => !isLead(m)).toList(), name),
                ),
              if (editsSmall)
                ListRow(
                  title: l10n.assignSmallGroupLead,
                  leading: const Icon(Symbols.add_rounded),
                  chevron: false,
                  onTap: () => _assignSmallLead(context, ref, small, members.where((m) => !isLead(m)).toList(), [
                    for (final l in leaders) l.uid,
                  ], name),
                ),
            ],
          ),
          // Above the 同工, which may be many.
          if (serviceSmallGroups.isNotEmpty || opensSmall)
            ListSection(
              header: l10n.smallGroups,
              children: [
                for (final g in serviceSmallGroups)
                  ListRow(
                    title: g.name,
                    subtitle: attendanceOn ? smallGroupMeetsLabel(l10n, g) : null,
                    onTap: () => context.push('/me/groups/small/${g.id}'),
                  ),
                if (opensSmall)
                  ListRow(
                    title: l10n.addSmallGroup,
                    leading: const Icon(Symbols.add_rounded),
                    chevron: false,
                    onTap: () => _addSmall(context, ref, group.id),
                  ),
              ],
            ),
          if (attendance != null) AttendanceSection(group: attendance),
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
                    MinistryGroup() || SmallGroup() => null,
                  },
                  chevron: false,
                  // Taken out at once, with 復原; only who this lead may move.
                  trailing: me.mayMove(m, group, service: service)
                      ? RowButton(
                          label: l10n.moveOutShort,
                          semanticsLabel: l10n.removeFromGroupLabel(m.name, name),
                          onPressed: () => runWithUndo(
                            context,
                            l10n.removedFromGroup(m.name, name),
                            () => ref.read(churchWritesProvider).groupMember(m, group, member: false),
                          ),
                        )
                      : null,
                ),
              if (addable.isNotEmpty)
                ListRow(
                  title: l10n.addGroupStaff,
                  leading: const Icon(Symbols.add_rounded),
                  chevron: false,
                  onTap: () => _add(context, ref, addable, name),
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
                    trailing: RowButton(
                      label: l10n.addAsStaff,
                      semanticsLabel: l10n.addAsStaffLabel(cand.member.name, name),
                      onPressed: () => runWithUndo(
                        context,
                        l10n.addedToGroup(cand.member.name, name),
                        () => ref
                            .read(churchWritesProvider)
                            .groupMember(cand.member, group, member: true, duties: cand.served.keys.toList()),
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
          if (editsSmall)
            ListSection(
              children: [
                ListRow(
                  title: l10n.deleteSmallGroup,
                  destructive: true,
                  chevron: false,
                  onTap: () => _deleteSmall(context, ref, small),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 新增小組 in service [service]: named, then its page.
  Future<void> _addSmall(BuildContext context, WidgetRef ref, String service) async {
    final l10n = L10n.of(context);
    final name = await promptText(
      context,
      title: l10n.addSmallGroup,
      hint: l10n.smallGroupName,
      maxLength: TextLimits.profileName,
    );
    if (name == null || !context.mounted) return;
    try {
      final id = await ref.churchData.saveSmallGroup(SmallGroupDetails(id: '', name: name, service: service));
      if (context.mounted) unawaited(context.push('/me/groups/small/$id'));
    } catch (e) {
      if (context.mounted) showToast(context, saveErrorText(l10n, e));
    }
  }

  /// Saves [next], with [leads] its 小組長; [done] said after, with 復原
  /// putting back [was] when given.
  Future<void> _saveSmall(
    BuildContext context,
    WidgetRef ref,
    SmallGroupDetails next, {
    List<String>? leads,
    List<String>? was,
    String? done,
  }) async {
    final l10n = L10n.of(context);
    final data = ref.churchData;
    try {
      await data.saveSmallGroup(next, leads: leads);
      if (done != null && context.mounted) {
        showToast(context, done, onUndo: was == null ? null : () => data.saveSmallGroup(next, leads: was));
      }
    } catch (e) {
      if (context.mounted) showToast(context, saveErrorText(l10n, e));
    }
  }

  Future<void> _renameSmall(BuildContext context, WidgetRef ref, SmallGroupDetails small) async {
    final l10n = L10n.of(context);
    final name = await promptText(
      context,
      title: l10n.smallGroupName,
      hint: l10n.smallGroupName,
      initial: small.name,
      maxLength: TextLimits.profileName,
    );
    if (name == null || name == small.name || !context.mounted) return;
    await _saveSmall(context, ref, small.copyWith(name: name));
  }

  Future<void> _meets(BuildContext context, WidgetRef ref, SmallGroupDetails small) async {
    final next = await pickSmallGroupMeets(context, small, ref.read(todayProvider));
    if (next == null || next == small || !context.mounted) return;
    await _saveSmall(context, ref, next);
  }

  /// [small]'s 小組長 now [leads], who were [was].
  Future<void> _setSmallLeads(
    BuildContext context,
    WidgetRef ref,
    SmallGroupDetails small,
    List<String> leads, {
    required List<String> was,
    required String done,
  }) => _saveSmall(context, ref, small, leads: leads, was: was, done: done);

  /// 指派小組長: anyone in the church, picked from a list, added to those there are.
  Future<void> _assignSmallLead(
    BuildContext context,
    WidgetRef ref,
    SmallGroupDetails small,
    List<Member> others,
    List<String> leads,
    String name,
  ) async {
    final l10n = L10n.of(context);
    others.sort((a, b) => a.name.compareTo(b.name));
    final picked = await showAppSheet<Member>(
      context,
      expand: others.length > 8,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: ListSection(
            header: l10n.assignSmallGroupLead,
            children: [for (final m in others) ListRow(title: m.name, onTap: () => Navigator.pop(context, m))],
          ),
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    await _setSmallLeads(
      context,
      ref,
      small,
      [...leads, picked.uid],
      was: leads,
      done: l10n.identityAdded(l10n.identitySmallGroupLeadOf(name)),
    );
  }

  /// 關閉小組, once asked: its 小組長 and 同工 come out of it; its 人數 stay.
  Future<void> _deleteSmall(BuildContext context, WidgetRef ref, SmallGroupDetails small) async {
    final l10n = L10n.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.deleteSmallGroupTitle(small.name),
      message: l10n.deleteSmallGroupBody,
      action: l10n.deleteSmallGroup,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.churchData.deleteSmallGroup(small.id);
      if (context.mounted) {
        showToast(context, l10n.smallGroupDeleted(small.name));
        context.pop();
      }
    } catch (e) {
      if (context.mounted) showToast(context, saveErrorText(l10n, e));
    }
  }

  /// 加入同工: anyone in the church this lead may add, picked from a list.
  Future<void> _add(BuildContext context, WidgetRef ref, List<Member> addable, String name) async {
    final l10n = L10n.of(context);
    final picked = await showAppSheet<Member>(
      context,
      expand: addable.length > 8,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: ListSection(
            header: l10n.addGroupStaff,
            children: [for (final m in addable) ListRow(title: m.name, onTap: () => Navigator.pop(context, m))],
          ),
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    await runWithUndo(
      context,
      l10n.addedToGroup(picked.name, name),
      () => ref.read(churchWritesProvider).groupMember(picked, group, member: true),
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
      SmallGroup(:final id) => SmallGroupLead(id),
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
