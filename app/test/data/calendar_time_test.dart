import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/firebase/codec.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';

void main() {
  test('海外裝置讀月底活動仍使用教會日期及時間', () {
    final event = calendarEventFromJson({
      'id': 'midnight',
      'title': '晨禱',
      'start': '2026-10-01T00:30:00+08:00',
      'end': '2026-10-01T01:30:00+08:00',
      'allDay': false,
    })!;
    expect(event.day, Day(2026, 10, 1));
    expect(event.start.hour, 0);
    expect(event.start.minute, 30);
    expect(event.months, ['2026-10']);
  });

  test('教會時刻寫回 Google 的瞬間不會重複加減裝置時差', () {
    final event = calendarEventFromJson({
      'title': '晨禱',
      'start': '2026-10-01T00:30:00+08:00',
      'end': '2026-10-01T01:30:00+08:00',
      'allDay': false,
    })!;
    final encoded = calendarEventToJson(event);
    expect(encoded['start'], '2026-09-30T16:30:00.000Z');
    expect(encoded['end'], '2026-09-30T17:30:00.000Z');
  });

  test('新建與讀取的活動使用同一種教會時刻，不混入裝置時區', () {
    final event = CalendarEvent(
      title: '晨禱',
      start: DateTime(2026, 10, 1, 0, 30),
      end: DateTime(2026, 10, 1, 1, 30),
    );
    expect(event.start, DateTime.utc(2026, 10, 1, 0, 30));
    expect(event.end, DateTime.utc(2026, 10, 1, 1, 30));
    expect(calendarEventToJson(event)['start'], '2026-09-30T16:30:00.000Z');
  });

  test('沒有明確時區的活動時間不猜成裝置時間', () {
    expect(
      calendarEventFromJson({
        'title': '缺時區',
        'start': '2026-10-01T00:30:00',
        'end': '2026-10-01T01:30:00',
        'allDay': false,
      }),
      isNull,
    );
  });
}
