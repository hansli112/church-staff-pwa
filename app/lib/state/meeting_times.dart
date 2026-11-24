import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/day.dart';
import '../domain/models.dart';
import 'attendance.dart';
import 'church_writes.dart';
import 'providers.dart';

/// A group's 聚會時間 as the church keeps it: a 小組's and a 其他聚會's on
/// it; a service's with its 人數 (null: by its rosters), on the service's
/// weekdays ([serviceWeekdays]), and on its weeks when not every one
/// ([serviceWeeks]: every other, or some of each month). A 事工 has none.
typedef GroupMeetingTime = ({MeetingTime? time, List<int>? serviceWeekdays, MeetingWeeks? serviceWeeks});

/// [GroupMeetingTime] of a group.
final meetingTimeProvider = Provider.autoDispose.family<GroupMeetingTime, ChurchGroup>(
  (ref, group) => switch (group) {
    SmallGroup(:final id) => (
      time: ref.watch(smallGroupsProvider).value?.byId(id)?.time,
      serviceWeekdays: null,
      serviceWeeks: null,
    ),
    GatheringGroup(:final id) => (
      time: ref.watch(gatheringsProvider).value?.where((g) => g.id == id).firstOrNull?.time,
      serviceWeekdays: null,
      serviceWeeks: null,
    ),
    ServiceGroup(:final id) => switch (ref.watch(servicesProvider).value?.byId(id)) {
      final s => (
        time: ref.watch(attendanceProvider(group.key)).value?.time,
        serviceWeekdays: s?.weekdays,
        serviceWeeks: s != null && s.repeats ? s.weeks : null,
      ),
    },
    MinistryGroup() => (time: null, serviceWeekdays: null, serviceWeeks: null),
  },
);

/// Setting a group's 聚會時間, wherever the church keeps it; who may is
/// Member.schedules.
class MeetingTimes {
  MeetingTimes(this._ref);

  final Ref _ref;

  /// Sets [group]'s 聚會時間 to [time]: null, a service's by its rosters, a
  /// 小組's or a 其他聚會's not set. Nothing is written when it is so already.
  Future<void> set(ChurchGroup group, MeetingTime? time) async {
    switch (group) {
      case SmallGroup(:final id):
        final small = _ref.read(smallGroupsProvider).value?.byId(id);
        final next = time ?? const MeetingTime();
        if (small == null || small.time == next) return;
        await _ref.read(churchWritesProvider).smallGroup(small, small.withTime(next)).done;
      case GatheringGroup(:final id):
        final gathering = _ref.read(gatheringsProvider).value?.where((g) => g.id == id).firstOrNull;
        final next = time ?? const MeetingTime();
        if (gathering == null || gathering.time == next) return;
        await _ref.churchData.attendance.saveGathering(gathering.copyWith(time: next));
      case ServiceGroup():
        if (_ref.read(attendanceProvider(group.key)).value?.time == time) return;
        await _ref.churchData.attendance.saveTime(group.key, time);
      case MinistryGroup():
        throw ArgumentError.value(group, 'group', 'a 事工 has no 聚會時間');
    }
  }
}

/// [MeetingTimes] of the current church.
final meetingTimesProvider = Provider<MeetingTimes>(MeetingTimes.new);
