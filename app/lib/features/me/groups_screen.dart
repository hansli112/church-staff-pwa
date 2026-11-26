import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:intl/intl.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/limits.dart';
import '../../domain/models.dart';
import '../../domain/staff.dart';
import '../../domain/text.dart';
import '../../domain/upcoming_events.dart';
import '../../l10n/app_localizations.dart';
import '../../state/attendance.dart';
import '../../state/calendar.dart';
import '../../state/church_writes.dart';
import '../../state/providers.dart';
import '../../state/staff_actions.dart';
import '../calendar/event_sheet.dart';
import '../common/errors.dart';
import '../common/site_pages.dart';
import '../common/saving_indicator.dart';
import '../rosters/day_block.dart';
import '../rosters/format.dart';
import '../rosters/future_changes.dart';
import 'attendance.dart';
import 'service_settings.dart';
import 'service_staff.dart';
import 'unread_page.dart';

/// What of a service has a page of its own, a row on the service's.
enum ServicePart {
  duties('duties'),
  events('events'),
  smallGroups('small-groups');

  const ServicePart(this.path);

  /// Its page's, under the service's.
  final String path;

  /// Its row's on the service's page, and its own page's.
  String title(L10n l10n) => switch (this) {
    duties => l10n.templateDuties,
    events => l10n.commonEvents,
    smallGroups => l10n.smallGroups,
  };
}

/// The page of [service]'s [part].
String servicePartPage(String service, ServicePart part) => '/me/groups/service/$service/${part.path}';

/// [service]'s row opening its [part], with how many it has: [count] in
/// [words] (「8 項」), or 沒有.
ListRow _partRow(BuildContext context, Service service, ServicePart part, int count, String Function(int) words) {
  final l10n = L10n.of(context);
  return ListRow(
    title: part.title(l10n),
    value: count == 0 ? l10n.servicePartNone : words(count),
    onTap: () => context.push(servicePartPage(service.id, part)),
  );
}

/// A group's 聚會人數 row in a section of its own; none for who does not see it.
Widget? _attendanceSection(BuildContext context, WidgetRef ref, AttendanceGroup group) =>
    switch (groupAttendanceRow(context, ref, group)) {
      final row? => SliverToBoxAdapter(child: ListSection(children: [row])),
      null => null,
    };

/// The page of [group]: `/me/groups/service/<id>`, `ministry/<id>` or
/// `small/<id>`.
String groupPage(ChurchGroup group) => '/me/groups/${group.key.replaceFirst(':', '/')}';

/// A service's, 小組's or 其他聚會's 人數 page (#95); a 其他聚會 has no other.
String attendancePage(ChurchGroup group) => switch (group) {
  GatheringGroup(:final id) => '/me/attendance/gathering/$id',
  _ => '${groupPage(group)}/attendance',
};

/// Where [group]'s 同工 are added: for a service, the page of its 同工;
/// otherwise the group's own page.
String groupStaffPage(ChurchGroup group) => switch (group) {
  ServiceGroup() => '${groupPage(group)}/staff',
  _ => groupPage(group),
};

/// 聚會與事工 (#82, #94), for admins: every service, put in order and
/// added here, and every 事工, with who leads it; each opens its page.
class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final ministries = ref.watch(ministriesProvider).value;
    final members = ref.watch(membersProvider).value ?? const <Member>[];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.groupsTitle), actions: const [SavingIndicator()]),
      body: CustomScrollView(
        slivers: [
          const ServiceListSection(),
          SliverToBoxAdapter(
            child: ListSection(
              header: l10n.ministries,
              footer: l10n.ministriesFooter,
              children: [
                for (final m in ministries?.ministries ?? const <Ministry>[])
                  ListRow(
                    title: m.name,
                    subtitle: ministryLine(l10n, m, members),
                    onTap: () => context.push('/me/groups/ministry/${m.id}'),
                  ),
                ListRow(
                  title: l10n.addMinistry,
                  leading: const Icon(Symbols.add_rounded),
                  chevron: false,
                  onTap: ministries == null ? null : () => addMinistry(context, ref, ministries),
                ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: Space.xl)),
        ],
      ),
    );
  }
}

