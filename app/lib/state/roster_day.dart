import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/day.dart';
import '../domain/models.dart';
import '../domain/roster_edit.dart';
import '../domain/schedule.dart';
import 'providers.dart';

/// What a service's day shows (RosterDayScreen): its [roster], and what I
/// may change on it.
@immutable
class RosterDay {
  const RosterDay({required this.roster, required this.past, required this.arranges, required this.addable});

  /// The roster shown: saved, or the one it starts from.
  final Roster roster;

  /// A day gone by: only looked at, by everyone, so nobody is told of
  /// changes to it.
  final bool past;

  /// What I arrange on it (a 事工's 負責人 only the duties it leads, #82).
  final Arranges arranges;

  /// The service's duties I may add to it.
  final List<String> addable;

  /// Whether I change anything on it: a day ahead I arrange some of.
  bool get canEdit => !past && arranges.any;

  /// Whether I change the whole day: its 特別活動, and any duty typed in.
  bool get wholeDay => arranges.all;
}

/// [RosterDay] of a service (its ID) on a day; null when the church has no
/// such service. A day ahead is the one saved, or the service's duties
/// when none is; a day gone by, as it was saved, from the list when it is
/// there or else read, and with no duties when nobody was arranged on it.
final rosterDayProvider = Provider.autoDispose.family<AsyncValue<RosterDay>?, (String, Day)>((ref, key) {
  final (serviceType, day) = key;
  final service = ref.watch(servicesProvider.select((s) => s.value?.byId(serviceType)));
  if (service == null) return null;
  final past = day.isBefore(ref.watch(todayProvider));

  /// The roster shown: saved, or the one it starts from.
  final Roster roster;
  if (past) {
    final listed = ref.watch(
      earlierRostersProvider(serviceType).select((e) => e.rosters.where((r) => r.day == day).firstOrNull),
    );
    if (listed != null) {
      roster = listed;
    } else {
      final saved = ref.watch(pastRosterProvider((serviceType, day)));
      if (!saved.hasValue) {
        return saved.hasError ? AsyncError(saved.error!, saved.stackTrace ?? StackTrace.current) : const AsyncLoading();
      }
      roster = saved.value ?? Roster(type: serviceType, day: day);
    }
  } else {
    roster =
        ref.watch(serviceRostersProvider(serviceType)).value?.where((r) => r.day == day).firstOrNull ??
        draftRoster(service, day);
  }
  final arranges = ref.watch(arrangesProvider(serviceType));
  return AsyncData(
    RosterDay(roster: roster, past: past, arranges: arranges, addable: addableDuties(roster, service.duties, arranges)),
  );
});
