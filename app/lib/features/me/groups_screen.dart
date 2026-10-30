import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
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

/// The page of [group]: `/me/groups/service/<id>`, `ministry/<id>` or
/// `small/<id>`.
String groupPage(ChurchGroup group) => '/me/groups/${group.key.replaceFirst(':', '/')}';

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
            header: l10n.servicesTitle,
            children: [
              for (final s in services) ListRow(title: s.name, onTap: () => context.push('/me/groups/service/${s.id}')),
            ],
          ),
          ListSection(
            header: l10n.ministries,
            footer: l10n.ministriesFooter,
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

  /// 新增事工, and on to setting it up: named, its duties picked (saved
  /// with it), its 負責人 assigned, then its page. 取消 at any step leaves
  /// the rest for its page.
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
    final services = ref.read(servicesProvider).value?.enabled ?? const <Service>[];
    // Null once 取消; none to pick, nothing to stop at.
    final duties = services.any((s) => s.duties.isNotEmpty)
        ? await pickMinistryDuties(context, services, const [])
        : const <MinistryDuty>[];
    if (!context.mounted) return;
    final before = settings.ministries;
    final ok = await runWithUndo(
      context,
      l10n.saved,
      () => ref.read(churchWritesProvider).ministries(before, [
        ...before,
        Ministry(id: id, name: name, duties: duties ?? const []),
      ]),
    );
    if (!ok || !context.mounted) return;
    if (duties != null) {
      final members = ref.read(membersProvider).value ?? const <Member>[];
      await assignLead(context, ref, MinistryGroup(id), name, members);
    }
    if (context.mounted) unawaited(context.push('/me/groups/ministry/$id'));
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
final _allRostersProvider = FutureProvider.autoDispose<List<Roster>>((ref) => ref.churchData.export.rosters());

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

  /// The group, as its page's path names it.
  final ChurchGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final named = ref.watch(churchGroupsProvider)?.byKey(this.group.key);
    // As the church has it: a 小組 with its service.
    final group = named?.group ?? this.group;
    final name = named?.name;
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
    // 行政 sees a service's 人數 here too, and changes nothing.
    final sees = me != null && (me.managesGroup(group) || (group is ServiceGroup && me.readsAttendance(group)));
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
        if (!m.isIn(group) && me.mayMove(m, group)) m,
    ]..sort((a, b) => a.name.compareTo(b.name));
    final staff = [...members.where((m) => m.isIn(group))]..sort((a, b) => a.name.compareTo(b.name));
    final candidates = group is SmallGroup
        ? const <Candidate>[]
        : [
            for (final c in groupCandidates(group, ref.watch(_allRostersProvider).value ?? const [], members, ministry))
              if (me.mayMove(c.member, group)) c,
          ];
    final serviceSmallGroups = switch (group) {
      ServiceGroup(:final id) => [...smallGroups.where((g) => g.service == id)],
      _ => const <SmallGroupDetails>[],
    };
    final opensSmall = switch (group) {
      ServiceGroup(:final id) => me.mayEditSmallGroup(null, id),
      _ => false,
    };
    final attendance = attendanceOn && group is! MinistryGroup
        ? ref.watch(attendanceGroupsProvider).where((g) => g.group == group).firstOrNull
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          if (admin && ministry != null)
            ListSection(
              footer: ministrySummary(l10n, ministry, services?.enabled ?? const [], leaders),
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
                ListRow(
                  title: l10n.identitySmallGroupLead,
                  value: leaders.isEmpty
                      ? l10n.smallGroupLeadUnassigned
                      : leaders.map((m) => m.name).join(l10n.listSeparator),
                  chevron: editsSmall,
                  onTap: editsSmall ? () => _assignSmallLead(context, ref, small, members, leaders, name) : null,
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
          // A 小組 has one 小組長, a row above; a service or a 事工, its 負責人.
          if (small == null)
            ListSection(
              header: l10n.leads,
              footer: leaders.isEmpty ? l10n.noLeads : null,
              children: [
                for (final m in leaders) ListRow(title: m.name, chevron: false),
                // One is enough; more share it, all alike.
                if (admin)
                  ListRow(
                    title: leaders.isEmpty ? l10n.assignLead : l10n.addAnotherLead,
                    leading: const Icon(Symbols.add_rounded),
                    chevron: false,
                    onTap: () => assignLead(
                      context,
                      ref,
                      group,
                      name,
                      members.where((m) => !isLead(m)).toList(),
                      another: leaders.isNotEmpty,
                    ),
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
            footer: group is MinistryGroup
                ? l10n.ministryStaffFooter(name)
                : staff.isEmpty
                ? l10n.noGroupStaff
                : null,
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
                  trailing: me.mayMove(m, group)
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

  /// Changes [small] to [next], refused once someone else changed it.
  Future<void> _saveSmall(BuildContext context, WidgetRef ref, SmallGroupDetails small, SmallGroupDetails next) async {
    final l10n = L10n.of(context);
    try {
      await ref.read(churchWritesProvider).smallGroup(small, next).done;
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
    await _saveSmall(context, ref, small, small.copyWith(name: name));
  }

  Future<void> _meets(BuildContext context, WidgetRef ref, SmallGroupDetails small) async {
    final next = await pickSmallGroupMeets(context, small, ref.read(todayProvider));
    if (next == null || next == small || !context.mounted) return;
    await _saveSmall(context, ref, small, next);
  }

  /// 指派小組長: the one, anyone in the church, picked from a list.
  /// Picking another takes the place of [leaders] (one, or from before,
  /// several); 取消指派 leaves none.
  Future<void> _assignSmallLead(
    BuildContext context,
    WidgetRef ref,
    SmallGroupDetails small,
    List<Member> members,
    List<Member> leaders,
    String name,
  ) async {
    final l10n = L10n.of(context);
    final everyone = [...members]..sort((a, b) => a.name.compareTo(b.name));
    final was = [for (final l in leaders) l.uid];
    // A uid, or '' for none.
    final picked = await showAppSheet<String>(
      context,
      expand: everyone.length > 8,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Above the list, which may be long.
              if (was.isNotEmpty)
                ListSection(
                  children: [
                    ListRow(
                      title: l10n.smallGroupLeadClear,
                      destructive: true,
                      onTap: () => Navigator.pop(context, ''),
                    ),
                  ],
                ),
              ListSection(
                header: l10n.assignSmallGroupLead,
                children: [
                  for (final m in everyone)
                    ListRow(title: m.name, selected: was.contains(m.uid), onTap: () => Navigator.pop(context, m.uid)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    final leads = [if (picked.isNotEmpty) picked];
    if (listEquals(leads, was)) return;
    final identity = l10n.identitySmallGroupLeadOf(name);
    await runWithUndo(
      context,
      picked.isEmpty ? l10n.identityRemoved(identity) : l10n.identityAdded(identity),
      () => ref.read(churchWritesProvider).smallGroup(small, small, leadsBefore: was, leads: leads),
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
    final picked = await pickMinistryDuties(context, services, ministry.duties);
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

/// 指派負責人 of [group], named [name]: one of [others], picked from a
/// list, made its 負責人 beside any it has ([another]).
Future<void> assignLead(
  BuildContext context,
  WidgetRef ref,
  ChurchGroup group,
  String name,
  List<Member> others, {
  bool another = false,
}) async {
  final l10n = L10n.of(context);
  final title = another ? l10n.addAnotherLead : l10n.assignLead;
  final sorted = [...others]..sort((a, b) => a.name.compareTo(b.name));
  final picked = await showAppSheet<Member>(
    context,
    expand: sorted.length > 8,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: ListSection(
          header: title,
          children: [for (final m in sorted) ListRow(title: m.name, onTap: () => Navigator.pop(context, m))],
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

/// The duties a 事工 links, ticked per service of [services] from
/// [initial]; null if 取消.
Future<List<MinistryDuty>?> pickMinistryDuties(
  BuildContext context,
  List<Service> services,
  List<MinistryDuty> initial,
) {
  return showAppSheet<List<MinistryDuty>>(
    context,
    expand: true,
    builder: (_) => _DutyPicker(services: services, initial: initial),
  );
}

/// What a 事工's 負責人 ([leads]) can do, told with its own settings, or
/// what it still needs: its duties place by place, its [services]' and
/// events', places with the same duties said together.
String ministrySummary(L10n l10n, Ministry ministry, List<Service> services, List<Member> leads) {
  if (ministry.duties.isEmpty) return l10n.ministryNeedsDuties;
  final places = [
    for (final s in services)
      if (ministry.dutiesIn(s.id) case final d when d.isNotEmpty) (place: s.name, duties: d),
    (place: l10n.ministryEvents, duties: ministry.dutiesIn(null)),
  ];
  final groups = <({List<String> places, Set<String> duties})>[];
  for (final p in places) {
    final same = groups.where((g) => setEquals(g.duties, p.duties)).firstOrNull;
    if (same != null) {
      same.places.add(p.place);
    } else {
      groups.add((places: [p.place], duties: p.duties));
    }
  }
  final duties = [
    for (final g in groups) l10n.dutiesOfServices(g.places.join(l10n.listSeparator), g.duties.join(l10n.listSeparator)),
  ].join(l10n.dutyGroupSeparator);
  return leads.isEmpty
      ? l10n.ministryOnceLeads(duties, ministry.name)
      : l10n.ministryLeadsCan(leads.length, leads.map((m) => m.name).join(l10n.listSeparator), duties, ministry.name);
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
    return UnsavedChanges(
      changed: () => !setEquals(_picked.toSet(), widget.initial.toSet()),
      child: Column(
        children: [
          SheetBar(
            title: l10n.ministryDuties,
            actions: [SecondaryButton(label: l10n.done, onPressed: () => Navigator.pop(context, _picked))],
          ),
          Expanded(
            child: ListView(
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
          ),
        ],
      ),
    );
  }
}