/// 新增事工 on 聚會與事工: named, its 負責人 assigned, then its page, where
/// its events are made. 取消 leaves the 負責人 for its page too.
Future<void> addMinistry(BuildContext context, WidgetRef ref, MinistrySettings settings) async {
  final l10n = L10n.of(context);
  final name = await promptText(
    context,
    title: l10n.addMinistry,
    hint: l10n.ministryName,
    maxLength: TextLimits.profileName,
  );
  if (name == null || !context.mounted) return;
  final id = newMinistryId(settings.ids);
  final before = settings.ministries;
  final ok = await runWithUndo(
    context,
    l10n.saved,
    () => ref.read(churchWritesProvider).ministries(before, [
      ...before,
      Ministry(id: id, name: name),
    ]),
  );
  if (!ok || !context.mounted) return;
  final members = ref.read(membersProvider).value ?? const <Member>[];
  await assignLead(context, ref, MinistryLead(id), l10n.identityLeadOf(name), members);
  if (context.mounted) unawaited(context.push('/me/groups/ministry/$id'));
}

/// A fresh 事工 ID that was never used in this church.
String newMinistryId(List<String> taken) {
  final rng = Random();
  while (true) {
    final id = 'm${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${rng.nextInt(1296).toRadixString(36)}';
    if (!taken.contains(id)) return id;
  }
}

/// Under a 事工 in 聚會與事工: who leads it, 「林豪佳、何宗婷」; null for
/// nobody yet.
String? ministryLine(L10n l10n, Ministry ministry, List<Member> members) {
  final leads = [
    for (final m in members)
      if (m.leadMinistries.contains(ministry.id)) m.name,
  ]..sort();
  return leads.isEmpty ? null : leads.join(l10n.listSeparator);
}

/// Every roster saved, read once when a group's page opens: who served
/// what, for 排過…的服事.
final _allRostersProvider = FutureProvider.autoDispose<List<Roster>>((ref) => ref.churchData.readOnce.rosters());

/// Someone who served [group]'s duties without being one of its 同工: each
/// duty and how many times.
typedef Candidate = ({Member member, Map<String, int> served});

/// Who served service [group] on [rosters] and is not one of its 同工,
/// most served first.
List<Candidate> groupCandidates(ServiceGroup group, List<Roster> rosters, List<Member> members) {
  final byUid = {for (final m in members) m.uid: m};
  final served = <String, Map<String, int>>{};
  for (final r in rosters) {
    if (r.forEvent?.cancelled ?? false) continue;
    for (final d in r.duties) {
      if (r.isEvent || r.type != group.id) continue;
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

/// [group]'s 同工 by name, who [me] may add to it by name, and for a
/// service who served it without being one, those [me] may add.
({List<Member> staff, List<Member> addable, List<Candidate> candidates}) groupPeople(
  WidgetRef ref,
  Member me,
  List<Member> members,
  ChurchGroup group,
) {
  int byName(Member a, Member b) => a.name.compareTo(b.name);
  return (
    staff: [...members.where((m) => m.isIn(group))]..sort(byName),
    addable: [
      for (final m in members)
        if (!m.isIn(group) && me.mayMove(m, group)) m,
    ]..sort(byName),
    candidates: group is ServiceGroup
        ? [
            for (final c in groupCandidates(group, ref.watch(_allRostersProvider).value ?? const [], members))
              if (me.mayMove(c.member, group)) c,
          ]
        : const <Candidate>[],
  );
}

/// A service's 同工, which may be a hundred: searched, 加入同工 at the
/// top, then who served it without being one, then each 同工 to 移出.
class GroupStaffScreen extends ConsumerStatefulWidget {
  const GroupStaffScreen({super.key, required this.group});

  final ServiceGroup group;

  @override
  ConsumerState<GroupStaffScreen> createState() => _GroupStaffScreenState();
}

class _GroupStaffScreenState extends ConsumerState<GroupStaffScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final name = ref.watch(churchGroupsProvider)?.byKey(widget.group.key)?.name;
    final me = ref.watch(meProvider).value;
    // 行政 reads them, as on the service's page.
    if (name == null || me == null || !(me.managesGroup(widget.group) || me.readsAttendance(widget.group))) {
      return unreadPage(context, ref, [meProvider, servicesProvider, ministriesProvider, smallGroupsProvider]);
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.groupStaffTitle(name)), actions: const [SavingIndicator()]),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
            child: SearchField(hint: l10n.searchMembers, onChanged: (q) => setState(() => _query = q)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: Space.xl),
              children: [GroupStaffSections(group: widget.group, name: name, query: _query, addFirst: true)],
            ),
          ),
        ],
      ),
    );
  }
}

/// [group]'s 同工, each to 移出 for who may move them, and 加入同工 ([addFirst]:
/// above them, in its own section); then, for a service, who served it
/// without being one, each to 加為同工. Only names matching [query]. In a
/// service, tapping one of its 同工 (or one just added) opens what they
/// serve there and their 小組.
class GroupStaffSections extends ConsumerWidget {
  const GroupStaffSections({
    super.key,
    required this.group,
    required this.name,
    this.query = '',
    this.addFirst = false,
  });

