import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/cache/calendar_read_cache.dart';
import 'package:martha/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('an observed different scope cannot resurrect an old persisted account before purge settles', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const old = CalendarCacheScope(project: 'demo-martha', uid: 'old', churchId: 'c', calendarId: 'cal', revision: '1');
    const next = CalendarCacheScope(
      project: 'demo-martha',
      uid: 'new',
      churchId: 'c',
      calendarId: 'cal',
      revision: '1',
    );
    final first = CalendarReadCache(prefs)..select(old);
    await first.save(old, '2026-10', [
      CalendarEvent(title: '舊資料', start: DateTime.utc(2026, 10, 18), end: DateTime.utc(2026, 10, 19), allDay: true),
    ], fetchedAt: DateTime.utc(2026, 10, 11));
    final reopened = CalendarReadCache(prefs)..select(next);
    reopened.select(old);
    expect(reopened.read('2026-10'), isNull);
  });

  test('calendar cache persists complete months only inside the exact authorized scope', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const scope = CalendarCacheScope(
      project: 'demo-martha',
      uid: 'u1',
      churchId: 'c1',
      calendarId: 'cal1',
      revision: '1:0',
    );
    final now = DateTime.utc(2026, 10, 11, 3);
    final event = CalendarEvent(
      id: 'ev1',
      title: '退修會',
      start: DateTime.utc(2026, 10, 18),
      end: DateTime.utc(2026, 10, 19),
      allDay: true,
    );
    final first = CalendarReadCache(prefs)..select(scope);
    await first.save(scope, '2026-10', [event], fetchedAt: now);
    final reopened = CalendarReadCache(prefs)..select(scope);
    expect(reopened.read('2026-10')!.events.single.title, '退修會');
    expect(reopened.read('2026-10')!.fetchedAt, now);
    reopened.select(
      const CalendarCacheScope(project: 'demo-martha', uid: 'u2', churchId: 'c1', calendarId: 'cal1', revision: '1:0'),
    );
    expect(reopened.read('2026-10'), isNull);
    reopened.select(scope);
    expect(reopened.read('2026-10'), isNull);
  });

  test('a month with a timed event is read back as it was saved', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const scope = CalendarCacheScope(
      project: 'demo-martha',
      uid: 'u1',
      churchId: 'c1',
      calendarId: 'cal1',
      revision: '1:0',
    );
    final timed = CalendarEvent(
      id: 'ev2',
      title: '同工會',
      start: DateTime.utc(2026, 10, 12, 19, 30),
      end: DateTime.utc(2026, 10, 12, 21),
    );
    final first = CalendarReadCache(prefs)..select(scope);
    await first.save(scope, '2026-10', [timed], fetchedAt: DateTime.utc(2026, 10, 11));
    final reopened = CalendarReadCache(prefs)..select(scope);
    final read = reopened.read('2026-10')!.events.single;
    expect((read.start, read.end, read.allDay), (timed.start, timed.end, false));
  });
}
