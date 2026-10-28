import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

// 排好幾週 (#90). The tests start on Thursday 1 October 2026: 10/4 has
// everyone, 10/11 nobody on 司琴 yet.

Future<void> go(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await settle(tester);
}

/// The cell of [role] on October [date].
Finder cell(String role, int date) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == '$role, 10月$date日 週日',
);

/// The date at the start of October [day]'s row.
Finder date(int day) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == '打開 10月$day日 週日',
);

/// Picks [name] for [role] on October [day] in the table.
Future<void> pick(WidgetTester tester, String role, int day, String name) async {
  await tester.tap(cell(role, day));
  await settle(tester);
  await tester.tap(find.text(name).last);
  await settle(tester);
}

/// 通知同工 answers [notice], or fails with [error].
class NotifyingBackend extends MemoryBackend {
  NotifyingBackend() : super(clock: testClock);

  PlannedNotice notice = (people: 1, later: false);
  Object? error;

  @override
  ChurchData church(String churchId) => _NotifyingData(this, churchId);
}

class _NotifyingData extends MemoryChurchData {
  _NotifyingData(this.backend, String churchId) : super(backend, churchId);

  final NotifyingBackend backend;

  @override
  Future<PlannedNotice> notifyPlanned(String serviceType) async {
    final error = backend.error;
    if (error != null) throw error;
    await super.notifyPlanned(serviceType);
    return backend.notice;
  }
}

/// Who waits for 通知同工 on 主日崇拜's days.
Set<String> waiting(MemoryBackend b) => {
  for (final MapEntry(:key, :value)
      in b.planned['grace']?.entries ?? const <MapEntry<String, ({String service, List<String> roles})>>[])
    if (value.service == 'sunday') key.split('/').last,
};

/// Holds [from] until it lifts, then drags it onto [to] and lets go.
Future<void> drag(WidgetTester tester, Finder from, Finder to) async {
  final gesture = await tester.startGesture(tester.getCenter(from));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  await gesture.moveTo(tester.getCenter(to));
  await tester.pump();
  await gesture.up();
  await settle(tester);
}