  final ChurchGroup group;

  /// The group's name.
  final String name;
  final String query;
  final bool addFirst;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final me = ref.watch(meProvider).value;
    final everyone = ref.watch(staffProvider).value;
    final members = everyone?.all;
    if (me == null || everyone == null || members == null) return const SizedBox.shrink();
    String? lineOf(List<String> parts) => parts.isEmpty ? null : parts.join(l10n.dotSeparator);
    final (:staff, :addable, :candidates) = groupPeople(ref, me, members, group);
    // A service's takes someone new by name too, who may add a plain 同工.
    final byName = group is ServiceGroup && me.addsStaffTo(group);
    final add = addable.isEmpty && !byName
        ? null
        : ListRow(
            title: l10n.addGroupStaff,
            leading: const Icon(Symbols.add_rounded),
            chevron: false,
            onTap: () => _add(context, ref, addable, staff: everyone, byName: byName),
          );
    final shownStaff = [
      for (final m in staff)
        if (matchesSearch(m.name, query)) m,
    ];
    final shownCandidates = [
      for (final c in candidates)
        if (matchesSearch(c.member.name, query)) c,
    ];
    return Column(
      children: [
        if (addFirst && add != null) ListSection(children: [add]),
        if (shownCandidates.isNotEmpty && addFirst) _candidates(context, ref, shownCandidates),
        ListSection(
          header: l10n.groupStaff,
          footer: staff.isEmpty
              ? l10n.noGroupStaff
              : shownStaff.isEmpty
              ? l10n.noMembersFound
              : null,
          children: [
            for (final m in shownStaff)
              ListRow(
                title: m.name,
                subtitle: lineOf([
                  if (group case ServiceGroup(:final id))
                    if (m.zones.where((z) => z.serviceType == id).firstOrNull?.duties case final duties?
                        when duties.isNotEmpty)
                      duties.join(l10n.listSeparator),
                ]),
                chevron: false,
                // What they serve there and their 小組, for who may move them.
                onTap: group is ServiceGroup && me.mayMove(m, group) ? () => _edit(context, m) : null,
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
            if (!addFirst && add != null) add,
          ],
        ),
        if (shownCandidates.isNotEmpty && !addFirst) _candidates(context, ref, shownCandidates),
      ],
    );
  }

  Widget _candidates(BuildContext context, WidgetRef ref, List<Candidate> candidates) {
    final l10n = L10n.of(context);
    return ListSection(
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
    );
  }

  /// 加入同工: anyone in the church this lead may add, picked from a list
  /// with a search; or, [byName], someone nobody here is named, who does not
  /// use the app (addByName). Then what they serve there.
  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    List<Member> addable, {
    required Staff staff,
    required bool byName,
  }) async {
    final l10n = L10n.of(context);
    final picked = await showAppSheet<Object>(
      context,
      expand: true,
      builder: (context) => _AddStaffSheet(addable: addable, staff: staff, byName: byName),
    );
    if (!context.mounted) return;
    switch (picked) {
      case final Member m:
        final added = await runWithUndo(
          context,
          l10n.addedToGroup(m.name, name),
          () => ref.read(churchWritesProvider).groupMember(m, group, member: true),
        );
        if (added && group is ServiceGroup && context.mounted) await _edit(context, m);
      case final String typed:
        try {
          final id = await ref.read(staffActionsProvider).add(typed, group.id);
          if (!context.mounted) return;
          Haptics.success();
          showToast(context, l10n.addedToGroup(typed, name));
          await _edit(context, Member(uid: id, name: typed));
        } catch (e) {
          if (!context.mounted) return;
          // Someone added them meanwhile, or the list was not up to date.
          showToast(context, nameErrorText(l10n, e, typed));
        }
    }
  }

  /// What [person] serves in this service and their 小組 in it, each
  /// ticked through the backend, as a 負責人 may (an admin alike).
  Future<void> _edit(BuildContext context, Member person) => showAppSheet<void>(
    context,
    builder: (context) => SafeArea(
      child: Consumer(
        builder: (context, ref, _) {
          final now = ref.watch(
            staffProvider.select((v) => v.value?.all.where((m) => m.uid == person.uid).firstOrNull),
          );
          final service = ref.watch(servicesProvider.select((v) => v.value?.byId(group.id)));
          final smallGroups = ref.watch(smallGroupsProvider).value ?? const <SmallGroupDetails>[];
          if (now == null || service == null) return const SizedBox.shrink();
          Future<bool> saved(Future<void> write) => savedOrSaid(context, write);

          return SingleChildScrollView(
            child: ServiceStaffSection(
              person: now,
              service: service,
              header: now.name,
              smallGroups: [...smallGroups.where((g) => g.service == service.id)],
              onDuty: (duty, on) => saved(
                (on ? ref.churchData.grantDuty : ref.churchData.revokeDuty)(now.uid, service.id, duty),
              ),
              onSmallGroup: (g, on) => saved(ref.read(churchWritesProvider).groupMember(now, g.group, member: on).done),
            ),
          );
        },
      ),
    ),
  );
}

