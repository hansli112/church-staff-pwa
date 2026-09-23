import 'dart:async';
import 'dart:convert';

import 'package:church_staff_pwa/features/calendar/data/google_calendar_month_reader.dart';
import 'package:church_staff_pwa/features/calendar/presentation/layout/month_event_layout.dart';
import 'package:church_staff_pwa/features/calendar/data/calendar_month_store.dart';
import 'package:church_staff_pwa/features/calendar/domain/entities/calendar_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The month data behind the calendar screen, driven without the screen: what
/// the grid gets to show after cache reads, Google reads and admin writes land
/// in whatever order they happen to land.

final _september = DateTime(2026, 9);
final _october = DateTime(2026, 10);

CalendarEvent _event(String id, DateTime day) => CalendarEvent(
  id: id,
  startTime: day,
  endTime: day.add(const Duration(days: 1)),
  isAllDay: true,
  title: id,
);

List<String> _ids(List<CalendarEvent>? events) =>
    (events ?? const <CalendarEvent>[]).map((e) => e.id).toList()..sort();

/// A fetcher whose answers the test releases one at a time.
class _ControlledFetcher {
  final List<(DateTime, Completer<List<CalendarEvent>>)> calls = [];

  Future<List<CalendarEvent>> call(DateTime month) {
    final completer = Completer<List<CalendarEvent>>();
    calls.add((month, completer));
    return completer.future;
  }

  void answer(int index, List<CalendarEvent> events) =>
      calls[index].$2.complete(events);
}

/// Storage that has nothing and cannot take anything more — a full
/// localStorage. Only the calls the store makes are implemented.
class _FullStorage implements SharedPreferences {
  @override
  String? getString(String key) => null;

  @override
  Set<String> getKeys() => const {};

