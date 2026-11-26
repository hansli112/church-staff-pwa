import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend.dart';
import '../domain/models.dart';
import '../domain/roster_news.dart';
import 'plan_draft.dart';
import 'providers.dart';
import 'session.dart';

/// A write that has been issued, and how to take it back.
///
/// [done] completes when the server confirms the online write; offline
/// writes are refused. [undo] takes back only what this write did, and is
/// refused ([CloudErrorCode.conflict]) once anything it wrote has changed
/// since, or ([CloudErrorCode.permissionDenied]) once the reader is in
/// another church or account.
typedef ChurchWrite = ({Future<void> done, Future<void> Function() undo});

/// The church and account a write or a preview was made in.
class WriteScope {
  WriteScope._(this._ref, this.data, this.uid);

  final Ref _ref;
  final ChurchData data;
  final String? uid;

  /// Refuses when the reader is no longer in this church and account: an
  /// undo or a preview applied later never follows them elsewhere.
  void check() {
    if (_ref.read(churchDataProvider)?.churchId != data.churchId || _ref.read(uidProvider) != uid) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
  }
}

/// Every reversible write to the church's rosters, members, services and
/// 小組.
///
/// Each compares against what the caller showed: a newer change by someone
/// else refuses the whole write, and an undo is the same compare-and-set in
/// reverse, so neither overwrites anyone (docs/design.md).
class ChurchWrites {
  ChurchWrites(this._ref);

  final Ref _ref;

  /// The church and account as they are now.
  WriteScope scope() => WriteScope._(_ref, _ref.churchData, _ref.read(uidProvider));

  /// [write] now in the church and account as they are; undo is [back],
  /// refused once the reader is in another church or account.
  ChurchWrite _reversible(Future<void> Function(ChurchData data) write, Future<void> Function(ChurchData data) back) {
    final scope = this.scope();
    return (
      done: write(scope.data),
      undo: () async {
        scope.check();
        await back(scope.data);
      },
    );
  }

  /// Writes [change]. Undo writes [undo]'s change, built when undoing, or
  /// [change] reversed; it throws to refuse.
  ///
  /// Made in 安排服事 while it is open, it waits there instead
  /// ([PlanDraft]), and so does its undo; a new 服事順序 it brings is saved
  /// at once all the same.
  ChurchWrite rosters(RosterChange change, {RosterChange Function()? undo}) {
    final draft = _ref.read(planDraftProvider.notifier);
    if (!draft.holds(change)) return _sent(change, undo: undo);
    final order = change.staffOrder;
    final ordered = order == null ? null : _sent(RosterChange(before: const {}, after: const {}, staffOrder: order));
    draft.add(change);
    return (
      done: ordered?.done ?? Future<void>.value(),
      undo: () async {
        final draft = _ref.read(planDraftProvider.notifier);
        // Saved or dropped since, with the page: nothing here to undo.
        if (!draft.holding) throw const CloudException(CloudErrorCode.conflict);
        draft.add(undo == null ? change.reversed : undo());
        await ordered?.undo();
      },
    );
  }

  /// [change] saved now, as [rosters] but never held back.
  ChurchWrite saveNow(RosterChange change) => _sent(change);

  ChurchWrite _sent(RosterChange change, {RosterChange Function()? undo}) => _reversible(
    (data) async {
      await _sendRosters(data, change);
      // Counted once written (GA4), by where it was made; an import is
      // counted by its session, which knows where its rows came from. A
      // 服事順序 alone, saved ahead of 安排服事's days, is no roster edit.
      if (change.via != RosterVia.import && change.after.isNotEmpty) {
        _ref.read(telemetryProvider).logEvent('roster_edit', {'via': change.via.name});
      }
    },
    (data) => _sendRosters(data, undo == null ? change.reversed : undo()),
  );

  /// [change] as a whole-day write, or, for a 事工's 負責人 who arranges
  /// only some duties of those days (#82), through the backend, which
  /// checks that only those changed.
  Future<void> _sendRosters(ChurchData data, RosterChange change) {
    bool whole(Roster r) =>
        (r.isEvent ? _ref.read(eventArrangesProvider(r.forEvent!.group)) : _ref.read(arrangesProvider(r.type))).all;
    final days = [...change.before.values, ...change.after.values].whereType<Roster>();
    final scoped = change.staffOrder == null && !days.every(whole);
    return scoped ? data.compareAndSetLedDuties(change) : data.compareAndSetRosters(change);
  }

  /// Writes what an admin sets on [before] to be [after].
  ChurchWrite member(Member before, Member after) => _reversible(
    (data) => data.compareAndSetMember(before: before, after: after),
    (data) => data.compareAndSetMember(before: after, after: before),
  );

  /// Edits one service, leaving every other one as it is. A duty rename
  /// also moves members' duties and the staff order; old rosters keep the
  /// old name.
  ChurchWrite service(Service before, Service after, {({String from, String to})? dutyRename}) => _reversible(
    (data) => data.compareAndSetService(before: before, after: after, dutyRename: dutyRename),
    (data) => data.compareAndSetService(
      before: after,
      after: before,
      dutyRename: dutyRename == null ? null : (from: dutyRename.to, to: dutyRename.from),
    ),
  );

  /// Replaces the church's 事工 (#82): adding, renaming or deleting one.
  ChurchWrite ministries(List<Ministry> before, List<Ministry> after) => _reversible(
    (data) => data.compareAndSetMinistries(before: before, after: after),
    (data) => data.compareAndSetMinistries(before: after, after: before),
  );

  /// 加為同工 ([member] true) or 移出 [group], by its 負責人 or an admin; undo
  /// does the opposite, a service's 同工 coming back with the duties and
  /// 小組 they had there.
  ChurchWrite groupMember(Member who, ChurchGroup group, {required bool member, List<String> duties = const []}) {
    final had = switch (group) {
      ServiceGroup(:final id) => who.zones.where((z) => z.serviceType == id).firstOrNull,
      MinistryGroup() || SmallGroup() || GatheringGroup() => null,
    };
    return _reversible(
      (data) => data.setGroupMember(who.uid, group, member: member, duties: duties),
      (data) => data.setGroupMember(
        who.uid,
        group,
        member: !member,
        duties: had?.duties ?? duties,
        smallGroups: had?.smallGroups ?? const [],
      ),
    );
  }

  /// Changes 小組 [before] to [after]; with [leads], they and nobody else
  /// are its 小組長, in place of [leadsBefore].
  ChurchWrite smallGroup(
    SmallGroupDetails before,
    SmallGroupDetails after, {
    List<String>? leadsBefore,
    List<String>? leads,
  }) => _reversible(
    (data) => data.saveSmallGroup(after, before: before, leads: leads, leadsBefore: leads == null ? null : leadsBefore),
    (data) => data.saveSmallGroup(before, before: after, leads: leads == null ? null : leadsBefore, leadsBefore: leads),
  );

  /// Replaces the list of services: adding one, or reordering them.
  ChurchWrite serviceList(List<Service> before, List<Service> after) => _reversible(
    (data) => data.compareAndSetServiceList(before: before, after: after),
    (data) => data.compareAndSetServiceList(before: after, after: before),
  );
}

final churchWritesProvider = Provider<ChurchWrites>(ChurchWrites.new);
