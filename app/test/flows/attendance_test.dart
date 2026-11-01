import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/design/components.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

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

Future<void> go(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await settle(tester);
}

void main() {
  testWidgets("a service's 負責人 fills in Sunday's 人數 from 首頁, and its page keeps it", (tester) async {
    final b = withAttendance(seededChurch(as: editor, clock: eveningOf(Day(2026, 10, 4))));
    await pumpApp(tester, b);
    await go(tester, '/home');
    expect(find.text('填寫人數'), findsOneWidget);
    // The card, above 我接下來的服事, which has 主日崇拜 too.
    await tester.tap(find.text('主日崇拜').first);
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, '人數'), '120');
    await tester.pump();
    await tapText(tester, '儲存');
    expect(b.attendance['grace']!['service:sunday']!.days[Day(2026, 10, 4)], const AttendanceDay.count(120));
    expect(find.text('填寫人數'), findsNothing, reason: 'filled in');

    await go(tester, '/me/groups/service/sunday');
    await tester.scrollUntilVisible(find.text('120 人'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('120 人'), findsOneWidget);
  });

  testWidgets('with 回報人數 off a 小組 is only a name: no meeting time, 人數 or 填寫人數', (tester) async {
    final b = withJoy(seededChurch(as: editor, clock: eveningOf(Day(2026, 10, 4))));
    await pumpApp(tester, b);
    await go(tester, '/home');
    expect(find.text('填寫人數'), findsNothing);
    await go(tester, '/me/groups/small/joy');
    expect(find.text('喜樂小組'), findsWidgets);
    expect(find.text('聚會時間'), findsNothing);
    expect(find.text('人數'), findsNothing);
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
    expect(find.textContaining('下次聚會'), findsWidgets, reason: 'the list, once on: from today, when each meets next');
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
    await scrollToShow(tester, find.text('補填其他日子'));
    expect(find.text('還沒設聚會時間'), findsWidgets);
  });

  testWidgets('a 小組 that has not met since 回報人數 came on says when it next meets, there too', (tester) async {
    final b = withJoy(seededChurch(clock: eveningOf(Day(2026, 10, 4))));
    b.churches['grace'] = b.churches['grace']!.copyWith(attendanceSince: () => Day(2026, 10, 4));
    await pumpApp(tester, b);
    await go(tester, '/me/attendance');
    final next = find.textContaining(RegExp(r'^下次聚會 10月9日'));
    expect(
      find.descendant(
        of: find.ancestor(of: find.text('喜樂小組'), matching: find.byType(ListRow)),
        matching: next,
      ),
      findsOneWidget,
    );
    await go(tester, '/me/groups/small/joy');
    await scrollToShow(tester, find.text('補填其他日子'));
    expect(next, findsOneWidget);
  });

  testWidgets('補填其他日子: a day it met off its 聚會時間, picked, then filled in', (tester) async {
    final b = withJoy(withAttendance(seededChurch(as: staffHao, clock: eveningOf(Day(2026, 10, 4)))));
    await pumpApp(tester, b);
    await go(tester, '/me/groups/small/joy');
    await scrollToShow(tester, find.text('補填其他日子'));
    await tapText(tester, '補填其他日子');
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
    await tester.scrollUntilVisible(find.text('新增小組'), 200, scrollable: find.byType(Scrollable).last);
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
    await go(tester, '/me/groups/service/sunday');
    await tester.scrollUntilVisible(find.text('未填'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('未填'), findsOneWidget);
  });

  testWidgets('its 小組長 marks 這次沒聚會; a week nobody filled in stays 未填, not 0', (tester) async {
    final b = withJoy(withAttendance(seededChurch(as: staffHao, clock: eveningOf(Day(2026, 10, 9)))));
    await pumpApp(tester, b);
    await go(tester, '/home');
    await tapText(tester, '喜樂小組');
    await tapText(tester, '這次沒聚會');
    expect(b.attendance['grace']!['small:joy']!.days[Day(2026, 10, 9)], const AttendanceDay.none());
    expect(find.text('填寫人數'), findsNothing);

    await go(tester, '/me/groups/small/joy');
    await tester.scrollUntilVisible(find.text('未填'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('沒聚會'), findsOneWidget, reason: '10/9');
    expect(find.text('未填'), findsOneWidget, reason: '10/2');
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

  testWidgets('paused, nothing is asked for and nothing left 未填', (tester) async {
    final b = withJoy(withAttendance(seededChurch(as: staffHao, clock: eveningOf(Day(2026, 10, 9)))));
    b.attendance['grace'] = {
      'small:joy': AttendanceRecord(
        pauses: [AttendancePause(from: Day(2026, 10, 1), until: Day(2026, 11, 1))],
      ),
    };
    await pumpApp(tester, b);
    await go(tester, '/home');
    expect(find.text('填寫人數'), findsNothing);
    await go(tester, '/me/groups/small/joy');
    await tester.scrollUntilVisible(find.textContaining('暫停'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('未填'), findsNothing);
    await tapText(tester, '恢復');
    expect(b.attendance['grace']!['small:joy']!.pauses, [
      AttendancePause(from: Day(2026, 10, 1), until: Day(2026, 10, 9)),
    ]);
    expect(find.text('未填'), findsOneWidget, reason: 'today, 10/9, asked for again; 10/2 stays paused');
  });

  testWidgets('its 小組長 pauses it until a day picked with one tap, in a sheet', (tester) async {
    final b = withJoy(withAttendance(seededChurch(as: staffHao, clock: eveningOf(Day(2026, 10, 9)))));
    await pumpApp(tester, b);
    await go(tester, '/me/groups/small/joy');
    await tester.scrollUntilVisible(find.text('暫停聚會一段時間'), 200, scrollable: find.byType(Scrollable).last);
    await tapText(tester, '暫停聚會一段時間');
    expect(find.byType(Dialog), findsNothing, reason: 'not the dialog that wants 確定 after the day');
    expect(find.text('哪一天恢復聚會？'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(CalendarDatePicker), matching: find.text('23')));
    await settle(tester);
    expect(find.byType(CalendarDatePicker), findsNothing);
    expect(b.attendance['grace']!['small:joy']!.pauses.last.until, Day(2026, 10, 23));
  });

  testWidgets('picking a year turns the month to it; only a day picks', (tester) async {
    final b = withJoy(withAttendance(seededChurch(as: staffHao, clock: eveningOf(Day(2026, 10, 9)))));
    await pumpApp(tester, b);
    await go(tester, '/me/groups/small/joy');
    await tester.scrollUntilVisible(find.text('暫停聚會一段時間'), 200, scrollable: find.byType(Scrollable).last);
    await tapText(tester, '暫停聚會一段時間');
    await tapText(tester, '2026年10月');
    await tapText(tester, '2027年');
    expect(find.byType(CalendarDatePicker), findsOneWidget, reason: 'still open');
    expect(b.attendance['grace']?['small:joy']?.pauses ?? const [], isEmpty);
    await tester.tap(find.descendant(of: find.byType(CalendarDatePicker), matching: find.text('5')));
    await settle(tester);
    expect(b.attendance['grace']!['small:joy']!.pauses.last.until, Day(2027, 10, 5));
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
    await go(tester, '/me/groups/service/sunday');
    await scrollToShow(tester, find.text('未填'));
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

    testWidgets("行政 sees each group's latest meeting, oldest first, and how many are 未填", (tester) async {
      final b = church();
      b.attendance['grace']!['service:youth'] = const AttendanceRecord(everyWeek: true);
      await pumpApp(tester, b);
      await go(tester, '/me');
      await tester.scrollUntilVisible(find.text('回報人數'), 200, scrollable: find.byType(Scrollable).last);
      await tapText(tester, '回報人數');
      expect(find.byType(Switch), findsNothing, reason: "turning it on or off is an admin's");
      expect(find.text('還有 2 個未填'), findsOneWidget);
      expect(inRow('主日崇拜', '120 人'), findsOneWidget, reason: "today's, 未填 yet, waits; 10/4's shows");
      expect(inRow('喜樂小組', '未填'), findsOneWidget);
      expect(inRow('青年崇拜', '未填'), findsOneWidget, reason: '每週都填人數, no roster');
      expect(find.text('平安小組'), findsNothing, reason: 'on a break');
      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      expect([y('主日崇拜'), y('喜樂小組'), y('青年崇拜')], orderedEquals([y('主日崇拜'), y('喜樂小組'), y('青年崇拜')]..sort()));
    });

    testWidgets('提醒 asks the 小組長, once a day', (tester) async {
      final b = church();
      await pumpApp(tester, b);
      await go(tester, '/me/attendance');
      await tester.tap(inRow('喜樂小組', '提醒'));
      await settle(tester);
      expect(find.text('已提醒'), findsOneWidget);
      expect(b.attendanceReminders['grace']!['small:joy']!.told, ['hao']);
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(inRow('喜樂小組', '提醒'));
      await settle(tester);
      expect(find.text('今天已經提醒過了'), findsOneWidget);
    });

    testWidgets('a row opens its page, where 行政 fills it in; then all are filled in', (tester) async {
      final b = church();
      await pumpApp(tester, b);
      await go(tester, '/me/attendance');
      await tapText(tester, '喜樂小組');
      await tester.scrollUntilVisible(find.text('未填').first, 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text('未填').first);
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, '人數'), '9');
      await tester.pump();
      await tapText(tester, '儲存');
      expect(b.attendance['grace']!['small:joy']!.days[Day(2026, 10, 9)], const AttendanceDay.count(9));
      await go(tester, '/me/attendance');
      expect(find.text('都填好了'), findsOneWidget);
    });

    testWidgets('聯合小組: its 小組長 fills in once, for 平安小組 too, and the page says so', (tester) async {
      final b = church(as: staffHao);
      b.attendance['grace']!.remove('small:peace');
      await pumpApp(tester, b);
      await go(tester, '/me/groups/small/joy');
      await tester.scrollUntilVisible(find.text('未填').first, 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text('未填').first);
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, '人數'), '30');
      await tester.pump();
      expect(find.text('和其他小組一起'), findsOneWidget);
      expect(b.warmedUp, contains(WarmUp.attendanceTogether), reason: 'filled in together through the backend');
      await tapText(tester, '平安小組');
      await tapText(tester, '儲存');
      final days = b.attendance['grace']!;
      expect(days['small:joy']!.days[Day(2026, 10, 9)], const AttendanceDay.count(30, together: ['small:peace']));
      expect(days['small:peace']!.days[Day(2026, 10, 9)], const AttendanceDay.joined('small:joy'));
      expect(find.text('和平安小組一起'), findsOneWidget);

      await go(tester, '/home');
      expect(find.text('填寫人數'), findsNothing);
    });

    testWidgets('聯合小組 never over a 小組 already filled in', (tester) async {
      final b = church(as: staffHao);
      b.attendance['grace']!['small:peace'] = AttendanceRecord(days: {Day(2026, 10, 9): const AttendanceDay.count(12)});
      await pumpApp(tester, b);
      await go(tester, '/me/groups/small/joy');
      await tester.scrollUntilVisible(find.text('未填').first, 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text('未填').first);
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, '人數'), '30');
      await tester.pump();
      await tapText(tester, '平安小組');
      await tapText(tester, '儲存');
      expect(find.text('選的小組那天已經填了人數'), findsOneWidget);
      expect(b.attendance['grace']!['small:peace']!.days[Day(2026, 10, 9)], const AttendanceDay.count(12));
    });

    testWidgets('每週都填人數: a service with no roster asks for its 人數 every week', (tester) async {
      final b = church(as: pastor);
      await pumpApp(tester, b);
      await go(tester, '/me/groups/service/youth');
      await scrollToShow(tester, find.text('每週都填人數'));
      expect(find.text('未填'), findsNothing);
      await tapText(tester, '每週都填人數');
      expect(b.attendance['grace']!['service:youth']!.everyWeek, isTrue);
      await tester.scrollUntilVisible(find.text('未填').first, 200, scrollable: find.byType(Scrollable).last);
      expect(find.text('未填'), findsWidgets);
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
}
