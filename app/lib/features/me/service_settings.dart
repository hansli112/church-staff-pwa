import 'dart:math';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../domain/staff_order.dart';
import '../../l10n/app_localizations.dart';
import '../../state/church_writes.dart';
import '../../state/providers.dart';
import '../../state/roster_actions.dart';
import '../rosters/future_changes.dart';
import '../common/errors.dart';
import '../common/labels.dart';
import '../common/saving_indicator.dart';

// A service's settings (#94), on its page in 聚會與事工: what used to be
// 服事設定. IDs only ever grow: a disabled service keeps its old rosters
// and 同工, and simply stops getting new days.

/// 聚會 in 聚會與事工: every service, a disabled one too, put in order by
/// dragging, and 新增聚會; each opens its page. Admins only.
class ServiceListSection extends ConsumerWidget {
  const ServiceListSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(servicesProvider).value;
    if (settings == null) return const SliverToBoxAdapter();
    final list = settings.services;

    Future<void> save(List<Service> next) async {
      try {
        await ref.read(churchWritesProvider).serviceList(list, next).done;
      } catch (e) {
        if (context.mounted) showToast(context, saveErrorText(l10n, e));
      }
    }

    Future<void> add() async {
      final name = await promptText(context, title: l10n.serviceAdd, hint: l10n.serviceName);
      if (name == null) return;
      final id = newServiceId(settings.ids);
      await save([...list, Service(id: id, name: name, weekday: DateTime.sunday)]);
      if (context.mounted) await context.push('/me/groups/service/$id');
    }

    return ReorderableSection<Service>(
      header: l10n.servicesTitle,
      footer: l10n.serviceDisabledFooter,
      items: list,
      keyOf: (s) => s.id,
      onReorder: save,
      row: (s, handle) => ListRow(
        title: s.name,
        subtitle: s.enabled
            ? weekdayLabel(l10n, s.weekday)
            : '${weekdayLabel(l10n, s.weekday)}${l10n.dotSeparator}${l10n.serviceDisabled}',
        trailing: handle,
        onTap: () => context.push('/me/groups/service/${s.id}'),
      ),
      after: [ListRow(title: l10n.serviceAdd, leading: const Icon(Symbols.add_rounded), onTap: add)],
    );
  }
}

/// A fresh service ID that was never used in this church.
String newServiceId(List<String> taken) {
  final rng = Random();
  while (true) {
    final id = 's${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${rng.nextInt(1296).toRadixString(36)}';
    if (!taken.contains(id)) return id;
  }
}

/// The page of [duty] in service [serviceId].
String dutyPage(String serviceId, String duty) =>
    Uri(path: '/me/groups/duty', queryParameters: {'service': serviceId, 'name': duty}).toString();

/// Who is on the list of [duty] in [serviceType] among [members], in its
/// staff [order].
List<Member> dutyPeople(List<Member> members, String serviceType, String duty, StaffOrder order) {
  final byName = {
    for (final m in members)
      if (m.serves(serviceType, duty)) m.name: m,
  };
  return [
    for (final name in order.orderedCandidates(duty, [...byName.keys]..sort())) byName[name]!,
  ];
}

/// The names on [duty]'s list in [serviceType], for under its row; null
/// while nobody is on it.
String? dutyPeopleLabel(WidgetRef ref, L10n l10n, String serviceType, String duty) {
  final members = ref.watch(membersProvider).value ?? const <Member>[];
  final order = ref.watch(staffOrderProvider(serviceType)).value ?? StaffOrder();
  final people = dutyPeople(members, serviceType, duty, order);
  return people.isEmpty ? null : people.map((m) => m.name).join(l10n.listSeparator);
}

/// The duties and 特別活動 still on [service]'s rosters after [today] that
/// it no longer has: what 同步未來服事表 can bring in line.
({List<String> duties, List<String> events}) staleOnRosters(Service service, List<Roster> rosters, Day today) {
  final ahead = [
    for (final r in rosters)
      if (r.type == service.id && r.day.isAfter(today)) r,
  ];
  return (
    duties: {
      for (final r in ahead)
        for (final d in r.duties)
          if (!service.duties.contains(d.role)) d.role,
    }.toList()..sort(),
    events: {
      for (final r in ahead)
        for (final e in r.events)
          if (!service.events.any((option) => option.name == e.name)) e.name,
    }.toList()..sort(),
  );
}

