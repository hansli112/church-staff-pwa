import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:church_staff_pwa/features/dashboard/domain/entities/recent_activity.dart';
import 'package:church_staff_pwa/features/dashboard/presentation/widgets/recent_activity_row.dart';

/// 日期欄是單行 + ellipsis：字太長不會報 overflow，只會被默默截掉，
/// 所以要主動量。
///
/// 但**不能**拿量到的數字去跟欄寬比對絕對值：widget test 跑的是測試字型
/// （每個字元都是 1em 的方塊），數字與括號被高估將近一倍。實測
/// 「08/12 (三) 19:30」在測試字型下是 180px，真實字型大約只有 96px。
/// 拿測試字型的絕對值當門檻，測到的是字型而不是版面。
///
/// 站得住腳的是**相對比較**：兩個字串在同一個字型下量，比出來的大小關係
/// 在真實字型下同樣成立。所以這裡守的是「新格式不會比改動前最寬的格式更寬」
/// —— 只要這條成立，這次改動就不可能造成原本沒有的跑版。
double _intrinsicWidth(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  return painter.width;
}

/// 首頁那張卡片外面有 body 的 16 padding，卡片內還有 16 —— 兩側各 32。
const double _horizontalChrome = 32 * 2;

RecentActivity _allDay(String start, String endExclusive) => RecentActivity(
  startTime: DateTime.parse('$start 00:00'),
  endTime: DateTime.parse('$endExclusive 00:00'),
  isAllDay: true,
  title: '夏令會',
);

RecentActivity _timed(String start, String end) => RecentActivity(
  startTime: DateTime.parse(start),
  endTime: DateTime.parse(end),
  isAllDay: false,
  title: '禱告會',
);

/// 改動前就存在、而且最長的格式：有時間的單日活動。當作寬度基準線。
final _widestExistingFormat = _timed('2026-08-12 19:30', '2026-08-12 21:00');

/// 跨月的區間是新格式裡最長的：08/30–09/02。
final _widestRangeFormat = _allDay('2026-08-30', '2026-09-03');

void main() {
  setUpAll(() async => initializeDateFormatting('zh_TW', null));

  group('跑版防線', () {
    test('跨日區間不比改動前最寬的格式更寬', () {
      final range = _intrinsicWidth(
        formatRecentActivityDate(_widestRangeFormat),
        RecentActivityRow.dateStyle,
      );
      final baseline = _intrinsicWidth(
        formatRecentActivityDate(_widestExistingFormat),
        RecentActivityRow.dateStyle,
      );

      expect(
        range,
        lessThanOrEqualTo(baseline),
        reason:
            '「${formatRecentActivityDate(_widestRangeFormat)}」($range) 比 '
            '「${formatRecentActivityDate(_widestExistingFormat)}」($baseline) 還寬，'
            '欄寬沒變，等於這次改動自己造成截斷',
      );
    });

    test('跨日格式刻意不帶星期，帶了就會超過基準線', () {
      // 記錄為什麼格式長這樣：加上 (三) 之類的星期會讓區間變成最寬的格式，
      // 上面那條防線就會失守。有人想加回星期時會先撞到這裡。
      final withWeekday = _intrinsicWidth(
        '08/30 (日)–09/02 (三)',
        RecentActivityRow.dateStyle,
      );
      final baseline = _intrinsicWidth(
        formatRecentActivityDate(_widestExistingFormat),
        RecentActivityRow.dateStyle,
      );
      expect(withWeekday, greaterThan(baseline));
    });

    testWidgets('標題起始位置不受日期格式影響', (tester) async {
      // 固定 flex 的用意就是這個：不同日期格式不能讓標題左右跳動。
      tester.view.physicalSize = const Size(390 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final xs = <double>[];
      for (final activity in [
        _allDay('2026-08-12', '2026-08-13'),
        _widestRangeFormat,
        _widestExistingFormat,
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 390 - _horizontalChrome,
                  child: RecentActivityRow(activity: activity),
                ),
              ),
            ),
          ),
        );
        xs.add(tester.getTopLeft(find.text(activity.title)).dx);
      }

      expect(xs.toSet(), hasLength(1), reason: '標題的 x 起點必須一致，實際: $xs');
    });

    testWidgets('窄螢幕上不會 overflow（該截的是文字，不是版面）', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320 - _horizontalChrome,
                child: RecentActivityRow(activity: _widestRangeFormat),
              ),
            ),
          ),
        ),
      );

      // RenderFlex overflow 會以例外的形式被 flutter_test 收集起來。
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('跨日活動顯示的是區間而不是只有開始那天', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RecentActivityRow(activity: _widestRangeFormat)),
      ),
    );
    expect(find.text('08/30–09/02'), findsOneWidget);
  });
}
