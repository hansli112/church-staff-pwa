import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../support/harness.dart';
import '../support/seed.dart';

// A duty's 負責人: 李美玉 leads 主日崇拜's 司琴.
MemoryBackend withWorship() => seededChurch(
  extra: [
    staffMei.withIdentities(const [DutyLead('sunday', '司琴')]),
  ],
  as: staffMei,
);

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

Future<void> go(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await settle(tester);
}

void main() {
  testWidgets('arranges the duty they lead; the rest of the day only shows', (tester) async {
    final b = withWorship();
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-11');

    // 司會 is someone else's: tapping it opens nothing.
    await tester.tap(find.text('司會'));
    await settle(tester);
    expect(find.text('完成'), findsNothing);

    await tapText(tester, '司琴');
    await tester.enterText(find.byType(TextField), '陳志豪');
    await settle(tester);
    await tapText(tester, '陳志豪');
    expect(peopleOn(b, 11, '司琴'), ['陳志豪']);
    expect(find.text('已更新司琴'), findsOneWidget);
    expect(peopleOn(b, 11, '司會'), ['王牧師'], reason: 'untouched');
  });

  testWidgets("swipes someone off its duty's list, but leaves the staff order alone", (tester) async {
    final b = withWorship();
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tapText(tester, '司琴');
    await tapText(tester, '選取');
    expect(find.byIcon(Symbols.drag_handle_rounded), findsNothing, reason: "the order is the service's");
    await tester.drag(find.byKey(const ValueKey('off/李美玉')), const Offset(-500, 0));
    await settle(tester);
    await tapText(tester, '完成');
    expect(b.members['grace']!['mei']!.zones.single.duties, ['招待']);
    expect(find.text('已把李美玉移出司琴名單'), findsOneWidget);
  });

  testWidgets('adds only the duty they lead, and does not tag the day', (tester) async {
    final b = withWorship();
    b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, 11))] = savedDay(b, 11).copyWith(
      duties: [
        for (final d in savedDay(b, 11).duties)
          if (d.role != '司琴') d,
      ],
    );
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-11');
    expect(find.text('特別活動'), findsNothing);
    await tapText(tester, '新增服事項目');
    expect(find.byType(TextField), findsNothing, reason: 'only what 敬拜團 leads');
    await tapText(tester, '司琴');
    expect(savedDay(b, 11).duties.map((d) => d.role), contains('司琴'));
  });

  testWidgets('sees the service its duty is in on the 服事表 tab', (tester) async {
    final b = withWorship();
    b.members['grace']!['mei'] = b.members['grace']!['mei']!.copyWith(zones: const []);
    await pumpApp(tester, b);
    await tapText(tester, '服事表');
    expect(find.text('你還沒加入任何聚會，請找管理員設定'), findsNothing);
  });

  testWidgets('a name nobody has, importing, is arranged this once: adding 同工 is not its to do', (tester) async {
    final b = withWorship();
    b.users['mei'] = b.users['mei']!.copyWith(photoAiConsent: true);
    await pumpApp(tester, b);
    await go(tester, '/rosters/import/sunday');
    await tapText(tester, '進階');
    await tester.ensureVisible(find.byType(TextField).last);
    await tester.pump();
    await tester.enterText(
      find.byType(TextField),
      jsonEncode([
        {
          'date': '2026-10-18',
          'duties': [
            {
              'role': '司琴',
              'people': ['小芬'],
            },
          ],
        },
      ]),
    );
    await tester.scrollUntilVisible(find.text('預覽'), 200, scrollable: find.byType(Scrollable).first);
    await tapText(tester, '預覽');
    await tapText(tester, '找不到這個人');
    expect(find.text('新增同工「小芬」'), findsNothing);
    await tapText(tester, '臨時排「小芬」');
    await tapText(tester, '套用到服事表');
    expect(b.pendingMembers['grace'] ?? const {}, isEmpty);
  });

  testWidgets('imports only the duty they lead, merged into the day', (tester) async {
    final b = withWorship();
    b.users['mei'] = b.users['mei']!.copyWith(photoAiConsent: true);
    await pumpApp(tester, b);
    await go(tester, '/rosters/import/sunday');
    await tapText(tester, '進階');
    await tester.ensureVisible(find.byType(TextField).last);
    await tester.pump();
    await tester.enterText(
      find.byType(TextField),
      jsonEncode([
        {
          'date': '2026-10-11',
          'duties': [
            {
              'role': '司會',
              'people': ['陳志豪'],
            },
            {
              'role': '司琴',
              'people': ['陳志豪'],
            },
          ],
          'events': [
            {'name': '聖餐', 'color': 0},
          ],
        },
      ]),
    );
    await tester.scrollUntilVisible(find.text('預覽'), 200, scrollable: find.byType(Scrollable).first);
    await tapText(tester, '預覽');
    expect(find.text('取代當天全部安排'), findsNothing);
    await tester.scrollUntilVisible(find.text('套用到服事表'), 300);
    await tapText(tester, '套用到服事表');
    expect(peopleOn(b, 11, '司琴'), ['陳志豪']);
    expect(peopleOn(b, 11, '司會'), ['王牧師'], reason: 'not 敬拜團’s');
    expect(savedDay(b, 11).events, isEmpty);
  });
}