/// A service's [part] on a page of its own, from the row on the service's
/// page (2026-11-23): there each as the page had it before.
class ServicePartScreen extends ConsumerWidget {
  const ServicePartScreen({super.key, required this.serviceId, required this.part});

  final String serviceId;
  final ServicePart part;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final me = ref.watch(meProvider).value;
    final service = ref.watch(servicesProvider).value?.byId(serviceId);
    final members = ref.watch(staffProvider).value?.all;
    final group = ServiceGroup(serviceId);
    // Who sees the service's page, 行政 too (#93).
    if (me == null || service == null || members == null || !(me.managesGroup(group) || me.readsAttendance(group))) {
      return unreadPage(context, ref, [meProvider, servicesProvider, staffProvider]);
    }
    final editsSettings = me.editsServiceSettings;
    return Scaffold(
      appBar: AppBar(
        title: Text(part.title(l10n)),
        actions: const [SavingIndicator()],
      ),
      body: CustomScrollView(
        slivers: [
          switch (part) {
            ServicePart.duties => serviceDutiesSliver(context, ref, service, admin: editsSettings),
            ServicePart.events => serviceEventsSliver(context, ref, service, admin: editsSettings),
            ServicePart.smallGroups => _SmallGroupsSection(
              service: serviceId,
              smallGroups: [...?ref.watch(smallGroupsProvider).value?.where((g) => g.service == serviceId)],
              opens: me.mayEditSmallGroup(null, serviceId),
              attendanceOn: ref.watch(churchProvider.select((c) => c.value?.attendanceSince != null)),
            ),
          },
          const SliverToBoxAdapter(child: SizedBox(height: Space.xl)),
        ],
      ),
    );
  }
}

/// 加入同工's list: those who may be added, narrowed by a search; with
/// [byName], a name nobody in [everyone] has is offered as someone new.
/// Closes with the [Member] picked, or the name typed.
class _AddStaffSheet extends StatefulWidget {
  const _AddStaffSheet({required this.addable, required this.staff, required this.byName});

  final List<Member> addable;
  final Staff staff;
  final bool byName;

  @override
  State<_AddStaffSheet> createState() => _AddStaffSheetState();
}

