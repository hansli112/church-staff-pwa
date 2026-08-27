import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:church_staff_pwa/features/dashboard/domain/entities/recent_activity.dart';

RecentActivity _timed(String start, String end, {String title = '活動'}) =>
    RecentActivity(
      startTime: DateTime.parse(start),
      endTime: DateTime.parse(end),
      isAllDay: false,
      title: title,
    );

/// 全日活動照 Google 的慣例：end.date 是**隔天**（不含當天）。
RecentActivity _allDay(
  String startDate,
  String endDateExclusive, {
  String title = '活動',
}) => RecentActivity(
  startTime: DateTime.parse('$startDate 00:00'),
  endTime: DateTime.parse('$endDateExclusive 00:00'),
  isAllDay: true,
  title: title,
);

void main() {
  setUpAll(() async => initializeDateFormatting('zh_TW', null));

  group('跨日活動的天數判讀', () {
    test('全日活動：end.date 是排他的，不能多算一天', () {
      // 8/12 到 8/14 的三天特會，Google 給的 end.date 是 8/15
      final retreat = _allDay('2026-08-12', '2026-08-15');
      expect(retreat.startDay, DateTime(2026, 8, 12));
      expect(retreat.endDay, DateTime(2026, 8, 14));
      expect(retreat.spansMultipleDays, isTrue);
    });

    test('單日全日活動不算跨日', () {
      final single = _allDay('2026-08-12', '2026-08-13');
      expect(single.endDay, DateTime(2026, 8, 12));
      expect(single.spansMultipleDays, isFalse);
    });

    test('有時間的活動跨過午夜才算跨日', () {
      expect(
        _timed('2026-08-12 19:00', '2026-08-12 21:00').spansMultipleDays,
        isFalse,
      );
      expect(
        _timed('2026-08-12 22:00', '2026-08-13 02:00').spansMultipleDays,
        isTrue,
      );
    });

    test('結束正好落在午夜不算跨到隔天', () {
      final event = _timed('2026-08-12 19:00', '2026-08-13 00:00');
      expect(event.endDay, DateTime(2026, 8, 12));
      expect(event.spansMultipleDays, isFalse);
    });

    test('資料壞掉（end 早於 start）時退化成單日，不會炸也不會算出負區間', () {
      final broken = _timed('2026-08-12 19:00', '2026-08-10 09:00');
      expect(broken.endDay, DateTime(2026, 8, 12));
      expect(broken.spansMultipleDays, isFalse);
    });
  });

  group('篩選：進行中的活動必須留下', () {
    // 這組是這次修改的核心。舊版以「開始時間」篩選，8/13 當天會把 8/12 開始
    // 的特會整個丟掉 —— 明明正在進行中。
    test('跨日全日活動在中間那天仍然要顯示', () {
      final retreat = _allDay('2026-08-12', '2026-08-15', title: '夏令會');
      final result = selectRecentActivities(
        [retreat],
        now: DateTime(2026, 8, 13, 10),
        limit: 3,
      );
      expect(result.map((e) => e.title), ['夏令會']);
      expect(retreat.isOngoing(DateTime(2026, 8, 13, 10)), isTrue);
    });

    test('跨日活動在最後一天仍然要顯示', () {
      final result = selectRecentActivities(
        [_allDay('2026-08-12', '2026-08-15', title: '夏令會')],
        now: DateTime(2026, 8, 14, 23, 59),
        limit: 3,
      );
      expect(result, hasLength(1));
    });

    test('跨日活動結束後就不再顯示', () {
      final result = selectRecentActivities(
        [_allDay('2026-08-12', '2026-08-15', title: '夏令會')],
        now: DateTime(2026, 8, 15, 0, 1),
        limit: 3,
      );
      expect(result, isEmpty);
    });

    test('進行中的有時間活動要留下，已結束的不留', () {
      final ongoing = _timed('2026-08-13 09:00', '2026-08-13 17:00');
      final finished = _timed('2026-08-13 06:00', '2026-08-13 08:00');
      final result = selectRecentActivities(
        [ongoing, finished],
        now: DateTime(2026, 8, 13, 10),
        limit: 3,
      );
      expect(result, hasLength(1));
      expect(result.single.startTime, ongoing.startTime);
    });

    test('今天的全日活動整天都算數，不會下午就消失', () {
      final result = selectRecentActivities(
        [_allDay('2026-08-13', '2026-08-14')],
        now: DateTime(2026, 8, 13, 15, 30),
        limit: 3,
      );
      expect(result, hasLength(1));
    });

    test('進行中的排在還沒開始的前面', () {
      final ongoing = _allDay('2026-08-12', '2026-08-15', title: '夏令會');
      final later = _allDay('2026-08-20', '2026-08-21', title: '兒童主日');
      final result = selectRecentActivities(
        [later, ongoing],
        now: DateTime(2026, 8, 13),
        limit: 3,
      );
      expect(result.map((e) => e.title), ['夏令會', '兒童主日']);
    });

    test('超過上限只取前幾筆', () {
      final result = selectRecentActivities(
        [
          for (var day = 14; day < 20; day++)
            _allDay('2026-08-$day', '2026-08-${day + 1}', title: 'day$day'),
        ],
        now: DateTime(2026, 8, 13),
        limit: 3,
      );
      expect(result.map((e) => e.title), ['day14', 'day15', 'day16']);
    });
  });

  group('日期文字', () {
    test('單日全日活動帶星期', () {
      expect(
        formatRecentActivityDate(_allDay('2026-08-12', '2026-08-13')),
        '08/12 (三)',
      );
    });

    test('單日有時間活動帶星期與時間', () {
      expect(
        formatRecentActivityDate(
          _timed('2026-08-12 19:30', '2026-08-12 21:00'),
        ),
        '08/12 (三) 19:30',
      );
    });

    test('跨日活動顯示區間', () {
      expect(
        formatRecentActivityDate(_allDay('2026-08-12', '2026-08-15')),
        '08/12–08/14',
      );
    });

    test('跨月的區間也正確', () {
      expect(
        formatRecentActivityDate(_allDay('2026-08-30', '2026-09-03')),
        '08/30–09/02',
      );
    });
  });

  group('JSON 往返', () {
    test('存進快取再讀出來，區間不會走樣', () {
      final original = _allDay('2026-08-12', '2026-08-15', title: '夏令會');
      final restored = RecentActivity.fromJson(original.toJson());
      expect(restored.startDay, original.startDay);
      expect(restored.endDay, original.endDay);
      expect(restored.isAllDay, isTrue);
      expect(restored.title, '夏令會');
    });

    test('舊版快取沒有 endTime 時退化成單日而不是崩潰', () {
      final restored = RecentActivity.fromJson({
        'startTime': '2026-08-12T09:00:00.000',
        'isAllDay': false,
        'title': '舊資料',
      });
      expect(restored.spansMultipleDays, isFalse);
    });
  });
}
