import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

  testWidgets('an admin turns 回報人數 on in 設定, from today', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me');
    await tester.scrollUntilVisible(find.text('回報人數'), 200, scrollable: find.byType(Scrollable).last);
    await tapText(tester, '回報人數');
    expect(b.churches['grace']!.attendanceSince, testToday);
  });

  testWidgets("a service's 負責人 opens a 小組 and names its 小組長", (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/me/groups/service/sunday');
    await tester.scrollUntilVisible(find.text('新增小組'), 200, scrollable: find.byType(Scrollable).last);
    await tapText(tester, '新增小組');
    await tester.enterText(find.byType(TextField), '喜樂小組');
    await tapText(tester, '儲存');
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

  testWidgets("行政 sees every service's 人數 from 設定, and fills in none", (tester) async {
    final b = withAttendance(seededChurch(as: office, extra: [office], clock: eveningOf(Day(2026, 10, 4))));
    b.attendance['grace'] = {
      'service:sunday': AttendanceRecord(days: {Day(2026, 10, 4): const AttendanceDay.count(120)}),
    };
    await pumpApp(tester, b);
    await go(tester, '/me');
    await tester.scrollUntilVisible(find.text('主日崇拜'), 200, scrollable: find.byType(Scrollable).last);
    await tapText(tester, '主日崇拜');
    await tester.scrollUntilVisible(find.text('120 人'), 200, scrollable: find.byType(Scrollable).last);
    await tapText(tester, '120 人');
    expect(find.text('這次沒聚會'), findsNothing, reason: 'nothing to fill in');
  });
}
