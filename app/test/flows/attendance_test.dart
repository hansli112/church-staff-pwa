import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:martha/core/design/components.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/export.dart';
import 'package:martha/state/session.dart';

import '../support/harness.dart';
import '../support/seed.dart';
import '../support/telemetry.dart';

// 回報人數 and 小組 (#85). 主日崇拜 meets on Sundays; 10/4 has a roster.

/// 21:30 at the church on [day].
DateTime Function() eveningOf(Day day) =>
    () => ChurchTimeZone.taipei.instantOf(DateTime.utc(day.year, day.month, day.day, 21, 30));

/// [b] with 回報人數 on since 10/1.
MemoryBackend withAttendance(MemoryBackend b) {
  b.churches['grace'] = b.churches['grace']!.copyWith(attendanceSince: () => Day(2026, 10, 1));
  return b;
}

/// 喜樂小組 of 主日崇拜, meeting on Fridays from 10/2, led by 陳志豪.
const joy = SmallGroupDetails(id: 'joy', name: '喜樂小組', service: 'sunday', weekday: DateTime.friday);

MemoryBackend withJoy(MemoryBackend b, {SmallGroupDetails group = joy}) {
  b.smallGroups['grace'] = {group.id: group};
  b.members['grace']!['hao'] = staffHao.withIdentities(const [SmallGroupLead('joy')]);
  return b;
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

/// [text] in the row titled [title].
Finder inRow(String title, String text) => find.descendant(
  of: find.ancestor(of: find.text(title), matching: find.byType(ListRow)),
  matching: find.text(text),
);

/// Scrolls the page until [finder] shows, and on past the tab bar that
/// covers the bottom: a service's page is long (#94).
Future<void> scrollToShow(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).last);
  await tester.drag(find.byType(Scrollable).last, const Offset(0, -200));
  await settle(tester);
}

class _Saver implements FileSaver {
  final files = <(String, Uint8List, String)>[];

  @override
  Future<bool> save(String name, Uint8List bytes, String mimeType) async {
    files.add((name, bytes, mimeType));
    return true;
  }
}

Future<void> go(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await settle(tester);
}

