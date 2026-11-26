import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/features/rosters/people_picker.dart';

import '../support/harness.dart';
import '../support/seed.dart';

// Android's edge-swipe back (#110). Predictive back hands the gesture to the
// nearest page route, so over an open sheet it popped the page underneath
// and left the sheet floating on top of it. The sheet refuses the pop now,
// so the gesture stops at the sheet and the sheet closes — what the back
// button already did through Navigator.maybePop.

Future<void> go(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await settle(tester);
}

String pathOf(WidgetTester tester) => GoRouter.of(tester.element(find.byType(Scaffold).last)).state.uri.path;

/// 司琴 on 10/11, empty: tapping it opens the picker from 安排服事.
Finder cell(String role, int date) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == '$role, 10月$date日 週日',
);

void main() {
  testWidgets('a sheet refuses the pop: the back stops at it and the page stays', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await tester.tap(cell('司琴', 11));
    await settle(tester);
    expect(find.byType(PeoplePicker), findsOneWidget);

    final sheet = ModalRoute.of(tester.element(find.byType(PeoplePicker)))!;
    expect(
      sheet.popDisposition,
      RoutePopDisposition.doNotPop,
      reason: 'a gesture that would pop the page underneath stops at the sheet instead',
    );

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(PeoplePicker), findsNothing, reason: 'the sheet closed');
    expect(pathOf(tester), '/rosters/plan/sunday', reason: 'the page under it did not move');
  });

  testWidgets('the day page keeps its sheet behaviour: back closes, unsaved changes still ask', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-11');

    await tester.tap(find.text('招待').last);
    await settle(tester);
    expect(find.byType(PeoplePicker), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(PeoplePicker), findsNothing, reason: 'nothing picked, closed at once');

    await tester.tap(find.text('招待').last);
    await settle(tester);
    await tester.tap(find.text('陳志豪').last);
    await settle(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('放棄變更？'), findsOneWidget, reason: 'a change in the sheet is not dropped by a back');
    await tester.tap(find.text('繼續編輯'));
    await settle(tester);
    expect(find.byType(PeoplePicker), findsOneWidget);
  });
}
