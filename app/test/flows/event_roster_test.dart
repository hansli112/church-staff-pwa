import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
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

final party = CalendarEvent(
  id: 'xmas',
  title: '聖誕晚會',
  start: DateTime(2026, 10, 9, 19),
  end: DateTime(2026, 10, 9, 21),
);

/// [seededChurch] with its calendar connected and [party] on it.
MemoryBackend church({Member as = pastor, Roster? saved, DateTime Function() clock = testClock}) {
  final b = seededChurch(as: as, extra: const [calendarEditor], clock: clock);
  b.connectCalendar('grace', calendarName: '教會行事曆');
  b.calendarEvents['grace'] = [party];
  if (saved != null) b.rosters['grace']![saved.id] = saved;
  return b;
}

Roster partyRoster(List<Duty> duties) => Roster(
  type: '',
  day: Day(2026, 10, 9),
  duties: duties,
  forEvent: RosterEvent(eventId: 'xmas', title: '聖誕晚會', lastDay: Day(2026, 10, 9)),
);

void main() {
  testWidgets('a roster editor of any 牧區 arranges an event from the calendar', (tester) async {
    final b = church(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tapText(tester, '聖誕晚會');
    await tapText(tester, '安排服事');
    expect(find.text('還沒有服事項目'), findsOneWidget);
    expect(b.rosters['grace']!.containsKey('ev_xmas'), isFalse, reason: 'nothing saved until a change');

    await tester.tap(find.byTooltip('編輯'));
    await settle(tester);
    await tapText(tester, '新增服事項目');
    // Every service's duties are offered.
    expect(find.text('司琴'), findsOneWidget);
    await tapText(tester, '司琴');
    expect(b.rosters['grace']!['ev_xmas']!.duties.map((d) => d.role), ['司琴']);

    // 李美玉 plays 司琴 on Sundays: she is first, though the event is in no 牧區.
    await tapText(tester, '司琴');
    await tapText(tester, '李美玉');
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    final duty = b.rosters['grace']!['ev_xmas']!.duties.single;
    expect(duty.people, ['李美玉']);
    expect(duty.uids, {'李美玉': 'mei'});
  });

  testWidgets('everyone sees how many serve on the event, and opens it read-only', (tester) async {
    await pumpApp(
      tester,
      church(
        as: staffHao,
        saved: partyRoster(const [
          Duty(role: '主持', people: ['李美玉'], uids: {'李美玉': 'mei'}),
          Duty(role: '招待', people: ['李美玉', '陳志豪'], uids: {'李美玉': 'mei', '陳志豪': 'hao'}),
        ]),
      ),
    );
    await go(tester, '/calendar');
    await tapText(tester, '聖誕晚會');
    expect(find.text('2 人'), findsOneWidget);
    await tapText(tester, '服事表');
    expect(find.text('主持'), findsOneWidget);
    expect(find.byTooltip('編輯'), findsNothing);
  });

  testWidgets('staff are not offered to arrange an event without a roster', (tester) async {
    await pumpApp(tester, church(as: staffHao));
    await go(tester, '/calendar');
    await tapText(tester, '聖誕晚會');
    expect(find.text('安排服事'), findsNothing);
    expect(find.byIcon(Icons.people_outline), findsNothing, reason: 'no 服事表 row');
  });

  testWidgets('going to the roster from the editor keeps what was changed there', (tester) async {
    final b = church(
      as: calendarEditor,
      saved: partyRoster(const [Duty(role: '主持')]),
    );
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tapText(tester, '聖誕晚會');
    await tester.enterText(find.byType(TextField).first, '聖誕感恩晚會');
    await tester.pump();
    await tapText(tester, '服事表');
    expect(b.calendarEvents['grace']!.single.title, '聖誕感恩晚會');
    expect(b.rosters['grace']!['ev_xmas']!.forEvent!.title, '聖誕感恩晚會');
    expect(find.text('主持'), findsOneWidget);
  });

  testWidgets('a calendar editor finds the roster in the editor too', (tester) async {
    await pumpApp(
      tester,
      church(
        as: calendarEditor,
        saved: partyRoster(const [Duty(role: '主持')]),
      ),
    );
    await go(tester, '/calendar');
    await tapText(tester, '聖誕晚會');
    expect(find.text('編輯活動'), findsOneWidget);
    await tapText(tester, '服事表');
    expect(find.text('主持'), findsOneWidget);
  });

  testWidgets('沿用 copies another event’s duties, not its people, with undo', (tester) async {
    final b = church();
    b.rosters['grace']!['ev_old'] = Roster(
      type: '',
      day: Day(2025, 12, 24),
      duties: const [
        Duty(role: '主持', people: ['王牧師'], uids: {'王牧師': 'pastor'}),
        Duty(role: '報到'),
      ],
      forEvent: RosterEvent(eventId: 'old', title: '去年聖誕晚會', lastDay: Day(2025, 12, 24)),
    );
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tapText(tester, '聖誕晚會');
    // The pastor edits the calendar: the row is in the editor.
    await tapText(tester, '安排服事');
    await tester.tap(find.byTooltip('編輯'));
    await settle(tester);
    await tapText(tester, '沿用其他活動');
    await tapText(tester, '去年聖誕晚會');
    final r = b.rosters['grace']!['ev_xmas']!;
    expect(r.duties, const [Duty(role: '主持'), Duty(role: '報到')]);
    await tapText(tester, '復原');
    expect(b.rosters['grace']!.containsKey('ev_xmas'), isFalse, reason: 'it was a draft nobody else touched');
  });

  testWidgets('a two-day event stays in 我的服事 on its second day', (tester) async {
    final retreat = Roster(
      type: '',
      day: Day(2026, 10, 9),
      duties: const [
        Duty(role: '報到', people: ['李美玉'], uids: {'李美玉': 'mei'}),
      ],
      forEvent: RosterEvent(eventId: 'camp', title: '秋季退修會', lastDay: Day(2026, 10, 10)),
    );
    await pumpApp(tester, church(as: staffMei, saved: retreat, clock: () => DateTime(2026, 10, 10, 9)));
    expect(find.textContaining('秋季退修會'), findsOneWidget);
  });

  testWidgets('a day of a recurring event starts with the last day’s duties, and records its calendar', (tester) async {
    final b = church(as: editor);
    final pray = CalendarEvent(
      id: 'pray_20261008',
      title: '禱告會',
      start: DateTime(2026, 10, 8, 19, 30),
      end: DateTime(2026, 10, 8, 21),
      recurringEventId: 'pray',
    );
    b.calendarEvents['grace'] = [pray];
    b.rosters['grace']!['ev_pray_20260910'] = Roster(
      type: '',
      day: Day(2026, 9, 10),
      duties: const [
        Duty(role: '領禱', people: ['王牧師']),
      ],
      forEvent: RosterEvent(
        eventId: 'pray_20260910',
        title: '禱告會',
        lastDay: Day(2026, 9, 10),
        recurringEventId: 'pray',
      ),
    );
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tapText(tester, '禱告會');
    await tapText(tester, '安排服事');
    expect(find.text('領禱'), findsOneWidget);
    expect(find.text('王牧師'), findsNothing, reason: 'the duties, not the people');

    await tapText(tester, '領禱');
    await tapText(tester, '林同工');
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    final saved = b.rosters['grace']!['ev_pray_20261008']!;
    expect(saved.forEvent!.calendarId, 'cal-grace');
    expect(saved.forEvent!.recurringEventId, 'pray');
  });
}
