import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend.dart';
import '../domain/event_roster.dart';
import '../domain/models.dart';
import '../domain/roster_edit.dart';
import '../domain/roster_import.dart';
import '../domain/schedule.dart';
import '../domain/staff_order.dart';
import 'church_writes.dart';
import 'providers.dart';

/// A bulk preview is scoped to the church and account that opened it.
class RosterPreview {
  RosterPreview._(this.plan, this.scope);

  final FutureRosterPlan plan;
  final WriteScope scope;
}

/// Writes for 安排服事表. Each returns a [ChurchWrite], so screens offer
/// 「復原」 instead of asking for confirmation.
///
/// It reads the church's services, saved rosters, members and staff orders
/// as this device has them. A screen that edits a service watches
/// [rosterEditingProvider] for it, which keeps all of them loaded and says
/// when they are; a write before then fails rather than guess.
class RosterActions {
  RosterActions(this._ref);

  final Ref _ref;

  ChurchData get _data => _ref.churchData;

  ChurchWrites get _writes => _ref.read(churchWritesProvider);

  static T _loaded<T>(AsyncValue<T> value, String what) =>
      value.hasValue ? value.requireValue : throw StateError('$what not loaded');

  ServiceSettings get _services => _loaded(_ref.read(servicesProvider), 'services');

  List<Roster> get _saved => _loaded(_ref.read(savedRostersProvider), 'rosters');

  Map<String, String> get _nameIds => uniqueNameIds(_loaded(_ref.read(membersProvider), 'members'));

  StaffOrder _order(String type) => _loaded(_ref.read(staffOrderProvider(type)), 'staff order');

  /// [r]'s staff order: its service's, or for an event's roster that of the
  /// first service ranking each duty.
  StaffOrder orderOf(Roster r) => r.isEvent
      ? eventStaffOrder(_services.services, {for (final s in _services.services) s.id: _order(s.id)})
      : _order(r.type);

  /// [r]'s day as this device sees it now: saved, or the template draft.
  Roster _now(Roster r) {
    for (final s in _saved) {
      if (s.id == r.id) return s;
    }
    final service = _services.byId(r.type);
    return service == null ? r.copyWith(saved: false) : draftRoster(service, r.day);
  }

  /// Puts [role] back to [previous] (or removes it when it did not exist)
  /// on the day as it is now, at its old position.
  Roster _withDutyRestored(Roster now, String role, Duty? previous, int index) {
    final rest = [
      for (final d in now.duties)
        if (d.role != role) d,
    ];
    if (previous == null) return now.copyWith(duties: rest);
    rest.insert(index.clamp(0, rest.length), previous);
    return now.copyWith(duties: rest);
  }

  bool _untouchedDraft(Roster before, Roster next) =>
      !before.saved && _now(before).copyWith(saved: false) == next.copyWith(saved: false);

  Roster? _persisted(Roster r) => r.saved ? r : null;

  /// Writes [next] over [before], which differ only in [role]; undo
  /// restores that duty while preserving unrelated edits.
  ChurchWrite _dutyWrite(Roster before, Roster next, String role) {
    final index = before.duties.indexWhere((d) => d.role == role);
    final previous = index < 0 ? null : before.duties[index];
    final written = next.duties.where((d) => d.role == role).firstOrNull;
    return _writes.rosters(
      RosterChange(before: {before.id: _persisted(before)}, after: {next.id: next}),
      undo: () {
        final now = _now(before);
        if (now.duties.where((d) => d.role == role).firstOrNull != written) {
          throw const CloudException(CloudErrorCode.conflict);
        }
        // An untouched draft goes back to following its template.
        final restore = _untouchedDraft(before, next) ? null : _withDutyRestored(now, role, previous, index);
        return RosterChange(before: {now.id: _persisted(now)}, after: {now.id: restore});
      },
    );
  }

  ChurchWrite setPeople(
    Roster roster,
    String role,
    List<String> people, {
    Set<String> guestNames = const {},
    List<String>? ranking,
  }) {
    final order = orderOf(roster);
    final afterOrder = ranking == null ? order : order.withRanking(role, ranking);
    final next = withPeople(roster, role, people, nameIds: _nameIds, order: afterOrder, guestNames: guestNames);
    if (ranking == null || order == afterOrder) return _dutyWrite(roster, next, role);
    if (roster.isEvent) throw StateError('Event rosters have no staff order');
    final before = <String, Roster?>{roster.id: _persisted(roster)};
    final after = <String, Roster?>{roster.id: next};
    for (final saved in _saved) {
      if (saved.type != roster.type || saved.id == roster.id) continue;
      final sorted = afterOrder.applyTo(saved);
      if (identical(sorted, saved)) continue;
      before[saved.id] = saved;
      after[saved.id] = sorted;
    }
    return _writes.rosters(
      RosterChange(
        before: before,
        after: after,
        staffOrder: (serviceType: roster.type, before: order, after: afterOrder),
      ),
    );
  }