void main() {
  testWidgets('a cell picks its people at once; nobody is told until 通知同工, once', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    expect(find.text('2026年10月'), findsOneWidget);
    expect(find.text('2026年11月'), findsOneWidget);
    final notify = find.widgetWithText(TextButton, '通知同工');
    expect(tester.widget<TextButton>(notify).onPressed, isNull, reason: 'nothing to tell yet');

    await tester.tap(cell('司琴', 11));
    await settle(tester);
    await tester.tap(find.text('李美玉').last);
    await settle(tester);
    expect(peopleOn(b, 11, '司琴'), ['李美玉']);
    expect(waiting(b), {'mei'});
    expect(find.descendant(of: cell('司琴', 11), matching: find.text('李美玉')), findsOneWidget);

    await tester.tap(notify);
    await settle(tester);
    expect(find.text('已通知 1 位同工'), findsOneWidget);
    expect(waiting(b), isEmpty);
    expect(tester.widget<TextButton>(notify).onPressed, isNull);
  });

  testWidgets('a 事工’s 負責人 sees only the duties it leads', (tester) async {
    const worship = Ministry(id: 'worship', name: '敬拜團', duties: [MinistryDuty('sunday', '司琴')]);
    final b = seededChurch(
      extra: [
        staffMei.withIdentities(const [MinistryLead('worship')]),
      ],
      as: staffMei,
    );
    b.ministries['grace'] = const MinistrySettings(ministries: [worship], ids: ['worship']);
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    expect(cell('司琴', 11), findsOneWidget);
    expect(cell('司會', 11), findsNothing);
    expect(cell('招待', 11), findsNothing);
  });

  testWidgets('opens at the first month with a gap; the months before are a tap away', (tester) async {
    final b = seededChurch();
    for (final date in [11, 18, 25]) {
      b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, date))] = savedDay(
        b,
        4,
      ).copyWith(day: Day(2026, 10, date));
    }
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    expect(find.text('2026年10月'), findsNothing);
    expect(find.text('2026年11月'), findsOneWidget);
    await tester.tap(find.text('顯示前面的月份'));
    await settle(tester);
    expect(find.text('2026年10月'), findsOneWidget);
    expect(find.text('2027年1月'), findsOneWidget, reason: 'the months after stay');
  });

  testWidgets('the picker says how often someone serves that month, and what else that day', (tester) async {
    final b = seededChurch();
    b.rosters['grace']![Roster.idFor('youth', Day(2026, 10, 11))] = Roster(
      type: 'youth',
      day: Day(2026, 10, 11),
      duties: const [
        Duty(role: '司會', people: ['李美玉'], uids: {'李美玉': 'mei'}),
      ],
    );
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tester.tap(find.text('司琴'));
    await settle(tester);
    // 10/4 主日 and 10/11 青年; not the day being arranged.
    expect(find.text('這個月已排 2 次 · 同一天：青年崇拜 司會'), findsOneWidget);
  });

  testWidgets('復原 here also waits for 通知同工; the day’s own page tells at once', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    final notify = find.widgetWithText(TextButton, '通知同工');
    await pick(tester, '司琴', 11, '李美玉');
    expect(tester.widget<TextButton>(notify).onPressed, isNotNull);
    await tester.tap(find.text('復原'));
    await settle(tester);
    expect(peopleOn(b, 11, '司琴'), isEmpty);
    expect(waiting(b), isEmpty, reason: 'on and off again: nothing to tell');
    expect(tester.widget<TextButton>(notify).onPressed, isNull);

    await pick(tester, '司琴', 11, '李美玉');
    b.planned.clear();
    await tester.tap(find.text('復原'));
    await settle(tester);
    expect(waiting(b), {'mei'}, reason: 'taken off, told with the rest');

    b.planned.clear();
    await go(tester, '/rosters/sunday/2026-10-11');
    await tester.tap(find.text('司琴'));
    await settle(tester);
    await tester.tap(find.text('李美玉').last);
    await settle(tester);
    expect(peopleOn(b, 11, '司琴'), ['李美玉']);
    expect(waiting(b), isEmpty);
  });

  testWidgets('a duty taken off a day shows a dash, and opens nothing', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await tester.tap(cell('司琴', 11));
    await settle(tester);
    await tester.tap(find.text('移除這項'));
    await settle(tester);
    expect(savedDay(b, 11).duties.map((d) => d.role), ['司會', '招待']);
    expect(find.descendant(of: cell('司琴', 11), matching: find.text('—')), findsOneWidget);
    await tester.tap(cell('司琴', 11));
    await settle(tester);
    expect(find.text('移除這項'), findsNothing);
  });

  testWidgets('a date opens its day', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await tester.tap(date(11));
    await settle(tester);
    expect(GoRouterState.of(tester.element(find.byType(Scaffold).last)).uri.path, '/rosters/sunday/2026-10-11');
  });

  testWidgets('another service, from its first gap; more months below', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    expect(find.text('2027年1月'), findsNothing);
    await tester.scrollUntilVisible(find.text('顯示更多'), 300, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('顯示更多'));
    await settle(tester);
    expect(find.text('2027年1月'), findsOneWidget);

    await tester.tap(find.text('青年崇拜'));
    await settle(tester);
    expect(
      find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '司會, 10月3日 週六'),
      findsOneWidget,
    );
    expect(cell('司琴', 11), findsNothing);
    expect(find.text('2027年1月'), findsNothing, reason: 'three months again');
  });

  testWidgets('pressed at night: says when they will hear', (tester) async {
    final b = seededChurch(into: NotifyingBackend()..notice = (people: 2, later: true));
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await pick(tester, '司琴', 11, '李美玉');
    await tester.tap(find.text('通知同工'));
    await settle(tester);
    expect(find.text('早上 7 點會通知 2 位同工'), findsOneWidget);
  });

  testWidgets('a failed 通知同工 says so, and 重試 sends it again', (tester) async {
    final backend = NotifyingBackend()..error = const CloudException(CloudErrorCode.unavailable);
    final b = seededChurch(into: backend);
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await pick(tester, '司琴', 11, '李美玉');
    await tester.tap(find.text('通知同工'));
    await settle(tester);
    expect(waiting(b), {'mei'}, reason: 'nobody told');
    backend.error = null;
    await tester.tap(find.text('重試'));
    await settle(tester);
    expect(find.text('已通知 1 位同工'), findsOneWidget);
    expect(waiting(b), isEmpty);
  });

  testWidgets('fits with text at twice its size', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b, textScale: 2);
    await go(tester, '/rosters/plan/sunday');
    expect(tester.takeException(), isNull);
    await pick(tester, '司琴', 11, '李美玉');
    expect(tester.takeException(), isNull);
  });
  testWidgets('和別週交換 in the picker: to a day nobody is on, moves them; nobody told yet', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await tester.tap(cell('司琴', 4));
    await settle(tester);
    await tester.tap(find.text('和別週交換'));
    await settle(tester);
    expect(find.text('和誰交換司琴？'), findsOneWidget);
    await tester.tap(find.text('10月11日 週日').last);
    await settle(tester);
    expect(peopleOn(b, 4, '司琴'), isEmpty);
    expect(peopleOn(b, 11, '司琴'), ['李美玉']);
    expect(findShown('已把「李美玉」移到 10月11日 週日'), findsOneWidget);
    expect(waiting(b), {'mei'});

    await tester.tap(find.text('復原'));
    await settle(tester);
    expect(peopleOn(b, 4, '司琴'), ['李美玉']);
    expect(peopleOn(b, 11, '司琴'), isEmpty);
    expect(waiting(b), isEmpty);
  });

  testWidgets('dragging a cell onto another day of the duty trades them', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await drag(tester, cell('招待', 4), cell('招待', 11));
    expect(peopleOn(b, 4, '招待'), ['李美玉']);
    expect(peopleOn(b, 11, '招待'), ['陳志豪', '李美玉']);
    expect(findShown('已交換「陳志豪、李美玉」和「李美玉」'), findsOneWidget);
    // 李美玉 招待 both days, as before: only 陳志豪 has news.
    expect(waiting(b), {'hao'});
  });

  testWidgets('a cell dropped on another duty, or let go of where it was, changes nothing', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await drag(tester, cell('司琴', 4), cell('招待', 11));
    await drag(tester, cell('司琴', 4), cell('司琴', 4));
    expect(peopleOn(b, 4, '司琴'), ['李美玉']);
    expect(peopleOn(b, 11, '司琴'), isEmpty);
    expect(peopleOn(b, 11, '招待'), ['李美玉']);
    expect(waiting(b), isEmpty);
  });
  testWidgets('held at the bottom, the table scrolls on; let go, it lands under the finger', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    // Six months: more than the screen holds.
    final rows = find.byKey(const PageStorageKey('plan-sunday'));
    await tester.scrollUntilVisible(find.text('顯示更多'), 300, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('顯示更多'));
    await settle(tester);
    await tester.drag(rows, const Offset(0, 5000));
    await settle(tester);
    final table = tester.getRect(rows);
    final edge = Offset(tester.getCenter(cell('司琴', 4)).dx, table.bottom - 4);
    final gesture = await tester.startGesture(tester.getCenter(cell('司琴', 4)));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(edge);
    final under = find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          (w.properties.label?.startsWith('司琴, ') ?? false) &&
          tester.getRect(find.byWidget(w)).contains(edge),
    );
    // The day under the finger, if a day (not a month's name).
    Day? there() {
      if (under.evaluate().length != 1) return null;
      final label = tester.widget<Semantics>(under).properties.label!;
      final [month, date] = [for (final m in RegExp(r'\d+').allMatches(label)) int.parse(m[0]!)];
      return Day(2026, month, date);
    }

    // The finger stays put; the table scrolls under it till a later day
    // is there.
    final first = there();
    bool scrolledOn() => there() != null && (first == null || there()!.isAfter(first));
    for (var i = 0; i < 40 && !scrolledOn(); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(scrolledOn(), isTrue);
    final day = there()!;
    await gesture.up();
    await settle(tester);
    final landed = b.rosters['grace']![Roster.idFor('sunday', day)]!;
    expect(landed.duties.firstWhere((d) => d.role == '司琴').people, ['李美玉']);
    expect(peopleOn(b, 4, '司琴'), isEmpty);
  });
}
