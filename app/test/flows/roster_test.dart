import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/features/rosters/roster_card.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

void main() {
  group('viewing', () {
    testWidgets('home lists my upcoming services', (tester) async {
      await pumpApp(tester, seededChurch(as: staffMei));
      expect(find.text('我接下來的服事'), findsOneWidget);
      expect(find.textContaining('10月4日'), findsOneWidget);
      expect(find.textContaining('司琴、招待'), findsOneWidget);
      expect(find.textContaining('10月11日'), findsOneWidget);
    });

    testWidgets("an event's roster shows in 我的服事 by its title and opens; a cancelled one is gone", (tester) async {
      final b = seededChurch(as: staffMei);
      b.rosters['grace']![Roster.idForEvent('x1')] = Roster(
        type: '',
        day: Day(2026, 10, 9),
        duties: const [
          Duty(role: '報到', people: ['李美玉'], uids: {'李美玉': 'mei'}),
        ],
        forEvent: RosterEvent(eventId: 'x1', title: '秋季退修會', lastDay: Day(2026, 10, 10)),
      );
      b.rosters['grace']![Roster.idForEvent('x2')] = Roster(
        type: '',
        day: Day(2026, 10, 9),
        duties: const [
          Duty(role: '主持', people: ['李美玉'], uids: {'李美玉': 'mei'}),
        ],
        forEvent: RosterEvent(eventId: 'x2', title: '取消的活動', lastDay: Day(2026, 10, 9), cancelled: true),
      );
      await pumpApp(tester, b);
      expect(find.textContaining('取消的活動'), findsNothing);
      await tapText(tester, '秋季退修會 · 報到');
      expect(find.text('秋季退修會'), findsOneWidget, reason: 'the title on top');
      expect(find.textContaining('10月10日'), findsOneWidget, reason: 'its last day');
    });

    testWidgets('home with nothing ahead says one sentence', (tester) async {
      await pumpApp(tester, seededChurch(as: john));
      expect(findShown('接下來沒有你的服事，排到你時會出現在這裡'), findsOneWidget);
    });

    testWidgets('roster tab shows saved days and template drafts', (tester) async {
      await pumpApp(tester, seededChurch(as: editor));
      await tapText(tester, '服事表');
      expect(find.text('主日崇拜'), findsOneWidget);
      expect(find.text('青年崇拜'), findsOneWidget);
      expect(find.text('林同工'), findsWidgets);
      // 10/18 is not saved: the template shows with nobody yet.
      await tester.scrollUntilVisible(find.textContaining('10月18日'), 300);
      expect(find.text('待定'), findsWidgets);
    });

    testWidgets('a member sees only their 牧區; one in none is told to ask an admin', (tester) async {
      await pumpApp(tester, seededChurch(as: staffMei));
      await tapText(tester, '服事表');
      expect(find.text('青年崇拜'), findsNothing);
      expect(find.textContaining('10月4日'), findsWidgets);

      await pumpApp(tester, seededChurch(as: john));
      await tapText(tester, '服事表');
      expect(find.text('你還沒有屬於任何牧區，請找管理員設定'), findsOneWidget);
    });

    testWidgets('a change rebuilds only the card it touched', (tester) async {
      final b = seededChurch(as: staffMei);
      await pumpApp(tester, b);
      await tapText(tester, '服事表');
      rosterCardBuilds.clear();
      b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, 11))] = savedDay(b, 11).copyWith(
        events: const [EventTag(name: '浸禮', color: 4)],
      );
      b.notify();
      await settle(tester);
      expect(rosterCardBuilds.keys, [Roster.idFor('sunday', Day(2026, 10, 11))]);
    });

    testWidgets('staff without permission get no edit controls', (tester) async {
      await pumpApp(tester, seededChurch(as: staffMei));
      await go(tester, '/rosters/sunday/2026-10-04');
      expect(find.byTooltip('編輯'), findsNothing);
      expect(find.textContaining('陳志豪', findRichText: true), findsOneWidget);
      await tester.tap(find.textContaining('陳志豪', findRichText: true));
      await settle(tester);
      expect(find.text('交換'), findsNothing);
    });

    testWidgets('a roster editor can only edit their own zone', (tester) async {
      await pumpApp(tester, seededChurch(as: editor));
      await go(tester, '/rosters/sunday/2026-10-04');
      expect(find.byTooltip('編輯'), findsOneWidget);
      await go(tester, '/rosters/youth/2026-10-03');
      expect(find.byTooltip('編輯'), findsNothing);
    });
  });

  group('arranging', () {
    testWidgets('picker lists people who serve the duty, in staff order', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '招待');
      expect(find.text('有這項服事'), findsOneWidget);
      final hao = tester.getTopLeft(find.text('陳志豪').last).dy;
      final mei = tester.getTopLeft(find.text('李美玉').last).dy;
      expect(hao < mei, isTrue, reason: 'staff order puts 陳志豪 first');
      expect(find.text('John Chen'), findsNothing, reason: 'does not serve 招待');

      await tapText(tester, '陳志豪');
      await tapText(tester, '完成');
      expect(peopleOn(b, 11, '招待'), ['陳志豪', '李美玉']);
      expect(find.text('已更新招待'), findsOneWidget);
    });

    testWidgets('search finds other members ignoring width and case, and can give them the duty', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '司琴');
      await tester.enterText(find.byType(TextField), 'ｊｏｈｎ');
      await settle(tester);
      expect(find.text('其他同工'), findsOneWidget);
      await tapText(tester, 'John Chen');
      expect(find.text('也讓John Chen負責司琴？'), findsOneWidget);
      await tapText(tester, '加上');
      await tapText(tester, '完成');

      expect(peopleOn(b, 11, '司琴'), ['John Chen']);
      expect(b.members['grace']!['john']!.serves('sunday', '司琴'), isTrue);

      // Next time he is in the upper section without searching.
      await go(tester, '/rosters/sunday/2026-10-04');
      await tapText(tester, '司琴');
      expect(find.text('John Chen'), findsOneWidget);
      expect(find.text('其他同工'), findsNothing);
    });

    testWidgets('when nobody serves the duty yet, everyone is listed to pick from', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/youth/2026-10-10');
      await tapText(tester, '司會');
      expect(find.text('還沒有人負責司會'), findsOneWidget);
      expect(find.text('其他同工'), findsOneWidget);
      await tapText(tester, 'John Chen');
      await tapText(tester, '加上');
      await tapText(tester, '完成');
      expect(b.members['grace']!['john']!.serves('youth', '司會'), isTrue);
    });

    testWidgets('no search results is one sentence; a typed name can be used', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '司琴');
      await tester.enterText(find.byType(TextField), '外請講員');
      await settle(tester);
      expect(find.text('用「外請講員」'), findsOneWidget);
      await tapText(tester, '用「外請講員」');
      await tapText(tester, '完成');
      expect(peopleOn(b, 11, '司琴'), ['外請講員']);
      expect(savedDay(b, 11).duties[1].uids, isEmpty);
    });

    testWidgets('the search box gets focus once the church has more than 30 people', (tester) async {
      final many = [for (var i = 0; i < 30; i++) Member(uid: 'x$i', name: '同工$i')];
      await pumpApp(tester, seededChurch(extra: many));
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '司琴');
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autofocus, isTrue);
    });

    testWidgets('removing a duty can be undone', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-04');
      await tester.drag(find.text('司琴').first, const Offset(-500, 0));
      await settle(tester);
      expect(savedDay(b, 4).duties.map((d) => d.role), ['司會', '招待']);
      await tapText(tester, '復原');
      expect(savedDay(b, 4).duties.map((d) => d.role), ['司會', '司琴', '招待']);
    });

    testWidgets('editing a draft saves it; undo returns it to the template', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-18');
      await tapText(tester, '招待');
      await tapText(tester, '李美玉');
      await tapText(tester, '完成');
      expect(peopleOn(b, 18, '招待'), ['李美玉']);
      await tapText(tester, '復原');
      expect(b.rosters['grace']!.containsKey(Roster.idFor('sunday', Day(2026, 10, 18))), isFalse);
    });

    testWidgets('a deleted account keeps its name on the roster', (tester) async {
      final b = seededChurch(as: staffMei);
      await b.cloud.deleteAccount();
      expect(peopleOn(b, 4, '司琴'), ['李美玉']);
    });
  });

  group('undo and offline', () {
    testWidgets('undo restores only its duty, keeping another editor\'s change', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-04');
      await tapText(tester, '司琴');
      await tapText(tester, '李美玉');
      await tapText(tester, '完成');
      expect(peopleOn(b, 4, '司琴'), isEmpty);
      // Someone else changes 司會 on the same day.
      b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, 4))] = Roster(
        type: 'sunday',
        day: Day(2026, 10, 4),
        events: savedDay(b, 4).events,
        duties: [
          for (final d in savedDay(b, 4).duties)
            d.role == '司會' ? const Duty(role: '司會', people: ['王牧師'], uids: {'王牧師': 'pastor'}) : d,
        ],
      );
      b.notify();
      await settle(tester);
      await tapText(tester, '復原');
      expect(peopleOn(b, 4, '司琴'), ['李美玉']);
      expect(peopleOn(b, 4, '司會'), ['王牧師']);
    });

    testWidgets('a slow (offline) write still answers, saying it will sync', (tester) async {
      final b = seededChurch()..writeDelay = const Duration(seconds: 5);
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-04');
      await tapText(tester, '司琴');
      await tapText(tester, '李美玉');
      await tapText(tester, '完成');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('已存在這台裝置，連上網路後會自動同步'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await settle(tester);
    });
  });

  group('swap', () {
    testWidgets('swaps two people in one write, and undo is one write', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-04');
      await tester.tap(find.text('陳志豪'));
      await settle(tester);
      await tapText(tester, '交換');
      expect(find.text('和誰交換招待？'), findsOneWidget);
      // 李美玉 already serves 招待 on 10/4, so 10/11 offers nobody to swap
      // with; draft weeks offer an empty slot.
      final sheet = find.byType(BottomSheet);
      expect(find.descendant(of: sheet, matching: find.text('李美玉')), findsNothing);
      await tester.tap(find.descendant(of: sheet, matching: find.text('空著')).first);
      await settle(tester);

      expect(peopleOn(b, 4, '招待'), ['李美玉']);
      expect(find.textContaining('已把 陳志豪 移到'), findsOneWidget);
      await tapText(tester, '復原');
      expect(peopleOn(b, 4, '招待'), ['陳志豪', '李美玉']);
    });

    testWidgets('a failed write leaves both days as they were', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tester.tap(find.text('王牧師'));
      await settle(tester);
      await tapText(tester, '交換');
      b.failNextWrite = Exception('offline');
      await tapText(tester, '林同工');
      expect(peopleOn(b, 4, '司會'), ['林同工']);
      expect(peopleOn(b, 11, '司會'), ['王牧師']);
      expect(find.text('沒有儲存成功，請檢查網路後再試一次'), findsOneWidget);
    });

    testWidgets('nobody to swap with says so in one sentence', (tester) async {
      // A service that no longer runs has no drafts; with one saved day
      // there is nobody to swap with.
      final b = seededChurch();
      b.setServices('grace', [sundayService.copyWith(enabled: false), youthService]);
      b.rosters['grace']!.remove(Roster.idFor('sunday', Day(2026, 10, 11)));
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-04');
      await tester.tap(find.text('李美玉').first);
      await settle(tester);
      await tapText(tester, '交換');
      expect(find.text('其他日期沒有可以交換的人'), findsOneWidget);
    });
  });

  group('special events', () {
    testWidgets('tick a common event and add a custom one to the common list', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tester.tap(find.byTooltip('編輯'));
      await settle(tester);
      await tapText(tester, '特別活動');
      await tapText(tester, '聖餐');
      await tester.enterText(find.byType(TextField), '特會');
      await tapText(tester, '加入常用選項');
      await tapText(tester, '新增');
      await tapText(tester, '完成');
      expect(savedDay(b, 11).events.map((e) => e.name), ['聖餐', '特會']);
      expect(b.services['grace']!.byId('sunday')!.events.map((e) => e.name), ['聖餐', '特會']);
      expect(find.text('已更新特別活動'), findsOneWidget);
    });

    testWidgets('closing the sheet without a change saves nothing', (tester) async {
      await pumpApp(tester, seededChurch());
      await go(tester, '/rosters/sunday/2026-10-04');
      await tester.tap(find.byTooltip('編輯'));
      await settle(tester);
      await tapText(tester, '特別活動');
      await tapText(tester, '完成');
      expect(find.text('復原'), findsNothing);
    });

    testWidgets('ticking an event off and on again is no change', (tester) async {
      final b = seededChurch();
      final day = savedDay(b, 4);
      const events = [EventTag(name: '聖餐', color: 0), EventTag(name: '浸禮', color: 4)];
      b.rosters['grace']![day.id] = day.copyWith(events: events);
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-04');
      await tester.tap(find.byTooltip('編輯'));
      await settle(tester);
      await tapText(tester, '特別活動');
      await tapText(tester, '聖餐');
      await tapText(tester, '聖餐');
      await tapText(tester, '完成');
      expect(find.text('復原'), findsNothing);
      expect(savedDay(b, 4).events, events);
    });
  });
}
