import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend.dart';
import '../domain/models.dart';
import 'providers.dart';

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

/// Every reversible write to the church's rosters, members and services.
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
  ChurchWrite rosters(RosterChange change, {RosterChange Function()? undo}) => _reversible(
    (data) => data.compareAndSetRosters(change),
    (data) => data.compareAndSetRosters(undo == null ? change.reversed : undo()),
  );

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

  /// Replaces the list of services: adding one, or reordering them.
  ChurchWrite serviceList(List<Service> before, List<Service> after) => _reversible(
    (data) => data.compareAndSetServiceList(before: before, after: after),
    (data) => data.compareAndSetServiceList(before: after, after: before),
  );
}

final churchWritesProvider = Provider<ChurchWrites>(ChurchWrites.new);
