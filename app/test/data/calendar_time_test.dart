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

  test('後端照教會時區送來的時間，就是教會的時刻（#73）', () {
    final event = calendarEventFromJson({
      'title': '主日',
      'start': '2026-10-31T23:30:00-07:00',
      'end': '2026-11-01T01:00:00-08:00',
      'allDay': false,
    })!;
    expect(event.start, DateTime.utc(2026, 10, 31, 23, 30));
    expect(event.end, DateTime.utc(2026, 11, 1, 1));
    expect((event.day, event.lastDay), (Day(2026, 10, 31), Day(2026, 11, 1)));
  });

  test('寫回時送教會的時刻、不帶時差，由後端照教會時區換算', () {
    final event = calendarEventFromJson({
      'title': '晨禱',
      'start': '2026-10-01T00:30:00+08:00',
      'end': '2026-10-01T01:30:00+08:00',
      'allDay': false,
    })!;
    final encoded = calendarEventToJson(event);
    expect(encoded['start'], '2026-10-01T00:30:00');
    expect(encoded['end'], '2026-10-01T01:30:00');
  });

  test('新建與讀取的活動使用同一種教會時刻，不混入裝置時區', () {
    final event = CalendarEvent(
      title: '晨禱',
      start: DateTime(2026, 10, 1, 0, 30),
      end: DateTime(2026, 10, 1, 1, 30),
    );
    expect(event.start, DateTime.utc(2026, 10, 1, 0, 30));
    expect(event.end, DateTime.utc(2026, 10, 1, 1, 30));
    expect(calendarEventToJson(event)['start'], '2026-10-01T00:30:00');
  });

  test('沒有教會時差的活動時間不猜', () {
    for (final start in ['2026-10-01T00:30:00', '2026-09-30T16:30:00.000Z']) {
      expect(
        calendarEventFromJson({'title': '缺時區', 'start': start, 'end': '2026-10-01T01:30:00+08:00', 'allDay': false}),
        isNull,
        reason: start,
      );
    }
  });
}
