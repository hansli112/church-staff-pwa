import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/design/components.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

Future<void> go(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await settle(tester);
}

const worship = MinistrySettings(
  ministries: [
    Ministry(id: 'worship', name: '敬拜團', duties: [MinistryDuty('sunday', '司琴')]),
  ],
  ids: ['worship'],
);

void main() {
  testWidgets("an admin makes a 事工 on its service's page, names its 負責人, then links its duties on its page (#82)", (
    tester,
  ) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me');
    await tapText(tester, '聚會與事工');
    await tapText(tester, '主日崇拜');
    await tester.scrollUntilVisible(find.text('新增事工'), 200, scrollable: find.byType(Scrollable).last);
    // Clear of the tab bar.
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -200));
    await settle(tester);
    await tapText(tester, '新增事工');
    await tester.enterText(find.byType(TextField), '敬拜團');
    await tapText(tester, '儲存');

    // Its 負責人 next, without looking for them; its duties are not asked.
    await tapText(tester, '陳志豪');
    final ministry = b.ministries['grace']!.ministries.single;
    expect(ministry.name, '敬拜團');
    expect(ministry.duties, isEmpty);
    expect(ministry.service, 'sunday', reason: 'made on its page');
    expect(b.members['grace']!['hao']!.leadMinistries, [ministry.id]);

    expect(find.text('敬拜團'), findsWidgets, reason: 'its page opened');
    await tapText(tester, '選服事項目');
    await tapText(tester, '司琴');
    await tapText(tester, '完成');
    expect(b.ministries['grace']!.ministries.single.duties, const [MinistryDuty('sunday', '司琴')]);
    expect(findShown('陳志豪可以排主日崇拜、活動的司琴，也可以改這幾項的名單'), findsOneWidget);
    expect(find.text('再加一位負責人'), findsOneWidget, reason: 'one is enough, more are possible');
    expect(find.text('李美玉'), findsNothing, reason: "司琴's list is on its service's page, not again here");
    expect(find.text('同工'), findsNothing, reason: 'a 事工 has no 同工 of its own (#94)');
    expect(find.text('加入同工'), findsNothing);

    await go(tester, '/me/groups/service/sunday');
    await tester.scrollUntilVisible(find.text('陳志豪 · 司琴'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('陳志豪 · 司琴'), findsOneWidget, reason: 'who leads it and what, on its service\'s page');
    await go(tester, '/me/groups');
    expect(find.text('敬拜團'), findsNothing, reason: "not church-wide: 主日崇拜's own");
  });

  testWidgets('a 事工 of several services, or of none, is listed church-wide; each service its own 敬拜團, named with it', (
    tester,
  ) async {
    final b = seededChurch();
    b.ministries['grace'] = const MinistrySettings(
      ministries: [
        Ministry(id: 'worship', name: '敬拜團', duties: [MinistryDuty('sunday', '司琴')]),
        Ministry(id: 'youthWorship', name: '敬拜團', duties: [MinistryDuty('youth', '司會')]),
        Ministry(id: 'sound', name: '音控組', duties: [MinistryDuty('sunday', '招待'), MinistryDuty('youth', '司會')]),
        Ministry(id: 'media', name: '多媒體'),
      ],
      ids: ['worship', 'youthWorship', 'sound', 'media'],
    );
    await pumpApp(tester, b);
    await go(tester, '/me/groups');
    await tester.scrollUntilVisible(find.text('多媒體'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('音控組'), findsOneWidget);
    expect(find.text('多媒體'), findsOneWidget, reason: 'no duties: only what calendar events belong to');
    expect(find.text('敬拜團'), findsNothing, reason: 'each on its own service\'s page');

    await go(tester, '/me/groups/ministry/youthWorship');
    expect(find.text('青年崇拜 · 敬拜團'), findsOneWidget, reason: 'beside 主日崇拜\'s, named with its service');
  });

  testWidgets('a 事工 made with its 負責人 left for later says what is missing', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me');
    await tapText(tester, '聚會與事工');
    await tapText(tester, '新增事工');
    await tester.enterText(find.byType(TextField), '關懷事工');
    await tapText(tester, '儲存');
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(b.ministries['grace']!.ministries.single.duties, isEmpty);
    expect(find.text('指派負責人'), findsOneWidget, reason: 'on its page, not asked again');
    expect(findShown('選好服事項目，負責人就能在聚會和活動排這些項目'), findsOneWidget);

    await tapText(tester, '選服事項目');
    await tapText(tester, '招待');
    await tapText(tester, '完成');
    expect(b.ministries['grace']!.ministries.single.duties, const [MinistryDuty('sunday', '招待')]);
    expect(findShown('指派之後，負責人可以排主日崇拜、活動的招待，也可以改這幾項的名單'), findsOneWidget);
  });

  testWidgets('a duty a 事工 leads that its service has not yet is added there and picked', (tester) async {
    final b = seededChurch();
    b.ministries['grace'] = const MinistrySettings(
      ministries: [Ministry(id: 'worship', name: '敬拜團')],
      ids: ['worship'],
    );
    await pumpApp(tester, b);
    await go(tester, '/me/groups/ministry/worship');
    await tapText(tester, '選服事項目');
    await tester.tap(find.text('新增服事項目').first);
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Vocal');
    await tapText(tester, '儲存');
    expect(b.services['grace']!.byId('sunday')!.duties.last, 'Vocal');
    await tapText(tester, '完成');
    expect(b.ministries['grace']!.ministries.single.duties, const [MinistryDuty('sunday', 'Vocal')]);
  });

  testWidgets("a 事工's duties that differ by service are said place by place, the same ones together; its 負責人 alike", (
    tester,
  ) async {
    // Its 負責人, who has each duty's list here.
    final b = seededChurch(
      as: staffHao,
      extra: [
        staffHao.withIdentities(const [MinistryLead('worship')]),
        staffMei.withIdentities(const [MinistryLead('worship')]),
      ],
    );
    b.ministries['grace'] = const MinistrySettings(
      ministries: [
        Ministry(
          id: 'worship',
          name: '敬拜團',
          duties: [MinistryDuty('sunday', '司琴'), MinistryDuty('sunday', '司會'), MinistryDuty('youth', '司會')],
        ),
      ],
      ids: ['worship'],
    );
    await pumpApp(tester, b);
    await go(tester, '/me/groups/ministry/worship');
    expect(
      findShown('李美玉、陳志豪都可以排主日崇拜、活動的司琴、司會；青年崇拜的司會，也可以改這幾項的名單'),
      findsOneWidget,
    );
    expect(find.text('主日崇拜 · 司會'), findsOneWidget, reason: 'in more than one service: named with it');
    expect(find.text('青年崇拜 · 司會'), findsOneWidget);
  });

  testWidgets("a 事工's 負責人 puts anyone on the list of its duty, who becomes the service's 同工 (#94)", (tester) async {
    final b = seededChurch(
      as: staffHao,
      extra: [
        staffHao.withIdentities(const [MinistryLead('worship')]),
      ],
    );
    b.ministries['grace'] = worship;
    await pumpApp(tester, b);
    await go(tester, '/me');
    await tapText(tester, '敬拜團');
    await tapText(tester, '司琴');
    expect(find.text('主日崇拜的同工'), findsOneWidget);
    expect(find.text('其他人'), findsOneWidget);
    expect(find.text('服事項目名稱'), findsNothing, reason: "the duty's name is the admin's");
    expect(find.text('刪除'), findsNothing);

    await tapText(tester, 'John Chen');
    final john = b.members['grace']!['john']!;
    expect(john.serves('sunday', '司琴'), isTrue);
    expect(john.zoneTypes, ['sunday'], reason: "one of 主日崇拜's 同工 now");
    expect(
      tester.getTopLeft(find.text('John Chen')).dy > tester.getTopLeft(find.text('其他人')).dy,
      isTrue,
      reason: 'his row stays where it was tapped',
    );
    // 林同工 leads 主日崇拜: a list gives nothing, so anyone may be on it.
    await tapText(tester, '林同工');
    expect(b.members['grace']!['editor']!.serves('sunday', '司琴'), isTrue);
    await tapText(tester, '李美玉');
    expect(b.members['grace']!['mei']!.serves('sunday', '司琴'), isFalse);
    expect(b.members['grace']!['mei']!.zoneTypes, ['sunday'], reason: 'still one of its 同工');
  });

  testWidgets("but only the lists of the duties it leads; another's it only reads", (tester) async {
    final b = seededChurch(
      as: staffHao,
      extra: [
        staffHao.withIdentities(const [MinistryLead('worship')]),
      ],
    );
    b.ministries['grace'] = worship;
    await pumpApp(tester, b);
    await go(tester, '/me/groups/duty?service=sunday&name=%E6%8B%9B%E5%BE%85');
    expect(find.text('其他人'), findsNothing);
    expect(find.text('John Chen'), findsNothing, reason: 'only who is on it');
    await tapText(tester, '李美玉');
    expect(b.members['grace']!['mei']!.serves('sunday', '招待'), isTrue);
    await go(tester, '/me/groups/service/sunday');
    expect(find.text('主日崇拜'), findsNothing, reason: "the service's page is its 負責人's");
  });

  testWidgets("a service's 負責人 edits the list of any of its duties from its page", (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/me/groups/service/sunday');
    await tester.scrollUntilVisible(find.text('招待').first, 200, scrollable: find.byType(Scrollable).last);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -200));
    await settle(tester);
    await tester.tap(find.text('招待').first);
    await settle(tester);
    expect(find.text('服事項目名稱'), findsNothing);
    await tapText(tester, 'John Chen');
    expect(b.members['grace']!['john']!.serves('sunday', '招待'), isTrue);
    await tapText(tester, '陳志豪');
    expect(b.members['grace']!['hao']!.serves('sunday', '招待'), isFalse);
  });

  testWidgets('on its page an admin sees each duty with its list, and puts a duty in a 事工, or none', (tester) async {
    final b = seededChurch();
    b.ministries['grace'] = const MinistrySettings(
      ministries: [Ministry(id: 'worship', name: '敬拜團')],
      ids: ['worship'],
    );
    await pumpApp(tester, b);
    await go(tester, '/me/groups/service/sunday');
    expect(find.text('2 人'), findsOneWidget, reason: "how many are on 招待's list");
    await tapText(tester, '司琴');
    expect(find.text('屬於哪個事工'), findsOneWidget);
    await tapText(tester, '屬於哪個事工');
    await tapText(tester, '敬拜團');
    expect(b.ministries['grace']!.ministries.single.duties, const [MinistryDuty('sunday', '司琴')]);
    await tapText(tester, '屬於哪個事工');
    await tapText(tester, '沒有');
    expect(b.ministries['grace']!.ministries.single.duties, isEmpty);
  });

  testWidgets('an admin takes out a 負責人 on the page at once, and 復原; a 牧者 stays, said so (#94)', (tester) async {
    final b = seededChurch(
      extra: [
        // Its 牧者 and, from before, its 負責人 too.
        staffHao.withIdentities(const [
          PastorIdentity(['sunday']),
          ServiceLead('sunday'),
        ]),
      ],
    );
    await pumpApp(tester, b);
    await go(tester, '/me/groups/service/sunday');
    expect(find.text('牧者'), findsOneWidget, reason: '陳志豪 leads it as its 牧者');
    expect(find.text('移出'), findsOneWidget, reason: "only 林同工's; 陳志豪 is changed on his own page");
    await tapText(tester, '移出');
    expect(b.members['grace']!['editor']!.identities, isEmpty);
    expect(find.text('已移除「主日崇拜 負責人」'), findsOneWidget);
    await tapText(tester, '復原');
    expect(b.members['grace']!['editor']!.identities, const [ServiceLead('sunday')]);
  });

  testWidgets("a service's 負責人 adds a helper to its 同工 with the duties they served", (tester) async {
    final b = seededChurch(as: editor);
    b.rosters['grace']![Roster.idFor('youth', Day(2026, 10, 10))] = Roster(
      type: 'youth',
      day: Day(2026, 10, 10),
      duties: const [
        Duty(role: '司會', people: ['John Chen'], uids: {'John Chen': 'john'}),
      ],
    );
    b.members['grace']!['editor'] = editor.withIdentities(const [ServiceLead('youth')]);
    await pumpApp(tester, b);
    await go(tester, '/me/groups/service/youth');
    // Said on the service's page; added on its 同工's.
    expect(findShown('排過青年崇拜的服事，還不是同工'), findsOneWidget);
    await tapText(tester, '1 人');
    await tapText(tester, '加為同工');
    final added = b.members['grace']!['john']!;
    expect(added.zoneTypes, ['youth']);
    expect(added.serves('youth', '司會'), isTrue);
  });

  testWidgets("a service's page counts its 同工; their own page has 加入同工 first, and a search", (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me/groups/service/sunday');
    await tester.scrollUntilVisible(find.text('3 人'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('加入同工'), findsNothing, reason: 'not under a list that may run to a hundred');
    await tapText(tester, '3 人');
    expect(find.text('主日崇拜的同工'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('加入同工')).dy,
      lessThan(tester.getTopLeft(find.text('李美玉')).dy),
      reason: 'in sight as it opens',
    );
    await tester.enterText(find.byType(TextField), '美玉');
    await settle(tester);
    expect(find.text('陳志豪'), findsNothing);
    await tapText(tester, '移出');
    expect(b.members['grace']!['mei']!.zoneTypes, isEmpty);
  });

  testWidgets("a duty's list on its service's page: the first three, and how many more", (tester) async {
    final b = seededChurch(
      extra: [
        for (final (uid, name) in [('w1', '王一'), ('w2', '王二'), ('w3', '王三')])
          Member(
            uid: uid,
            name: name,
            zones: const [
              Zone(serviceType: 'sunday', duties: ['招待']),
            ],
          ),
      ],
    );
    await pumpApp(tester, b);
    await go(tester, '/me/groups/service/sunday');
    expect(find.text('5 人'), findsOneWidget);
  });

  testWidgets('in 聚會與事工 a service shows it opens its page, as well as that it can be moved', (tester) async {
    await pumpApp(tester, seededChurch());
    await go(tester, '/me/groups');
    final row = find.ancestor(of: find.text('主日崇拜'), matching: find.byType(ListRow)).first;
    expect(find.descendant(of: row, matching: find.byIcon(Symbols.chevron_right_rounded)), findsOneWidget);
    expect(find.descendant(of: row, matching: find.byIcon(Symbols.drag_handle_rounded)), findsOneWidget);
  });

  testWidgets("行政 reads a service's 同工 on their page, and moves nobody; a search with no one says so", (tester) async {
    await pumpApp(tester, seededChurch(as: office, extra: [office]));
    await go(tester, '/me/groups/service/sunday');
    await tester.scrollUntilVisible(find.text('3 人'), 200, scrollable: find.byType(Scrollable).last);
    await tapText(tester, '3 人');
    expect(find.text('李美玉'), findsOneWidget);
    expect(find.text('移出'), findsNothing);
    expect(find.text('加入同工'), findsNothing);
    await tester.enterText(find.byType(TextField), '沒有這個人');
    await settle(tester);
    expect(find.text('找不到這位同工'), findsOneWidget);
  });
}