class _AddStaffSheetState extends State<_AddStaffSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final typed = _query.trim();
    final known = widget.staff.hasName(typed);
    return SafeArea(
      child: Column(
        children: [
          SheetBar(title: l10n.addGroupStaff, actions: const []),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
            child: SearchField(hint: l10n.searchMembers, onChanged: (q) => setState(() => _query = q)),
          ),
          Expanded(
            child: ListView(
              children: [
                ListSection(
                  children: [
                    for (final m in widget.addable)
                      if (matchesSearch(m.name, _query)) ListRow(title: m.name, onTap: () => Navigator.pop(context, m)),
                    if (widget.byName && typed.isNotEmpty && !known)
                      ListRow(
                        title: l10n.pickerUseName(typed),
                        subtitle: l10n.noAccount,
                        leading: const Icon(Symbols.add_rounded),
                        onTap: () => Navigator.pop(context, typed),
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

/// One group's page (#82, #94). A service's: its name and weekday, its
/// 負責人, then a row each opening its 服事項目, 常用特別活動, 小組 (#85),
/// 同工 (and those who served it without being one) and 人數. A 事工's:
/// its name, its 負責人 and its events on the calendar; it has no 同工 of
/// its own. A 小組's, managed also by its service's 負責人: when it meets,
/// its 小組長 (as many as it has), its 人數 and its 同工. Admins assign and
/// 移出 a 負責人 here; a 牧者 only on their own page.
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
    final members = ref.watch(staffProvider).value?.all;
    final attendanceOn = ref.watch(churchProvider.select((c) => c.value?.attendanceSince != null));
    final service = switch (group) {
      ServiceGroup(:final id) => services?.byId(id),
      _ => null,
    };
    final ministry = switch (group) {
      MinistryGroup(:final id) => ministries?.byId(id),
      _ => null,
    };
    final small = switch (group) {
      SmallGroup(:final id) => smallGroups.byId(id),
      _ => null,
    };
    // 行政 sees its 人數 here too, from 人數總覽 (#93), and changes nothing else.
    final sees = me != null && (me.managesGroup(group) || me.readsAttendance(group));
    if (me == null || name == null || members == null || !sees) {
      return unreadPage(context, ref, [
        meProvider,
        servicesProvider,
        ministriesProvider,
        smallGroupsProvider,
        staffProvider,
      ]);
    }
    final admin = me.isAdmin;
    // A 小組's service's 負責人 open, change and close it, and name its 小組長.
    final editsSmall = small != null && me.mayEditSmallGroup(small.service, small.service);
    bool isLead(Member m) => m.leadsGroup(group);
    final leaders = [...members.where(isLead)]..sort((a, b) => a.name.compareTo(b.name));
    final (:staff, addable: _, :candidates) = groupPeople(ref, me, members, group);
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
    Widget box(Widget child) => SliverToBoxAdapter(child: child);
    // What a 小組長 does here is the one most often asked.
    final guide = group is SmallGroup ? const [GuideButton(Guide.smallGroups)] : const <Widget>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        // Leads' changes wait on the backend as much as an admin's (2026-11-23).
        actions: savingActions(guide),
      ),
      body: CustomScrollView(
        slivers: [
          if (service != null) box(serviceBasicsSection(context, ref, service, admin: me.editsServiceSettings)),
          if (admin && ministry != null)
            box(
              ListSection(
                children: [
                  ListRow(
                    title: l10n.ministryName,
                    value: ministry.name,
                    onTap: () => _rename(context, ref, ministry),
                  ),
                ],
              ),
            ),
          if (small != null)
            box(
              ListSection(
                // Which service, over the rows: one without ＞ among those
                // with it read as broken (2026-11-19).
                header: switch (services?.byId(small.service)?.name) {
                  final s? => l10n.smallGroupOfService(s),
                  null => null,
                },
                children: [
                  ListRow(
                    title: l10n.smallGroupName,
                    value: small.name,
                    chevron: editsSmall,
                    onTap: editsSmall ? () => _renameSmall(context, ref, small) : null,
                  ),
                  // When it meets matters only to 回報人數; its 小組長 set it too.
                  if (attendanceOn)
                    ListRow(
                      title: l10n.smallGroupMeets,
                      value: smallGroupMeetsLabel(l10n, small),
                      // Not 行政, who sees it from 人數總覽 (#93).
                      chevron: me.schedules(small.group),
                      onTap: me.schedules(small.group) ? () => changeMeetingTime(context, ref, small.group) : null,
                    ),
                ],
              ),
            ),
          // A 小組's 小組長, often a couple who lead it together; its
          // service's 負責人 name them too, through the backend.
          if (small != null)
            box(
              ListSection(
                header: l10n.identitySmallGroupLead,
                footer: leaders.isEmpty && !editsSmall ? l10n.smallGroupLeadUnassigned : null,
                children: [
                  for (final m in leaders)
                    ListRow(
                      title: m.name,
                      chevron: false,
                      trailing: editsSmall
                          ? RowButton(
                              label: l10n.moveOutShort,
                              semanticsLabel: l10n.removeIdentityLabel(l10n.identitySmallGroupLeadOf(name)),
                              onPressed: () => _setSmallLeads(context, ref, small, leaders, [
                                for (final l in leaders)
                                  if (l.uid != m.uid) l.uid,
                              ], removed: true),
                            )
                          : null,
                    ),
                  if (editsSmall)
                    ListRow(
                      title: leaders.isEmpty ? l10n.assignSmallGroupLead : l10n.addAnotherSmallGroupLead,
                      leading: const Icon(Symbols.add_rounded),
                      chevron: false,
                      onTap: () => _addSmallLead(context, ref, small, members, leaders),
                    ),
                ],
              ),
            )
          // A service or a 事工, its 負責人.
          else
            box(
              ListSection(
                header: l10n.leads,
                footer: leaders.isEmpty ? l10n.noLeads : null,
                children: [
                  for (final m in leaders)
                    leadRow(context, ref, m, leadOf(group), l10n.identityLeadOf(name), admin: admin),
                  // One is enough; more share it, all alike.
                  if (admin)
                    ListRow(
                      title: leaders.isEmpty ? l10n.assignLead : l10n.addAnotherLead,
                      leading: const Icon(Symbols.add_rounded),
                      chevron: false,
                      onTap: () => assignLead(
                        context,
                        ref,
                        leadOf(group),
                        l10n.identityLeadOf(name),
                        members.where((m) => !isLead(m)).toList(),
                        another: leaders.isNotEmpty,
                      ),
                    ),
                ],
              ),
            ),
          if (ministry != null) box(MinistryEvents(ministry: ministry, leaders: leaders)),
          // A service's lists each a row, on their own pages, so its page
          // keeps to a screen however long they are (2026-11-23). Its 同工
          // may be a hundred: listed with who served it without being one.
          if (service != null)
            box(
              ListSection(
                children: [
                  _partRow(context, service, ServicePart.duties, service.duties.length, l10n.serviceDutyCount),
                  if (me.editsServiceSettings || service.events.isNotEmpty)
                    _partRow(context, service, ServicePart.events, service.events.length, l10n.serviceItemCount),
                  if (serviceSmallGroups.isNotEmpty || opensSmall)
                    _partRow(
                      context,
                      service,
                      ServicePart.smallGroups,
                      serviceSmallGroups.length,
                      l10n.serviceItemCount,
                    ),
                  ListRow(
                    title: l10n.groupStaff,
                    value: l10n.groupStaffCount(staff.length),
                    onTap: () => context.push(groupStaffPage(group)),
                  ),
                  if (candidates.isNotEmpty)
                    ListRow(
                      title: l10n.groupCandidates(name),
                      value: l10n.groupStaffCount(candidates.length),
                      onTap: () => context.push(groupStaffPage(group)),
                    ),
                  if (attendance != null) ?groupAttendanceRow(context, ref, attendance),
                ],
              ),
            )
          else ...[
            if (attendance != null) ?_attendanceSection(context, ref, attendance),
            // A 小組's, here; a 事工's are those on its duties' lists (#94).
            if (ministry == null) box(GroupStaffSections(group: group, name: name)),
          ],
          if (admin && service != null)
            box(
              ListSection(
                children: [
                  ListRow(
                    title: l10n.deleteService,
                    destructive: true,
                    chevron: false,
                    onTap: () => ServiceEdits(context, ref, service).delete(
                      // Back once asked, off the list while the backend has
                      // it; opened from a link, the page has nothing under it.
                      leave: () => context.canPop() ? context.pop() : context.go('/me/groups'),
                    ),
                  ),
                ],
              ),
            ),
          if (admin && ministry != null)
            box(
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
            ),
          if (editsSmall)
            box(
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
            ),
          const SliverToBoxAdapter(child: SizedBox(height: Space.xl)),
        ],
      ),
    );
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

  /// 指派小組長 or 再加一位: anyone in the church but [leaders], picked
  /// from a list, beside them.
  Future<void> _addSmallLead(
    BuildContext context,
    WidgetRef ref,
    SmallGroupDetails small,
    List<Member> members,
    List<Member> leaders,
  ) async {
    final l10n = L10n.of(context);
    final picked = await pickLead(
      context,
      ref,
      [
        for (final m in members)
          if (!leaders.contains(m)) m,
      ],
      header: leaders.isEmpty ? l10n.assignSmallGroupLead : l10n.addAnotherSmallGroupLead,
    );
    if (picked == null || !context.mounted) return;
    await _setSmallLeads(context, ref, small, leaders, [for (final l in leaders) l.uid, picked.uid]);
  }

  /// [small]'s 小組長 from [leaders] to [next] (uids), with 復原.
  Future<void> _setSmallLeads(
    BuildContext context,
    WidgetRef ref,
    SmallGroupDetails small,
    List<Member> leaders,
    List<String> next, {
    bool removed = false,
  }) async {
    final l10n = L10n.of(context);
    final identity = l10n.identitySmallGroupLeadOf(small.name);
    await runWithUndo(
      context,
      removed ? l10n.identityRemoved(identity) : l10n.identityAdded(identity),
      () => ref
          .read(churchWritesProvider)
          .smallGroup(small, small, leadsBefore: [for (final l in leaders) l.uid], leads: next),
    );
  }

  /// 刪除小組, once asked: its 小組長 and 同工 come out of it; its 人數 stay.
  Future<void> _deleteSmall(BuildContext context, WidgetRef ref, SmallGroupDetails small) async {
    final l10n = L10n.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.deleteSmallGroupTitle(small.name),
      action: l10n.deleteSmallGroup,
    );
    if (!ok || !context.mounted) return;
    // Back at once, off the list while the backend deletes it (2026-11-23);
    // said on the page under it, this one gone.
    final feedback = Navigator.of(context).context;
    final data = ref.churchData;
    context.pop();
    try {
      await data.deleteSmallGroup(small.id);
      if (feedback.mounted) showToast(feedback, l10n.smallGroupDeleted(small.name));
    } catch (e) {
      if (feedback.mounted) showToast(feedback, saveErrorText(l10n, e));
    }
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

  Future<void> _delete(BuildContext context, WidgetRef ref, Ministry ministry) async {
    final before = ref.read(ministriesProvider).value?.ministries;
    if (before == null) return;
    // Back at once, off the list while the backend deletes it.
    unawaited(
      runWithUndo(
        context,
        L10n.of(context).ministryDeleted(ministry.name),
        () => ref.read(churchWritesProvider).ministries(before, [
          for (final m in before)
            if (m.id != ministry.id) m,
        ]),
      ),
    );
    context.pop();
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

/// A service's 小組, each opening its page, and 新增小組 for whoever
/// [opens] them: one being made shows at once, saving, then its page opens.
class _SmallGroupsSection extends ConsumerStatefulWidget {
  const _SmallGroupsSection({
    required this.service,
    required this.smallGroups,
    required this.opens,
    required this.attendanceOn,
  });

  final String service;
  final List<SmallGroupDetails> smallGroups;
  final bool opens;
  final bool attendanceOn;

  @override
  ConsumerState<_SmallGroupsSection> createState() => _SmallGroupsSectionState();
}

class _SmallGroupsSectionState extends ConsumerState<_SmallGroupsSection> {
  /// The names of the 小組 being made, until saved.
  final _adding = <String>[];

  /// A sliver: who opens them drags them in order, as everywhere lists them.
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    Widget row(SmallGroupDetails g) => ListRow(
      title: g.name,
      subtitle: widget.attendanceOn ? smallGroupMeetsLabel(l10n, g) : null,
      chevron: true,
      onTap: () => context.push('/me/groups/small/${g.id}'),
    );
    final after = [
      for (final name in _adding)
        if (!widget.smallGroups.any((g) => g.name == name))
          ListRow(
            title: name,
            chevron: false,
            trailing: Semantics(
              label: l10n.saving,
              child: const SizedBox.square(dimension: 18, child: CircularProgressIndicator.adaptive(strokeWidth: 2)),
            ),
          ),
      if (widget.opens)
        ListRow(title: l10n.addSmallGroup, leading: const Icon(Symbols.add_rounded), chevron: false, onTap: _add),
    ];
    if (!widget.opens) {
      return SliverToBoxAdapter(
        child: ListSection(children: [for (final g in widget.smallGroups) row(g), ...after]),
      );
    }
    return ReorderableSection<SmallGroupDetails>(
      items: widget.smallGroups,
      keyOf: (g) => g.id,
      row: row,
      onReorder: (next) async {
        try {
          await ref.churchData.orderSmallGroups(widget.service, [for (final g in next) g.id]);
        } catch (e) {
          if (mounted) showToast(this.context, saveErrorText(l10n, e));
        }
      },
      after: after,
    );
  }

  /// 新增小組: named, shown while saved, then its page.
  Future<void> _add() async {
    final l10n = L10n.of(context);
    final name = await promptText(
      context,
      title: l10n.addSmallGroup,
      hint: l10n.smallGroupName,
      maxLength: TextLimits.profileName,
    );
    if (name == null || !mounted) return;
    setState(() => _adding.add(name));
    try {
      final id = await ref.churchData.saveSmallGroup(SmallGroupDetails(id: '', name: name, service: widget.service));
      if (mounted) unawaited(context.push('/me/groups/small/$id'));
    } catch (e) {
      if (mounted) showToast(context, saveErrorText(l10n, e));
    } finally {
      if (mounted) setState(() => _adding.remove(name));
    }
  }
}

/// A 事工's events on the calendar from today, a few months ahead, each
/// opening it; 新增活動 for whoever may make its events; and what its
/// 負責人 ([leaders]) can do with them.
class MinistryEvents extends ConsumerWidget {
  const MinistryEvents({super.key, required this.ministry, required this.leaders});

  final Ministry ministry;
  final List<Member> leaders;

  /// How many months, this one included, its events are read for.
  static const months = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final ready = ref.watch(calendarSettingsProvider).value?.ready ?? false;
    if (!ready) return const SizedBox.shrink();
    final me = ref.watch(meProvider).value;
    final group = MinistryGroup(ministry.id).key;
    final today = ref.watch(todayProvider);
    final now = ref.watch(churchTimeZoneProvider).clock(ref.watch(clockProvider)());
    final events = upcomingEvents([
      for (var i = 0; i < months; i++)
        ref.watch(calendarEventsProvider(monthKey(DateTime.utc(today.year, today.month + i)))).value ??
            const <CalendarEvent>[],
    ], now: now).where((e) => e.group == group).toList();
    final makes = me?.mayWriteEvent(null, group) ?? false;
    final names = leaders.map((m) => m.name).join(l10n.listSeparator);
    return ListSection(
      header: l10n.ministryEvents,
      footer: leaders.isEmpty ? l10n.ministryOnceLeadsEvents : l10n.ministryLeadsCanEvents(leaders.length, names),
      children: [
        for (final e in events)
          ListRow(
            // As 首頁's 近期活動: one already under way is on today.
            leading: dayBlock(e.day.isBefore(today) ? today : e.day, today, color: e.color),
            title: e.title,
            subtitle: [
              dayBesideBlock(l10n, e.day.isBefore(today) ? today : e.day, today),
              if (!e.allDay && !e.day.isBefore(today)) DateFormat.Hm().format(e.start),
            ].join(' · '),
            onTap: () => (me?.editsEvent(e) ?? false)
                ? editEvent(context, ref, e, month: DateTime(e.start.year, e.start.month))
                : showEventDetail(context, e),
          ),
        if (makes)
          ListRow(
            title: l10n.calNewEvent,
            leading: const Icon(Symbols.add_rounded),
            chevron: false,
            onTap: () => editEvent(context, ref, null, month: DateTime(today.year, today.month), group: group),
          ),
      ],
    );
  }
}

/// The 身分 of [group]'s 負責人: a service's, a 事工's or a 小組's.
Identity leadOf(ChurchGroup group) => switch (group) {
  ServiceGroup(:final id) => ServiceLead(id),
  MinistryGroup(:final id) => MinistryLead(id),
  SmallGroup(:final id) => SmallGroupLead(id),
  GatheringGroup() => throw StateError('a 其他聚會 has no 負責人'),
};

/// 指派負責人 [lead] (shown as [identity], 「多媒體 負責人」): one of
/// [others], picked from a list, given it beside any who hold it
/// ([another]).
Future<void> assignLead(
  BuildContext context,
  WidgetRef ref,
  Identity lead,
  String identity,
  List<Member> others, {
  bool another = false,
}) async {
  final l10n = L10n.of(context);
  final picked = await pickLead(context, ref, others, header: another ? l10n.addAnotherLead : l10n.assignLead);
  if (picked == null || !context.mounted) return;
  await runWithUndo(
    context,
    l10n.identityAdded(identity),
    () => ref.read(churchWritesProvider).member(picked, picked.withIdentities([...picked.identities, lead])),
  );
}

/// One of the holders, [m], of [lead] (shown as [identity]). A service's
/// 牧者 says so and is changed only on their own page; a 負責人 an admin
/// takes out here at once, with 復原 (#94). None left is fine.
Widget leadRow(BuildContext context, WidgetRef ref, Member m, Identity lead, String identity, {required bool admin}) {
  final l10n = L10n.of(context);
  final pastor = switch (lead) {
    ServiceLead(:final service) => m.identities.any(
      (i) => i is PastorIdentity && (i.services == null || i.services!.contains(service)),
    ),
    _ => false,
  };
  return ListRow(
    title: m.name,
    subtitle: pastor ? l10n.identityPastor : null,
    chevron: false,
    trailing: admin && !pastor && m.identities.contains(lead)
        ? RowButton(
            label: l10n.moveOutShort,
            semanticsLabel: l10n.removeIdentityLabel(identity),
            onPressed: () => runWithUndo(
              context,
              l10n.identityRemoved(identity),
              () => ref.read(churchWritesProvider).member(m, m.withIdentities([...m.identities]..remove(lead))),
            ),
          )
        : null,
  );
}

/// A 負責人 or 小組長 picked from [others], searched by name; null if 取消.
/// Not 同工 with no account: a 身分 is held by someone who signs in.
Future<Member?> pickLead(BuildContext context, WidgetRef ref, List<Member> others, {required String header}) {
  final noAccount = ref.read(staffProvider).value?.noAccount ?? const <String>{};
  final sorted = [
    for (final m in others)
      if (!noAccount.contains(m.uid)) m,
  ]..sort((a, b) => a.name.compareTo(b.name));
  return showAppSheet<Member>(
    context,
    expand: true,
    builder: (_) => _LeadPicker(header: header, people: sorted),
  );
}

class _LeadPicker extends StatefulWidget {
  const _LeadPicker({required this.header, required this.people});

  final String header;
  final List<Member> people;

  @override
  State<_LeadPicker> createState() => _LeadPickerState();
}

class _LeadPickerState extends State<_LeadPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final m in widget.people)
        if (q.isEmpty || m.name.toLowerCase().contains(q)) m,
    ];
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
            child: SearchField(hint: l10n.searchMembers, onChanged: (q) => setState(() => _query = q)),
          ),
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                ListSection(
                  header: widget.header,
                  footer: shown.isEmpty ? l10n.noMembersFound : null,
                  children: [for (final m in shown) ListRow(title: m.name, onTap: () => Navigator.pop(context, m))],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
