import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/cache/calendar_read_cache.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/calendar_months.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A calendar whose reads are counted, and answer when told to.
class Calendar {
  final events = <CalendarEvent>[];
  final reads = <String>[];
  Completer<void>? held;
  Object? error;

  Future<List<CalendarEvent>> read(String month) async {
    reads.add(month);
    await held?.future;
    if (error case final e?) throw e;
    return [
      for (final e in events)
        if (e.months.contains(month)) e,
    ];
  }
}

class View implements CalendarMonthView {
  List<CalendarEvent>? shown;
  int reloads = 0;
  Object? denied;

  @override
  void show(List<CalendarEvent> events) => shown = events;

  @override
  void reload() => reloads++;

  @override
  void deny(Object error, StackTrace stack) => denied = error;
}

final meeting = CalendarEvent(
  id: 'meeting',
  title: '同工會',
  start: DateTime.utc(2026, 10, 12),
  end: DateTime.utc(2026, 10, 13),
);

void main() {
  late Calendar calendar;
  late DateTime now;
  late CalendarMonths months;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    calendar = Calendar()..events.add(meeting);
    now = DateTime.utc(2026, 10, 11);
    months = CalendarMonths(
      key: (uid: 'pastor', churchId: 'grace', calendarId: 'cal', revision: '1'),
      read: calendar.read,
      cache: CalendarReadCache(await SharedPreferences.getInstance()),
      cacheScope: null,
      clock: () => now,
    );
  });

  test('a month read under a minute ago is shown again at once; after that it is read again', () async {
    expect(await months.events('2026-10'), [meeting]);
    now = now.add(const Duration(seconds: 59));
    expect(months.events('2026-10'), [meeting], reason: 'no wait, no read');
    now = now.add(const Duration(seconds: 2));
    await months.events('2026-10');
    expect(calendar.reads, ['2026-10', '2026-10']);
  });

  test('a month asked for again while it is read shares that read; a refresh reads anew', () async {
    calendar.held = Completer();
    final first = months.events('2026-10');
    final again = months.events('2026-10');
    final refreshed = months.events('2026-10', refresh: true);
    calendar.held!.complete();
    expect(await first, [meeting]);
    expect(await again, [meeting]);
    expect(await refreshed, [meeting]);
    expect(calendar.reads, ['2026-10', '2026-10']);
  });

  test('only the six months left most recently are kept', () async {
    final view = View();
    for (final month in ['2026-01', '2026-02', '2026-03', '2026-04', '2026-05', '2026-06', '2026-07']) {
      months.show(month, view);
      await months.events(month);
      months.release(month, view);
    }
    await pumpEventQueue();
    await months.events('2026-07');
    await months.events('2026-02');
    await months.events('2026-01');
    expect(calendar.reads.skip(7), ['2026-01']);
  });

  test('a refusal drops every month, tells what shows them, and fails reads begun before it', () async {
    final october = View(), november = View();
    months.show('2026-10', october);
    await months.events('2026-10');
    calendar.held = Completer();
    months.show('2026-11', november);
    const refusal = CloudException(CloudErrorCode.permissionDenied);
    final pending = expectLater(Future.sync(() => months.events('2026-11')), throwsA(same(refusal)));
    calendar.error = refusal;
    final refused = expectLater(Future.sync(() => months.events('2026-10', refresh: true)), throwsA(same(refusal)));
    calendar.held!.complete();
    await refused;
    await pending;
    expect((october.denied, november.denied), (refusal, refusal));
    calendar.error = null;
    expect(await months.events('2026-10'), [meeting], reason: 'nothing kept: read again');
  });

  test('a saved event is shown in every month holding it; one being read is read again', () async {
    final october = View(), november = View();
    months.show('2026-10', october);
    await months.events('2026-10');
    months.show('2026-11', november);
    calendar.held = Completer();
    unawaited(Future.sync(() => months.events('2026-11')));
    final moved = meeting.copyWith(title: '改到十一月', start: DateTime.utc(2026, 11, 2), end: DateTime.utc(2026, 11, 3));
    await months.write(meeting, previous: meeting, send: () async => moved, now: () => months);
    expect(october.shown, isEmpty);
    expect(november.reloads, 1, reason: 'its read began before the save');
    calendar.held!.complete();
  });

  test('after overlapping writes to one event, the months showing it are read again in full', () async {
    final view = View();
    months.show('2026-10', view);
    await months.events('2026-10');
    final first = Completer<CalendarEvent>(), second = Completer<CalendarEvent>();
    final writes = [
      months.write(
        meeting.copyWith(title: '第一版'),
        previous: meeting,
        send: () => first.future,
        now: () => months,
      ),
      months.write(
        meeting.copyWith(title: '第二版'),
        previous: meeting,
        send: () => second.future,
        now: () => months,
      ),
    ];
    second.complete(meeting.copyWith(title: '第二版'));
    await writes[1];
    expect(view.reloads, 0);
    first.complete(meeting.copyWith(title: '第一版'));
    await writes[0];
    expect(view.reloads, 1, reason: 'which the server committed last, only a read can tell');
  });

  test(
    'a write outlasting its months is applied to none; the months read since for that calendar read it again',
    () async {
      final view = View();
      final since = CalendarMonths(
        key: months.key,
        read: calendar.read,
        cache: CalendarReadCache(await SharedPreferences.getInstance()),
        cacheScope: null,
        clock: () => now,
      );
      since.show('2026-10', view);
      await since.events('2026-10');
      await months.write(
        meeting.copyWith(title: '改名'),
        previous: meeting,
        send: () async => meeting,
        now: () => since,
      );
      expect((view.shown, view.reloads), (null, 1));
    },
  );

  test('a refused write has the months still readable read again', () async {
    final view = View();
    months.show('2026-10', view);
    await months.events('2026-10');
    const refusal = CloudException(CloudErrorCode.permissionDenied);
    await expectLater(
      months.write(meeting, previous: meeting, send: () async => throw refusal, now: () => months),
      throwsA(same(refusal)),
    );
    expect((view.reloads, view.denied), (1, null));
  });

  group('shown at once, read again behind', () {
    test('a month read over a minute ago shows at once while it is read again; the new read then shows', () async {
      final view = View();
      months.show('2026-10', view);
      expect(await months.events('2026-10'), [meeting]);
      now = now.add(const Duration(seconds: 61));
      final moved = meeting.copyWith(title: '同工會（改時間）');
      calendar.events
        ..clear()
        ..add(moved);
      calendar.held = Completer();

      expect(months.events('2026-10'), [meeting], reason: 'no wait');
      expect(calendar.reads, ['2026-10', '2026-10']);
      expect(months.status('2026-10').cached, isFalse, reason: 'online, read again: no offline notice');
      calendar.held!.complete();
      await pumpEventQueue();
      expect(view.shown, [moved]);
    });

    test('a month this device saved shows at once after the app starts again, then the new read', () async {
      const scope = CalendarCacheScope(
        project: 'p',
        uid: 'pastor',
        churchId: 'grace',
        calendarId: 'cal',
        revision: '1',
      );
      final prefs = await SharedPreferences.getInstance();
      CalendarMonths start() {
        final cache = CalendarReadCache(prefs)..select(scope);
        return CalendarMonths(
          key: (uid: 'pastor', churchId: 'grace', calendarId: 'cal', revision: '1'),
          read: calendar.read,
          cache: cache,
          cacheScope: scope,
          clock: () => now,
        );
      }

      await start().events('2026-10');
      await pumpEventQueue();
      final moved = meeting.copyWith(title: '同工會（改時間）');
      calendar.events
        ..clear()
        ..add(moved);
      calendar.held = Completer();
      final again = start();
      final view = View();
      again.show('2026-10', view);

      final shown = again.events('2026-10');
      expect(shown, isA<List<CalendarEvent>>(), reason: 'what this device saved, without waiting');
      expect([for (final e in shown as List<CalendarEvent>) e.title], [meeting.title]);
      calendar.held!.complete();
      await pumpEventQueue();
      expect(view.shown, [moved]);
    });

    test('when reading again fails, the month stays, saying when it was read', () async {
      final view = View();
      months.show('2026-10', view);
      await months.events('2026-10');
      final readAt = now;
      now = now.add(const Duration(minutes: 5));
      calendar.error = const CloudException(CloudErrorCode.unknown);

      expect(months.events('2026-10'), [meeting]);
      await pumpEventQueue();
      expect(view.shown, [meeting]);
      expect(months.status('2026-10').cached, isTrue);
      expect(months.status('2026-10').fetchedAt, readAt);
      expect(months.status('2026-10').refreshError, isNotNull);
    });

    test('a month read ahead shows at once when opened, without another read', () async {
      months.prefetch('2026-11');
      await pumpEventQueue();
      expect(calendar.reads, ['2026-11']);
      final view = View();
      months.show('2026-11', view);
      expect(months.events('2026-11'), isA<List<CalendarEvent>>());
      months.prefetch('2026-11');
      expect(calendar.reads, ['2026-11'], reason: 'read once');
    });

    test('a month opened while it is read ahead waits for that read, not another', () async {
      calendar.held = Completer();
      months.prefetch('2026-10');
      final view = View();
      months.show('2026-10', view);
      final shown = months.events('2026-10');
      expect(shown, isA<Future<List<CalendarEvent>>>());
      calendar.held!.complete();
      expect(await shown, [meeting]);
      expect(calendar.reads, ['2026-10']);
    });

    test('a month that failed to read ahead is read again when opened', () async {
      calendar.error = const CloudException(CloudErrorCode.unknown);
      months.prefetch('2026-10');
      await pumpEventQueue();
      calendar.error = null;
      expect(await months.events('2026-10'), [meeting]);
      expect(calendar.reads, ['2026-10', '2026-10']);
    });
  });
}
