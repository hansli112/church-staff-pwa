import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/calendar.dart';
import 'package:martha/state/providers.dart';

import '../support/harness.dart';
import 'calendar_test.dart' show CalendarBackend;

Future<void> authorize(ProviderContainer container) async {
  container.listen(appStageProvider, (_, _) {});
  container.listen(meProvider, (_, _) {});
  container.listen(calendarSettingsProvider, (_, _) {});
  await pumpEventQueue();
}

void main() {
  test('offline calendar reopens its exact persisted month as dated cache, not fresh data', () async {
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
    final overrides = await testOverrides(b);
    final first = ProviderContainer(overrides: overrides, retry: (_, _) => null);
    await authorize(first);
    first.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await first.read(calendarEventsProvider('2026-10').future);
    await pumpEventQueue();
    first.dispose();

    b.setOnline(false);
    final second = ProviderContainer(overrides: overrides, retry: (_, _) => null);
    addTearDown(second.dispose);
    await authorize(second);
    second.listen(calendarEventsProvider('2026-10'), (_, _) {});
    final events = await second.read(calendarEventsProvider('2026-10').future);
    expect(events.single.title, '同工會');
    final status = second.read(calendarReadStatusProvider('2026-10'));
    expect(status.cached, isTrue);
    expect(status.fetchedAt, testNow.toUtc());
  });
}