void main() {
  testWidgets("a service's 負責人 fills in Sunday's 人數 from 首頁, and its page keeps it", (tester) async {
    final b = withAttendance(seededChurch(as: editor, clock: eveningOf(Day(2026, 10, 4))));
    final telemetry = RecordingTelemetry();
    await pumpApp(tester, b, overrides: [telemetryProvider.overrideWithValue(telemetry)]);
    await go(tester, '/home');
    expect(find.text('填寫人數'), findsOneWidget);
    // The card, above 我接下來的服事, which has 主日崇拜 too.
    await tester.tap(find.text('主日崇拜').first);
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, '人數'), '120');
    await tester.pump();
    await tapText(tester, '儲存');
    expect(b.attendance['grace']!['service:sunday']!.days[Day(2026, 10, 4)], const AttendanceDay.count(120));
    expect(telemetry.named('attendance_report'), [null]);
    expect(find.text('填寫人數'), findsNothing, reason: 'filled in');

    await go(tester, '/me/groups/service/sunday');
    await scrollToShow(tester, inRow('聚會人數', '120 人'));
    expect(inRow('聚會人數', '120 人'), findsOneWidget, reason: 'its page says the latest in one row (#95)');
    await tester.tap(inRow('聚會人數', '120 人'));
    await settle(tester);
    expect(find.text('主日崇拜的聚會人數'), findsOneWidget);
    expect(find.text('120 人'), findsOneWidget);
    expect(find.text('新增一次聚會'), findsOneWidget);
  });

  testWidgets(
    'a service on several weekdays asks for 人數 on each with a roster; its 聚會時間 is by its rosters or every week',
    (
      tester,
    ) async {
      final b = withAttendance(seededChurch(as: editor, clock: eveningOf(Day(2026, 10, 11))));
      b.setServices('grace', [
        sundayService.copyWith(weekdays: [DateTime.wednesday, DateTime.sunday]),
        youthService,
      ]);
      b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, 7))] = Roster(type: 'sunday', day: Day(2026, 10, 7));
      await pumpApp(tester, b);
      await go(tester, '/home');
      expect(find.textContaining('10月11日'), findsWidgets, reason: "Sunday's");
      expect(find.textContaining('10月7日'), findsWidgets, reason: "Wednesday's, which has a roster too");

      await go(tester, '/me/groups/service/sunday/attendance');
      expect(inRow('聚會時間', '有服事表的週三、週日'), findsOneWidget);
      await tapText(tester, '聚會時間');
      expect(find.text('隔週'), findsNothing, reason: 'every other week or month is for one day');
      expect(find.text('每月'), findsNothing);
      await tapText(tester, '每週');
      await tapText(tester, '儲存');
      expect(b.attendance['grace']!['service:sunday']!.time, MeetingTime(startsOn: Day(2026, 10, 11)));
      expect(inRow('聚會時間', '每週三、週日'), findsOneWidget);
    },
  );

  testWidgets('首頁連結 (每日靈糧) stays at the top of 首頁, above 填寫人數', (tester) async {
    final b = withAttendance(seededChurch(as: editor, clock: eveningOf(Day(2026, 10, 4))))
      ..churchLinks['grace'] = const ChurchLink(title: '每日靈糧', url: 'https://grace.example/daily');
    await pumpApp(tester, b);
    await go(tester, '/home');
    expect(tester.getTopLeft(find.text('每日靈糧')).dy, lessThan(tester.getTopLeft(find.text('填寫人數')).dy));
  });

  testWidgets('with 回報人數 off a 小組 is only a name: no meeting time, 人數 or 填寫人數', (tester) async {
    final b = withJoy(seededChurch(as: editor, clock: eveningOf(Day(2026, 10, 4))));
    await pumpApp(tester, b);
    await go(tester, '/home');
    expect(find.text('填寫人數'), findsNothing);
    await go(tester, '/me/groups/small/joy');
    expect(find.text('喜樂小組'), findsWidgets);
    expect(find.text('聚會時間'), findsNothing);
    expect(find.text('聚會人數'), findsNothing);
  });

  testWidgets('an admin turns 回報人數 on on its page from 設定, from today, and its list shows there', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me');
    await tester.scrollUntilVisible(find.text('回報人數'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('未開啟'), findsOneWidget);
    await tapText(tester, '回報人數');
    expect(find.text('還沒有要填的聚會'), findsNothing, reason: 'nothing to list while off');
    await tester.tap(find.byType(Switch));
    await settle(tester);
    expect(b.churches['grace']!.attendanceSince, testToday);
    expect(find.text('還沒有要填的聚會'), findsOneWidget, reason: "once on, this week's list: 主日 10/4 is next week's");
  });

  testWidgets('a new 小組 says its 聚會時間 is not set, on its page and on 回報人數', (
    tester,
  ) async {
    final b = withJoy(
      withAttendance(seededChurch(clock: eveningOf(Day(2026, 10, 4)))),
      group: const SmallGroupDetails(id: 'joy', name: '喜樂小組', service: 'sunday'),
    );
    await pumpApp(tester, b);
    await go(tester, '/me/attendance');
    expect(inRow('喜樂小組', '還沒設聚會時間'), findsOneWidget, reason: 'a new 小組 is found here too');
    expect(inRow('喜樂小組', '提醒'), findsNothing);
    await tapText(tester, '喜樂小組');
    expect(find.text('喜樂小組的聚會人數'), findsOneWidget, reason: 'nothing to fill in: its 人數 page');
    expect(inRow('聚會時間', '未設定'), findsOneWidget, reason: 'set from here');
  });

  testWidgets('a 小組 that has not met since 回報人數 came on says which day, there by when it meets', (tester) async {
    // Monday: it meets on Friday, this week.
    final b = withJoy(seededChurch(clock: eveningOf(Day(2026, 10, 5))));
    b.churches['grace'] = b.churches['grace']!.copyWith(attendanceSince: () => Day(2026, 10, 5));
    await pumpApp(tester, b);
    await go(tester, '/me/attendance');
    expect(
      find.descendant(
        of: find.ancestor(of: find.text('喜樂小組'), matching: find.byType(ListRow)),
        matching: find.text('10月9日 週五'),
      ),
      findsOneWidget,
      reason: 'the day, as the meetings already met say theirs',
    );
    await go(tester, '/me/groups/small/joy');
    final next = find.text('每週五');
    expect(inRow('聚會時間', '每週五'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('聚會人數'), 200, scrollable: find.byType(Scrollable).last);
    expect(next, findsOneWidget, reason: 'said once, by 聚會時間');
  });

  testWidgets('新增一次聚會: a day it met off its 聚會時間, picked, then filled in', (tester) async {
    final b = withJoy(withAttendance(seededChurch(as: staffHao, clock: eveningOf(Day(2026, 10, 4)))));
    await pumpApp(tester, b);
    await go(tester, '/me/groups/small/joy/attendance');
    await tapText(tester, '新增一次聚會');
    await tester.tap(find.descendant(of: find.byType(CalendarDatePicker), matching: find.text('3')));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, '人數'), '12');
    await tester.pump();
    await tapText(tester, '儲存');
    expect(b.attendance['grace']!['small:joy']!.days[Day(2026, 10, 3)]?.count, 12);
  });

  testWidgets("a service's 負責人 opens a 小組 and names its 小組長", (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/me/groups/service/sunday');
    await tapText(tester, '小組');
    await tapText(tester, '新增小組');
    await tester.enterText(find.byType(TextField), '喜樂小組');
    b.smallGroupSaveHeld = Completer();
    await tapText(tester, '儲存');
    expect(find.text('喜樂小組'), findsOneWidget, reason: 'listed at once, though the server has not answered');
    expect(find.byType(CircularProgressIndicator), findsWidgets, reason: 'saving');
    b.smallGroupSaveHeld!.complete();
    await settle(tester);
    final made = b.smallGroups['grace']!.values.single;
    expect((made.name, made.service), ('喜樂小組', 'sunday'));
    expect(find.text('喜樂小組'), findsWidgets, reason: 'its page opened');

    await tapText(tester, '未指派');
    await tapText(tester, '陳志豪');
    expect(b.members['grace']!['hao']!.leadSmallGroups, [made.id]);
    expect(b.members['grace']!['hao']!.identities, [SmallGroupLead(made.id)]);
  });

  testWidgets('刪除小組 goes back at once, the 小組 off the list while the backend deletes it, and back if it cannot', (
    tester,
  ) async {
    final b = withJoy(seededChurch(as: editor));
    await pumpApp(tester, b);
    await go(tester, '/me/groups/service/sunday/small-groups');
    Future<void> delete() async {
      await tapText(tester, '喜樂小組');
      await tester.scrollUntilVisible(find.text('刪除小組'), 300);
      await tapText(tester, '刪除小組');
      await tester.tap(find.text('刪除小組').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    b.smallGroupSaveHeld = Completer();
    await delete();
    expect(find.text('喜樂小組'), findsNothing, reason: 'off the list at once, though the server has not answered');
    b.smallGroupSaveHeld!.completeError(const CloudException(CloudErrorCode.unavailable));
    await settle(tester);
    expect(find.text('喜樂小組'), findsOneWidget, reason: 'back, as the server has it');

    b.smallGroupSaveHeld = null;
    await delete();
    await settle(tester);
    expect(b.smallGroups['grace']!.containsKey('joy'), isFalse);
    expect(find.text('已刪除「喜樂小組」'), findsOneWidget);
  });

  testWidgets('a 小組 has one 小組長: another picked takes the place, and 取消指派 leaves none', (tester) async {
    final b = withJoy(seededChurch(as: editor));
    await pumpApp(tester, b);
    await go(tester, '/me/groups/small/joy');
    expect(find.text('指派小組長'), findsNothing, reason: 'one row, 小組長, not a list to add to');
    await tapText(tester, '陳志豪');
    await tapText(tester, '李美玉');
    expect(b.members['grace']!['hao']!.leadSmallGroups, isEmpty);
    expect(b.members['grace']!['mei']!.leadSmallGroups, ['joy']);

    await tapText(tester, '李美玉');
    await tapText(tester, '取消指派');
    expect(b.members['grace']!['mei']!.leadSmallGroups, isEmpty);
    expect(find.text('未指派'), findsOneWidget);
  });

  testWidgets("a service's 牧者 sees its 人數 but is not reminded: no 填寫人數 on 首頁, no 回報人數提醒", (tester) async {
    final b = withAttendance(seededChurch(as: editor, clock: eveningOf(Day(2026, 10, 4))));
    b.members['grace']![editor.uid] = editor.withIdentities(const [
      PastorIdentity(['sunday']),
    ]);
    await pumpApp(tester, b);
    await go(tester, '/home');
    expect(find.text('填寫人數'), findsNothing);
    await go(tester, '/me/notifications');
    expect(find.text('回報人數提醒'), findsNothing);
    await go(tester, '/me/groups/service/sunday/attendance');
    expect(find.text('未填'), findsOneWidget);
  });

  testWidgets('its 小組長 marks 這次沒聚會; a week nobody filled in stays 未填, not 0', (tester) async {
    final b = withJoy(withAttendance(seededChurch(as: staffHao, clock: eveningOf(Day(2026, 10, 9)))));
    await pumpApp(tester, b);
    await go(tester, '/home');
    await tester.tap(find.text('喜樂小組').first);
    await settle(tester);
    await tapText(tester, '這次沒聚會');
    expect(b.attendance['grace']!['small:joy']!.days[Day(2026, 10, 9)], const AttendanceDay.none());
    expect(find.text('喜樂小組'), findsOneWidget, reason: '10/2 still asks for its 人數');

    await go(tester, '/me/groups/small/joy/attendance');
    expect(find.text('沒聚會'), findsOneWidget, reason: '10/9');
    expect(find.text('未填'), findsOneWidget, reason: '10/2');
    expect(titleColor(tester, '沒聚會'), isNot(titleColor(tester, '未填')), reason: 'greyed: it did not meet');
    // 補填.
    await tapText(tester, '未填');
    await tester.enterText(find.widgetWithText(TextField, '人數'), '8');
    await tester.pump();
    await tapText(tester, '儲存');
    expect(b.attendance['grace']!['small:joy']!.days[Day(2026, 10, 2)], const AttendanceDay.count(8));
  });

  testWidgets('its 小組長 sets when it meets: every other Friday', (tester) async {
    final b = withJoy(
      withAttendance(seededChurch(as: staffHao)),
      group: const SmallGroupDetails(id: 'joy', name: '喜樂小組', service: 'sunday'),
    );
    await pumpApp(tester, b);
    await go(tester, '/me/groups/small/joy');
    expect(find.text('未設定'), findsOneWidget);
    await tapText(tester, '聚會時間');
    await tapText(tester, '隔週');
    await tapText(tester, '週五');
    await tapText(tester, '儲存');
    final g = b.smallGroups['grace']!['joy']!;
    expect((g.weekday, g.every, g.startsOn), (DateTime.friday, 2, Day(2026, 10, 2)));
    expect(find.text('隔週五'), findsOneWidget);
  });

  testWidgets("an older app's pause still asks for nothing and leaves nothing 未填; 回報人數 shows off", (tester) async {
    final b = withJoy(withAttendance(seededChurch(as: staffHao, clock: eveningOf(Day(2026, 10, 9)))));
    b.attendance['grace'] = {
      'small:joy': AttendanceRecord(
        pauses: [AttendancePause(from: Day(2026, 10, 1), until: Day(2026, 11, 1))],
      ),
    };
    await pumpApp(tester, b);
    await go(tester, '/home');
    expect(find.text('填寫人數'), findsNothing);
    await go(tester, '/me/groups/small/joy/attendance');
    expect(find.text('未填'), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('its 小組長 turns its 回報人數 off for a break, and on: the weeks between stay asked for nothing', (
    tester,
  ) async {
    final b = withJoy(withAttendance(seededChurch(as: staffHao, clock: eveningOf(Day(2026, 10, 16)))));
    b.attendance['grace'] = {
      'small:joy': AttendanceRecord(
        pauses: [
          // Long over, before any page looks: dropped, so the list never fills.
          AttendancePause(from: Day(2026, 1, 2), until: Day(2026, 2, 6)),
          AttendancePause.off(Day(2026, 10, 9)),
        ],
      ),
    };
    await pumpApp(tester, b);
    await go(tester, '/home');
    expect(find.text('填寫人數'), findsNothing, reason: 'off: 10/9 and today ask for nothing');
    await go(tester, '/me/groups/small/joy/attendance');
    expect(inRow('10月2日 週五', '未填'), findsOneWidget, reason: 'before it went off');
    expect(find.textContaining('10月9日'), findsNothing);
    await tester.tap(find.byType(Switch));
    await settle(tester);
    expect(b.attendance['grace']!['small:joy']!.pauses, [
      AttendancePause(from: Day(2026, 10, 9), until: Day(2026, 10, 16)),
    ]);
    expect(find.textContaining('10月9日'), findsNothing, reason: 'the week it was off');
    expect(find.text('未填'), findsNWidgets(2), reason: 'today, and 10/2');

    await tester.tap(find.byType(Switch));
    await settle(tester);
    expect(b.attendance['grace']!['small:joy']!.pauses.last, AttendancePause.off(Day(2026, 10, 16)));
  });

  testWidgets('picking a year turns the month to it; only a day picks', (tester) async {
    final b = withJoy(withAttendance(seededChurch(as: staffHao, clock: eveningOf(Day(2026, 10, 9)))));
    await pumpApp(tester, b);
    await go(tester, '/me/groups/small/joy/attendance');
    await tapText(tester, '新增一次聚會');
    await tapText(tester, '2026年10月');
    await tapText(tester, '2025年');
    expect(find.byType(CalendarDatePicker), findsOneWidget, reason: 'still open');
    await tester.tap(find.descendant(of: find.byType(CalendarDatePicker), matching: find.text('20')));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, '人數'), '7');
    await tester.pump();
    await tapText(tester, '儲存');
    expect(b.attendance['grace']!['small:joy']!.days[Day(2025, 10, 20)], const AttendanceDay.count(7));
  });

  testWidgets('a meeting filled in stays listed when the 小組 moves to another day', (tester) async {
    final b = withJoy(
      withAttendance(seededChurch(as: staffHao, clock: eveningOf(Day(2026, 10, 9)))),
      group: joy.copyWith(startsOn: () => Day(2026, 10, 2)),
    );
    b.attendance['grace'] = {
      'small:joy': AttendanceRecord(days: {Day(2026, 10, 2): const AttendanceDay.count(8)}),
    };
    await pumpApp(tester, b);
    await go(tester, '/me/groups/small/joy');
    await tapText(tester, '聚會時間');
    await tapText(tester, '週三');
    await tapText(tester, '儲存');
    expect(b.smallGroups['grace']!['joy']!.weekday, DateTime.wednesday);
    await tester.scrollUntilVisible(find.text('8 人'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('8 人'), findsOneWidget);
  });

  testWidgets("行政 fills in a service's 人數 from its page", (tester) async {
    final b = withAttendance(seededChurch(as: office, extra: [office], clock: eveningOf(Day(2026, 10, 4))));
    await pumpApp(tester, b);
    await go(tester, '/me/groups/service/sunday/attendance');
    await tapText(tester, '未填');
    await tester.enterText(find.widgetWithText(TextField, '人數'), '120');
    await tester.pump();
    await tapText(tester, '儲存');
    expect(b.attendance['grace']!['service:sunday']!.days[Day(2026, 10, 4)], const AttendanceDay.count(120));
  });

  group('人數總覽 (#93)', () {
    /// 平安小組 of 主日崇拜, on Fridays too, led by 李美玉.
    const peace = SmallGroupDetails(id: 'peace', name: '平安小組', service: 'sunday', weekday: DateTime.friday);

    /// Sunday 10/11 at 21:30: 主日崇拜 met 10/4 (120 人) and today (未填); 喜樂小組
    /// met Friday 10/9 (未填); 平安小組 is on a break; 青年崇拜 never has a roster.
    MemoryBackend church({Member as = office}) {
      final b = withJoy(withAttendance(seededChurch(as: as, extra: [office], clock: eveningOf(Day(2026, 10, 11)))));
      b.smallGroups['grace']!['peace'] = peace;
      b.attendance['grace'] = {
        'service:sunday': AttendanceRecord(days: {Day(2026, 10, 4): const AttendanceDay.count(120)}),
        'small:peace': AttendanceRecord(
          pauses: [AttendancePause(from: Day(2026, 10, 1), until: Day(2026, 11, 1))],
        ),
      };
      return b;
    }

    testWidgets('行政 opens on the latest week anyone filled in, Sunday to Saturday, and turns through them', (
      tester,
    ) async {
      final b = church();
      b.attendance['grace']!['service:youth'] = const AttendanceRecord(time: MeetingTime());
      await pumpApp(tester, b);
      await go(tester, '/me');
      await tester.scrollUntilVisible(find.text('回報人數'), 200, scrollable: find.byType(Scrollable).last);
      await tapText(tester, '回報人數');
      expect(find.byType(Switch), findsNothing, reason: "turning it on or off is an admin's");
      expect(find.text('10月4日 – 10月10日'), findsOneWidget, reason: "nothing is filled in this week yet: today's");
      expect(findShown('還有 2 個未填'), findsOneWidget, reason: 'no totals: people come to more than one');
      expect(find.textContaining('120 人 ·'), findsNothing);
      expect(inRow('主日崇拜', '120 人'), findsOneWidget);
      expect(inRow('喜樂小組', '未填'), findsOneWidget, reason: '10/9');
      expect(inRow('青年崇拜', '未填'), findsOneWidget, reason: '每週都填人數, no roster; Saturday 10/10');
      expect(find.text('平安小組'), findsNothing, reason: 'on a break');
      double at(Finder f) => tester.getTopLeft(f).dy;
      final ys = [at(inRow('主日崇拜', '120 人')), at(inRow('喜樂小組', '未填')), at(inRow('青年崇拜', '未填'))];
      expect(ys, orderedEquals([...ys]..sort()), reason: 'a service, then its 小組, whatever the day; then the next');
      IconButton arrow(IconData icon) => tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

      await tester.tap(find.byTooltip('上一週'));
      await settle(tester);
      expect(find.text('9月27日 – 10月3日'), findsOneWidget);
      expect(inRow('喜樂小組', '未填'), findsOneWidget, reason: '10/2');
      expect(arrow(Symbols.chevron_left_rounded).onPressed, isNull, reason: '回報人數 came on that week');

      await tester.tap(find.byTooltip('下一週'));
      await settle(tester);
      await tester.tap(find.byTooltip('下一週'));
      await settle(tester);
      expect(find.text('10月11日 – 10月17日'), findsOneWidget);
      expect(inRow('主日崇拜', '未填'), findsOneWidget, reason: 'today, still to fill in');
      expect(find.text('提醒'), findsNothing, reason: "today's reminder is still to come");
      expect(find.textContaining('個未填'), findsNothing, reason: "today's not counted, as on 首頁");
      expect(at(inRow('主日崇拜', '未填')), lessThan(at(find.text('喜樂小組'))), reason: 'the same order every week');
      expect(arrow(Symbols.chevron_right_rounded).onPressed, isNull, reason: 'this week is the last');
    });

    testWidgets("a service's 小組 by their 聚會時間, whatever their order", (tester) async {
      final b = church();
      b.smallGroups['grace']!['peace'] = peace.copyWith(weekday: () => DateTime.wednesday, order: () => 2);
      b.smallGroups['grace']!['joy'] = joy.copyWith(order: () => 1);
      b.smallGroups['grace']!['hope'] = const SmallGroupDetails(id: 'hope', name: '盼望小組', service: 'sunday', order: 0);
      b.attendance['grace']!.remove('small:peace');
      await pumpApp(tester, b);
      await go(tester, '/me/attendance');
      await tester.tap(find.byTooltip('下一週'));
      await settle(tester);
      double at(Finder f) => tester.getTopLeft(f).dy;
      final ys = [at(find.text('平安小組')), at(find.text('喜樂小組')), at(inRow('盼望小組', '還沒設聚會時間'))];
      expect(ys, orderedEquals([...ys]..sort()), reason: 'Wednesday, Friday, then one with no 聚會時間');
    });

    testWidgets('a week all filled in says so, a 聯合小組 says with whom, and 沒聚會 is greyed', (tester) async {
      final b = church();
      b.attendance['grace'] = {
        'service:sunday': AttendanceRecord(days: {Day(2026, 10, 4): const AttendanceDay.count(120)}),
        'service:youth': AttendanceRecord(
          time: const MeetingTime(),
          days: {Day(2026, 10, 10): const AttendanceDay.none()},
        ),
        'small:joy': AttendanceRecord(
          days: {
            Day(2026, 10, 9): const AttendanceDay.count(30, together: ['small:peace']),
          },
        ),
        'small:peace': AttendanceRecord(days: {Day(2026, 10, 9): const AttendanceDay.joined('small:joy')}),
      };
      await pumpApp(tester, b);
      await go(tester, '/me/attendance');
      expect(find.text('10月11日 – 10月17日'), findsOneWidget, reason: "all filled in: today's week");
      await tester.tap(find.byTooltip('上一週'));
      await settle(tester);
      expect(findShown('都填好了'), findsOneWidget);
      expect(inRow('平安小組', '和喜樂小組一起'), findsOneWidget);
      expect(inRow('青年崇拜', '沒聚會'), findsOneWidget);
      expect(titleColor(tester, '沒聚會'), isNot(titleColor(tester, '120 人')), reason: 'greyed');
    });

    testWidgets('a break marked ahead opens no week; this week lists only who still meets in it', (tester) async {
      final b = church();
      b.attendance['grace']!['service:sunday'] = AttendanceRecord(
        days: {Day(2026, 10, 4): const AttendanceDay.count(120), Day(2026, 10, 11): const AttendanceDay.none()},
      );
      // Every other Wednesday from 10/21: not this week.
      b.smallGroups['grace']!['hope'] = SmallGroupDetails(
        id: 'hope',
        name: '盼望小組',
        service: 'sunday',
        weekday: DateTime.wednesday,
        every: 2,
        startsOn: Day(2026, 10, 21),
      );
      await pumpApp(tester, b);
      await go(tester, '/me/attendance');
      expect(find.text('10月4日 – 10月10日'), findsOneWidget, reason: "this week's only 沒聚會 is no one filling in");
      await tester.tap(find.byTooltip('下一週'));
      await settle(tester);
      expect(inRow('主日崇拜', '沒聚會'), findsOneWidget);
      expect(find.text('盼望小組'), findsNothing, reason: 'it meets next week');
    });

    testWidgets('one 提醒 beside 還有 N 個未填 asks for them all, once a day', (tester) async {
      final b = church();
      b.attendance['grace']!['service:youth'] = const AttendanceRecord(time: MeetingTime(), fillers: ['mei']);
      // Nobody fills it in yet.
      b.gatherings['grace'] = {
        'meal': Gathering(
          id: 'meal',
          name: '長者共餐',
          time: MeetingTime(weekday: DateTime.wednesday, startsOn: Day(2026, 10, 7)),
        ),
      };
      await pumpApp(tester, b);
      await go(tester, '/me/attendance');
      expect(find.text('提醒'), findsOneWidget, reason: 'not one a row');
      double right(Finder f) => tester.getTopRight(f).dx;
      expect(right(inRow('喜樂小組', '未填')), right(inRow('主日崇拜', '120 人')), reason: '未填 lines up with the counts');
      await tapText(tester, '提醒');
      expect(findShown('已提醒。長者共餐沒有可以提醒的人，請直接聯絡。'), findsOneWidget);
      expect(b.attendanceReminders['grace']!['small:joy']!.told, ['hao']);
      expect(b.attendanceReminders['grace']!['service:youth']!.told, ['mei']);
      await tester.pump(const Duration(seconds: 5));
      await tapText(tester, '提醒');
      expect(find.text('今天已經提醒過了'), findsOneWidget);
    });

    testWidgets('提醒 shows it is asking, and cannot be asked twice meanwhile', (tester) async {
      final b = church();
      await pumpApp(tester, b);
      await go(tester, '/me/attendance');
      b.writeHeld = Completer();
      await tapText(tester, '提醒');
      // One where 提醒 was, one beside 儲存中….
      expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
      expect(find.text('儲存中…'), findsOneWidget);
      expect(find.text('提醒'), findsNothing, reason: 'not to be tapped again while it asks');
      b.writeHeld!.complete();
      b.writeHeld = null;
      await settle(tester);
      expect(find.text('今天已經提醒過了'), findsNothing);
      expect(findShownContaining('已提醒'), findsOneWidget);
      expect(find.text('提醒'), findsOneWidget);
    });

    testWidgets('匯出 shares 聚會人數.csv: every meeting listed, from 回報人數 came on, past the weeks it turns', (
      tester,
    ) async {
      final b = church();
      b.attendance['grace']!['small:joy'] = AttendanceRecord(
        days: {
          // Filled in before it came on again, and as 聯合小組.
          Day(2026, 9, 25): const AttendanceDay.count(8, note: '有新朋友, 2 位'),
          Day(2026, 10, 9): const AttendanceDay.joined('small:peace'),
        },
      );
      final saver = _Saver();
      await pumpApp(tester, b, overrides: [fileSaverProvider.overrideWithValue(saver)]);
      await go(tester, '/me/attendance');
      await tapText(tester, '匯出');
      final (name, bytes, mime) = saver.files.single;
      expect(name, '聚會人數.csv');
      expect(mime, 'text/csv');
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF], reason: 'a BOM, so Excel reads Chinese');
      expect(
        utf8.decode(bytes),
        '日期,聚會,人數,備註\r\n'
        '2026-09-25,喜樂小組,8,"有新朋友, 2 位"\r\n'
        '2026-10-02,喜樂小組,未填,\r\n'
        '2026-10-04,主日崇拜,120,\r\n'
        '2026-10-09,喜樂小組,和平安小組一起,\r\n'
        '2026-10-11,主日崇拜,未填,\r\n',
      );
    });

    testWidgets('匯出 lists 未填 only as far back as the weeks it turns; before, what was filled in', (tester) async {
      final b = church();
      b.churches['grace'] = b.churches['grace']!.copyWith(attendanceSince: () => Day(2026, 5, 1));
      b.attendance['grace']!['small:joy'] = AttendanceRecord(days: {Day(2026, 5, 8): const AttendanceDay.count(7)});
      final saver = _Saver();
      await pumpApp(tester, b, overrides: [fileSaverProvider.overrideWithValue(saver)]);
      await go(tester, '/me/attendance');
      await tapText(tester, '匯出');
      final rows = utf8.decode(saver.files.single.$2).split('\r\n');
      expect(rows[1], '2026-05-08,喜樂小組,7,');
      expect(rows[2], '2026-07-24,喜樂小組,未填,', reason: '12 weeks before 10/11 on');
    });

    testWidgets("a service's 負責人 exports its own and its 小組' only", (tester) async {
      final b = church(as: editor);
      b.attendance['grace']!['service:youth'] = AttendanceRecord(
        time: const MeetingTime(),
        days: {Day(2026, 10, 3): const AttendanceDay.count(30)},
      );
      final saver = _Saver();
      await pumpApp(tester, b, overrides: [fileSaverProvider.overrideWithValue(saver)]);
      await go(tester, '/me/attendance');
      await tapText(tester, '匯出');
      final csv = utf8.decode(saver.files.single.$2);
      expect(csv, contains('主日崇拜'));
      expect(csv, contains('喜樂小組'));
      expect(csv, isNot(contains('青年崇拜')));
    });

    testWidgets("a row opens that meeting's 填寫人數, with no row to the group's 人數 page", (tester) async {
      final b = church();
      await pumpApp(tester, b);
      await go(tester, '/me/attendance');
      await tapText(tester, '喜樂小組');
      await tester.enterText(find.widgetWithText(TextField, '人數'), '9');
      await tester.pump();
      await tapText(tester, '儲存');
      expect(b.attendance['grace']!['small:joy']!.days[Day(2026, 10, 9)], const AttendanceDay.count(9));
      expect(findShown('都填好了'), findsOneWidget, reason: 'the week stays, though it would open on the next now');

      await tapText(tester, '喜樂小組');
      expect(find.text('喜樂小組的聚會人數'), findsNothing, reason: 'filling in, nothing to look up');
    });

    testWidgets("a service's 負責人 finds its 人數 and its 小組' under 我負責的, and reminds them (#95)", (tester) async {
      final b = church(as: editor);
      b.attendance['grace']!['service:youth'] = const AttendanceRecord(time: MeetingTime());
      await pumpApp(tester, b);
      await go(tester, '/me');
      await tester.scrollUntilVisible(find.text('回報人數'), 200, scrollable: find.byType(Scrollable).last);
      await tapText(tester, '回報人數');
      expect(find.byType(Switch), findsNothing);
      expect(find.text('新增其他聚會'), findsNothing, reason: 'admins and 行政 set those');
      expect(find.text('編輯'), findsNothing);
      expect(find.text('主日崇拜'), findsWidgets);
      expect(find.text('青年崇拜'), findsNothing, reason: 'not theirs');
      await tapText(tester, '提醒');
      expect(b.attendanceReminders['grace']!['small:joy']!.told, ['hao']);
    });

    testWidgets('聯合小組: its 小組長 fills in once, for 平安小組 too, and the page says so', (tester) async {
      final b = church(as: staffHao);
      b.attendance['grace']!.remove('small:peace');
      await pumpApp(tester, b);
      await go(tester, '/me/groups/small/joy/attendance');
      await tester.tap(find.text('未填').first);
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, '人數'), '30');
      await tester.pump();
      expect(find.text('和其他小組一起'), findsOneWidget);
      double y(Finder f) => tester.getTopLeft(f).dy;
      final count = find.widgetWithText(TextField, '人數');
      expect(y(find.text('這次沒聚會')), lessThan(y(count)), reason: 'up by the date, above the keyboard');
      expect(y(find.text('平安小組')), lessThan(y(find.widgetWithText(TextField, '備註'))), reason: 'the note last');
      expect(b.warmedUp, contains(WarmUp.attendanceTogether), reason: 'filled in together through the backend');
      await tapText(tester, '平安小組');
      await tapText(tester, '儲存');
      final days = b.attendance['grace']!;
      expect(days['small:joy']!.days[Day(2026, 10, 9)], const AttendanceDay.count(30, together: ['small:peace']));
      expect(days['small:peace']!.days[Day(2026, 10, 9)], const AttendanceDay.joined('small:joy'));
      expect(find.text('和平安小組一起'), findsOneWidget);

      await go(tester, '/home');
      expect(find.textContaining('10月9日'), findsNothing);
    });

    testWidgets('聯合小組 never over a 小組 already filled in', (tester) async {
      final b = church(as: staffHao);
      b.attendance['grace']!['small:peace'] = AttendanceRecord(days: {Day(2026, 10, 9): const AttendanceDay.count(12)});
      await pumpApp(tester, b);
      await go(tester, '/me/groups/small/joy/attendance');
      await tester.tap(find.text('未填').first);
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, '人數'), '30');
      await tester.pump();
      await tapText(tester, '平安小組');
      await tapText(tester, '儲存');
      expect(find.text('選的小組那天已經填了人數'), findsOneWidget);
      expect(b.attendance['grace']!['small:peace']!.days[Day(2026, 10, 9)], const AttendanceDay.count(12));
    });

    testWidgets('聚會時間: a service with no roster asks for its 人數 every week from then on', (tester) async {
      final b = church(as: pastor);
      await pumpApp(tester, b);
      await go(tester, '/me/groups/service/youth/attendance');
      expect(inRow('聚會時間', '有服事表的週六'), findsOneWidget);
      await tapText(tester, '聚會時間');
      await tapText(tester, '每週');
      await tapText(tester, '儲存');
      expect(b.attendance['grace']!['service:youth']!.time, MeetingTime(startsOn: Day(2026, 10, 17)));
      expect(inRow('聚會時間', '每週六'), findsOneWidget);
      expect(find.text('未填'), findsNothing, reason: 'the weeks before, without a roster, ask for nothing');
    });

    testWidgets("a reminder's link opens that meeting's 填寫人數", (tester) async {
      final b = church(as: staffHao);
      await pumpApp(tester, b);
      await go(tester, '/home?fill=small:joy&day=2026-10-09');
      await tester.enterText(find.widgetWithText(TextField, '人數'), '11');
      await tester.pump();
      await tapText(tester, '儲存');
      expect(b.attendance['grace']!['small:joy']!.days[Day(2026, 10, 9)], const AttendanceDay.count(11));
    });
  });

  group('負責回報、聚會時間、其他聚會', () {
    testWidgets("a service's 負責人 asks its 招待 to fill in its 人數 too", (tester) async {
      final b = withAttendance(seededChurch(as: editor, clock: eveningOf(Day(2026, 10, 4))));
      await pumpApp(tester, b);
      await go(tester, '/me/groups/service/sunday/attendance');
      expect(inRow('負責回報', '林同工'), findsOneWidget, reason: 'its 負責人');
      await tapText(tester, '負責回報');
      await tapText(tester, '李美玉');
      await tapText(tester, '完成');
      expect(b.attendance['grace']!['service:sunday']!.fillers, ['mei']);
      expect(inRow('負責回報', '林同工、李美玉'), findsOneWidget);
    });

    testWidgets('負責回報 lists who is asked first, then the service\'s 同工; anyone else by searching', (tester) async {
      final others = [for (var i = 1; i <= 6; i++) Member(uid: 'p$i', name: '路人$i')];
      final b = withAttendance(seededChurch(as: editor, extra: others, clock: eveningOf(Day(2026, 10, 4))));
      b.attendance['grace'] = {
        'service:sunday': const AttendanceRecord(fillers: ['hao']),
      };
      await pumpApp(tester, b);
      await go(tester, '/me/groups/service/sunday/attendance');
      await tapText(tester, '負責回報');
      double at(String text) => tester.getTopLeft(find.text(text).last).dy;
      expect(at('林同工'), lessThan(at('陳志豪')), reason: 'its 負責人, fixed in');
      expect(at('陳志豪'), lessThan(at('主日崇拜的同工')), reason: 'asked already: first');
      expect(at('主日崇拜的同工'), lessThan(at('李美玉')));
      expect(find.text('路人1'), findsNothing, reason: 'not one of its 同工');
      expect(find.text('王牧師'), findsNothing);

      await tester.enterText(find.byType(TextField), '路人1');
      await settle(tester);
      await tapText(tester, '路人1');
      await tester.enterText(find.byType(TextField), '');
      await settle(tester);
      expect(at('路人1'), lessThan(at('主日崇拜的同工')), reason: 'ticked from a search: with who is asked');
      await tapText(tester, '李美玉');
      expect(at('李美玉'), greaterThan(at('主日崇拜的同工')), reason: 'ticked where it is, not moved');
      await tapText(tester, '完成');
      expect(b.attendance['grace']!['service:sunday']!.fillers, ['hao', 'p1', 'mei']);
    });

    testWidgets("小組 are dragged in order on their service's page", (tester) async {
      final b = withJoy(withAttendance(seededChurch(clock: eveningOf(Day(2026, 10, 11)))));
      b.smallGroups['grace']!['peace'] = const SmallGroupDetails(id: 'peace', name: '平安小組', service: 'sunday');
      await pumpApp(tester, b);
      await go(tester, '/me/groups/service/sunday/small-groups');
      double at(String text) => tester.getTopLeft(find.text(text).first).dy;
      expect(at('平安小組'), greaterThan(at('喜樂小組')), reason: 'by name, never placed');
      await dragRow(tester, '平安小組', -1);
      expect(b.smallGroups['grace']!['peace']!.order, 0);
      expect(b.smallGroups['grace']!['joy']!.order, 1);
      expect(at('平安小組'), lessThan(at('喜樂小組')));
    });

    testWidgets("其他聚會 are dragged in order on the page their section's 編輯 opens, and listed so", (tester) async {
      final b = withAttendance(seededChurch(clock: eveningOf(Day(2026, 10, 11))));
      b.gatherings['grace'] = {
        'kids': const Gathering(id: 'kids', name: '兒童學習天地'),
        'meal': const Gathering(id: 'meal', name: '長者共餐'),
      };
      await pumpApp(tester, b);
      await go(tester, '/me/attendance');
      expect(find.text('兒童學習天地'), findsNothing, reason: 'neither meets this week');
      await tester.scrollUntilVisible(find.text('新增其他聚會'), 200, scrollable: find.byType(Scrollable).last);
      expect(find.text('其他聚會'), findsOneWidget, reason: 'their section still, to add one: no row below it');
      await tapText(tester, '編輯');
      expect(find.text('兒童學習天地'), findsOneWidget, reason: 'all of them');
      double at(String text) => tester.getTopLeft(find.text(text).last).dy;
      expect(at('兒童學習天地'), lessThan(at('長者共餐')));
      await dragRow(tester, '長者共餐', -1);
      expect([b.gatherings['grace']!['meal']!.order, b.gatherings['grace']!['kids']!.order], [0, 1]);
      expect(at('長者共餐'), lessThan(at('兒童學習天地')));
    });

    testWidgets('who cannot open 小組 sees them in order, with nothing to drag', (tester) async {
      final b = withJoy(withAttendance(seededChurch(as: office, extra: [office], clock: eveningOf(Day(2026, 10, 11)))));
      b.smallGroups['grace']!['peace'] = const SmallGroupDetails(
        id: 'peace',
        name: '平安小組',
        service: 'sunday',
        order: 0,
      );
      b.smallGroups['grace']!['joy'] = joy.copyWith(order: () => 1);
      await pumpApp(tester, b);
      await go(tester, '/me/groups/service/sunday/small-groups');
      expect(tester.getTopLeft(find.text('平安小組')).dy, lessThan(tester.getTopLeft(find.text('喜樂小組')).dy));
      expect(find.byIcon(Symbols.drag_handle_rounded), findsNothing);
    });

    testWidgets("a service's own 聚會時間 keeps the meetings it had by its rosters before", (tester) async {
      final b = withAttendance(seededChurch(as: editor, clock: eveningOf(Day(2026, 10, 11))));
      await pumpApp(tester, b);
      await go(tester, '/me/groups/service/sunday/attendance');
      await tapText(tester, '聚會時間');
      await tapText(tester, '每週');
      await tapText(tester, '儲存');
      expect(b.attendance['grace']!['service:sunday']!.time, MeetingTime(startsOn: Day(2026, 10, 11)));
      expect(find.textContaining('10月4日'), findsOneWidget, reason: 'it had a roster: still asks for its 人數');
      await tapText(tester, '聚會時間');
      await tapText(tester, '每月');
      await tapText(tester, '第 2 個週日');
      await tapText(tester, '儲存');
      expect(
        b.attendance['grace']!['service:sunday']!.time?.startsOn,
        Day(2026, 10, 11),
        reason: '10/11 is the second',
      );
    });

    testWidgets('who is asked fills them in from 首頁, and sets nothing else', (tester) async {
      final b = withAttendance(seededChurch(as: staffMei, clock: eveningOf(Day(2026, 10, 4))));
      b.attendance['grace'] = {
        'service:sunday': const AttendanceRecord(fillers: ['mei']),
      };
      await pumpApp(tester, b);
      await go(tester, '/home');
      expect(find.text('填寫人數'), findsOneWidget);
      await tester.tap(find.text('主日崇拜').first);
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, '人數'), '86');
      await tester.pump();
      await tapText(tester, '儲存');
      expect(b.attendance['grace']!['service:sunday']!.days[Day(2026, 10, 4)], const AttendanceDay.count(86));
      await go(tester, '/me/groups/service/sunday/attendance');
      expect(find.text('86 人'), findsOneWidget);
      ListRow row(String title) =>
          tester.widget<ListRow>(find.ancestor(of: find.text(title), matching: find.byType(ListRow)));
      expect(row('負責回報').onTap, isNull, reason: 'seen, not set');
      expect(row('聚會時間').onTap, isNull);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('首頁 lists each meeting of the last two weeks still without its 人數, until filled in', (tester) async {
      final b = withAttendance(seededChurch(as: editor, clock: eveningOf(Day(2026, 10, 11))));
      b.attendance['grace'] = {'service:sunday': const AttendanceRecord(time: MeetingTime())};
      await pumpApp(tester, b);
      await go(tester, '/home');
      expect(find.textContaining('10月11日'), findsWidgets);
      expect(find.textContaining('10月4日'), findsWidgets, reason: 'last week, still not filled in');
      await tester.tap(find.textContaining('10月4日').first);
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, '人數'), '100');
      await tester.pump();
      await tapText(tester, '儲存');
      expect(find.textContaining('10月4日'), findsNothing);
      expect(find.text('填寫人數'), findsOneWidget, reason: "today's is still to fill in");
    });

    testWidgets("with only today's still to fill in, a week is neither 未填 nor 都填好了", (tester) async {
      final b = withAttendance(seededChurch(as: office, extra: [office], clock: eveningOf(Day(2026, 10, 11))));
      b.attendance['grace'] = {
        'service:sunday': AttendanceRecord(days: {Day(2026, 10, 4): const AttendanceDay.count(120)}),
      };
      await pumpApp(tester, b);
      await go(tester, '/me/attendance');
      expect(find.text('10月11日 – 10月17日'), findsOneWidget, reason: "the week before all filled in: today's week");
      expect(inRow('主日崇拜', '未填'), findsOneWidget);
      expect(find.textContaining('個未填'), findsNothing);
      expect(find.textContaining('都填好了'), findsNothing);
    });

    testWidgets("with the week before all filled in, 首頁 says today's is still to fill in, and opens its week", (
      tester,
    ) async {
      final b = withAttendance(seededChurch(as: office, extra: [office], clock: eveningOf(Day(2026, 10, 11))));
      b.attendance['grace'] = {
        'service:sunday': AttendanceRecord(days: {Day(2026, 10, 4): const AttendanceDay.count(120)}),
      };
      await pumpApp(tester, b);
      await go(tester, '/home');
      expect(inRow('回報人數', '今天的還沒填'), findsOneWidget);
      await tapText(tester, '回報人數');
      expect(find.text('10月11日 – 10月17日'), findsOneWidget);
    });

    testWidgets('admins and 行政 see on 首頁 how many are still 未填, and open 回報人數 from it', (tester) async {
      final b = withJoy(withAttendance(seededChurch(as: office, extra: [office], clock: eveningOf(Day(2026, 10, 11)))));
      b.attendance['grace'] = {
        'service:sunday': AttendanceRecord(days: {Day(2026, 10, 4): const AttendanceDay.count(120)}),
      };
      await pumpApp(tester, b);
      await go(tester, '/home');
      expect(inRow('回報人數', '還有 1 個未填'), findsOneWidget, reason: '喜樂小組 on 10/9: the week the page opens on');
      await tapText(tester, '回報人數');
      expect(find.text('10月4日 – 10月10日'), findsOneWidget, reason: 'the latest week anyone filled in');
      expect(findShown('還有 1 個未填'), findsOneWidget, reason: 'as 首頁 said');
    });

    testWidgets('a 小組長 sets its 聚會時間 from its 人數 page: 每月第 1、3 個週五', (tester) async {
      final b = withJoy(
        withAttendance(seededChurch(as: staffHao, clock: eveningOf(Day(2026, 10, 11)))),
        group: const SmallGroupDetails(id: 'joy', name: '喜樂小組', service: 'sunday'),
      );
      await pumpApp(tester, b);
      await go(tester, '/me/groups/small/joy/attendance');
      expect(inRow('聚會時間', '未設定'), findsOneWidget);
      await tapText(tester, '聚會時間');
      await tapText(tester, '每月');
      await tapText(tester, '週五');
      await tester.ensureVisible(find.text('第 3 個週五'));
      await tapText(tester, '第 1 個週五');
      await tapText(tester, '第 3 個週五');
      await tapText(tester, '儲存');
      final joy = b.smallGroups['grace']!['joy']!;
      expect((joy.weekday, joy.startsOn), (DateTime.friday, Day(2026, 10, 16)));
      expect(joy.monthWeeks, [1, 3]);
      expect(inRow('聚會時間', '每月第 1、3 個週五'), findsOneWidget);
    });

    testWidgets('an admin adds a 其他聚會, sets when it meets and who fills it in', (tester) async {
      final b = withAttendance(seededChurch(clock: eveningOf(Day(2026, 10, 11))));
      await pumpApp(tester, b);
      await go(tester, '/me/attendance');
      await tester.scrollUntilVisible(find.text('新增其他聚會'), 200, scrollable: find.byType(Scrollable).last);
      await tapText(tester, '新增其他聚會');
      await tester.enterText(find.byType(TextField), '長者共餐');
      await tapText(tester, '新增');
      expect(find.text('長者共餐的聚會人數'), findsOneWidget);
      await tapText(tester, '聚會時間');
      await tapText(tester, '週三');
      await tapText(tester, '儲存');
      await tapText(tester, '負責回報');
      await tapText(tester, '李美玉');
      await tapText(tester, '完成');
      final g = b.gatherings['grace']!.values.single;
      expect((g.name, g.time.weekday), ('長者共餐', DateTime.wednesday));
      expect(b.attendance['grace']!['gathering:${g.id}']!.fillers, ['mei']);
      expect(inRow('負責回報', '李美玉'), findsOneWidget);
    });

    testWidgets('a 其他聚會 has its own section on 回報人數; 行政 reminds who fills it in', (tester) async {
      final b = withAttendance(seededChurch(as: office, extra: [office], clock: eveningOf(Day(2026, 10, 11))));
      b.gatherings['grace'] = {
        'meal': Gathering(
          id: 'meal',
          name: '長者共餐',
          time: MeetingTime(weekday: DateTime.wednesday, startsOn: Day(2026, 10, 7)),
        ),
      };
      b.attendance['grace'] = {
        'service:sunday': AttendanceRecord(days: {Day(2026, 10, 4): const AttendanceDay.count(120)}),
        'gathering:meal': const AttendanceRecord(fillers: ['mei']),
      };
      await pumpApp(tester, b);
      await go(tester, '/me/attendance');
      await scrollToShow(tester, inRow('長者共餐', '未填'));
      expect(inRow('長者共餐', '未填'), findsOneWidget, reason: 'its own section, after the services');
      expect(find.text('長者共餐'), findsOneWidget, reason: 'once: its settings are a page away');
      expect(find.text('其他聚會'), findsOneWidget, reason: 'the section, with nothing below');
      expect(find.text('新增其他聚會'), findsOneWidget, reason: '行政 adds them too');
      await tester.scrollUntilVisible(find.text('提醒'), -200, scrollable: find.byType(Scrollable).last);
      await tapText(tester, '提醒');
      expect(b.attendanceReminders['grace']!['gathering:meal']!.told, ['mei']);
    });
  });

  testWidgets('回報人數 turned on is on at once, and off again if it cannot be', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me');
    await tester.scrollUntilVisible(find.text('回報人數'), 200, scrollable: find.byType(Scrollable).last);
    await tapText(tester, '回報人數');
    b.writeHeld = Completer();
    await tester.tap(find.byType(Switch));
    await settle(tester);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue, reason: 'on at once');
    expect(find.text('儲存中…'), findsOneWidget);

    b.writeHeld!.completeError(const CloudException(CloudErrorCode.unavailable));
    await settle(tester);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(b.churches['grace']!.attendanceSince, isNull);
  });

  testWidgets('刪除其他聚會 goes back at once, off the list while the backend deletes it', (tester) async {
    final b = withAttendance(seededChurch());
    b.gatherings['grace'] = {'meal': const Gathering(id: 'meal', name: '長者共餐')};
    await pumpApp(tester, b);
    await go(tester, '/me/attendance/gathering/meal');
    b.writeHeld = Completer();
    await tester.scrollUntilVisible(find.text('刪除其他聚會'), 200, scrollable: find.byType(Scrollable).last);
    await tapText(tester, '刪除其他聚會');
    expect(find.text('刪除其他聚會'), findsNothing, reason: 'back at once');
    expect(find.text('長者共餐'), findsNothing, reason: 'off the list, though the server has not answered');

    b.writeHeld!.complete();
    await settle(tester);
    expect(b.gatherings['grace'], isEmpty);
    expect(find.text('已刪除「長者共餐」'), findsOneWidget);
  });
}

/// The title's color in the row that shows [value].
Color? titleColor(WidgetTester tester, String value) {
  final row = find.ancestor(of: find.text(value), matching: find.byType(ListRow));
  return tester.widget<Text>(find.descendant(of: row, matching: find.byType(Text)).first).style?.color;
}
