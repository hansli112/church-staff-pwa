import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

const calendarEditor = Member(uid: 'cal', name: '行事曆同工', groups: {Group.calendarEditors});

void main() {
  testWidgets('not connected: staff see one sentence, the admin gets a way to connect', (tester) async {
    await pumpApp(tester, seededChurch(as: staffMei));
    await go(tester, '/calendar');
    expect(find.text('教會還沒有連接行事曆'), findsOneWidget);
    expect(find.text('連接 Google 日曆'), findsNothing);
  });

  testWidgets('the admin is warned about the unverified screen before connecting', (tester) async {
    await pumpApp(tester, seededChurch());
    await go(tester, '/calendar');
    await tapText(tester, '連接 Google 日曆');
    expect(find.textContaining('這個應用程式未經驗證'), findsOneWidget);
  });

  testWidgets('after connecting, the admin picks a calendar and everyone sees events', (tester) async {
    final b = seededChurch();
    b.connectCalendar('grace');
    b.calendarEvents['grace'] = [
      CalendarEvent(id: 'e1', title: '同工會', start: DateTime(2026, 10, 10, 19, 30), end: DateTime(2026, 10, 10, 21)),
    ];
    await pumpApp(tester, b);
    await go(tester, '/me/calendar');
    await tapText(tester, '教會行事曆');
    expect(b.calendars['grace']!.calendarName, '教會行事曆');
    await go(tester, '/calendar');
    expect(find.text('同工會'), findsOneWidget);
    expect(find.text('19:30'), findsOneWidget);
  });

  testWidgets('staff have no edit entry; calendar editors add and delete with undo', (tester) async {
    final b = seededChurch(as: calendarEditor, extra: const [calendarEditor]);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      CalendarEvent(id: 'e1', title: '同工會', start: DateTime(2026, 10, 10), end: DateTime(2026, 10, 11), allDay: true),
    ];
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tester.tap(find.byTooltip('新增活動'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '禱告會');
    await tester.pump();
    await tapText(tester, '儲存');
    expect(b.calendarEvents['grace']!.map((e) => e.title), containsAll(['同工會', '禱告會']));

    await tapText(tester, '同工會');
    await tapText(tester, '刪除活動');
    expect(b.calendarEvents['grace']!.map((e) => e.title), ['禱告會']);
    await tapText(tester, '復原');
    expect(b.calendarEvents['grace']!.map((e) => e.title), containsAll(['同工會', '禱告會']));
  });

  testWidgets('renaming a three-day event keeps its three days', (tester) async {
    final b = seededChurch(as: calendarEditor, extra: const [calendarEditor]);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      CalendarEvent(id: 'camp', title: '夏令營', start: DateTime(2026, 10, 9), end: DateTime(2026, 10, 12), allDay: true),
    ];
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tapText(tester, '夏令營');
    await tester.enterText(find.byType(TextField).first, '秋令營');
    await tester.pump();
    await tapText(tester, '儲存');
    final camp = b.calendarEvents['grace']!.single;
    expect(camp.title, '秋令營');
    expect(camp.end, DateTime(2026, 10, 12));
  });

  testWidgets('staff cannot edit even when connected', (tester) async {
    final b = seededChurch(as: staffMei);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    expect(find.byTooltip('新增活動'), findsNothing);
    expect(find.text('這個月沒有活動'), findsOneWidget);
  });

  testWidgets('a revoked grant asks the admin to reconnect', (tester) async {
    final b = seededChurch();
    b.calendars['grace'] = const CalendarSettings(connected: true, needsReconnect: true, calendarName: 'x');
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    expect(find.text('行事曆的授權失效了'), findsOneWidget);
    expect(find.text('重新連接'), findsOneWidget);
  });
}
