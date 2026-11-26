import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/features/rosters/people_picker.dart';

import '../support/harness.dart';
import '../support/seed.dart';

// Android's edge-swipe back (#110). A sheet is one route on the root
// navigator (so that it covers the tab bar), while the page it was opened
// from stays the current route of its tab's own navigator. Predictive back
// asks each page route whether it is current and may pop, so the page took
// the gesture and went back underneath the sheet. A route on the sheet's
// navigator cannot claim the gesture instead, so while a sheet is up
// showAppSheet holds the tab navigator with a transparent route: the page is
// no longer current, nothing takes the swipe, and it falls back to an
// ordinary back, which lands on the sheet as the back button does.

/// Android's predictive back over the channel the engine sends it on, as
/// packages/flutter's own tests do.
Future<void> gesture(WidgetTester tester, String method, {double progress = 0.0}) async {
  final data = const StandardMethodCodec().encodeMethodCall(
    MethodCall(method, <String, dynamic>{
      'touchOffset': <double>[5.0, 300.0],
      'progress': progress,
      'swipeEdge': 0, // left edge
    }),
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/backgesture', data, (_) {});
  await tester.pump();
}

Future<void> swipeBack(WidgetTester tester) async {
  await gesture(tester, 'startBackGesture');
  await gesture(tester, 'updateBackGestureProgress', progress: 1.0);
  await gesture(tester, 'commitBackGesture');
  await settle(tester);
}

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
  testWidgets('an edge swipe over a sheet closes the sheet; the page under it stays', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await tester.tap(cell('司琴', 11));
    await settle(tester);
    expect(find.byType(PeoplePicker), findsOneWidget);

    await swipeBack(tester);

    expect(find.byType(PeoplePicker), findsNothing, reason: 'the swipe closed the sheet');
    expect(pathOf(tester), '/rosters/plan/sunday', reason: 'the page under the sheet did not move');
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

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
