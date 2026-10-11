import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/calendar.dart';

import '../support/harness.dart';
import 'calendar_offline_test.dart' show authorize;
import 'calendar_test.dart' show CalendarBackend;

void main() {
  test('after a failed read marked the device offline, retrying still asks the backend', () async {
    final b = CalendarBackend();
    b.calendarEvents['grace'] = [
      CalendarEvent(
        id: 'meeting',
        title: '同工會',
        start: DateTime.utc(2026, 10, 18),
        end: DateTime.utc(2026, 10, 19),
        allDay: true,
      ),
    ];
    final container = ProviderContainer(overrides: await testOverrides(b), retry: (_, _) => null);
    addTearDown(container.dispose);
    await authorize(container);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.read(calendarEventsProvider('2026-10').future);

    // A read failed in a lift; a phone sends no event when the network returns.
    b.connectivity.observe(false);
    final reads = b.reads.length;
    container.invalidate(calendarEventsProvider('2026-10'));
    final events = await container.read(calendarEventsProvider('2026-10').future);
    expect(b.reads.length, reads + 1, reason: 'a retry is a real request, not the stale offline flag');
    expect(events.single.title, '同工會');
    expect(container.read(calendarReadStatusProvider('2026-10')).cached, isFalse);
  });
}
