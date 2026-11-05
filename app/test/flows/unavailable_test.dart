import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/session.dart';

import '../support/harness.dart';
import '../support/seed.dart';
import '../support/telemetry.dart';

// 不能服事的日子 (#91). The tests start on Thursday 1 October 2026: 李美玉
// ushers on 10/4 and 10/11.

Future<void> go(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await settle(tester);
}

/// October [day] on the page of days, scrolled to.
Future<Finder> october(WidgetTester tester, int day) async {
  final f = find.byWidgetPredicate(
    (w) => w is Semantics && (w.properties.label?.startsWith('2026年10月$day日') ?? false),
  );
  await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  await settle(tester);
  return f;
}

/// Back to the top of the page.
Future<void> top(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 5000));
  await settle(tester);
}

UnavailableDays? meisDays(MemoryBackend b) => b.unavailable['grace']?['mei'];

Day _oct(int d) => Day(2026, 10, d);

/// The cell of [role] on October [date] in 安排服事.
Finder cell(String role, int date) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == '$role, 10月$date日 週日',
);

void main() {
  testWidgets('a tap marks a day, again clears it; one already served on is said', (tester) async {
    final b = seededChurch(as: staffMei);
    final telemetry = RecordingTelemetry();
    await pumpApp(tester, b, overrides: [telemetryProvider.overrideWithValue(telemetry)]);
    await go(tester, '/me');
    await tester.tap(find.text('不能服事的日子'));
    await settle(tester);

    await tester.tap(await october(tester, 11));
    await settle(tester);
    expect(meisDays(b), const UnavailableDays().add(_oct(11), _oct(11)));
    await top(tester);
    expect(find.text('這幾天你已經被排到'), findsOneWidget);
    expect(find.text('主日崇拜 招待'), findsOneWidget);

    await tester.tap(await october(tester, 11));
    await settle(tester);
    expect(meisDays(b)!.isEmpty, isTrue);
    expect(find.text('這幾天你已經被排到'), findsNothing);
    expect(telemetry.named('unavailable_set'), [null, null], reason: 'each change kept');
  });

  testWidgets('held and dragged, a stretch; it takes a reason, and is removed with 復原', (tester) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b);
    await go(tester, '/me/unavailable');

    final from = await october(tester, 20);
    final gesture = await tester.startGesture(tester.getCenter(from));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(tester.getCenter(await october(tester, 23)));
    await tester.pump();
    await gesture.up();
    await settle(tester);
    expect(meisDays(b)!.spans, [UnavailableSpan(_oct(20), _oct(23))]);

    await top(tester);
    await tester.tap(find.text('10月20日 – 10月23日'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '出國');
    await tester.tap(find.text('儲存'));
    await settle(tester);
    expect(meisDays(b)!.spans.single.note, '出國');
    expect(find.text('出國'), findsOneWidget);

    await tester.tap(find.text('移除'));
    await settle(tester);
    expect(meisDays(b)!.isEmpty, isTrue);
    await tester.tap(find.text('復原'));
    await settle(tester);
    expect(meisDays(b)!.spans, [UnavailableSpan(_oct(20), _oct(23), note: '出國')]);
  });

  testWidgets('whoever arranges sees it: last in the picker with its reason, greyed in the table', (tester) async {
    final b = seededChurch(as: editor);
    b.unavailable['grace'] = {'mei': const UnavailableDays().add(_oct(11), _oct(18), note: '出國')};
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');

    final usher = tester.getSemantics(cell('招待', 11));
    expect(usher.value, '李美玉, 這天不行');

    await tester.tap(cell('司琴', 11));
    await settle(tester);
    expect(find.textContaining('這天不行：出國'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('陳志豪').last).dy,
      lessThan(tester.getTopLeft(find.text('李美玉').last).dy),
      reason: 'who can serve first',
    );
    await tester.tap(find.text('李美玉').last);
    await settle(tester);
    expect(peopleOn(b, 11, '司琴'), ['李美玉'], reason: 'still to be picked');
    expect(find.text('已更新司琴・李美玉這天不行'), findsOneWidget);
  });

  testWidgets("a day's own picker says so too, opened first thing", (tester) async {
    final b = seededChurch(as: editor);
    b.unavailable['grace'] = {'mei': const UnavailableDays().add(_oct(11), _oct(11))};
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tester.tap(find.text('司琴'));
    await settle(tester);
    expect(find.textContaining('這天不行'), findsOneWidget);
  });

  testWidgets('請同工填 asks those on the lists, through the month picked, once confirmed', (tester) async {
    final b = seededChurch(as: editor);
    final telemetry = RecordingTelemetry();
    await pumpApp(tester, b, overrides: [telemetryProvider.overrideWithValue(telemetry)]);
    await go(tester, '/rosters/plan/sunday');

    await tester.tap(find.byIcon(Symbols.more_horiz_rounded));
    await settle(tester);
    await tester.tap(find.text('請同工填不能服事的日子'));
    await settle(tester);
    await tester.tap(find.text('2026年12月').last);
    await settle(tester);
    expect(find.text('要通知 2 位同工填 10月到12月不能服事的日子嗎？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settle(tester);
    expect(b.unavailableAsks['grace'], isNull, reason: 'nothing until confirmed');

    await tester.tap(find.byIcon(Symbols.more_horiz_rounded));
    await settle(tester);
    await tester.tap(find.text('請同工填不能服事的日子'));
    await settle(tester);
    await tester.tap(find.text('2026年12月').last);
    await settle(tester);
    await tester.tap(find.text('通知'));
    await settle(tester);
    expect(find.text('已通知 2 位同工'), findsOneWidget);
    final asked = b.unavailableAsks['grace']!['sunday']!;
    expect((asked.from, asked.to), (_oct(1), Day(2026, 12, 1)));
    expect(asked.told..sort(), ['hao', 'mei']);
    expect(telemetry.named('unavailable_ask'), [
      {'people': 2},
    ], reason: 'once confirmed, not the time 取消 was tapped');

    await tester.tap(find.byIcon(Symbols.more_horiz_rounded));
    await settle(tester);
    expect(find.text('上次 10月1日 請過'), findsOneWidget);
  });
}
