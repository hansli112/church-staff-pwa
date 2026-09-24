import 'dart:convert';

import 'package:church_staff_pwa/core/config/church_config.dart';
import 'package:church_staff_pwa/core/time/church_time.dart';
import 'package:church_staff_pwa/features/calendar/data/calendar_write_service.dart';
import 'package:church_staff_pwa/features/calendar/data/google_calendar_event.dart';
import 'package:church_staff_pwa/features/calendar/data/google_calendar_month_reader.dart';
import 'package:church_staff_pwa/features/calendar/domain/entities/calendar_event.dart';
import 'package:church_staff_pwa/features/calendar/presentation/layout/month_event_layout.dart';
import 'package:church_staff_pwa/features/dashboard/domain/entities/recent_activity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/church_test_config.dart';

void main() {
  setUp(
    () => setTestChurchConfig(calendar: true, timeZone: 'America/New_York'),
  );

  for (final isAllDay in [true, false]) {
    test(
      'calendar and dashboard share cached time semantics (allDay=$isAllDay)',
      () {
        final json = <String, dynamic>{
          'id': 'shared-time',
          'title': '測試活動',
          'isAllDay': isAllDay,
          'startTime': isAllDay
              ? '2026-03-08T00:00:00.000Z'
              : '2026-03-08T06:30:00.000Z',
          'endTime': isAllDay
              ? '2026-03-10T00:00:00.000Z'
              : '2026-03-08T07:30:00.000Z',
        };
        final calendar = CalendarEvent.fromJson(json);
        final recent = RecentActivity.fromJson(json);
        expect(recent.startTime, calendar.startTime);
        expect(recent.endTime, calendar.endTime);
        expect(recent.startInstant, calendar.startInstant);
        expect(recent.startDay, calendar.startDay);
        expect(recent.endDay, calendar.endDay);
        expect(
          calendar.startInstant.toUtc(),
          isAllDay
              ? DateTime.utc(2026, 3, 8, 5)
              : DateTime.utc(2026, 3, 8, 6, 30),
        );
        expect(
          CalendarEvent.fromJson(calendar.toJson()).startInstant,
          calendar.startInstant,
        );
        expect(
          RecentActivity.fromJson(recent.toJson()).startInstant,
          recent.startInstant,
        );
      },
    );
  }

  test('shared parsing preserves each model\'s missing-end cache fallback', () {
    for (final isAllDay in [true, false]) {
      final json = <String, dynamic>{
        'title': '舊快取',
        'isAllDay': isAllDay,
        'startTime': '2026-03-08T00:00:00.000Z',
      };
      final calendar = CalendarEvent.fromJson(json);
      final recent = RecentActivity.fromJson(json);
      expect(recent.startTime, calendar.startTime);
      expect(calendar.endTime, calendar.startTime);
      expect(recent.endTime, recent.startTime.add(const Duration(minutes: 1)));
    }
  });

  test('month query boundaries account for both spring and autumn DST', () {
    final spring = calendarMonthWindow(DateTime.utc(2026, 3));
    expect(spring.timeMin, DateTime.utc(2026, 3, 1, 5));
    expect(spring.timeMax, DateTime.utc(2026, 4, 1, 4));
    final autumn = calendarMonthWindow(DateTime.utc(2026, 11));
    expect(autumn.timeMin, DateTime.utc(2026, 11, 1, 4));
    expect(autumn.timeMax, DateTime.utc(2026, 12, 1, 5));
  });

  test(
    'reader requests the configured zone and its midnight boundaries',
    () async {
      final reader = GoogleCalendarMonthReader(
        client: MockClient((request) async {
          expect(request.url.queryParameters['timeZone'], 'America/New_York');
          expect(
            request.url.queryParameters['timeMin'],
            '2026-03-01T05:00:00.000Z',
          );
          expect(
            request.url.queryParameters['timeMax'],
            '2026-04-01T04:00:00.000Z',
          );
          return http.Response(jsonEncode({'items': []}), 200);
        }),
      );
      expect(await reader.fetchMonth(DateTime.utc(2026, 3)), isEmpty);
    },
  );

  test('timed events render on the church date rather than their UTC date', () {
    final event = calendarEventFromGoogleItem({
      'id': 'late',
      'summary': '晚間聚會',
      'start': {'dateTime': '2026-03-02T02:00:00Z'},
      'end': {'dateTime': '2026-03-02T03:00:00Z'},
    })!;
    expect(event.startTime.hour, 21);
    expect(event.startDay, DateTime.utc(2026, 3, 1));
    final layout = MonthEventLayout.compute(DateTime.utc(2026, 3), [event]);
    expect(layout.segmentsOn(DateTime.utc(2026, 3, 1)), hasLength(1));
    expect(layout.segmentsOn(DateTime.utc(2026, 3, 2)), isEmpty);
    final draft = CalendarEventDraft.fromEvent(event);
    expect(draft.toJson()['start'], '2026-03-01T21:00:00-05:00');
    expect(draft.toJson()['end'], '2026-03-01T22:00:00-05:00');
    final restored = CalendarEvent.fromJson(event.toJson());
    expect(restored.startTime.hour, 21);
    expect(restored.startDay, event.startDay);
  });

  test(
    'all-day dates survive cache round trips and changes of church zone',
    () {
      final event = calendarEventFromGoogleItem({
        'id': 'all-day',
        'summary': '春季營會',
        'start': {'date': '2026-03-07'},
        'end': {'date': '2026-03-10'},
      })!;
      expect(event.startTime, DateTime.utc(2026, 3, 7));
      expect(event.endDay, DateTime.utc(2026, 3, 9));
      ChurchConfig.current = testChurchConfig(timeZone: 'Pacific/Auckland');
      final restored = CalendarEvent.fromJson(event.toJson());
      expect(restored.startDay, DateTime.utc(2026, 3, 7));
      expect(restored.endDay, DateTime.utc(2026, 3, 9));
      final activity = RecentActivity.fromJson({...event.toJson()});
      expect(activity.startDay, DateTime.utc(2026, 3, 7));
      expect(activity.endDay, DateTime.utc(2026, 3, 9));
    },
  );

  test(
    'spring clock changes keep elapsed duration and wall times distinct',
    () {
      final event = calendarEventFromGoogleItem({
        'id': 'spring',
        'summary': '聚會',
        'start': {'dateTime': '2026-03-08T01:30:00-05:00'},
        'end': {'dateTime': '2026-03-08T03:30:00-04:00'},
      })!;
      expect(
        event.endTime.difference(event.startTime),
        const Duration(hours: 1),
      );
      final draft = CalendarEventDraft.fromEvent(event);
      expect(draft.startTime, const TimeOfDay(hour: 1, minute: 30));
      expect(draft.endTime, const TimeOfDay(hour: 3, minute: 30));
      expect(draft.validate(), isNull);
      expect(
        draft
            .copyWith(startTime: const TimeOfDay(hour: 2, minute: 30))
            .validate(),
        contains('夏令時間'),
      );
    },
  );

  test('editing a repeated DST hour retains its existing occurrence', () {
    final event = calendarEventFromGoogleItem({
      'id': 'autumn',
      'summary': '秋季聚會',
      'start': {'dateTime': '2026-11-01T01:45:00-04:00'},
      'end': {'dateTime': '2026-11-01T01:15:00-05:00'},
    })!;
    final draft = CalendarEventDraft.fromEvent(event).copyWith(title: '改名');
    expect(draft.validate(), isNull);
    expect(draft.toJson()['start'], '2026-11-01T01:45:00-04:00');
    expect(draft.toJson()['end'], '2026-11-01T01:15:00-05:00');
    final moved = draft.copyWith(
      startDate: DateTime.utc(2026, 11, 2),
      endDate: DateTime.utc(2026, 11, 2),
      startTime: const TimeOfDay(hour: 0, minute: 30),
    );
    expect(moved.validate(), isNull);
    expect(moved.toJson()['start'], '2026-11-02T00:30:00-05:00');
  });

  test('all-day validation compares dates, not browser-local instants', () {
    final draft = CalendarEventDraft.forDay(
      DateTime.utc(2026, 3, 8),
    ).copyWith(title: '活動', allDay: true);
    // Material's date picker returns a device-local DateTime.
    final picked = DateTime(2026, 3, 8);
    expect(draft.copyWith(startDate: picked).validate(), isNull);
    expect(draft.copyWith(endDate: picked).validate(), isNull);
  });

  test('all-day events sort at church midnight before early timed events', () {
    ChurchConfig.current = testChurchConfig(timeZone: 'Asia/Taipei');
    final allDay = calendarEventFromGoogleItem({
      'id': 'all-day',
      'summary': '全日活動',
      'start': {'date': '2026-03-08'},
      'end': {'date': '2026-03-09'},
    })!;
    final early = calendarEventFromGoogleItem({
      'id': 'early',
      'summary': '清晨活動',
      'start': {'dateTime': '2026-03-08T06:00:00+08:00'},
      'end': {'dateTime': '2026-03-08T07:00:00+08:00'},
    })!;
    final layout = MonthEventLayout.compute(DateTime.utc(2026, 3), [
      early,
      allDay,
    ]);
    expect(
      layout.segmentsOn(DateTime.utc(2026, 3, 8)).first.event.id,
      'all-day',
    );
    final recent = selectRecentActivities(
      [
        RecentActivity.fromJson(early.toJson()),
        RecentActivity.fromJson(allDay.toJson()),
      ],
      now: DateTime.utc(2026, 3, 7),
      limit: 3,
    );
    expect(recent.first.title, '全日活動');
  });

  test('recent all-day events expire at church midnight, not UTC midnight', () {
    final activity = RecentActivity(
      startTime: DateTime.utc(2026, 3, 8),
      endTime: DateTime.utc(2026, 3, 9),
      isAllDay: true,
      title: '當日活動',
    );
    expect(
      activity.isCurrentOrUpcoming(DateTime.utc(2026, 3, 9, 3, 59)),
      isTrue,
    );
    expect(activity.isCurrentOrUpcoming(DateTime.utc(2026, 3, 9, 4)), isFalse);
    expect(
      ChurchTime.atDate(DateTime.utc(2026, 3, 9)).toUtc(),
      DateTime.utc(2026, 3, 9, 4),
    );
  });
}
