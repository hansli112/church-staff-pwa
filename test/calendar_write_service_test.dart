import 'dart:convert';

import 'package:church_staff_pwa/features/calendar/data/calendar_write_service.dart';
import 'package:church_staff_pwa/features/calendar/presentation/widgets/_calendar_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _endpoint = Uri.parse('https://app.example/api/calendar/events');

CalendarEventDraft _draft({
  String title = '青年小組',
  bool allDay = true,
  DateTime? start,
  DateTime? end,
  TimeOfDay startTime = const TimeOfDay(hour: 19, minute: 0),
  TimeOfDay endTime = const TimeOfDay(hour: 21, minute: 30),
  String location = '',
  String description = '',
}) {
  final startDate = start ?? DateTime(2026, 8, 20);
  return CalendarEventDraft(
    title: title,
    allDay: allDay,
    startDate: startDate,
    endDate: end ?? startDate,
    startTime: startTime,
    endTime: endTime,
    location: location,
    description: description,
  );
}

/// Records every request so a test can assert what actually went out, not only
/// what came back.
class _Recorder {
  final List<http.Request> requests = [];

  MockClient client(http.Response Function(http.Request) respond) {
    return MockClient((request) async {
      requests.add(request);
      return respond(request);
    });
  }
}

http.Response _googleItem({String id = 'evt-1'}) => http.Response(
  jsonEncode({
    'id': id,
    'summary': '青年小組',
    'start': {'date': '2026-08-20'},
    'end': {'date': '2026-08-21'},
  }),
  201,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

CalendarWriteService _service(
  http.Client client, {
  Future<String?> Function()? idToken,
}) {
  return CalendarWriteService(
    client: client,
    endpoint: _endpoint,
    idToken: idToken ?? () async => 'test-token',
  );
}

void main() {
  group('CalendarEventDraft', () {
    test('an all-day draft sends plain dates and the inclusive end', () {
      final body = _draft(
        start: DateTime(2026, 8, 20),
        end: DateTime(2026, 8, 22),
      ).toJson();

      expect(body['allDay'], isTrue);
      expect(body['start'], '2026-08-20');
      // Google's exclusive end is the server's job — the client stays in the
      // terms the user typed.
      expect(body['end'], '2026-08-22');
    });

    test('a timed draft sends wall-clock time with no offset', () {
      final body = _draft(
        allDay: false,
        startTime: const TimeOfDay(hour: 9, minute: 5),
        endTime: const TimeOfDay(hour: 11, minute: 0),
      ).toJson();

      expect(body['start'], '2026-08-20T09:05');
      expect(body['end'], '2026-08-20T11:00');
    });

    test('pads single-digit months and days', () {
      final body = _draft(start: DateTime(2026, 1, 5)).toJson();
      expect(body['start'], '2026-01-05');
    });

    test('trims the text fields', () {
      final body = _draft(title: '  聚會  ', location: ' 教會 ').toJson();
      expect(body['title'], '聚會');
      expect(body['location'], '教會');
    });

    test('rejects an empty title', () {
      expect(_draft(title: '   ').validate(), '請填寫標題');
    });

    test('rejects an end date before the start', () {
      final invalid = _draft(
        start: DateTime(2026, 8, 20),
        end: DateTime(2026, 8, 19),
      );
      expect(invalid.validate(), '結束日期不能早於開始日期');
    });

    test('accepts an equal start and end date', () {
      expect(_draft().validate(), isNull);
    });

    test('rejects an end time before the start on the same day', () {
      final invalid = _draft(
        allDay: false,
        startTime: const TimeOfDay(hour: 19, minute: 0),
        endTime: const TimeOfDay(hour: 18, minute: 59),
      );
      expect(invalid.validate(), '結束時間不能早於開始時間');
    });

    // A retreat running 19:00 Friday to 12:00 Sunday has an "earlier" clock
    // time at the end; only comparing the times would wrongly reject it.
    test('accepts a later day even when the clock time is earlier', () {
      final valid = _draft(
        allDay: false,
        start: DateTime(2026, 8, 20),
        end: DateTime(2026, 8, 22),
        startTime: const TimeOfDay(hour: 19, minute: 0),
        endTime: const TimeOfDay(hour: 12, minute: 0),
      );
      expect(valid.validate(), isNull);
    });

    test('forDay defaults to a single all-day event on that day', () {
      final draft = CalendarEventDraft.forDay(DateTime(2026, 8, 20, 13, 45));
      expect(draft.allDay, isTrue);
      expect(draft.startDate, DateTime(2026, 8, 20));
      expect(draft.endDate, DateTime(2026, 8, 20));
      expect(draft.title, isEmpty);
    });

    // Round-tripping an event through the edit form must not shift its dates.
    test('fromEvent restores the inclusive end date of an all-day event', () {
      final event = calendarEventFromGoogleItem({
        'id': 'x',
        'summary': '夏令營',
        'start': {'date': '2026-08-20'},
        'end': {'date': '2026-08-23'},
      })!;

      final draft = CalendarEventDraft.fromEvent(event);
      expect(draft.allDay, isTrue);
      expect(draft.startDate, DateTime(2026, 8, 20));
      expect(draft.endDate, DateTime(2026, 8, 22));
      expect(draft.toJson()['end'], '2026-08-22');
    });

    // endDay deliberately walks back a microsecond so an all-day event does not
    // occupy an extra cell. Applying that to a *timed* event ending at midnight
    // collapses the end onto the start day, and the form then refuses to save
    // an event it just opened — the event becomes uneditable.
    //
    // Built from local DateTimes rather than a Google item on purpose: parsing
    // an offset timestamp would land both ends on the same local day in some
    // time zones and the midnight crossing would not reproduce.
    test('fromEvent keeps a timed event ending at midnight editable', () {
      final event = CalendarEvent(
        id: 'x',
        title: '跨夜禱告',
        isAllDay: false,
        startTime: DateTime(2026, 8, 20, 22),
        endTime: DateTime(2026, 8, 21),
      );

      final draft = CalendarEventDraft.fromEvent(event);
      expect(draft.validate(), isNull);
      expect(draft.endDate, DateTime(2026, 8, 21));
      expect(draft.toJson()['start'], '2026-08-20T22:00');
      expect(draft.toJson()['end'], '2026-08-21T00:00');
    });

    test('fromEvent clamps a timed event whose end precedes its start', () {
      final event = CalendarEvent(
        id: 'x',
        title: '壞資料',
        isAllDay: false,
        startTime: DateTime(2026, 8, 20, 19),
        endTime: DateTime(2026, 8, 19, 19),
      );

      final draft = CalendarEventDraft.fromEvent(event);
      expect(draft.endDate, DateTime(2026, 8, 20));
    });

    test('fromEvent restores the times of a timed event', () {
      final event = calendarEventFromGoogleItem({
        'id': 'x',
        'summary': '禱告會',
        'location': '教會',
        'start': {'dateTime': '2026-08-20T19:00:00+08:00'},
        'end': {'dateTime': '2026-08-20T21:00:00+08:00'},
      })!;

      final draft = CalendarEventDraft.fromEvent(event);
      expect(draft.allDay, isFalse);
      expect(draft.location, '教會');
      expect(draft.startTime, TimeOfDay.fromDateTime(event.startTime));
    });
  });

  group('CalendarWriteService.create', () {
    test('posts to the endpoint with the bearer token', () async {
      final recorder = _Recorder();
      final service = _service(recorder.client((_) => _googleItem()));

      final event = await service.create(_draft());

      expect(event.id, 'evt-1');
      expect(event.isAllDay, isTrue);
      expect(recorder.requests.single.method, 'POST');
      expect(recorder.requests.single.url, _endpoint);
      expect(
        recorder.requests.single.headers['Authorization'],
        'Bearer test-token',
      );
      expect(jsonDecode(recorder.requests.single.body)['title'], '青年小組');
    });

    test('refuses without sending anything when there is no token', () async {
      final recorder = _Recorder();
      final service = _service(
        recorder.client((_) => _googleItem()),
        idToken: () async => null,
      );

      await expectLater(
        service.create(_draft()),
        throwsA(
          isA<CalendarWriteException>().having(
            (e) => e.message,
            'message',
            '請先登入',
          ),
        ),
      );
      expect(recorder.requests, isEmpty);
    });

    test('surfaces the message the API wrote', () async {
      final service = _service(
        _Recorder().client(
          (_) => http.Response(
            jsonEncode({'error': '只有管理員可以編輯行事曆'}),
            403,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );

      await expectLater(
        service.create(_draft()),
        throwsA(
          isA<CalendarWriteException>().having(
            (e) => e.message,
            'message',
            '只有管理員可以編輯行事曆',
          ),
        ),
      );
    });

    // Anything in front of the function — Cloudflare, a stale service worker —
    // can answer with HTML instead of the JSON shape.
    test(
      'falls back to a status message when the body is not our JSON',
      () async {
        final service = _service(
          _Recorder().client((_) => http.Response('<html>502</html>', 502)),
        );

        await expectLater(
          service.create(_draft()),
          throwsA(
            isA<CalendarWriteException>().having(
              (e) => e.message,
              'message',
              '伺服器忙碌中，請稍後再試',
            ),
          ),
        );
      },
    );

    test('maps a transport failure to a network message', () async {
      final service = _service(
        MockClient((_) async => throw const SocketExceptionStub()),
      );

      await expectLater(
        service.create(_draft()),
        throwsA(
          isA<CalendarWriteException>().having(
            (e) => e.message,
            'message',
            '連線失敗，請檢查網路後再試一次',
          ),
        ),
      );
    });

    test('keeps a non-UTF8-safe Chinese message intact', () async {
      final service = _service(
        _Recorder().client(
          (_) => http.Response.bytes(
            utf8.encode(jsonEncode({'error': '沒有權限寫入這本日曆，請聯絡管理員'})),
            502,
          ),
        ),
      );

      await expectLater(
        service.create(_draft()),
        throwsA(
          isA<CalendarWriteException>().having(
            (e) => e.message,
            'message',
            '沒有權限寫入這本日曆，請聯絡管理員',
          ),
        ),
      );
    });
  });

  group('CalendarWriteService.update and delete', () {
    test('patches the event by id', () async {
      final recorder = _Recorder();
      final service = _service(recorder.client((_) => _googleItem()));

      await service.update('evt-1', _draft());

      expect(recorder.requests.single.method, 'PATCH');
      expect(recorder.requests.single.url.path, '/api/calendar/events/evt-1');
    });

    test(
      'escapes an id that needs it instead of adding a path segment',
      () async {
        final recorder = _Recorder();
        final service = _service(
          recorder.client((_) => http.Response('', 204)),
        );

        await service.delete('a/b c');

        expect(recorder.requests.single.url.pathSegments.last, 'a/b c');
        expect(
          recorder.requests.single.url.path,
          '/api/calendar/events/a%2Fb%20c',
        );
      },
    );

    test('deletes with no body and accepts 204', () async {
      final recorder = _Recorder();
      final service = _service(recorder.client((_) => http.Response('', 204)));

      await service.delete('evt-1');

      expect(recorder.requests.single.method, 'DELETE');
      expect(recorder.requests.single.body, isEmpty);
    });

    test('reports an already-deleted event', () async {
      final service = _service(
        _Recorder().client(
          (_) => http.Response(
            jsonEncode({'error': '這個活動已經不存在了'}),
            404,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );

      await expectLater(
        service.delete('gone'),
        throwsA(
          isA<CalendarWriteException>().having(
            (e) => e.message,
            'message',
            '這個活動已經不存在了',
          ),
        ),
      );
    });
  });
}

/// Stands in for a real socket failure; MockClient has no way to simulate one
/// other than throwing.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