  /// Reuses only already arranged, unbound names in this service and duty.
  /// Explicit staff order is respected; no order is learned from rosters.
  List<String> guestSuggestions(String? type, String role) {
    final names = <String>{
      for (final r in _saved)
        if (type == null ? r.isEvent : !r.isEvent && r.type == type)
          for (final d in r.duties)
            if (d.role == role)
              for (final name in d.people)
                if (name.trim().isNotEmpty && !d.uids.containsKey(name)) name,
    }.toList()..sort();
    return type == null ? names : _order(type).sort(role, names);
  }

  RosterPreview previewGuestRemoval(String type, String role, String name) => RosterPreview._(
    planGuestRemoval(saved: _saved, type: type, role: role, name: name, today: _ref.read(todayProvider)),
    _writes.scope(),
  );

  RosterPreview previewDutyRename(String type, String from, String to) => RosterPreview._(
    planDutyRename(saved: _saved, type: type, from: from, to: to, today: _ref.read(todayProvider)),
    _writes.scope(),
  );

  RosterPreview previewEventRename(String type, String from, String to) => RosterPreview._(
    planEventRename(saved: _saved, type: type, from: from, to: to, today: _ref.read(todayProvider)),
    _writes.scope(),
  );

  /// Applies exactly the previewed documents; a newer edit rejects the whole
  /// operation. Undo uses the reverse baseline, never overwriting newer work.
  ChurchWrite applyFuturePreview(RosterPreview preview) {
    void stillFuture() {
      final today = _ref.read(todayProvider);
      if (preview.plan.conflicts.isNotEmpty ||
          preview.plan.before.values.any((r) => r == null || !r.day.isAfter(today))) {
        throw const CloudException(CloudErrorCode.conflict);
      }
    }

    preview.scope.check();
    stillFuture();
    final change = RosterChange(before: preview.plan.before, after: preview.plan.after);
    return _writes.rosters(
      change,
      undo: () {
        stillFuture();
        return change.reversed;
      },
    );
  }

  ChurchWrite removeDuty(Roster roster, String role) => _dutyWrite(roster, withoutDuty(roster, role), role);

  ChurchWrite addDuty(Roster roster, String role) => setPeople(roster, role, const []);

  /// Adds those of [roles] that [roster] lacks, with nobody yet, in one
  /// write: 沿用 another event's duties. Undo takes back the ones still
  /// empty.
  ChurchWrite addDuties(Roster roster, List<String> roles) {
    final have = {for (final d in roster.duties) d.role};
    final added = [
      for (final r in {...roles})
        if (!have.contains(r)) r,
    ];
    final next = roster.copyWith(
      duties: [
        ...roster.duties,
        for (final r in added) Duty(role: r),
      ],
    );
    return _writes.rosters(
      RosterChange(before: {roster.id: _persisted(roster)}, after: {next.id: next}),
      undo: () {
        final now = _now(roster);
        final restored = _untouchedDraft(roster, next)
            ? null
            : now.copyWith(
                duties: [
                  for (final d in now.duties)
                    if (!added.contains(d.role) || d.people.isNotEmpty) d,
                ],
              );
        return RosterChange(before: {now.id: _persisted(now)}, after: {now.id: restored});
      },
    );
  }

  /// Sets the day's tags and, when requested, its common-event options in
  /// one events-only transaction. Any newer settings/day baseline refuses
  /// the whole write; undo reverses both baselines in the same transaction.
  ChurchWrite setEvents(Roster roster, List<EventTag> events, {List<EventTag> addToCommon = const []}) {
    final next = roster.copyWith(events: events);
    // Ticking a tag off and on again only moves it to the end: the day
    // stays as it is (a draft stays a draft).
    final changed = !setEquals(events.toSet(), roster.events.toSet());
    final service = _services.byId(roster.type);
    final common = addToCommon.isEmpty || service == null
        ? null
        : service.copyWith(events: [...service.events, ...addToCommon]);
    if (!changed && common == null) return (done: Future<void>.value(), undo: () async {});
    return _writes.rosters(
      RosterChange(
        before: {if (changed) roster.id: _persisted(roster)},
        after: {if (changed) next.id: next},
        serviceChange: common == null ? null : (before: service!, after: common),
      ),
    );
  }

