import '../domain/models.dart';
import '../domain/staff_order.dart';
import 'backend.dart';

/// One atomic roster write: exactly the documents in [before] go to
/// [after], or nothing is written. Null means an absent document.
///
/// Building one checks it, so a malformed change never reaches a backend:
/// the maps must have identical keys, each non-null roster must match its
/// key, a [serviceChange] may only change common events, and the whole
/// write must fit in one transaction ([CloudReason.tooManyChanges]).
final class RosterChange {
  RosterChange({
    required Map<String, Roster?> before,
    required Map<String, Roster?> after,
    this.via = 'app',
    this.staffOrder,
    this.serviceChange,
  }) : before = Map.unmodifiable(before),
       after = Map.unmodifiable(after) {
    if (before.length != after.length || before.keys.any((key) => !after.containsKey(key))) {
      throw ArgumentError('before and after must have identical roster keys');
    }
    for (final entry in [...before.entries, ...after.entries]) {
      if (entry.key.isEmpty || entry.key.contains('/') || (entry.value != null && entry.value!.id != entry.key)) {
        throw ArgumentError('roster key must match the document id');
      }
    }
    if (serviceChange case final change? when change.after.copyWith(events: change.before.events) != change.before) {
      throw ArgumentError('roster serviceChange may only change common events');
    }
    if (after.length + (staffOrder == null ? 0 : 1) + (serviceChange == null ? 0 : 1) > maxWrites) {
      throw const CloudException(CloudErrorCode.quotaExceeded, reason: CloudReason.tooManyChanges);
    }
  }

  /// Firestore's limit on the writes in one transaction.
  static const maxWrites = 500;

  final Map<String, Roster?> before;
  final Map<String, Roster?> after;

  /// Where the change came from; `import` tells the backend not to send a
  /// push for every day.
  final String via;

  final ({String serviceType, StaffOrder before, StaffOrder after})? staffOrder;

  /// The only settings change allowed alongside rosters: common events.
  final ({Service before, Service after})? serviceChange;

  /// The change that takes this one back, refused if anything it wrote has
  /// changed since.
  RosterChange get reversed => RosterChange(
    before: after,
    after: before,
    via: via,
    staffOrder: switch (staffOrder) {
      final o? => (serviceType: o.serviceType, before: o.after, after: o.before),
      null => null,
    },
    serviceChange: switch (serviceChange) {
      final s? => (before: s.after, after: s.before),
      null => null,
    },
  );

  /// Whether [actual] is what this change expects at [id].
  /// [Roster.saved] is an on-screen draft marker, never a persisted value.
  bool expects(String id, Roster? actual) => actual?.copyWith(saved: true) == before[id]?.copyWith(saved: true);
}
