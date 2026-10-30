import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/design/tokens.dart';
import 'package:martha/data/memory/memory_backend.dart';
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
      expect(findDay('10月4日'), findsOneWidget);
      expect(find.textContaining('司琴、招待'), findsOneWidget);
      expect(findDay('10月11日'), findsOneWidget);
      expect(find.text('主日崇拜'), findsWidgets, reason: 'each day is titled by its service');
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
      expect(findShownContaining('10月10日'), findsOneWidget, reason: 'both days');
      await tapText(tester, '秋季退修會');
      expect(find.text('秋季退修會'), findsOneWidget, reason: 'the title on top');
      expect(find.textContaining('10月10日'), findsOneWidget, reason: 'its last day');
    });

    testWidgets('home with nothing ahead says one sentence', (tester) async {
      await pumpApp(tester, seededChurch(as: john));
      expect(findShown('接下來沒有你的服事，排到你時會出現在這裡'), findsOneWidget);
    });

    testWidgets('roster tab shows saved days and template drafts', (tester) async {
      await pumpApp(tester, seededChurch(as: pastor));
      await tapText(tester, '服事表');
      expect(find.text('主日崇拜'), findsOneWidget);
      expect(find.text('青年崇拜'), findsOneWidget);
      expect(find.text('林同工'), findsWidgets);
      // 10/18 is not saved: the template shows with nobody yet.
      await tester.scrollUntilVisible(findDay('10月18日'), 300);
      expect(find.text('待定'), findsWidgets);
    });

    testWidgets('a member sees only their 牧區; one in none is told to ask an admin', (tester) async {
      await pumpApp(tester, seededChurch(as: staffMei));
      await tapText(tester, '服事表');
      expect(find.text('青年崇拜'), findsNothing);
      expect(findDay('10月4日'), findsWidgets);

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

    testWidgets("a service's 負責人 edits only its rosters", (tester) async {
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
      expect(find.text('排過招待的人'), findsOneWidget);
      final hao = tester.getTopLeft(find.text('陳志豪').last).dy;
      final mei = tester.getTopLeft(find.text('李美玉').last).dy;
      expect(hao < mei, isTrue, reason: 'staff order puts 陳志豪 first');
      expect(find.text('John Chen'), findsNothing, reason: 'does not serve 招待');

      await tapText(tester, '陳志豪');
      await tapText(tester, '完成');
      expect(peopleOn(b, 11, '招待'), ['陳志豪', '李美玉']);
      expect(find.text('已更新招待'), findsOneWidget);
    });

    testWidgets('the picker saves with 完成 only: 取消 leaves the day as it was', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '招待');
      await tapText(tester, '陳志豪');
      await tapText(tester, '取消');
      expect(find.text('放棄變更？'), findsOneWidget);
      await tapText(tester, '放棄變更');
      expect(find.text('排過招待的人'), findsNothing, reason: 'the picker has closed');
      expect(peopleOn(b, 11, '招待'), ['李美玉']);
      expect(find.text('已更新招待'), findsNothing);
    });

    testWidgets('a changed picker asks before it closes any other way; an unchanged one just closes', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '招待');
      await tapText(tester, '陳志豪');

      Future<void> keepEditing() async {
        expect(find.text('放棄變更？'), findsOneWidget);
        await tapText(tester, '繼續編輯');
        expect(find.text('排過招待的人').hitTestable(), findsOneWidget, reason: 'still open, all the way up');
        expect(peopleOn(b, 11, '招待'), ['李美玉'], reason: 'nothing saved yet');
      }

      await tester.binding.handlePopRoute();
      await settle(tester);
      await keepEditing();
      await tester.tapAt(const Offset(20, 20));
      await settle(tester);
      await keepEditing();
      await tester.fling(find.text('招待').last, const Offset(0, 600), 3000);
      await settle(tester);
      await keepEditing();

      await tapText(tester, '完成');
      expect(peopleOn(b, 11, '招待'), ['陳志豪', '李美玉']);

      await tapText(tester, '招待');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('放棄變更？'), findsNothing);
      expect(find.text('排過招待的人'), findsNothing, reason: 'closed at once');
    });

    testWidgets('a duty only ever one person has: picking someone puts them there instead, at once', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '司會');
      await tapText(tester, '林同工');
      expect(find.text('排過司會的人'), findsNothing, reason: 'the picker has closed');
      expect(peopleOn(b, 11, '司會'), ['林同工']);
      expect(find.text('已更新司會'), findsOneWidget);
      await tapText(tester, '復原');
      expect(peopleOn(b, 11, '司會'), ['王牧師']);
    });

    testWidgets('a duty only ever one person has takes a second with 再加一位', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '司會');
      await tapText(tester, '再加一位');
      await tapText(tester, '林同工');
      expect(find.text('排過司會的人'), findsOneWidget, reason: 'still open for more');
      await tapText(tester, '完成');
      expect(peopleOn(b, 11, '司會'), unorderedEquals(['王牧師', '林同工']));
    });

    testWidgets('two people on a duty in the past weeks keep it to pick several', (tester) async {
      final b = seededChurch();
      b.rosters['grace']![Roster.idFor('sunday', Day(2026, 9, 20))] = Roster(
        type: 'sunday',
        day: Day(2026, 9, 20),
        duties: const [
          Duty(role: '司會', people: ['林同工', '王牧師'], uids: {'林同工': 'editor', '王牧師': 'pastor'}),
        ],
      );
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '司會');
      await tapText(tester, '林同工');
      expect(find.text('排過司會的人'), findsOneWidget, reason: 'still open for more');
      await tapText(tester, '完成');
      expect(peopleOn(b, 11, '司會'), unorderedEquals(['王牧師', '林同工']));
    });

    testWidgets('two people on a duty on a day ahead keep it to pick several', (tester) async {
      final b = seededChurch();
      b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, 18))] = Roster(
        type: 'sunday',
        day: Day(2026, 10, 18),
        duties: const [
          Duty(role: '司會', people: ['林同工', '王牧師'], uids: {'林同工': 'editor', '王牧師': 'pastor'}),
        ],
      );
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '司會');
      expect(find.text('再加一位'), findsNothing);
      await tapText(tester, '林同工');
      expect(find.text('排過司會的人'), findsOneWidget, reason: 'still open for more');
    });

    testWidgets('a helper found by searching can join as a second with 再加一位', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '司會');
      await tester.enterText(find.byType(TextField), 'John');
      await settle(tester);
      await tapText(tester, '再加一位');
      await tapText(tester, 'John Chen');
      await tapText(tester, '完成');
      expect(peopleOn(b, 11, '司會'), unorderedEquals(['王牧師', 'John Chen']));
    });

    testWidgets('search finds other members ignoring width and case; a helper is scheduled this once (#82)', (
      tester,
    ) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '司琴');
      await tester.enterText(find.byType(TextField), 'ｊｏｈｎ');
      await settle(tester);
      expect(find.text('其他同工'), findsOneWidget);
      await tapText(tester, 'John Chen');
      expect(find.byType(AlertDialog), findsNothing, reason: 'nothing to answer: picking is enough');

      expect(peopleOn(b, 11, '司琴'), ['John Chen']);
      expect(b.members['grace']!['john']!.serves('sunday', '司琴'), isFalse, reason: 'not one of 主日崇拜’s 同工');
    });

    testWidgets('picking one of the service’s 同工 remembers them for the duty', (tester) async {
      final b = seededChurch(extra: const [johnOnSunday]);
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '司琴');
      await tester.enterText(find.byType(TextField), 'John');
      await settle(tester);
      await tapText(tester, 'John Chen');
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
      expect(findShown('這個聚會的同工排過一次，下次就會列在上面'), findsOneWidget);
      expect(find.text('其他同工'), findsOneWidget);
      await tapText(tester, 'John Chen');
      final youth = b.rosters['grace']![Roster.idFor('youth', Day(2026, 10, 10))]!;
      expect(youth.duties.firstWhere((d) => d.role == '司會').people, ['John Chen']);
      expect(b.members['grace']!['john']!.serves('youth', '司會'), isFalse);
    });

    testWidgets('a roster editor, who cannot change members, schedules someone without remembering them', (
      tester,
    ) async {
      final b = seededChurch(as: editor);
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '司琴');
      await tester.enterText(find.byType(TextField), 'John');
      await settle(tester);
      await tapText(tester, 'John Chen');
      expect(peopleOn(b, 11, '司琴'), ['John Chen']);
      expect(b.members['grace']!['john']!.serves('sunday', '司琴'), isFalse);
    });

    testWidgets('an admin takes someone off a duty’s list in 編輯; searching still finds them', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '招待');
      await tapText(tester, '編輯');
      await tester.tap(find.byTooltip('從名單移除李美玉'));
      await settle(tester);
      await tapText(tester, '完成');
      expect(find.text('排過招待的人'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '美玉');
      await settle(tester);
      expect(find.text('其他同工'), findsOneWidget, reason: 'off the list, still in the church');
      await tapText(tester, '完成');
      expect(b.members['grace']!['mei']!.serves('sunday', '招待'), isFalse);
      expect(b.members['grace']!['mei']!.serves('sunday', '司琴'), isTrue);
      expect(peopleOn(b, 11, '招待'), ['李美玉'], reason: 'this Sunday is as it was');

      expect(find.text('已從招待名單移除李美玉'), findsOneWidget);
      await tapText(tester, '復原');
      expect(b.members['grace']!['mei']!.serves('sunday', '招待'), isTrue);
    });

    testWidgets('taking the last one off the list still leaves a way out of 編輯', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '司琴');
      await tapText(tester, '編輯');
      await tester.tap(find.byTooltip('從名單移除李美玉'));
      await settle(tester);
      await tapText(tester, '完成');
      await tapText(tester, '完成');
      expect(b.members['grace']!['mei']!.serves('sunday', '司琴'), isFalse);
    });

    testWidgets('picked from 其他同工 and unpicked again: not put on the list', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '招待');
      await tester.enterText(find.byType(TextField), 'John');
      await settle(tester);
      await tapText(tester, 'John Chen');
      await tapText(tester, 'John Chen');
      await tapText(tester, '完成');
      expect(peopleOn(b, 11, '招待'), ['李美玉']);
      expect(b.members['grace']!['john']!.serves('sunday', '招待'), isFalse);
    });

    testWidgets('taken off and tapped again: back on the list, still scheduled', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '招待');
      await tapText(tester, '編輯');
      await tester.tap(find.byTooltip('從名單移除李美玉'));
      await settle(tester);
      await tapText(tester, '完成');
      await tester.enterText(find.byType(TextField), '美玉');
      await settle(tester);
      await tapText(tester, '李美玉');
      await tapText(tester, '完成');
      expect(peopleOn(b, 11, '招待'), ['李美玉']);
      expect(b.members['grace']!['mei']!.serves('sunday', '招待'), isTrue);
    });

    testWidgets('someone put on the list by being picked comes last in staff order', (tester) async {
      final b = seededChurch(extra: const [johnOnSunday]);
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      // 司琴 has no staff order yet: by name, John Chen would come first.
      await tapText(tester, '司琴');
      await tester.enterText(find.byType(TextField), 'John');
      await settle(tester);
      await tapText(tester, 'John Chen');
      await go(tester, '/rosters/sunday/2026-10-04');
      await tapText(tester, '司琴');
      final mei = tester.getTopLeft(find.text('李美玉').last).dy;
      final john = tester.getTopLeft(find.text('John Chen').last).dy;
      expect(mei < john, isTrue);
    });

    testWidgets('a roster editor reorders but cannot take anyone off the list', (tester) async {
      await pumpApp(tester, seededChurch(as: editor));
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '招待');
      await tapText(tester, '調整順序');
      expect(find.byTooltip('從名單移除李美玉'), findsNothing);
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

    testWidgets('a large picker can search, select different distant names, and keep them when closed', (tester) async {
      final many = [
        for (var i = 0; i < 500; i++)
          Member(
            uid: 'large$i',
            name: '同工${i.toString().padLeft(4, '0')}',
            zones: const [
              Zone(serviceType: 'sunday', duties: ['招待']),
            ],
          ),
      ];
      final b = seededChurch(extra: many);
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '招待');
      for (final name in ['同工0499', '同工0000']) {
        await tester.enterText(find.byType(TextField), name);
        await settle(tester);
        await tapText(tester, name);
      }
      await tapText(tester, '完成');
      expect(peopleOn(b, 11, '招待'), containsAll(['同工0499', '同工0000', '李美玉']));
    });

    testWidgets('with the keyboard up, the end of a long list scrolls out from under it', (tester) async {
      final many = [
        for (var i = 0; i < 40; i++)
          Member(
            uid: 'k$i',
            name: '同工$i',
            zones: const [
              Zone(serviceType: 'sunday', duties: ['招待']),
            ],
          ),
      ];
      await pumpApp(tester, seededChurch(extra: many));
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '招待');
      // The phone's keyboard, over the bottom half, for the search box.
      final half = tester.view.physicalSize.height / 2;
      tester.view.viewInsets = FakeViewPadding(bottom: half);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await tester.fling(find.byType(ListView).last, const Offset(0, -20000), 5000);
      await settle(tester);
      expect(
        tester.getRect(find.text('移除這項')).bottom,
        lessThan(half / tester.view.devicePixelRatio),
        reason: 'not under the keyboard',
      );
    });

    testWidgets('a name on the day is its own tap target, full size and apart from the next', (tester) async {
      await pumpApp(tester, seededChurch());
      await go(tester, '/rosters/sunday/2026-10-04');
      Finder chip(String name) => find.ancestor(of: find.text(name), matching: find.byType(InkWell)).first;
      final minimum = Space.minTap(Theme.of(tester.element(find.text('陳志豪'))).platform);
      final hao = tester.getRect(chip('陳志豪'));
      expect(hao.height, greaterThanOrEqualTo(minimum));
      expect(hao.width, greaterThanOrEqualTo(minimum));
      // 招待: 陳志豪、李美玉 (李美玉 is on 司琴 above too).
      final next = tester.getRect(find.ancestor(of: find.text('李美玉').last, matching: find.byType(InkWell)).first);
      expect(next.left - hao.right, greaterThanOrEqualTo(Space.s), reason: 'a gap between two names on one row');
    });

    testWidgets('when nobody serves a duty, an admin can invite people from the picker', (tester) async {
      await pumpApp(tester, seededChurch());
      await go(tester, '/rosters/youth/2026-10-10');
      await tapText(tester, '司會');
      expect(findShown('這個聚會的同工排過一次，下次就會列在上面'), findsOneWidget);
      await tapText(tester, '邀請同工');
      expect(find.text('建立邀請連結'), findsOneWidget, reason: 'the invites page');
    });

    testWidgets('a roster editor, who cannot invite, gets no invite button', (tester) async {
      final b = seededChurch(as: editor);
      final day = savedDay(b, 11);
      b.rosters['grace']![day.id] = day.copyWith(
        duties: [
          ...day.duties,
          const Duty(role: '音控', people: []),
        ],
      );
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '音控');
      expect(find.text('還沒有人負責音控'), findsOneWidget);
      expect(find.text('邀請同工'), findsNothing);
    });

    testWidgets('a failed save offers 重試, which saves what was picked', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '司琴');
      b.failNextWrite = Exception('offline');
      await tapText(tester, '李美玉');
      expect(find.text('沒有儲存成功，請檢查網路後再試一次'), findsOneWidget);
      expect(peopleOn(b, 11, '司琴'), isEmpty);
      await tapText(tester, '重試');
      expect(peopleOn(b, 11, '司琴'), ['李美玉']);
      expect(find.text('已更新司琴'), findsOneWidget);
    });

    testWidgets("on an iPhone the day's title stays centred beside 儲存中 and the menu", (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final b = seededChurch();
        await pumpApp(tester, b);
        await go(tester, '/rosters/sunday/2026-10-11');
        b.writeDelay = const Duration(seconds: 3);
        await tapText(tester, '司會');
        await tapText(tester, '林同工');
        expect(find.text('儲存中…'), findsOneWidget);
        final title = find.descendant(of: find.byType(AppBar), matching: find.text('主日崇拜'));
        expect(tester.getCenter(title).dx, moreOrLessEquals(tester.getCenter(find.byType(AppBar)).dx, epsilon: 1));
        await tester.pump(const Duration(seconds: 3));
        await settle(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a pick shows on the day at once, saying 儲存中 until the backend has it', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      expect(find.text('林同工'), findsNothing);
      b.writeDelay = const Duration(seconds: 3);
      await tapText(tester, '司會');
      await tapText(tester, '林同工');
      expect(peopleOn(b, 11, '司會'), isNot(contains('林同工')), reason: 'not written yet');
      expect(find.text('林同工'), findsOneWidget);
      expect(find.text('儲存中…'), findsOneWidget);
      expect(find.text('已更新司會'), findsNothing);

      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(peopleOn(b, 11, '司會'), contains('林同工'));
      expect(find.text('林同工'), findsOneWidget);
      expect(find.text('儲存中…'), findsNothing);
      expect(find.text('已更新司會'), findsOneWidget);
    });

    testWidgets('a pick the backend refuses goes off the day again', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      b.writeDelay = const Duration(seconds: 3);
      b.failNextWrite = Exception('offline');
      await tapText(tester, '司會');
      await tapText(tester, '林同工');
      expect(find.text('林同工'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(find.text('林同工'), findsNothing);
      expect(find.text('沒有儲存成功，請檢查網路後再試一次'), findsOneWidget);
    });

    testWidgets('a service nobody is arranged in yet offers to start, to those who can', (tester) async {
      MemoryBackend newChurch(Member as) {
        final b = MemoryBackend(clock: testClock);
        final cid = b.addChurch('恩典堂', id: 'grace');
        b.setServices(cid, const [sundayService]);
        b.addMember(cid, pastor);
        b.addMember(cid, staffMei);
        b.auth.signInAs('${as.uid}@example.com', uid: as.uid, name: as.name);
        b.users[as.uid] = UserProfile(uid: as.uid, name: as.name, email: '${as.uid}@example.com');
        b.notify();
        return b;
      }

      await pumpApp(tester, newChurch(staffMei));
      await tapText(tester, '服事表');
      expect(find.text('開始安排'), findsNothing);

      await pumpApp(tester, newChurch(pastor));
      await tapText(tester, '服事表');
      expect(find.text('還沒有安排任何人'), findsOneWidget);
      // A roster already on paper: the way to read it in is right here too.
      expect(find.text('用照片匯入'), findsOneWidget);
      await tapText(tester, '開始安排');
      expect(find.textContaining('10月4日'), findsOneWidget, reason: 'the first day, to arrange');
      expect(find.byTooltip('編輯'), findsOneWidget);
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
      await tester.tap(find.byTooltip('已移除「李美玉」'));
      await settle(tester);
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

    testWidgets('offline, a change is refused and says so; nothing waits to sync later', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-04');
      final before = peopleOn(b, 4, '司琴');
      b.setOnline(false);
      await settle(tester);
      await tapText(tester, '司琴');
      await tester.tap(find.byTooltip('已移除「李美玉」'));
      await settle(tester);
      await tapText(tester, '完成');
      expect(find.text('離線中，連線後才能儲存'), findsOneWidget);
      b.setOnline(true);
      await settle(tester);
      expect(peopleOn(b, 4, '司琴'), before, reason: 'reconnecting sends nothing that was refused');
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
      await tester.tap(find.descendant(of: sheet, matching: find.text('待定')).first);
      await settle(tester);

      expect(peopleOn(b, 4, '招待'), ['李美玉']);
      expect(findShownContaining('已把「陳志豪」移到'), findsOneWidget);
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

    testWidgets('tapping the day\'s tags opens 特別活動, as the menu does', (tester) async {
      final b = seededChurch();
      final day = savedDay(b, 4);
      b.rosters['grace']![day.id] = day.copyWith(events: const [EventTag(name: '聖餐', color: 0)]);
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-04');
      await tapText(tester, '聖餐');
      await tapText(tester, '聖餐');
      await tapText(tester, '完成');
      expect(savedDay(b, 4).events, isEmpty);
    });

    testWidgets('staff only see the tags', (tester) async {
      final b = seededChurch(as: staffHao);
      final day = savedDay(b, 4);
      b.rosters['grace']![day.id] = day.copyWith(events: const [EventTag(name: '聖餐', color: 0)]);
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-04');
      await tapText(tester, '聖餐');
      expect(find.text('完成'), findsNothing);
    });
  });
}
