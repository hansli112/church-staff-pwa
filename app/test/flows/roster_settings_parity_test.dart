import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/core/design/components.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> go(WidgetTester tester, String route) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(route);
  await settle(tester);
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(findShown(text).last);
  await settle(tester);
}

TextSpan shownName(WidgetTester tester, String name) {
  final text = tester.widget<RichText>(find.text(name, findRichText: true));
  TextSpan? found;
  text.text.visitChildren((span) {
    if (span is TextSpan && span.text == name) found = span;
    return true;
  });
  return found!;
}

void main() {
  testWidgets('a guest future-removal menu opens a cancellable preview before changing any day', (tester) async {
    final b = seededChurch(as: editor);
    final first = savedDay(b, 4).copyWith(
      duties: const [
        Duty(role: '司琴', people: ['外請老師']),
      ],
    );
    final next = savedDay(b, 11).copyWith(
      duties: const [
        Duty(role: '司琴', people: ['外請老師']),
      ],
    );
    b.rosters['grace']![first.id] = first;
    b.rosters['grace']![next.id] = next;
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-04');
    await tapText(tester, '外請老師');
    await tapText(tester, '移除未來的外請安排');

    expect(find.text('移除「外請老師」的未來安排'), findsOneWidget);
    expect(find.textContaining('10月11日'), findsOneWidget);
    expect(savedDay(b, 4), first);
    expect(savedDay(b, 11), next);
    await tapText(tester, '取消');
    expect(savedDay(b, 4), first);

    await tapText(tester, '外請老師');
    await tapText(tester, '移除未來的外請安排');
    await tapText(tester, '套用變更');
    expect(savedDay(b, 4).duties.single.people, isEmpty);
    expect(savedDay(b, 11).duties.single.people, isEmpty);
    await tapText(tester, '復原');
    expect(savedDay(b, 4), first);
    expect(savedDay(b, 11), next);
  });

  testWidgets('an admin edits an existing common-event color without altering assignments', (tester) async {
    final b = seededChurch();
    final arranged = savedDay(b, 4);
    await pumpApp(tester, b);
    await go(tester, '/me/services/sunday');
    await tester.scrollUntilVisible(find.text('聖餐'), 300);
    await tapText(tester, '聖餐');
    await tapText(tester, '顏色');
    await tapText(tester, '藍');

    expect(b.services['grace']!.byId('sunday')!.events.single.color, 4);
    expect(savedDay(b, 4), arranged);
    await tapText(tester, '復原');
    expect(b.services['grace']!.byId('sunday')!.events.single.color, 0);
  });

  testWidgets('common-event options can move in both directions without reordering existing tags', (tester) async {
    final b = seededChurch();
    b.setServices('grace', [
      sundayService.copyWith(
        events: const [
          EventTag(name: '聖餐', color: 0),
          EventTag(name: '浸禮', color: 4),
        ],
      ),
      youthService,
    ]);
    final arranged = savedDay(b, 4);
    await pumpApp(tester, b);
    await go(tester, '/me/services/sunday');
    await tester.scrollUntilVisible(find.text('浸禮'), 300);
    final baptism = find.ancestor(of: find.text('浸禮'), matching: find.byType(ListRow));
    await tester.tap(find.descendant(of: baptism, matching: find.byTooltip('上移')));
    await settle(tester);

    expect(b.services['grace']!.byId('sunday')!.events.map((e) => e.name), ['浸禮', '聖餐']);
    expect(savedDay(b, 4), arranged);
    final moved = find.ancestor(of: find.text('浸禮'), matching: find.byType(ListRow));
    await tester.tap(find.descendant(of: moved, matching: find.byTooltip('下移')));
    await settle(tester);
    expect(b.services['grace']!.byId('sunday')!.events.map((e) => e.name), ['聖餐', '浸禮']);
  });

  testWidgets('renaming a duty offers a separate future preview, applies only on request and undoes the bulk change', (
    tester,
  ) async {
    final b = seededChurch();
    final historic = savedDay(b, 4).copyWith(day: Day(2026, 9, 27));
    b.rosters['grace']![historic.id] = historic;
    final arranged = savedDay(b, 4);
    await pumpApp(tester, b);
    await go(tester, '/me/services/sunday');
    await tapText(tester, '司琴');
    await tapText(tester, '改名');
    await tester.enterText(find.byType(TextField), '鋼琴');
    await tapText(tester, '儲存');

    expect(find.text('同步「司琴」為「鋼琴」'), findsOneWidget);
    expect(b.services['grace']!.byId('sunday')!.duties, ['司會', '鋼琴', '招待']);
    expect(savedDay(b, 4), arranged, reason: 'renaming settings never silently rewrites assignments');
    await tapText(tester, '套用變更');
    expect(savedDay(b, 4).duties[1].role, '鋼琴');
    expect(savedDay(b, 4).duties[1].uids, {'李美玉': 'mei'});
    expect(b.rosters['grace']![historic.id], historic);
    await tapText(tester, '復原');
    expect(savedDay(b, 4), arranged);
    expect(
      b.services['grace']!.byId('sunday')!.duties,
      contains('鋼琴'),
      reason: 'the explicit bulk change has its own undo',
    );
  });

  testWidgets('cancelled future synchronization can be previewed again from the renamed option', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me/services/sunday');
    await tapText(tester, '司琴');
    await tapText(tester, '改名');
    await tester.enterText(find.byType(TextField), '鋼琴');
    await tapText(tester, '儲存');
    await tapText(tester, '取消');
    expect(savedDay(b, 4).duties[1].role, '司琴');

    await tapText(tester, '鋼琴');
    await tapText(tester, '同步未來服事表');
    await tapText(tester, '司琴');
    expect(find.text('同步「司琴」為「鋼琴」'), findsOneWidget);
    await tapText(tester, '套用變更');
    expect(savedDay(b, 4).duties[1].role, '鋼琴');
  });

  testWidgets('common-event renaming no longer silently rewrites arranged days', (tester) async {
    final b = seededChurch();
    final arranged = savedDay(b, 4);
    await pumpApp(tester, b);
    await go(tester, '/me/services/sunday');
    await tester.scrollUntilVisible(find.text('聖餐'), 300);
    await tapText(tester, '聖餐');
    await tapText(tester, '改名');
    await tester.enterText(find.byType(TextField), '聖餐主日');
    await tapText(tester, '儲存');

    expect(find.text('同步「聖餐」為「聖餐主日」'), findsOneWidget);
    expect(savedDay(b, 4), arranged);
    await tapText(tester, '取消');
    expect(b.services['grace']!.byId('sunday')!.events.single.name, '聖餐主日');
    expect(savedDay(b, 4), arranged);
    await tapText(tester, '復原');
    expect(b.services['grace']!.byId('sunday')!.events.single.name, '聖餐');
    expect(savedDay(b, 4), arranged);
  });

  testWidgets('ordinary roster editors cannot open settings editing through a direct route', (tester) async {
    await pumpApp(tester, seededChurch(as: editor));
    await go(tester, '/me/services/sunday');
    expect(find.text('聚會名稱'), findsNothing);
    expect(find.text('新增服事項目'), findsNothing);
    expect(find.text('只有管理員能改服事設定'), findsOneWidget);
    await go(tester, '/me/services');
    expect(find.text('新增聚會'), findsNothing);
    expect(find.text('只有管理員能改服事設定'), findsOneWidget);
  });

  testWidgets('a refused swipe removal leaves the configured option visible and reports failure', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me/services/sunday');
    b.failNextWrite = const CloudException(CloudErrorCode.unavailable, reason: CloudReason.offlineReadOnly);
    await tester.drag(find.text('司琴'), const Offset(-500, 0));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('司琴'), findsOneWidget);
    expect(find.text('離線中，連線後才能儲存'), findsOneWidget);
    expect(find.text('復原'), findsNothing);
    expect(b.services['grace']!.byId('sunday')!.duties, contains('司琴'));
  });

  testWidgets('deleting configured duty and common-event options keeps existing assignments', (tester) async {
    final b = seededChurch();
    final arranged = savedDay(b, 4);
    await pumpApp(tester, b);
    await go(tester, '/me/services/sunday');
    await tapText(tester, '司琴');
    await tapText(tester, '移除');
    expect(b.services['grace']!.byId('sunday')!.duties, isNot(contains('司琴')));
    expect(savedDay(b, 4), arranged);
    expect(b.members['grace']!['mei']!.serves('sunday', '司琴'), isTrue);
    await tapText(tester, '復原');
    expect(b.services['grace']!.byId('sunday')!.duties, contains('司琴'));

    await tester.scrollUntilVisible(find.text('聖餐'), 300);
    await tapText(tester, '聖餐');
    await tapText(tester, '移除');
    expect(b.services['grace']!.byId('sunday')!.events, isEmpty);
    expect(savedDay(b, 4), arranged);
    await tapText(tester, '復原');
    expect(b.services['grace']!.byId('sunday')!.events, const [EventTag(name: '聖餐', color: 0)]);
  });

  testWidgets('a rejected settings undo is reported rather than silently ignored', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me/services/sunday');
    await tapText(tester, '司琴');
    await tapText(tester, '移除');
    b.failNextWrite = const CloudException(CloudErrorCode.unavailable);
    await tapText(tester, '復原');

    expect(find.text('復原失敗，請再試一次'), findsOneWidget);
    expect(b.services['grace']!.byId('sunday')!.duties, isNot(contains('司琴')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing people and explicit staff order in one picker keeps both choices', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-04');
    await tapText(tester, '招待');
    await tester.enterText(find.byType(TextField), '新外請');
    await settle(tester);
    await tapText(tester, '用「新外請」');
    await tapText(tester, '調整順序');
    final gesture = await tester.startGesture(tester.getCenter(find.byIcon(Symbols.drag_handle_rounded).first));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await settle(tester);
    await tapText(tester, '完成');
    await tapText(tester, '完成');

    expect(peopleOn(b, 4, '招待'), containsAll(['李美玉', '陳志豪', '新外請']));
    expect(peopleOn(b, 4, '招待').take(2), ['李美玉', '陳志豪']);
    expect(find.textContaining('資料已被其他同工修改'), findsNothing);
  });

  testWidgets('future guest preview remains scrollable and cancellable with large text in dark mode', (tester) async {
    const name = '姓名很長的外請老師姓名很長的外請老師姓名很長的外請老師姓名很長的外請老師';
    final b = seededChurch(as: editor);
    final before = savedDay(b, 4).copyWith(
      duties: const [
        Duty(role: '司琴', people: [name]),
      ],
    );
    b.rosters['grace']![before.id] = before;
    await pumpApp(tester, b, textScale: 3, brightness: Brightness.dark);
    await go(tester, '/rosters/sunday/2026-10-04');
    await tapText(tester, name);
    expect(tester.takeException(), isNull, reason: 'the person menu must also fit large text');
    await tapText(tester, '移除未來的外請安排');

    expect(tester.takeException(), isNull);
    expect(findShown('取消'), findsOneWidget);
    expect(find.text('套用變更'), findsOneWidget);
    await tapText(tester, '取消');
    expect(savedDay(b, 4), before);
  });

  testWidgets('show more adds the next thirteen weeks of drafts in the roster tab', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/rosters');
    await tester.scrollUntilVisible(find.text('顯示更多'), 500);
    await tapText(tester, '顯示更多');

    expect(findDay('1月3日'), findsWidgets);
    expect(b.rosters['grace']!.length, 2, reason: 'extending the view never persists drafts');
    await tester.scrollUntilVisible(find.text('顯示更多'), 500);
    expect(findDay('3月28日'), findsWidgets);
  });

  testWidgets('arranged guest suggestions are reused without guessing a same-name member uid', (tester) async {
    final b = seededChurch();
    final prior = savedDay(b, 4).copyWith(
      duties: const [
        Duty(role: '司琴', people: ['John Chen']),
      ],
    );
    b.rosters['grace']![prior.id] = prior;
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tapText(tester, '司琴');
    expect(find.text('外請名字'), findsOneWidget);
    await tapText(tester, 'John Chen');
    expect(find.text('也讓John Chen負責司琴？'), findsNothing);
    await tapText(tester, '完成');

    final duty = savedDay(b, 11).duties.firstWhere((d) => d.role == '司琴');
    expect(duty.people, ['John Chen']);
    expect(duty.uids, isEmpty);
  });

  testWidgets('readonly service names highlight my bound uid, never a same-text guest', (tester) async {
    final b = seededChurch(as: john);
    final roster = savedDay(b, 4).copyWith(
      duties: const [
        Duty(role: '講道', people: ['John Chen']),
        Duty(role: '招待', people: ['不同顯示姓名'], uids: {'不同顯示姓名': 'john'}),
      ],
    );
    b.rosters['grace']![roster.id] = roster;
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-04');

    expect(shownName(tester, 'John Chen').style?.fontWeight, isNot(FontWeight.w700));
    expect(shownName(tester, '不同顯示姓名').style?.fontWeight, FontWeight.w700);
  });

  testWidgets('readonly event names also highlight only the assigned uid, not a same-text guest', (tester) async {
    final b = seededChurch(as: john);
    final roster = Roster(
      type: '',
      day: Day(2026, 10, 4),
      duties: const [
        Duty(role: '講道', people: ['John Chen']),
        Duty(role: '招待', people: ['不同顯示姓名'], uids: {'不同顯示姓名': 'john'}),
      ],
      forEvent: RosterEvent(eventId: 'identity-event', title: '身分測試活動', lastDay: Day(2026, 10, 4)),
    );
    b.rosters['grace']![roster.id] = roster;
    await pumpApp(tester, b);
    await go(tester, '/rosters/event/identity-event');

    expect(shownName(tester, 'John Chen').style?.fontWeight, isNot(FontWeight.w700));
    expect(shownName(tester, '不同顯示姓名').style?.fontWeight, FontWeight.w700);
  });
}
