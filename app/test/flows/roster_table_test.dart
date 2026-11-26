import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/features/rosters/roster_image.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../support/harness.dart';
import '../support/seed.dart';

// 表格: a service's days as the table 安排服事 has, every duty, to look at,
// for whoever does not arrange all of it. The tests start on Thursday
// 1 October 2026: 10/4 has 陳志豪 on 招待.

Future<void> go(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await settle(tester);
}

String path(WidgetTester tester) => GoRouter.of(tester.element(find.byType(Scaffold).last)).state.uri.path;

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

/// The cell of [role] on October [date].
Finder cell(String role, int date) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == '$role, 10月$date日 週日',
);

SemanticsProperties props(WidgetTester tester, Finder f) => tester.widget<Semantics>(f).properties;

/// 敬拜團 links 主日崇拜's 司琴, and 李美玉 leads it.
const worship = Ministry(id: 'worship', name: '敬拜團');

void main() {
  testWidgets('who arranges none of it opens 表格 from 服事表: every duty, their own marked, nothing to pick', (
    tester,
  ) async {
    await pumpApp(tester, seededChurch(as: staffHao));
    await go(tester, '/rosters');
    expect(find.text('安排服事'), findsNothing);
    await tapText(tester, '表格');
    expect(path(tester), '/rosters/table/sunday');

    for (final duty in ['司會', '司琴', '招待']) {
      expect(find.text(duty), findsOneWidget, reason: 'every duty a column');
    }
    expect(props(tester, cell('招待', 4)).value, '陳志豪、李美玉');
    expect(props(tester, cell('招待', 4)).selected, isTrue, reason: 'his own');
    expect(props(tester, cell('司會', 4)).selected, isFalse);
    expect(props(tester, cell('司琴', 11)).value, '待定');
    expect(find.text('完成'), findsNothing);

    await tester.tap(cell('招待', 11));
    await settle(tester);
    expect(find.byType(BottomSheet), findsNothing, reason: 'only to look at');
    expect(path(tester), '/rosters/table/sunday');

    await tester.tap(find.byTooltip('分享成圖片'));
    await settle(tester);
    final picture = find.byType(RosterImage);
    expect(
      find.descendant(of: picture, matching: find.text('司會')),
      findsOneWidget,
      reason: 'every duty too',
    );
    expect(find.descendant(of: picture, matching: find.text('招待')), findsOneWidget);
  });

  testWidgets('opening, the table has the months that fill the screen at once, not built again as it slides in', (
    tester,
  ) async {
    await pumpApp(tester, seededChurch(as: staffHao));
    await go(tester, '/rosters');
    await tester.tap(find.text('表格').last);
    // Built first offstage, as a page being pushed is.
    final table = find.byType(TableView, skipOffstage: false);
    do {
      await tester.pump(const Duration(milliseconds: 16));
    } while (table.evaluate().isEmpty);
    final first = tester.widget(table);
    await settle(tester);
    expect(tester.widget(table), same(first), reason: 'no months joined on after the first layout');
  });

  testWidgets('a date opens its day', (tester) async {
    await pumpApp(tester, seededChurch(as: staffHao));
    await go(tester, '/rosters/table/sunday');
    await tester.tap(
      find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '打開 10月4日 週日'),
    );
    await settle(tester);
    expect(path(tester), '/rosters/sunday/2026-10-04');
  });

  testWidgets("a 事工's 負責人 opens 看整張服事表 from 安排服事's ⋯, last, after what arranging does", (tester) async {
    final b = seededChurch(
      extra: [
        staffMei.withIdentities(const [DutyLead('sunday', '司琴')]),
      ],
      as: staffMei,
    );
    b.ministries['grace'] = const MinistrySettings(ministries: [worship], ids: ['worship']);
    await pumpApp(tester, b);
    await go(tester, '/rosters');
    expect(find.text('表格'), findsNothing, reason: '安排服事 is there instead');
    await tapText(tester, '安排服事');
    expect(find.text('司會'), findsNothing, reason: 'only 司琴 to arrange');
    await tester.tap(find.byIcon(Symbols.more_horiz_rounded));
    await settle(tester);
    double at(String text) => tester.getTopLeft(find.text(text)).dy;
    final ys = [at('請同工填不能服事日'), at('從照片匯入'), at('分享成圖片'), at('看整張服事表')];
    expect(ys, orderedEquals([...ys]..sort()), reason: 'before arranging, while, after; then to look at');
    await tapText(tester, '看整張服事表');
    expect(path(tester), '/rosters/table/sunday');
    expect(find.text('司會'), findsOneWidget);
    expect(props(tester, cell('司琴', 4)).selected, isTrue, reason: 'hers');
  });

  testWidgets('who arranges all of it has neither', (tester) async {
    await pumpApp(tester, seededChurch());
    await go(tester, '/rosters');
    expect(find.text('表格'), findsNothing);
    await tapText(tester, '安排服事');
    await tester.tap(find.byIcon(Symbols.more_horiz_rounded));
    await settle(tester);
    expect(find.text('看整張服事表'), findsNothing, reason: 'the table it is in has it all');
  });
}
