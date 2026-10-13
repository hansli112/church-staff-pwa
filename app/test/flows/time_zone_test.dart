import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/providers.dart';

import '../support/harness.dart';
import '../support/seed.dart';

// A church's own time zone (#73): made in its maker's, changed by an admin,
// and every time shown on its clock, wherever the phone is.

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

void main() {
  testWidgets("a church starts in its maker's phone's time zone", (tester) async {
    final b = MemoryBackend(clock: testClock)..auth.googleAccount = 'alice@gmail.com';
    await pumpApp(tester, b, phoneTimeZone: ChurchTimeZone.losAngeles);
    await tapText(tester, '使用 Google 登入');
    await tapText(tester, '建立新教會');
    await tester.enterText(find.byType(TextField), '洛杉磯恩典堂');
    await tester.pump();
    await tapText(tester, '建立');
    expect(b.churches.values.single.timeZone, ChurchTimeZone.losAngeles);
  });

  testWidgets('an admin changes it after saying so, and today follows', (tester) async {
    // Thursday 9:00 in Taipei: still Wednesday evening in Los Angeles.
    final b = seededChurch();
    await pumpApp(tester, b);
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    expect(container.read(todayProvider), Day(2026, 10, 1));

    await go(tester, '/me/church');
    expect(find.text('台北（UTC+8）'), findsOneWidget);
    await tapText(tester, '時區');
    // 1 October: summer time in Los Angeles and Vancouver.
    expect(find.text('UTC−7'), findsNWidgets(2));
    await tapText(tester, '洛杉磯');
    expect(find.text('改成洛杉磯時間？'), findsOneWidget);
    await tapText(tester, '取消');
    expect(b.churches['grace']!.timeZone, ChurchTimeZone.taipei);

    await tapText(tester, '洛杉磯');
    await tapText(tester, '改成洛杉磯時間');
    expect(b.churches['grace']!.timeZone, ChurchTimeZone.losAngeles);
    expect(container.read(todayProvider), Day(2026, 9, 30));
  });

  testWidgets('everyone sees it; only admins change it', (tester) async {
    await pumpApp(tester, seededChurch(as: staffMei));
    await go(tester, '/me/church');
    expect(find.text('台北（UTC+8）'), findsOneWidget);
    await tapText(tester, '時區');
    expect(find.text('洛杉磯'), findsNothing);
  });

  testWidgets("the calendar says its times are the church's when the phone is elsewhere", (tester) async {
    Future<void> calendarWith(Duration phone) async {
      final b = seededChurch(as: staffMei);
      b.connectCalendar('grace', calendarName: '教會行事曆');
      b.calendarEvents['grace'] = [
        CalendarEvent(id: 'e1', title: '同工會', start: DateTime(2026, 10, 2, 19), end: DateTime(2026, 10, 2, 21)),
      ];
      await pumpApp(tester, b, phoneOffset: phone);
      await go(tester, '/calendar');
    }

    await calendarWith(const Duration(hours: 8));
    expect(find.text('教會當地時間（台北）'), findsNothing);
    await calendarWith(const Duration(hours: -7));
    expect(find.text('教會當地時間（台北）'), findsOneWidget);
    expect(find.text('19:00'), findsOneWidget, reason: "the church's 7 pm, not the phone's");
  });

  testWidgets('picking a calendar kept in another time zone says so', (tester) async {
    final b = seededChurch();
    b.connectCalendar('grace', calendarName: '教會行事曆', calendarId: 'cal-1');
    b.calendarChoices = const [
      (id: 'cal-1', name: '教會行事曆', timeZone: 'America/Phoenix'),
      (id: 'cal-2', name: '青年行事曆', timeZone: 'Asia/Hong_Kong'),
    ];
    await pumpApp(tester, b);
    await go(tester, '/me/calendar');
    expect(find.textContaining('這本日曆的時區是America/Phoenix'), findsOneWidget);

    b.connectCalendar('grace', calendarName: '青年行事曆', calendarId: 'cal-2');
    await settle(tester);
    expect(find.textContaining('這本日曆的時區是'), findsNothing, reason: "Hong Kong's clock is Taipei's");
  });
}
