import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:martha/core/design/components.dart';
import 'package:martha/core/design/tokens.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/attendance.dart';
import 'package:martha/state/providers.dart';
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

/// A finger put down on October [from] and lifted on [to], straight away:
/// no holding first.
Future<void> dragAcross(WidgetTester tester, int from, int to) async {
  final start = tester.getCenter(await october(tester, from));
  final end = tester.getCenter(await october(tester, to));
  final gesture = await tester.startGesture(start);
  await gesture.moveTo(Offset.lerp(start, end, 0.5)!);
  await tester.pump();
  await gesture.moveTo(end);
  await tester.pump();
  await gesture.up();
  await settle(tester);
}

/// The color October [day] is shown in.
Future<Color?> dayColor(WidgetTester tester, int day) async =>
    tester.widget<Text>(find.descendant(of: await october(tester, day), matching: find.byType(Text))).style?.color;

/// The color of [weekday]'s letter atop the month.
Color? weekdayColor(WidgetTester tester, String weekday) => tester
    .widget<Text>(find.descendant(of: find.byType(ExcludeSemantics), matching: find.text(weekday)).first)
    .style
    ?.color;

bool shownMarked(WidgetTester tester, int day) {
  final f = find.byWidgetPredicate(
    (w) => w is Semantics && (w.properties.label?.startsWith('2026年10月$day日') ?? false),
  );
  return tester.widget<Semantics>(f).properties.selected ?? false;
}

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

  testWidgets('the weekdays one does not serve on are dimmed, and still marked with a tap', (tester) async {
    const c = AppColors.light;
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b);
    await go(tester, '/me/unavailable');

    expect(weekdayColor(tester, '日'), c.label, reason: '李美玉 serves on Sundays');
    expect(weekdayColor(tester, '一'), c.secondaryLabel);
    expect(await dayColor(tester, 4), c.label);
    expect(await dayColor(tester, 5), c.secondaryLabel);
    expect(await dayColor(tester, 5), isNot(c.tertiaryLabel), reason: 'not to be taken for a day gone by');

    await tester.tap(await october(tester, 5));
    await settle(tester);
    expect(meisDays(b), const UnavailableDays().add(_oct(5), _oct(5)));
    expect(await dayColor(tester, 5), c.accent);
  });

  testWidgets('one in no service has none dimmed', (tester) async {
    const c = AppColors.light;
    await pumpApp(tester, seededChurch(as: john));
    await go(tester, '/me/unavailable');

    expect(await dayColor(tester, 4), c.label);
    expect(await dayColor(tester, 5), c.label);
    await top(tester);
    expect(weekdayColor(tester, '日'), c.secondaryLabel, reason: 'the weekdays as they were, none standing out');
  });

  testWidgets('the months go on through next December, so all of next year can be marked', (tester) async {
    await pumpApp(tester, seededChurch(as: staffMei));
    await go(tester, '/me/unavailable');
    for (var i = 0; i < 20; i++) {
      final next = find.ancestor(of: find.byTooltip('下個月'), matching: find.byType(IconButton));
      if (tester.widget<IconButton>(next).onPressed == null) break;
      await tester.tap(next);
      await settle(tester);
    }
    expect(find.text('2027年12月'), findsOneWidget);
  });

  testWidgets('dragged across days, a stretch; its row says 寫原因 till it takes one, and it is removed with 復原', (
    tester,
  ) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b);
    await go(tester, '/me/unavailable');
    expect(find.text('加一段期間'), findsNothing, reason: 'dragging does it');

    await dragAcross(tester, 20, 23);
    expect(meisDays(b)!.spans, [UnavailableSpan(_oct(20), _oct(23))]);

    await top(tester);
    expect(find.text('寫原因'), findsOneWidget, reason: 'on the row, not only in the small words under the list');
    await tester.tap(find.text('寫原因'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '出國');
    await tester.tap(find.text('儲存'));
    await settle(tester);
    expect(meisDays(b)!.spans.single.note, '出國');
    expect(find.text('出國'), findsOneWidget);
    expect(find.text('寫原因'), findsNothing);

    await tester.tap(find.text('刪除'));
    await settle(tester);
    expect(meisDays(b)!.isEmpty, isTrue);
    expect(findShown('已刪除「10月20日 – 10月23日」'), findsOneWidget);
    await tester.tap(find.text('復原'));
    await settle(tester);
    expect(meisDays(b)!.spans, [UnavailableSpan(_oct(20), _oct(23), note: '出國')]);
  });

  testWidgets('dragged from a day already marked, the days are cleared instead', (tester) async {
    final b = seededChurch(as: staffMei);
    b.unavailable['grace'] = {'mei': const UnavailableDays().add(_oct(19), _oct(24), note: '出國')};
    await pumpApp(tester, b);
    await go(tester, '/me/unavailable');

    await dragAcross(tester, 22, 26);
    expect(meisDays(b)!.spans, [UnavailableSpan(_oct(19), _oct(21), note: '出國')]);
  });

  testWidgets('days tapped while a slow save is on its way stay marked, until the saved ones come back too', (
    tester,
  ) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b);
    await go(tester, '/me/unavailable');
    b.writeDelay = const Duration(seconds: 1);
    final echo = b.unavailableEchoHeld = Completer<void>();

    await tester.tap(await october(tester, 20));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(await october(tester, 21));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      expect([shownMarked(tester, 20), shownMarked(tester, 21)], [true, true], reason: 'after ${i * 300} ms');
    }
    expect(meisDays(b)!.spans, [UnavailableSpan(_oct(20), _oct(21))], reason: 'saved one after the other');
    b.unavailableEchoHeld = null;
    echo.complete();
    await settle(tester);
    expect([shownMarked(tester, 20), shownMarked(tester, 21)], [true, true]);
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
    expect(findShownContaining('這天不行：出國'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('陳志豪').last).dy,
      lessThan(tester.getTopLeft(find.text('李美玉').last).dy),
      reason: 'who can serve first',
    );
    await tester.tap(find.text('李美玉').last);
    await settle(tester);
    expect(
      find.descendant(of: cell('司琴', 11), matching: find.text('李美玉')),
      findsOneWidget,
      reason: 'still to be picked',
    );
    expect(find.text('已更新司琴 · 李美玉這天不行'), findsOneWidget);
  });

  testWidgets("a day's own picker says so too, opened first thing", (tester) async {
    final b = seededChurch(as: editor);
    b.unavailable['grace'] = {'mei': const UnavailableDays().add(_oct(11), _oct(11))};
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tester.tap(find.text('司琴'));
    await settle(tester);
    expect(findShownContaining('這天不行'), findsOneWidget);
  });

  testWidgets('通知同工填 asks those on the lists about the months picked from a grid by year, once confirmed', (
    tester,
  ) async {
    final b = seededChurch(as: editor);
    final telemetry = RecordingTelemetry();
    await pumpApp(tester, b, overrides: [telemetryProvider.overrideWithValue(telemetry)]);
    await go(tester, '/rosters/plan/sunday');

    await tester.tap(find.byIcon(Symbols.more_horiz_rounded));
    await settle(tester);
    await tester.tap(find.text('請同工填不能服事日'));
    await settle(tester);
    expect(find.text('要問哪幾個月？'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^2027年12月')), findsOneWidget, reason: 'all of next year');
    expect(find.bySemanticsLabel(RegExp('^2028年1月')), findsNothing);
    expect(find.text('2026年'), findsOneWidget);
    expect(find.text('2027年'), findsOneWidget);
    expect(find.text('12月'), findsNWidgets(2), reason: 'each year its own months');
    expect(
      tester.getTopLeft(find.text('2027年')).dy,
      greaterThan(tester.getTopLeft(find.bySemanticsLabel(RegExp('^2026年12月')).last).dy),
      reason: 'next year below this one',
    );
    expect(findShownContaining('通知過'), findsNothing, reason: 'not when it last asked');
    expect(find.bySemanticsLabel('2026年10月, 開始'), findsOneWidget, reason: 'the first month not arranged');
    expect(find.text('通知 10月'), findsOneWidget, reason: 'one month, till an end is picked');
    await tester.tap(find.bySemanticsLabel(RegExp('^2026年12月')).last);
    await settle(tester);
    expect(find.bySemanticsLabel('2026年12月, 結束'), findsOneWidget);
    await tester.tap(find.text('通知 10月到12月'));
    await settle(tester);
    expect(find.text('要通知 2 位同工填 10月到12月不能服事的日子嗎？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settle(tester);
    expect(b.unavailableAsks['grace'], isNull, reason: 'nothing until confirmed');

    await tester.tap(find.byIcon(Symbols.more_horiz_rounded));
    await settle(tester);
    await tester.tap(find.text('請同工填不能服事日'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('^2026年12月')).last);
    await settle(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('^2026年11月')).last);
    await settle(tester);
    expect(find.text('通知 11月'), findsOneWidget, reason: 'with an end picked, a tap starts anew');
    await tester.tap(find.bySemanticsLabel(RegExp('^2027年1月')).last);
    await settle(tester);
    await tester.tap(find.text('通知 11月到1月'));
    await settle(tester);
    await tester.tap(find.text('通知'));
    await settle(tester);
    expect(find.text('已通知 2 位同工'), findsOneWidget);
    final asked = b.unavailableAsks['grace']!['sunday']!;
    expect((asked.from, asked.to), (Day(2026, 11, 1), Day(2027, 1, 1)));
    expect(asked.told..sort(), ['hao', 'mei']);
    expect(telemetry.named('unavailable_ask'), [
      {'people': 2},
    ], reason: 'once confirmed, not the time 取消 was tapped');
  });

  testWidgets('a month whose every day has someone on each duty is 已排好, and the months start after it', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    final sundays = [for (var d = _oct(4); d.month == 10; d = d.addDays(7)) d];
    for (final d in sundays) {
      final r = b.rosters['grace']![Roster.idFor('sunday', d)];
      final duties = r?.duties ?? [for (final role in b.services['grace']!.byId('sunday')!.duties) Duty(role: role)];
      b.rosters['grace']![Roster.idFor('sunday', d)] = Roster(
        type: 'sunday',
        day: d,
        duties: [
          for (final x in duties) x.people.isEmpty ? x.copyWith(people: const ['李美玉']) : x,
        ],
        saved: true,
      );
    }
    b.notify();
    await settle(tester);
    await tester.tap(find.byIcon(Symbols.more_horiz_rounded));
    await settle(tester);
    await tester.tap(find.text('請同工填不能服事日'));
    await settle(tester);
    expect(find.bySemanticsLabel('2026年10月, 已排好'), findsOneWidget);
    expect(find.bySemanticsLabel('2026年11月, 開始'), findsOneWidget);
  });

  testWidgets('asked, home says the months until sent; the page opens on the first, with 都可以服事 or 送出', (tester) async {
    final b = seededChurch(as: staffMei);
    final telemetry = RecordingTelemetry();
    b.unavailableAsked['grace'] = {'mei': (at: testNow, from: Day(2026, 12, 1), to: Day(2027, 1, 1))};
    await pumpApp(tester, b, overrides: [telemetryProvider.overrideWithValue(telemetry)]);
    await go(tester, '/home');
    expect(find.text('12月到1月'), findsOneWidget);
    await tester.tap(find.text('填不能服事的日子'));
    await settle(tester);

    expect(find.text('2026年12月'), findsOneWidget, reason: 'the first month asked');
    expect(find.text('請填這兩個月'), findsOneWidget, reason: 'the months asked, above them');
    expect(find.text('填知道的就好，送出後還能改。'), findsOneWidget);
    await tester.tap(find.text('1月'));
    await settle(tester);
    expect(find.text('2027年1月'), findsOneWidget, reason: 'a month asked, a tap away');
    await tester.tap(find.text('12月'));
    await settle(tester);
    expect(find.text('2026年12月'), findsOneWidget);
    expect(find.text('都可以服事'), findsOneWidget, reason: 'none of those days marked');
    final dec13 = find.byWidgetPredicate(
      (w) => w is Semantics && (w.properties.label?.startsWith('2026年12月13日') ?? false),
    );
    await tester.tap(dec13);
    await settle(tester);
    expect(find.text('都可以服事'), findsNothing);
    await tester.tap(find.text('送出'));
    await settle(tester);
    expect(b.unavailableSentAt['grace']?['mei'], isNotNull);
    expect(meisDays(b), const UnavailableDays().add(Day(2026, 12, 13), Day(2026, 12, 13)), reason: 'kept first');
    expect(find.text('已送出'), findsOneWidget);
    expect(find.text('請填這兩個月'), findsNothing, reason: 'sent');
    expect(find.text('填知道的就好，送出後還能改。'), findsNothing);
    expect(telemetry.named('unavailable_send'), [
      {'free': false},
    ]);

    await tester.tap(dec13);
    await settle(tester);
    expect(meisDays(b)!.isEmpty, isTrue, reason: 'still kept as it changes');
    expect(find.text('已送出'), findsOneWidget);

    await go(tester, '/home');
    expect(find.text('填不能服事的日子'), findsNothing, reason: 'sent');
  });

  testWidgets('home waits for what was asked of me, then shows it with my days, not after them', (tester) async {
    final b = seededChurch(as: staffMei);
    final asked = StreamController<UnavailableAsked?>();
    addTearDown(asked.close);
    await pumpApp(tester, b, overrides: [unavailableAskedProvider.overrideWith((ref) => asked.stream)]);
    await go(tester, '/home');
    expect(find.text('我接下來的服事'), findsNothing, reason: 'waiting for the server');
    expect(find.text('填不能服事的日子'), findsNothing);

    asked.add(UnavailableAsked(at: testNow, from: Day(2026, 12, 1), to: Day(2026, 12, 1)));
    await settle(tester);
    expect(find.text('我接下來的服事'), findsOneWidget);
    expect(find.text('填不能服事的日子'), findsOneWidget, reason: 'in the same frame as my days');
  });

  testWidgets('home waits for 人數 still to fill in too, then shows it with my days', (tester) async {
    final b = seededChurch(as: staffMei);
    final fills = StreamController<Set<String>>();
    addTearDown(fills.close);
    b.churches['grace'] = b.churches['grace']!.copyWith(attendanceSince: () => Day(2026, 9, 1));
    await pumpApp(tester, b, overrides: [myFillsProvider.overrideWith((ref) => fills.stream)]);
    await go(tester, '/home');
    expect(find.text('我接下來的服事'), findsNothing, reason: 'waiting for what I fill in');
    fills.add(const {});
    await settle(tester);
    expect(find.text('我接下來的服事'), findsOneWidget);
  });

  testWidgets('home shows my days when what was asked of me cannot be read', (tester) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(
      tester,
      b,
      overrides: [unavailableAskedProvider.overrideWith((ref) => Stream.error(Exception('offline')))],
    );
    await go(tester, '/home');
    expect(find.text('我接下來的服事'), findsOneWidget);
    expect(find.text('填不能服事的日子'), findsNothing);
  });

  testWidgets('都可以服事 sends with no days marked, and home stops asking', (tester) async {
    final b = seededChurch(as: staffMei);
    final telemetry = RecordingTelemetry();
    b.unavailableAsked['grace'] = {'mei': (at: testNow, from: Day(2026, 12, 1), to: Day(2026, 12, 1))};
    await pumpApp(tester, b, overrides: [telemetryProvider.overrideWithValue(telemetry)]);
    await go(tester, '/me/unavailable');
    await tester.tap(find.text('都可以服事'));
    await settle(tester);
    expect(b.unavailableSentAt['grace']?['mei'], isNotNull);
    expect(find.text('已送出'), findsOneWidget);
    expect(telemetry.named('unavailable_send'), [
      {'free': true},
    ]);
    await go(tester, '/home');
    expect(find.text('填不能服事的日子'), findsNothing);
  });

  testWidgets('送出 while a day is being kept, and the keeping fails: nothing is sent', (tester) async {
    final b = seededChurch(as: staffMei);
    b.unavailableAsked['grace'] = {'mei': (at: testNow, from: Day(2026, 12, 1), to: Day(2026, 12, 1))};
    await pumpApp(tester, b);
    await go(tester, '/me/unavailable');
    b.writeDelay = const Duration(seconds: 1);
    b.failNextWrite = const CloudException(CloudErrorCode.unknown);

    await tester.tap(
      find.byWidgetPredicate((w) => w is Semantics && (w.properties.label?.startsWith('2026年12月13日') ?? false)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('送出'));
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    expect(meisDays(b), isNull);
    expect(b.unavailableSentAt['grace']?['mei'], isNull, reason: 'the days asked for are not those kept');
    expect(find.text('已送出'), findsNothing);
    expect(find.text('都可以服事'), findsOneWidget, reason: 'still to send');
  });

  testWidgets('the ask known only after the page opens: it goes to the month asked, unless moved by hand', (
    tester,
  ) async {
    final b = seededChurch(as: staffMei);
    await pumpApp(tester, b);
    await go(tester, '/me/unavailable');
    expect(find.text('2026年10月'), findsOneWidget, reason: 'nothing asked, as far as it knows');

    b.unavailableAsked['grace'] = {'mei': (at: testNow, from: Day(2026, 12, 1), to: Day(2026, 12, 1))};
    b.notify();
    await settle(tester);
    expect(find.text('2026年12月'), findsOneWidget, reason: 'the month asked');

    await tester.tap(find.byTooltip('下個月'));
    await settle(tester);
    b.unavailableAsked['grace'] = {
      'mei': (at: testNow.add(const Duration(hours: 1)), from: Day(2026, 11, 1), to: Day(2026, 11, 1)),
    };
    b.notify();
    await settle(tester);
    expect(find.text('2027年1月'), findsOneWidget, reason: 'left where it was moved to');
  });

  testWidgets('not asked, nothing to send', (tester) async {
    await pumpApp(tester, seededChurch(as: staffMei));
    await go(tester, '/me/unavailable');
    expect(find.text('送出'), findsNothing);
    expect(find.text('都可以服事'), findsNothing);
    expect(find.textContaining('請填'), findsNothing);
    expect(find.text('2026年10月'), findsOneWidget);
  });

  testWidgets(
    "asked again, the months' sheet says who has not sent and who has, by name; 再通知 tells only those yet to",
    (tester) async {
      final b = seededChurch(as: editor);
      final telemetry = RecordingTelemetry();
      await pumpApp(tester, b, overrides: [telemetryProvider.overrideWithValue(telemetry)]);
      await go(tester, '/rosters/plan/sunday');
      Future<void> openMonths() async {
        await tester.tap(find.byIcon(Symbols.more_horiz_rounded));
        await settle(tester);
        await tester.tap(find.text('請同工填不能服事日'));
        await settle(tester);
      }

      await openMonths();
      expect(find.textContaining('還沒填'), findsNothing, reason: 'never asked');
      await tester.tap(find.bySemanticsLabel(RegExp('^2026年12月')).last);
      await settle(tester);
      await tester.tap(find.text('通知 10月到12月'));
      await settle(tester);
      await tester.tap(find.text('通知'));
      await settle(tester);

      await openMonths();
      expect(find.bySemanticsLabel(RegExp('^2027年12月')), findsOneWidget, reason: 'new months still to pick');
      await tester.tap(find.text('10月到12月・2 位還沒填'));
      await settle(tester);
      expect(find.text('10月到12月不能服事的日子'), findsOneWidget);
      expect(find.text('10月1日通知'), findsOneWidget);
      expect(find.text('還沒填・2 位'), findsOneWidget);

      b.unavailableSentAt['grace'] = {'mei': testNow};
      b.notify();
      await settle(tester);
      expect(find.text('還沒填・1 位'), findsOneWidget);
      expect(find.text('填好了・1 位'), findsOneWidget);
      expect(
        find.descendant(of: find.widgetWithText(ListSection, '填好了・1 位'), matching: find.text('李美玉')),
        findsOneWidget,
        reason: 'who has filled theirs, by name',
      );
      await tester.tap(find.text('再通知這 1 位'));
      await settle(tester);
      expect(find.text('已通知 1 位同工'), findsOneWidget);
      expect(telemetry.named('unavailable_remind'), [
        {'people': 1},
      ]);

      await openMonths();
      expect(find.text('10月到12月・1 位還沒填'), findsOneWidget);
    },
  );

  testWidgets(
    "the round's sheet says under each name the days asked they cannot serve; a change to them answers it too",
    (tester) async {
      final b = seededChurch(as: editor);
      b.unavailableAsks['grace'] = {
        'sunday': (at: testNow, from: Day(2026, 10, 1), to: Day(2026, 11, 1), told: const ['mei', 'hao']),
      };
      b.unavailableSentAt['grace'] = {'hao': testNow};
      b.unavailable['grace'] = {
        // 10/14 is a Wednesday, and 12/6 not a month asked: neither said.
        'mei': const UnavailableDays()
            .add(_oct(11), _oct(11), note: '出國')
            .add(_oct(14), _oct(14))
            .add(Day(2026, 11, 22), Day(2026, 11, 22))
            .add(Day(2026, 12, 6), Day(2026, 12, 6)),
      };
      await pumpApp(tester, b);
      await go(tester, '/rosters/plan/sunday');
      await tester.tap(find.byIcon(Symbols.more_horiz_rounded));
      await settle(tester);
      await tester.tap(find.text('請同工填不能服事日'));
      await settle(tester);
      await tester.tap(find.text('10月到11月・1 位還沒填'));
      await settle(tester);
      expect(
        find.descendant(of: find.widgetWithText(ListSection, '還沒填・1 位'), matching: findShown('10/11（出國）、11/22 不行')),
        findsOneWidget,
        reason: 'not answered, and still what they have marked',
      );
      expect(
        find.descendant(of: find.widgetWithText(ListSection, '填好了・1 位'), matching: find.text('都可以')),
        findsOneWidget,
      );

      // 李美玉 changes her days on her own page: that answers it.
      b.unavailable['grace']!['mei'] = b.unavailable['grace']!['mei']!.add(Day(2026, 11, 8), Day(2026, 11, 8));
      (b.unavailableChangedAt['grace'] ??= {})['mei'] = testNow.add(const Duration(hours: 1));
      b.notify();
      await settle(tester);
      expect(find.text('填好了・2 位'), findsOneWidget);
      expect(findShown('10/11（出國）、11/8、11/22 不行'), findsOneWidget);
      expect(find.textContaining('再通知'), findsNothing, reason: 'nobody left to tell');
    },
  );

  testWidgets('通知同工填 on its way: asked once; the menu greys it till it is done', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    Future<PopupMenuItem<String>> askItem() async {
      await tester.tap(find.byIcon(Symbols.more_horiz_rounded));
      await settle(tester);
      final item = tester.widget<PopupMenuItem<String>>(find.widgetWithText(PopupMenuItem<String>, '請同工填不能服事日'));
      return item;
    }

    expect((await askItem()).enabled, isTrue);
    await tester.tap(find.text('請同工填不能服事日'));
    await settle(tester);
    await tester.tap(find.text('通知 10月'));
    await settle(tester);
    b.writeHeld = Completer<void>();
    await tester.tap(find.text('通知'));
    await settle(tester);
    expect((await askItem()).enabled, isFalse, reason: 'one on its way');
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);

    b.writeHeld!.complete();
    b.writeHeld = null;
    await settle(tester);
    expect(find.text('已通知 2 位同工'), findsOneWidget);
    expect((await askItem()).enabled, isTrue);
  });

  testWidgets('an ask whose months are gone by is not shown', (tester) async {
    final b = seededChurch(as: editor);
    b.unavailableAsks['grace'] = {
      'sunday': (at: testNow, from: Day(2026, 8, 1), to: Day(2026, 9, 1), told: ['mei']),
    };
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await tester.tap(find.byIcon(Symbols.more_horiz_rounded));
    await settle(tester);
    await tester.tap(find.text('請同工填不能服事日'));
    await settle(tester);
    expect(find.textContaining('還沒填'), findsNothing);
  });

  testWidgets('with nobody on the lists to ask, 通知 is greyed', (tester) async {
    final b = seededChurch(as: editor);
    final people = b.members['grace']!;
    for (final uid in [...people.keys]) {
      if (uid != editor.uid) people[uid] = people[uid]!.copyWith(zones: const []);
    }
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');

    await tester.tap(find.byIcon(Symbols.more_horiz_rounded));
    await settle(tester);
    await tester.tap(find.text('請同工填不能服事日'));
    await settle(tester);
    expect(find.text('要問哪幾個月？'), findsNothing, reason: 'greyed: nothing opens');
  });
}