  @override
  Future<bool> setString(String key, String value) =>
      Future.error(StateError('QuotaExceededError'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _cacheKey(DateTime month) =>
    'calendar_events_${month.year}_${month.month.toString().padLeft(2, '0')}';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // The race: the screen opens, paints the cached month, and the first Google
  // read is still out when an admin saves. That read was sent before the save,
  // so when it lands it describes the calendar *without* the new event. It
  // used to be applied anyway — wiping the local patch and stamping the month
  // fresh, so the new event vanished for ten minutes.
  test('a read sent before a write cannot undo it', () async {
    final existing = _event('existing', DateTime(2026, 9, 10));
    final added = _event('added', DateTime(2026, 9, 20));
    SharedPreferences.setMockInitialValues({
      _cacheKey(_september): jsonEncode([existing.toJson()]),
    });
    final fetcher = _ControlledFetcher();
    final months = CalendarMonthStore(fetchMonth: fetcher.call);
    addTearDown(months.dispose);

    unawaited(months.ensureLoaded(_september));
    await pumpEventQueue();
    expect(_ids(months.eventsForMonth(_september)), ['existing']);
    expect(fetcher.calls, hasLength(1));

    months.applyWrite(added: added);
    expect(_ids(months.eventsForMonth(_september)), ['added', 'existing']);

    // The stale answer, from before the write.
    fetcher.answer(0, [existing]);
    await pumpEventQueue();

    expect(
      _ids(months.eventsForMonth(_september)),
      ['added', 'existing'],
      reason: 'the stale read must not overwrite the patch',
    );
    expect(
      fetcher.calls,
      hasLength(2),
      reason: 'the refresh the write asked for must still happen',
    );

    fetcher.answer(1, [existing, added]);
    await pumpEventQueue();
    expect(_ids(months.eventsForMonth(_september)), ['added', 'existing']);

    // And that fresh answer is what the device keeps for next time.
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString(_cacheKey(_september))!) as List;
    expect(saved.map((e) => (e as Map)['id']), ['existing', 'added']);
  });

  test('a write with no read in flight refetches straight away', () async {
    final fetcher = _ControlledFetcher();
    final months = CalendarMonthStore(fetchMonth: fetcher.call);
    addTearDown(months.dispose);

    final load = months.ensureLoaded(_september);
    fetcher.answer(0, [_event('a', DateTime(2026, 9, 3))]);
    await load;

    months.applyWrite(removed: _event('a', DateTime(2026, 9, 3)));
    expect(months.eventsForMonth(_september), isEmpty);
    expect(fetcher.calls, hasLength(2));
    expect(fetcher.calls.last.$1, _september);
  });

  // Moving an event from September to October has to refresh both: the month
  // it left still has it in its cache otherwise.
  test('an edit refetches the month the event left as well', () async {
    final fetcher = _ControlledFetcher();
    final months = CalendarMonthStore(fetchMonth: fetcher.call);
    addTearDown(months.dispose);

    final before = _event('a', DateTime(2026, 9, 29));
    final after = _event('a', DateTime(2026, 10, 2));
    final loads = [
      months.ensureLoaded(_september),
      months.ensureLoaded(_october),
    ];
    fetcher.answer(0, [before]);
    fetcher.answer(1, const []);
    await Future.wait(loads);

    months.applyWrite(removed: before, added: after);

    expect(months.eventsForMonth(_september), isEmpty);
    expect(_ids(months.eventsForMonth(_october)), ['a']);
    expect(fetcher.calls.skip(2).map((c) => c.$1), [_september, _october]);
  });

  test('a month read within ten minutes is not read again', () async {
    var now = DateTime(2026, 9, 23, 12);
    final fetcher = _ControlledFetcher();
    final months = CalendarMonthStore(fetchMonth: fetcher.call, now: () => now);
    addTearDown(months.dispose);

    final first = months.ensureLoaded(_september);
    fetcher.answer(0, const []);
    await first;

    now = now.add(const Duration(minutes: 9));
    await months.ensureLoaded(_september);
    expect(fetcher.calls, hasLength(1));

    now = now.add(const Duration(minutes: 2));
    unawaited(months.ensureLoaded(_september));
    await pumpEventQueue();
    expect(fetcher.calls, hasLength(2));
    fetcher.answer(1, const []);
  });

  group('the Google read', () {
    // What Google does with timeMin/timeMax: an event is listed when it
    // overlaps the window — it ends after timeMin and starts before timeMax.
    MockClient googleWith(List<Map<String, dynamic>> items) => MockClient((
      request,
    ) async {
      final timeMin = DateTime.parse(request.url.queryParameters['timeMin']!);
      final timeMax = DateTime.parse(request.url.queryParameters['timeMax']!);
      final listed = items.where((item) {
        final start = DateTime.parse(item['start']['dateTime'] as String);
        final end = DateTime.parse(item['end']['dateTime'] as String);
        return end.isAfter(timeMin) && start.isBefore(timeMax);
      }).toList();
      return http.Response(
        jsonEncode({'items': listed}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    // The window used to run from UTC midnight, which is 08:00 in Taipei. An
    // event at 00:30 on the 1st then came back in the *previous* month's
    // listing, whose layout drops it as not its own — and October's listing
    // never had it — so it was on no page at all.
    //
    // Built from local times, so it holds wherever the test runs; it only
    // tells the two windows apart on a machine that is not on UTC, like the
    // Taipei ones this app is used on (`TZ=Asia/Taipei flutter test`).
    test('an event at 00:30 on the 1st shows on the 1st', () async {
      final start = DateTime(2026, 10, 1, 0, 30);
      final client = googleWith([
        {
          'id': 'early',
          'summary': '清晨禱告',
          'start': {'dateTime': start.toUtc().toIso8601String()},
          'end': {
            'dateTime': start
                .add(const Duration(hours: 1))
                .toUtc()
                .toIso8601String(),
          },
        },
      ]);
      final months = CalendarMonthStore(
        fetchMonth: GoogleCalendarMonthReader(client: client).fetchMonth,
      );
      addTearDown(months.dispose);

      await months.ensureLoaded(_september);
      await months.ensureLoaded(_october);

      final october = MonthEventLayout.compute(
        _october,
        months.eventsForMonth(_october)!,
      );
      expect(october.segmentsOn(DateTime(2026, 10, 1)).map((s) => s.event.id), [
        'early',
      ]);
    });

    test('the window is local midnight to local midnight', () {
      final window = calendarMonthWindow(_october);
      expect(window.timeMin, DateTime(2026, 10, 1).toUtc());
      expect(window.timeMax, DateTime(2026, 11, 1).toUtc());
      // December rolls over into the next year.
      expect(
        calendarMonthWindow(DateTime(2026, 12)).timeMax,
        DateTime(2027, 1, 1).toUtc(),
      );
    });

    test('a rejected read shows Google\'s reason', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': 'API key not valid'},
          }),
          400,
        ),
      );
      final months = CalendarMonthStore(
        fetchMonth: GoogleCalendarMonthReader(client: client).fetchMonth,
      );
      addTearDown(months.dispose);

      await months.ensureLoaded(_september);
      expect(months.errorForMonth(_september), '載入失敗（400）：API key not valid');
    });

    test('offline with nothing cached says so', () async {
      final months = CalendarMonthStore(
        fetchMonth: (_) => Future.error(TimeoutException('no network')),
      );
      addTearDown(months.dispose);

      await months.ensureLoaded(_september);
      expect(months.errorForMonth(_september), '離線或連線逾時，且沒有快取資料');
    });

    test('offline with a cached copy shows the copy and no error', () async {
      SharedPreferences.setMockInitialValues({
        _cacheKey(_september): jsonEncode([
          _event('cached', DateTime(2026, 9, 8)).toJson(),
        ]),
      });
      final months = CalendarMonthStore(
        fetchMonth: (_) => Future.error(TimeoutException('no network')),
      );
      addTearDown(months.dispose);

      await months.ensureLoaded(_september);
      expect(_ids(months.eventsForMonth(_september)), ['cached']);
      expect(months.errorForMonth(_september), isNull);
    });
  });

  // Caching the answer is a bonus, not part of loading: the month is already
  // on screen, so a full disk must not turn into an "offline" error for it.
  test('a month that loaded but could not be cached is not an error', () async {
    final months = CalendarMonthStore(
      fetchMonth: (_) async => [_event('a', DateTime(2026, 9, 8))],
      prefs: () async => _FullStorage(),
    );
    addTearDown(months.dispose);

    await months.ensureLoaded(_september);

    expect(_ids(months.eventsForMonth(_september)), ['a']);
    expect(months.errorForMonth(_september), isNull);
  });

  test('every change hands out a new list', () async {
    final fetcher = _ControlledFetcher();
    final months = CalendarMonthStore(fetchMonth: fetcher.call);
    addTearDown(months.dispose);

    final load = months.ensureLoaded(_september);
    fetcher.answer(0, const []);
    await load;
    final before = months.eventsForMonth(_september);

    months.applyWrite(added: _event('a', DateTime(2026, 9, 4)));
    // The screen reuses a month's layout while the list is identical(), so an
    // in-place edit here would leave the old bars on screen.
    expect(identical(months.eventsForMonth(_september), before), isFalse);
    expect(before, isEmpty);
  });
}
