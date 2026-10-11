import '../domain/models.dart';

/// Reject a programming error before opening a transaction. No document
/// outside the explicitly previewed keyset can be touched.
void validateRosterCompareAndSet(Map<String, Roster?> before, Map<String, Roster?> after) {
  if (before.length != after.length || before.keys.any((key) => !after.containsKey(key))) {
    throw ArgumentError('before and after must have identical roster keys');
  }
  for (final entry in [...before.entries, ...after.entries]) {
    if (entry.key.isEmpty || entry.key.contains('/') || (entry.value != null && entry.value!.id != entry.key)) {
      throw ArgumentError('roster key must match the document id');
    }
  }
}

/// The only settings mutation allowed alongside roster CAS is common event
/// options. This is not an arbitrary metadata writer or a duty rename seam.
void validateRosterServiceChange(({Service before, Service after})? change) {
  if (change != null && change.after.copyWith(events: change.before.events) != change.before) {
    throw ArgumentError('roster serviceChange may only change common events');
  }
}

/// [Roster.saved] is an on-screen draft marker, never a persisted value.
bool rosterMatchesBaseline(Roster? actual, Roster? baseline) =>
    actual?.copyWith(saved: true) == baseline?.copyWith(saved: true);