/// Changes an admin makes to [service], each saved at once with 復原.
class ServiceEdits {
  ServiceEdits(this.context, this.ref, this.service);

  final BuildContext context;
  final WidgetRef ref;
  final Service service;

  L10n get _l10n => L10n.of(context);

  /// [service] changed to [next], saying [message] (服事設定已儲存);
  /// [dutyRename] moves the 同工's lists and staff order with a duty.
  Future<bool> save(Service next, {String? message, ({String from, String to})? dutyRename}) => runWithUndo(
    context,
    message ?? _l10n.serviceSettingsSaved,
    () => ref.read(churchWritesProvider).service(service, next, dutyRename: dutyRename),
  );

  /// 改名 for the service.
  Future<void> rename() async {
    final name = await promptText(context, title: _l10n.rename, hint: _l10n.serviceName, initial: service.name);
    if (name != null) await save(service.copyWith(name: name));
  }

  /// The weekday it meets, picked in a sheet.
  Future<void> pickWeekday() async {
    final l10n = _l10n;
    final day = await showAppSheet<int>(
      context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: ListSection(
            header: l10n.weekday,
            children: [
              for (var d = 1; d <= 7; d++)
                ListRow(
                  title: weekdayLabel(l10n, d),
                  selected: service.weekday == d,
                  onTap: () => Navigator.pop(context, d),
                ),
            ],
          ),
        ),
      ),
    );
    if (day != null) await save(service.copyWith(weekday: day));
  }

  /// 新增服事項目: named, last on the list; its name once on it, or null.
  Future<String?> addDuty() async {
    final name = await promptText(context, title: _l10n.addDuty, hint: _l10n.dutyName);
    if (name == null) return null;
    if (service.duties.contains(name)) return name;
    return await save(service.copyWith(duties: [...service.duties, name])) ? name : null;
  }

  /// Duty [d] taken off the service; arranged days and the lists keep it.
  Future<bool> removeDuty(String d) => save(
    service.copyWith(
      duties: [
        for (final x in service.duties)
          if (x != d) x,
      ],
    ),
    message: _l10n.dutyRemoved(d),
  );

  /// 改名 for duty [from]: its new name once saved, and then 同步未來服事表
  /// offered; null if not.
  Future<String?> renameDuty(String from) async {
    final to = await promptText(context, title: _l10n.rename, hint: _l10n.dutyName, initial: from);
    if (to == null || to == from || service.duties.contains(to)) return null;
    final saved = await save(
      service.copyWith(duties: [for (final d in service.duties) d == from ? to : d]),
      dutyRename: (from: from, to: to),
    );
    if (!saved || !context.mounted) return null;
    await synchronize(to, from: from);
    return to;
  }

  /// Brings the rosters after today in line with option [target]: [from],
  /// or one picked of [stale], renamed to it.
  Future<void> synchronize(String target, {String? from, List<String> stale = const [], bool event = false}) async {
    final original =
        from ??
        await showAppSheet<String>(
          context,
          builder: (context) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListSection(
                  header: event ? L10n.of(context).serviceSyncOriginalEvent : L10n.of(context).serviceSyncOriginalDuty,
                  children: [
                    for (final name in stale) ListRow(title: name, onTap: () => Navigator.pop(context, name)),
                  ],
                ),
              ],
            ),
          ),
        );
    if (original == null || !context.mounted) return;
    final actions = ref.read(rosterActionsProvider);
    final preview = event
        ? actions.previewEventRename(service.id, original, target)
        : actions.previewDutyRename(service.id, original, target);
    if (preview.plan.isEmpty && preview.plan.conflicts.isEmpty) return;
    final apply = await showFutureRosterPreview(
      context,
      title: L10n.of(context).serviceFutureSyncTitle(original, target),
      preview: preview,
      today: ref.read(todayProvider),
    );
    if (!apply || !context.mounted) return;
    await runWithUndo(
      context,
      L10n.of(context).serviceFutureSyncSaved(preview.plan.before.length),
      () => actions.applyFuturePreview(preview),
    );
  }

  /// 新增特別活動: named, in the next color.
  Future<void> addEvent() async {
    final name = await promptText(context, title: _l10n.customEvent, hint: _l10n.eventName);
    if (name != null && !service.events.any((e) => e.name == name)) {
      await save(
        service.copyWith(
          events: [
            ...service.events,
            EventTag(name: name, color: service.events.length % 6),
          ],
        ),
      );
    }
  }

  /// 常用特別活動 [e] taken off; arranged days keep it.
  Future<void> removeEvent(EventTag e) => save(
    service.copyWith(
      events: [
        for (final x in service.events)
          if (x.name != e.name) x,
      ],
    ),
    message: _l10n.removed(e.name),
  );

  /// Tapping a 常用特別活動: rename it, its color, bring the rosters after
  /// today in line ([stale]: the names still on them), or remove it.
  Future<void> eventActions(EventTag e, List<String> stale) async {
    final l10n = _l10n;
    final choice = await showAppSheet<String>(
      context,
      builder: (context) => SafeArea(
        child: ListSection(
          header: e.name,
          children: [
            ListRow(
              title: l10n.rename,
              leading: const Icon(Symbols.edit_rounded),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListRow(
              title: l10n.serviceEventColor,
              leading: const Icon(Symbols.palette_rounded),
              onTap: () => Navigator.pop(context, 'color'),
            ),
            if (stale.isNotEmpty)
              ListRow(
                title: l10n.serviceSyncFutureRosters,
                leading: const Icon(Symbols.event_repeat_rounded),
                onTap: () => Navigator.pop(context, 'synchronize'),
              ),
            ListRow(
              title: l10n.remove,
              destructive: true,
              leading: const Icon(Symbols.delete_rounded),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'rename':
        await _renameEvent(e);
      case 'color':
        await _editColor(e);
      case 'synchronize':
        await synchronize(e.name, stale: stale, event: true);
      case 'remove':
        await removeEvent(e);
    }
  }

  Future<void> _renameEvent(EventTag from) async {
    final to = await promptText(context, title: _l10n.rename, hint: _l10n.eventName, initial: from.name);
    if (to == null || to == from.name || service.events.any((e) => e.name == to)) return;
    final renamed = EventTag(name: to, color: from.color);
    final saved = await save(
      service.copyWith(events: [for (final e in service.events) e.name == from.name ? renamed : e]),
    );
    if (!saved || !context.mounted) return;
    await synchronize(to, from: from.name, event: true);
  }

  Future<void> _editColor(EventTag event) async {
    final l10n = _l10n;
    final color = await showAppSheet<int>(
      context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: ListSection(
            header: L10n.of(context).serviceEventColorTitle(event.name),
            children: [
              for (final (i, name) in [
                l10n.colorName0,
                l10n.colorName1,
                l10n.colorName2,
                l10n.colorName3,
                l10n.colorName4,
                l10n.colorName5,
              ].indexed)
                ListRow(
                  title: name,
                  leading: Tag.event(context, ' ', i),
                  selected: i == event.color,
                  onTap: () => Navigator.pop(context, i),
                ),
            ],
          ),
        ),
      ),
    );
    if (color == null || color == event.color || !context.mounted) return;
    await save(
      service.copyWith(
        events: [for (final e in service.events) e.name == event.name ? EventTag(name: e.name, color: color) : e],
      ),
    );
  }
}

/// The top of a service's page: its name, weekday and whether it still
/// runs; an admin changes them, anyone else reads them.
Widget serviceBasicsSection(BuildContext context, WidgetRef ref, Service service, {required bool admin}) {
  final l10n = L10n.of(context);
  final edits = ServiceEdits(context, ref, service);
  return ListSection(
    children: [
      ListRow(
        title: l10n.serviceName,
        value: service.name,
        chevron: admin,
        onTap: admin ? edits.rename : null,
      ),
      ListRow(
        title: l10n.weekday,
        value: weekdayLabel(l10n, service.weekday),
        chevron: admin,
        onTap: admin ? edits.pickWeekday : null,
      ),
      if (admin)
        SwitchRow(
          title: l10n.serviceEnabled,
          value: service.enabled,
          onChanged: (v) => edits.save(service.copyWith(enabled: v)),
        ),
    ],
  );
}

/// A service's 服事項目 (#94), one level, in the order its rosters have
/// them: each with who is on its list, opening its page. An admin drags
/// them in order, swipes one away and adds one.
Widget serviceDutiesSliver(BuildContext context, WidgetRef ref, Service service, {required bool admin}) {
  final l10n = L10n.of(context);
  ListRow row(String d, Widget? handle) => ListRow(
    title: d,
    subtitle: dutyPeopleLabel(ref, l10n, service.id, d),
    trailing: handle,
    onTap: () => context.push(dutyPage(service.id, d)),
  );
  if (!admin) {
    return SliverToBoxAdapter(
      child: ListSection(
        header: l10n.templateDuties,
        children: [for (final d in service.duties) row(d, null)],
      ),
    );
  }
  final edits = ServiceEdits(context, ref, service);
  return ReorderableSection<String>(
    header: l10n.templateDuties,
    footer: l10n.templateFooter,
    items: service.duties,
    keyOf: (d) => 'duty/$d',
    onReorder: (next) => edits.save(service.copyWith(duties: next)),
    row: (d, handle) => Dismissible(
      key: ValueKey('duty/$d'),
      direction: DismissDirection.endToStart,
      background: const SwipeDeleteBackground(),
      confirmDismiss: (_) async {
        await edits.removeDuty(d);
        return false; // The successful server change removes the row.
      },
      child: row(d, handle),
    ),
    after: [ListRow(title: l10n.addDuty, leading: const Icon(Symbols.add_rounded), onTap: edits.addDuty)],
  );
}

/// A service's 常用特別活動: an admin's to change; anyone else reads them.
Widget serviceEventsSliver(BuildContext context, WidgetRef ref, Service service, {required bool admin}) {
  final l10n = L10n.of(context);
  if (!admin) {
    return SliverToBoxAdapter(
      child: service.events.isEmpty
          ? const SizedBox.shrink()
          : ListSection(
              header: l10n.commonEvents,
              children: [
                for (final e in service.events)
                  ListRow(title: e.name, leading: Tag.event(context, ' ', e.color), chevron: false),
              ],
            ),
    );
  }
  final edits = ServiceEdits(context, ref, service);
  final stale = staleOnRosters(
    service,
    ref.watch(savedRostersProvider).value ?? const [],
    ref.watch(todayProvider),
  ).events;
  return ReorderableSection<EventTag>(
    header: l10n.commonEvents,
    items: service.events,
    keyOf: (e) => 'event/${e.name}',
    onReorder: (next) => edits.save(service.copyWith(events: next)),
    row: (e, handle) => Dismissible(
      key: ValueKey('event/${e.name}'),
      direction: DismissDirection.endToStart,
      background: const SwipeDeleteBackground(),
      confirmDismiss: (_) async {
        await edits.removeEvent(e);
        return false;
      },
      child: ListRow(
        title: e.name,
        leading: Tag.event(context, ' ', e.color),
        trailing: handle,
        onTap: () => edits.eventActions(e, stale),
      ),
    ),
    after: [ListRow(title: l10n.addEvent, leading: const Icon(Symbols.add_rounded), onTap: edits.addEvent)],
  );
}

/// One 服事項目's page (#94): who is on its list, ticked on and off by
/// whoever edits it (Member.editsDutyList), the service's 同工 first; and,
/// for an admin, its name, its 事工, bringing the rosters after today in
/// line, and deleting it.
class DutyScreen extends ConsumerStatefulWidget {
  const DutyScreen({super.key, required this.serviceId, required this.duty});

  final String serviceId;

  /// As the page's link names it.
  final String duty;

  @override
  ConsumerState<DutyScreen> createState() => _DutyScreenState();
}

class _DutyScreenState extends ConsumerState<DutyScreen> {
  /// The duty as renamed here; the link keeps the name it opened with.
  late String _duty = widget.duty;

  /// The service's 同工 as the page opened: someone ticked under 其他人
  /// becomes one, and stays in place there rather than jumping up.
  Set<String>? _staffAtOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final me = ref.watch(meProvider).value;
    final service = ref.watch(servicesProvider).value?.byId(widget.serviceId);
    final members = ref.watch(membersProvider).value;
    final ministries = ref.watch(ministriesProvider).value?.ministries ?? const <Ministry>[];
    // Renamed back by 復原: the name it opened with again.
    final duty = service == null || service.duties.contains(_duty) ? _duty : widget.duty;
    if (me == null || service == null || members == null || !service.duties.contains(duty)) {
      return Scaffold(appBar: AppBar());
    }
    final admin = me.editsServiceSettings;
    final edits = me.editsDutyList(ministries, service.id, duty);
    final ministry = ministries.where((m) => m.duties.contains(MinistryDuty(service.id, duty))).firstOrNull;
    final serving = dutyPeople(
      members,
      service.id,
      duty,
      ref.watch(staffOrderProvider(service.id)).value ?? StaffOrder(),
    );
    final byName = [...members]..sort((a, b) => a.name.compareTo(b.name));
    final staff = _staffAtOpen ??= {
      for (final m in members)
        if (m.zoneTypes.contains(service.id)) m.uid,
    };
    final stale = admin
        ? staleOnRosters(service, ref.watch(savedRostersProvider).value ?? const [], ref.watch(todayProvider)).duties
        : const <String>[];
    final serviceEdits = ServiceEdits(context, ref, service);

    ListRow person(Member m) => ListRow(
      title: m.name,
      selected: m.serves(service.id, duty),
      onTap: () => _toggle(m, service.id, duty),
    );

    return Scaffold(
      appBar: AppBar(title: Text(duty), actions: admin ? const [SavingIndicator()] : null),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (edits) ...[
            ListSection(
              header: l10n.zoneSwitch(service.name),
              children: [
                for (final m in byName)
                  if (staff.contains(m.uid)) person(m),
              ],
            ),
            if (byName.any((m) => !staff.contains(m.uid)))
              ListSection(
                header: l10n.dutyOthers,
                children: [
                  for (final m in byName)
                    if (!staff.contains(m.uid)) person(m),
                ],
              ),
          ] else
            ListSection(
              footer: serving.isEmpty ? l10n.nobodyYet : null,
              children: [for (final m in serving) ListRow(title: m.name, chevron: false)],
            ),
          ListSection(
            children: [
              if (admin)
                ListRow(
                  title: l10n.dutyName,
                  value: duty,
                  onTap: () async {
                    final to = await serviceEdits.renameDuty(duty);
                    if (to != null && mounted) setState(() => _duty = to);
                  },
                ),
              ListRow(
                title: l10n.dutyMinistry,
                value: ministry?.name ?? l10n.ministryDutiesNone,
                chevron: admin,
                onTap: admin ? () => _pickMinistry(service.id, duty, ministry) : null,
              ),
              if (admin && stale.isNotEmpty)
                ListRow(
                  title: l10n.serviceSyncFutureRosters,
                  onTap: () => serviceEdits.synchronize(duty, stale: stale),
                ),
            ],
          ),
          if (admin)
            ListSection(
              children: [
                ListRow(
                  title: l10n.delete,
                  destructive: true,
                  chevron: false,
                  onTap: () async {
                    if (await serviceEdits.removeDuty(duty) && context.mounted) context.pop();
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// [m] put on the list or taken off it; one of the service's 同工 now, if
  /// they were not.
  Future<void> _toggle(Member m, String serviceId, String duty) async {
    Haptics.selection();
    final data = ref.churchData;
    try {
      await (m.serves(serviceId, duty) ? data.revokeDuty : data.grantDuty)(m.uid, serviceId, duty);
    } catch (e) {
      if (mounted) showToast(context, saveErrorText(L10n.of(context), e));
    }
  }

  /// Which 事工 the duty belongs to: one, or none. Linked to more than one
  /// from before, it is one once picked.
  Future<void> _pickMinistry(String serviceId, String duty, Ministry? current) async {
    final l10n = L10n.of(context);
    final before = ref.read(ministriesProvider).value?.ministries;
    if (before == null) return;
    // A 事工's ID, or '' for none.
    final picked = await showAppSheet<String>(
      context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: ListSection(
            header: l10n.dutyMinistry,
            children: [
              ListRow(
                title: l10n.ministryDutiesNone,
                selected: current == null,
                onTap: () => Navigator.pop(context, ''),
              ),
              for (final m in before)
                ListRow(title: m.name, selected: m.id == current?.id, onTap: () => Navigator.pop(context, m.id)),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final key = MinistryDuty(serviceId, duty);
    final next = [
      for (final m in before)
        m.copyWith(
          duties: [
            for (final d in m.duties)
              if (d != key) d,
            if (m.id == picked) key,
          ],
        ),
    ];
    if (next.every((m) => before.contains(m))) return;
    await runWithUndo(context, l10n.saved, () => ref.read(churchWritesProvider).ministries(before, next));
  }
}
