import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/meeting_times.dart';
import 'package:martha/state/providers.dart';

import '../support/harness.dart';
import '../support/seed.dart';

const _joy = SmallGroupDetails(id: 'joy', name: '喜樂小組', service: 'sunday');
const _prayer = Gathering(id: 'prayer', name: '禱告會');

final _fridays = MeetingTime(weekday: DateTime.friday, every: 2, startsOn: Day(2026, 10, 2));

Future<ProviderContainer> opened(MemoryBackend b) async {
  b.smallGroups['grace'] = {'joy': _joy};
  b.gatherings['grace'] = {'prayer': _prayer};
  final container = ProviderContainer(overrides: await testOverrides(b));
  addTearDown(container.dispose);
  container.listen(appStageProvider, (_, _) {});
  for (final g in [_joy.group, const GatheringGroup('prayer'), const ServiceGroup('sunday')]) {
    container.listen(meetingTimeProvider(g), (_, _) {});
  }
  await pumpEventQueue();
  return container;
}

void main() {
  test("a 小組's 聚會時間 is its own, set on it", () async {
    final b = seededChurch();
    final c = await opened(b);
    expect(c.read(meetingTimeProvider(_joy.group)).time, const MeetingTime());

    await c.read(meetingTimesProvider).set(_joy.group, _fridays);
    await pumpEventQueue();
    expect(b.smallGroups['grace']!['joy']!.time, _fridays);
    expect(c.read(meetingTimeProvider(_joy.group)).time, _fridays);
  });

  test("a 其他聚會's is its own too", () async {
    final b = seededChurch();
    final c = await opened(b);
    await c.read(meetingTimesProvider).set(const GatheringGroup('prayer'), _fridays);
    await pumpEventQueue();
    expect(b.gatherings['grace']!['prayer']!.time, _fridays);
    expect(c.read(meetingTimeProvider(const GatheringGroup('prayer'))).time, _fridays);
  });

  test("a service's is kept with its 人數, on the service's weekdays; none is by its rosters", () async {
    final b = seededChurch();
    final c = await opened(b);
    const sunday = ServiceGroup('sunday');
    expect(c.read(meetingTimeProvider(sunday)).time, isNull);
    expect(c.read(meetingTimeProvider(sunday)).serviceWeekdays, [DateTime.sunday]);

    final every = MeetingTime(startsOn: Day(2026, 11, 1));
    await c.read(meetingTimesProvider).set(sunday, every);
    await pumpEventQueue();
    expect(b.attendance['grace']!['service:sunday']!.time, every);
    expect(c.read(meetingTimeProvider(sunday)).time, every);

    await c.read(meetingTimesProvider).set(sunday, null);
    await pumpEventQueue();
    expect(c.read(meetingTimeProvider(sunday)).time, isNull);
  });

  test('who sets it: a 小組 by its 小組長 and its service, the rest by who sets its 人數', () {
    final lead = staffMei.withIdentities(const [SmallGroupLead('joy')]);
    expect(lead.schedules(const SmallGroup('joy', service: 'sunday')), isTrue);
    expect(editor.schedules(const SmallGroup('joy', service: 'sunday')), isTrue);
    expect(staffMei.schedules(const SmallGroup('joy', service: 'sunday')), isFalse);
    expect(editor.schedules(const ServiceGroup('sunday')), isTrue);
    expect(editor.schedules(const ServiceGroup('youth')), isFalse);
    expect(office.schedules(const SmallGroup('joy', service: 'sunday')), isFalse, reason: '行政 sees it from 人數總覽');
    expect(office.schedules(const GatheringGroup('prayer')), isTrue);
    expect(pastor.schedules(const MinistryGroup('worship')), isFalse);
  });
}