  /// Swaps two people in [role] in one batch; undo puts both days' [role]
  /// back, also in one batch.
  ChurchWrite swap(String role, SwapSide a, SwapSide b) {
    final (a2, b2) = swapPeople(role, a, b, nameIds: _nameIds, order: _order(a.roster.type));
    int indexOf(Roster r) => r.duties.indexWhere((d) => d.role == role);
    Duty? dutyOf(Roster r) => indexOf(r) < 0 ? null : r.duties[indexOf(r)];
    final prevA = dutyOf(a.roster), prevB = dutyOf(b.roster);
    final idxA = indexOf(a.roster), idxB = indexOf(b.roster);
    return _writes.rosters(
      RosterChange(
        before: {a.roster.id: _persisted(a.roster), b.roster.id: _persisted(b.roster)},
        after: {a2.id: a2, b2.id: b2},
      ),
      undo: () {
        final nowA = _now(a.roster), nowB = _now(b.roster);
        if (dutyOf(nowA) != dutyOf(a2) || dutyOf(nowB) != dutyOf(b2)) {
          throw const CloudException(CloudErrorCode.conflict);
        }
        return RosterChange(
          before: {nowA.id: _persisted(nowA), nowB.id: _persisted(nowB)},
          after: {
            nowA.id: _untouchedDraft(a.roster, a2) ? null : _withDutyRestored(nowA, role, prevA, idxA),
            nowB.id: _untouchedDraft(b.roster, b2) ? null : _withDutyRestored(nowB, role, prevB, idxB),
          },
        );
      },
    );
  }

  /// Gives [member] the duty, so the picker lists them first next time.
  Future<void> grantDuty(Member member, String type, String role) => _data.grantDuty(member.uid, type, role);

  /// What importing [rows] into [type] would do, against the rosters as
  /// they are now.
  ImportPlan previewImport(
    String type,
    List<dynamic> rows, {
    ImportMode mode = ImportMode.merge,
    Map<String, ImportPersonChoice> people = const {},
  }) => planImport(
    rows: rows,
    service: _services.byId(type) ?? (throw StateError('No service $type')),
    members: _loaded(_ref.read(membersProvider), 'members'),
    saved: _saved,
    order: _order(type),
    today: _ref.read(todayProvider),
    mode: mode,
    people: people,
  );

  /// Imports [rows] into [type], planned again now so edits made since the
  /// preview are not overwritten, and the staff order the plan grew. Undo
  /// puts back each imported day whole, as it was before the import (an
  /// edit made to it since is lost), and the staff order.
  ChurchWrite applyImport(
    String type,
    List<dynamic> rows, {
    ImportMode mode = ImportMode.merge,
    Map<String, ImportPersonChoice> people = const {},
    ImportPlan? preview,
  }) {
    final plan = previewImport(type, rows, mode: mode, people: people);
    if (!plan.canApply) throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.unparseable);
    final scope = _writes.scope();
    void validate() {
      scope.check();
      final member = _ref.read(meProvider).value;
      if (scope.uid == null || !_ref.read(churchOpenProvider) || !(member?.canEditRosters(type) ?? false)) {
        throw const CloudException(CloudErrorCode.permissionDenied);
      }
    }

    validate();
    final before = {for (final e in plan.changes.entries) e.key: e.value.before};
    final after = {for (final e in plan.changes.entries) e.key: e.value.after};
    final order = _order(type);
    if (preview != null &&
        (!mapEquals({for (final e in preview.changes.entries) e.key: e.value.before}, before) ||
            !mapEquals({for (final e in preview.changes.entries) e.key: e.value.after}, after) ||
            preview.order.changesTo(plan.order).isNotEmpty)) {
      throw const CloudException(CloudErrorCode.conflict);
    }
    final changedOrder = order.changesTo(plan.order).isNotEmpty;
    final change = RosterChange(
      before: before,
      after: after,
      via: 'import',
      staffOrder: changedOrder ? (serviceType: type, before: order, after: plan.order) : null,
    );
    return _writes.rosters(
      change,
      undo: () {
        validate();
        return change.reversed;
      },
    );
  }
}

/// Whether everything [RosterActions] reads for an event's roster is
/// loaded: every service's staff order too. Watching it keeps them loaded.
final eventEditingProvider = Provider.autoDispose<bool>((ref) {
  final services = ref.watch(servicesProvider);
  final loaded = [
    services,
    ref.watch(savedRostersProvider),
    ref.watch(membersProvider),
    for (final s in services.value?.services ?? const <Service>[]) ref.watch(staffOrderProvider(s.id)),
  ];
  return services.hasValue && loaded.every((v) => v.hasValue);
});

/// Whether everything [RosterActions] reads for service [type] is loaded.
/// A screen that edits the service watches this, which also keeps it
/// loaded: Riverpod pauses what nobody watches.
final rosterEditingProvider = Provider.autoDispose.family<bool, String>((ref, type) {
  final loaded = [
    ref.watch(servicesProvider),
    ref.watch(savedRostersProvider),
    ref.watch(membersProvider),
    ref.watch(staffOrderProvider(type)),
  ];
  return loaded.every((v) => v.hasValue);
});
final rosterActionsProvider = Provider<RosterActions>(RosterActions.new);
