import 'package:church_staff_pwa/features/calendar/presentation/widgets/_calendar_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Google item shapes here are trimmed copies of real API responses. This
/// parser feeds both the month listing and the create/edit response, so a change
/// that only looks right for one of them still has to pass all of these.
void main() {
  group('calendarEventFromGoogleItem', () {
    test('parses a timed event', () {
      final event = calendarEventFromGoogleItem({
        'id': 'abc',
        'summary': '禱告會',
        'location': '教會 2F',
        'description': '帶聖經',
        'start': {'dateTime': '2026-08-20T19:00:00+08:00'},
        'end': {'dateTime': '2026-08-20T21:00:00+08:00'},
      })!;

      expect(event.id, 'abc');
      expect(event.title, '禱告會');
      expect(event.location, '教會 2F');
      expect(event.description, '帶聖經');
      expect(event.isAllDay, isFalse);
      expect(
        event.startTime,
        DateTime.parse('2026-08-20T19:00:00+08:00').toLocal(),
      );
    });

    // Google's end.date is exclusive, so a one-day event ends "tomorrow".
    // endDay has to walk that back or the bar spans two cells.
    test('a single-day all-day event occupies exactly one day', () {
      final event = calendarEventFromGoogleItem({
        'id': 'all-day',
        'summary': '特會',
        'start': {'date': '2026-08-20'},
        'end': {'date': '2026-08-21'},
      })!;

      expect(event.isAllDay, isTrue);
      expect(event.startDay, DateTime(2026, 8, 20));
      expect(event.endDay, DateTime(2026, 8, 20));
      expect(event.spansMultipleDays, isFalse);
      expect(event.occursOnDate(DateTime(2026, 8, 20)), isTrue);
      expect(event.occursOnDate(DateTime(2026, 8, 21)), isFalse);
    });

    test('a multi-day all-day event covers every day in between', () {
      final event = calendarEventFromGoogleItem({
        'id': 'camp',
        'summary': '夏令營',
        'start': {'date': '2026-08-20'},
        'end': {'date': '2026-08-23'},
      })!;

      expect(event.spansMultipleDays, isTrue);
      expect(event.endDay, DateTime(2026, 8, 22));
      for (final day in [20, 21, 22]) {
        expect(
          event.occursOnDate(DateTime(2026, 8, day)),
          isTrue,
          reason: '8/$day',
        );
      }
      expect(event.occursOnDate(DateTime(2026, 8, 23)), isFalse);
    });

    test(
      'a timed event is not treated as all-day even with a date sibling',
      () {
        final event = calendarEventFromGoogleItem({
          'id': 'x',
          'start': {
            'dateTime': '2026-08-20T19:00:00+08:00',
            'date': '2026-08-20',
          },
          'end': {'dateTime': '2026-08-20T20:00:00+08:00'},
        })!;
        expect(event.isAllDay, isFalse);
      },
    );

    test('skips a cancelled event', () {
      expect(
        calendarEventFromGoogleItem({
          'id': 'gone',
          'status': 'cancelled',
          'start': {'date': '2026-08-20'},
          'end': {'date': '2026-08-21'},
        }),
        isNull,
      );
    });

    test('skips an entry with no usable start', () {
      expect(calendarEventFromGoogleItem({'id': 'x', 'summary': 'y'}), isNull);
      expect(
        calendarEventFromGoogleItem({
          'id': 'x',
          'start': {'timeZone': 'Asia/Taipei'},
        }),
        isNull,
      );
    });

    test('falls back to a placeholder title', () {
      final event = calendarEventFromGoogleItem({
        'id': 'x',
        'summary': '   ',
        'start': {'date': '2026-08-20'},
        'end': {'date': '2026-08-21'},
      })!;
      expect(event.title, '未命名活動');
    });

    test(
      'blank location and description become null rather than empty rows',
      () {
        final event = calendarEventFromGoogleItem({
          'id': 'x',
          'summary': 'y',
          'location': '   ',
          'description': '',
          'start': {'date': '2026-08-20'},
          'end': {'date': '2026-08-21'},
        })!;
        expect(event.location, isNull);
        expect(event.description, isNull);
      },
    );

    // Two id-less events in one response must not collapse into one, because
    // the layout code keys lanes off `identity`.
    test('id-less events get distinct synthetic ids', () {
      Map<String, dynamic> item() => {
        'summary': '同名活動',
        'start': {'date': '2026-08-20'},
        'end': {'date': '2026-08-21'},
      };
      final first = calendarEventFromGoogleItem(item(), fallbackIndex: 0)!;
      final second = calendarEventFromGoogleItem(item(), fallbackIndex: 1)!;
      expect(first.identity, isNot(second.identity));
    });

    test('an end before the start does not produce a negative span', () {
      final event = calendarEventFromGoogleItem({
        'id': 'x',
        'summary': 'y',
        'start': {'dateTime': '2026-08-20T19:00:00+08:00'},
        'end': {'dateTime': '2026-08-20T18:00:00+08:00'},
      })!;
      expect(event.endDay, event.startDay);
      expect(event.occursOnDate(DateTime(2026, 8, 20)), isTrue);
    });

    test(
      'throws on a malformed date so the caller can skip just that item',
      () {
        expect(
          () => calendarEventFromGoogleItem({
            'id': 'x',
            'start': {'date': 'not-a-date'},
            'end': {'date': '2026-08-21'},
          }),
          throwsFormatException,
        );
      },
    );
  });

  group('CalendarEvent round trip', () {
    test('survives the SharedPreferences cache format', () {
      final event = calendarEventFromGoogleItem({
        'id': 'abc',
        'summary': '特會',
        'location': '教會',
        'start': {'date': '2026-08-20'},
        'end': {'date': '2026-08-23'},
      })!;

      final restored = CalendarEvent.fromJson(event.toJson());
      expect(restored.id, event.id);
      expect(restored.isAllDay, event.isAllDay);
      expect(restored.startDay, event.startDay);
      expect(restored.endDay, event.endDay);
      expect(restored.location, event.location);
      expect(restored.description, isNull);
    });
  });
}
