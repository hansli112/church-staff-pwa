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
import '../common/saving_indicator.dart';
import '../rosters/future_changes.dart';
import 'attendance.dart';
import 'service_settings.dart';

/// The page of [group]: `/me/groups/service/<id>`, `ministry/<id>` or
/// `small/<id>`.
String groupPage(ChurchGroup group) => '/me/groups/${group.key.replaceFirst(':', '/')}';

/// 聚會與事工 (#82, #94), for admins: every service, put in order and
/// added here, and every 事工 with who leads it and what; each opens its
/// page. 服事設定 is part of a service's page now.
class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final ministries = ref.watch(ministriesProvider).value;
    final members = ref.watch(membersProvider).value ?? const <Member>[];
    final services = ref.watch(servicesProvider).value?.enabled ?? const <Service>[];
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
                    subtitle: ministryLine(l10n, m, services, members),
                    onTap: () => context.push('/me/groups/ministry/${m.id}'),
                  ),
                ListRow(
                  title: l10n.addMinistry,
                  leading: const Icon(Symbols.add_rounded),
                  chevron: false,
                  onTap: ministries == null ? null : () => _add(context, ref, ministries),
                ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: Space.xl)),
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

/// Under a 事工 in 聚會與事工: who leads it and the duties it leads, as
/// 「芳伶・敬拜、Vocal、司琴、鼓」; null when it has neither.
String? ministryLine(L10n l10n, Ministry ministry, List<Service> services, List<Member> members) {
  final leads = [
    for (final m in members)
      if (m.leadMinistries.contains(ministry.id)) m.name,
  ]..sort();
  final duties = {for (final d in ministry.duties) d.duty};
  final line = [
    if (leads.isNotEmpty) leads.join(l10n.listSeparator),
    if (duties.isNotEmpty) duties.join(l10n.listSeparator),
  ];
  return line.isEmpty ? null : line.join(l10n.dotSeparator);
}

/// Every roster saved, read once when a group's page opens: who served
/// what, for 排過…的服事.
final _allRostersProvider = FutureProvider.autoDispose<List<Roster>>((ref) => ref.churchData.readOnce.rosters());

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

/// One group's page (#82, #94). A service's: its settings (name, weekday,
/// 服事項目 with who is on each list, 常用特別活動; an admin's to change),
/// its 負責人, its 小組 (#85), its 人數, its 同工 and those who served it
/// without being one. A 事工's: its name, its 負責人 and the duties it
/// leads with their lists; it has no 同工 of its own. A 小組's, managed
/// also by its service's 負責人: when it meets, its 小組長, its 人數 and
/// its 同工. Admins assign and 移出 a 負責人 here; a 牧者 only on their own
/// page.
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
    final candidates = group is ServiceGroup
        ? [
            for (final c in groupCandidates(group, ref.watch(_allRostersProvider).value ?? const [], members, null))
              if (me.mayMove(c.member, group)) c,
          ]
        : const <Candidate>[];
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
    return Scaffold(
      appBar: AppBar(title: Text(name), actions: admin ? const [SavingIndicator()] : null),
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
                      // Not 行政, who sees it from 人數總覽 (#93).
                      chevron: me.schedulesSmallGroup(small.group),
                      onTap: me.schedulesSmallGroup(small.group) ? () => _meets(context, ref, small) : null,
                    ),
                ],
              ),
            ),
          // A 小組 has one 小組長, a row above; a service or a 事工, its 負責人.
          if (small == null)
            box(
              ListSection(
                header: l10n.leads,
                footer: leaders.isEmpty ? l10n.noLeads : null,
                children: [
                  for (final m in leaders) _leadRow(context, ref, m, name, admin: admin),
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
            ),
          if (service != null) ...[
            serviceDutiesSliver(context, ref, service, admin: me.editsServiceSettings),
            serviceEventsSliver(context, ref, service, admin: me.editsServiceSettings),
          ],
          if (ministry != null)
            box(
              _MinistryDuties(
                ministry: ministry,
                services: services?.services ?? const [],
                leaders: leaders,
                admin: admin,
              ),
            ),
          // Above the 同工, which may be many.
          if (serviceSmallGroups.isNotEmpty || opensSmall)
            box(
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
            ),
          if (attendance != null) box(AttendanceSection(group: attendance)),
          // A 事工's people are those on its duties' lists (#94).
          if (ministry == null)
            box(
              ListSection(
                header: l10n.groupStaff,
                footer: staff.isEmpty ? l10n.noGroupStaff : null,
                children: [
                  for (final m in staff)
                    ListRow(
                      title: m.name,
                      subtitle: switch (group) {
                        ServiceGroup(:final id) => switch (m.zones
                            .where((z) => z.serviceType == id)
                            .firstOrNull
                            ?.duties) {
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
            ),
          if (candidates.isNotEmpty)
            box(
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

  /// One of the 負責人, [m], of the group named [name]. A 牧者 of it says
  /// so and is changed only on their own page; a 負責人 an admin takes out
  /// here at once, with 復原 (#94). None left is fine.
  Widget _leadRow(BuildContext context, WidgetRef ref, Member m, String name, {required bool admin}) {
    final l10n = L10n.of(context);
    final lead = switch (group) {
      ServiceGroup(:final id) => ServiceLead(id) as Identity,
      MinistryGroup(:final id) => MinistryLead(id),
      SmallGroup(:final id) => SmallGroupLead(id),
    };
    final pastor = switch (group) {
      ServiceGroup(:final id) => m.identities.any(
        (i) => i is PastorIdentity && (i.services == null || i.services!.contains(id)),
      ),
      _ => false,
    };
    final identity = l10n.identityLeadOf(name);
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

/// What a 事工 leads (#94): each duty with who is on its list, opening
/// the duty's page; the service named too when it leads duties in more
/// than one. An admin picks the duties last.
class _MinistryDuties extends ConsumerWidget {
  const _MinistryDuties({required this.ministry, required this.services, required this.leaders, required this.admin});

  final Ministry ministry;
  final List<Service> services;
  final List<Member> leaders;
  final bool admin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final duties = [
      for (final s in services)
        for (final d in s.duties)
          if (ministry.duties.contains(MinistryDuty(s.id, d))) (service: s, duty: d),
    ];
    final places = {for (final d in duties) d.service.id}.length;
    return ListSection(
      header: l10n.ministryDuties,
      footer: ministrySummary(l10n, ministry, services.where((s) => s.enabled).toList(), leaders),
      children: [
        for (final d in duties)
          ListRow(
            title: places > 1 ? '${d.service.name}${l10n.dotSeparator}${d.duty}' : d.duty,
            subtitle: dutyPeopleLabel(ref, l10n, d.service.id, d.duty),
            onTap: () => context.push(dutyPage(d.service.id, d.duty)),
          ),
        if (admin)
          ListRow(
            title: l10n.ministryPickDuties,
            leading: const Icon(Symbols.checklist_rounded),
            chevron: false,
            onTap: () => _pick(context, ref),
          ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final picked = await pickMinistryDuties(context, services.where((s) => s.enabled).toList(), ministry.duties);
    final before = ref.read(ministriesProvider).value?.ministries;
    if (picked == null || before == null || !context.mounted) return;
    await runWithUndo(
      context,
      L10n.of(context).saved,
      () => ref.read(churchWritesProvider).ministries(before, [
        for (final m in before) m.id == ministry.id ? m.copyWith(duties: picked) : m,
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
      ? l10n.ministryOnceLeads(duties)
      : l10n.ministryLeadsCan(leads.length, leads.map((m) => m.name).join(l10n.listSeparator), duties);
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
