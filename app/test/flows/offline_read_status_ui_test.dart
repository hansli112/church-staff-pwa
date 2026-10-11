import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:martha/state/calendar.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

void main() {
  testWidgets('transport offline status marks every main tab read-only and fits dark large text', (tester) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b, brightness: Brightness.dark, textScale: 3);
    expect(find.text('離線唯讀：連線後才能儲存變更'), findsNothing);
    b.setOnline(false);
    await settle(tester);
    expect(find.text('離線唯讀：連線後才能儲存變更'), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (final path in ['/rosters', '/calendar', '/me']) {
      await go(tester, path);
      expect(find.text('離線唯讀：連線後才能儲存變更'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    b.setOnline(true);
    await settle(tester);
    expect(find.text('離線唯讀：連線後才能儲存變更'), findsNothing);
  });

  testWidgets('home and calendar identify cached activities with their church-clock read time', (tester) async {
    final b = seededChurch(as: staffMei, clock: () => DateTime.utc(2026, 10, 1, 1));
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      CalendarEvent(
        id: 'meeting',
        title: '同工會',
        start: DateTime.utc(2026, 10, 10, 19),
        end: DateTime.utc(2026, 10, 10, 21),
      ),
    ];
    await pumpApp(tester, b);
    await tester.scrollUntilVisible(find.text('同工會'), 150, scrollable: find.byType(Scrollable).last);
    expect(find.text('同工會'), findsOneWidget);
    b.setOnline(false);
    await settle(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    final status = container.read(calendarReadStatusProvider('2026-10'));
    expect(status.cached, isTrue);
    expect(status.fetchedAt, DateTime.utc(2026, 10, 1, 1));
    await tester.scrollUntilVisible(
      find.textContaining('資料讀取於10/1 09:00'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('離線資料'), findsWidgets);
    expect(find.textContaining('資料讀取於10/1 09:00'), findsWidgets);

    await go(tester, '/calendar');
    expect(find.textContaining('離線資料'), findsOneWidget);
    expect(find.textContaining('資料讀取於10/1 09:00'), findsOneWidget);
    expect(find.text('同工會'), findsWidgets);
  });
}
