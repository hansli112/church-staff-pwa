import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/features/calendar/calendar_screen.dart';

import 'harness.dart';

/// The month the calendar shows, as its title has it: 「10月 2026」.
Finder calendarMonth(String title) => find.text(title, findRichText: true);

/// Swipes the calendar [by] months on (back, when negative), anywhere on
/// it: over the agenda, so with the month grid folded away too. Not
/// settled, for a test that holds the read.
Future<void> swipeMonth(WidgetTester tester, int by) => tester.fling(
  find.descendant(of: find.byType(CalendarScreen), matching: find.byType(CustomScrollView)),
  Offset(by > 0 ? -300 : 300, 0),
  1000,
);

/// Opens the calendar's 顯示與篩選 menu.
Future<void> openCalendarMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('顯示與篩選'));
  await settle(tester);
}

/// Picks [label] in the calendar's menu: 月曆和列表, 只看列表 or a filter.
/// Not settled, for a test that looks while it folds.
Future<void> pickInCalendarMenu(WidgetTester tester, String label) async {
  await openCalendarMenu(tester);
  await tester.tap(find.ancestor(of: find.text(label).last, matching: find.byType(CheckedPopupMenuItem<Object>)));
}

/// The filter ticked in the calendar's menu, which is closed again.
Future<String> calendarFilterShown(WidgetTester tester) async {
  await openCalendarMenu(tester);
  final ticked = tester
      .widgetList<CheckedPopupMenuItem<Object>>(find.byType(CheckedPopupMenuItem<Object>))
      .where((i) => i.checked && i.value is String)
      .single;
  await tester.tapAt(const Offset(5, 300));
  await settle(tester);
  return (ticked.child! as Text).data!;
}
