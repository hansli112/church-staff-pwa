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

const media = MinistrySettings(
  ministries: [Ministry(id: 'media', name: '多媒體')],
  ids: ['media'],
);

void main() {
  testWidgets('an admin makes a 事工 on 聚會與事工 and names its 負責人, searched; its page has its events (#82)', (
    tester,
  ) async {
    final b = seededChurch();
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await go(tester, '/me');
    await tapText(tester, '聚會與事工');
    await tester.scrollUntilVisible(find.text('新增事工'), 200, scrollable: find.byType(Scrollable).last);
    await tapText(tester, '新增事工');
    await tester.enterText(find.byType(TextField), '多媒體');
    await tapText(tester, '儲存');

    // Its 負責人 next, searched for.
    expect(find.text('李美玉'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '志豪');
    await settle(tester);
    expect(find.text('李美玉'), findsNothing);
    await tapText(tester, '陳志豪');
    final ministry = b.ministries['grace']!.ministries.single;
    expect(ministry.name, '多媒體');
    expect(b.members['grace']!['hao']!.leadMinistries, [ministry.id]);

    expect(find.text('多媒體'), findsWidgets, reason: 'its page opened');
    expect(find.text('活動'), findsOneWidget);
    expect(findShown('陳志豪可以新增、修改這些活動，排它們的服事'), findsOneWidget);
    expect(find.text('再加一位負責人'), findsOneWidget, reason: 'one is enough, more are possible');
    expect(find.text('同工'), findsNothing, reason: 'a 事工 has no 同工 of its own (#94)');
    expect(find.text('服事項目'), findsNothing, reason: 'it links no duties');

    await go(tester, '/me/groups');
    await tester.scrollUntilVisible(find.text('多媒體'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('陳志豪'), findsOneWidget, reason: 'who leads it, under it');
  });

  testWidgets('every 事工 is listed on 聚會與事工, those from before that linked duties too', (tester) async {
    final b = seededChurch();
    b.ministries['grace'] = const MinistrySettings(
      ministries: [
        Ministry(id: 'worship', name: '敬拜團'),
        Ministry(id: 'media', name: '多媒體'),
      ],
      ids: ['worship', 'media'],
    );
    await pumpApp(tester, b);
    await go(tester, '/me/groups');
    await tester.scrollUntilVisible(find.text('多媒體'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('敬拜團'), findsOneWidget);
    expect(find.text('多媒體'), findsOneWidget);
    await go(tester, '/me/groups/service/sunday');
    expect(find.text('事工'), findsNothing, reason: 'a service has no 事工 of its own');
  });

  testWidgets('with none yet, 事工 still shows on 聚會與事工, saying what goes there, with 新增事工', (tester) async {
    final b = seededChurch();
    b.ministries['grace'] = const MinistrySettings();
    await pumpApp(tester, b);
    await go(tester, '/me/groups');
    final footer = find.byWidgetPredicate((w) => w is BalancedText && w.text == '時間不固定、在行事曆上排活動的，例如多媒體、佈置。');
    await tester.scrollUntilVisible(footer, 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('事工'), findsOneWidget);
    expect(find.text('新增事工'), findsOneWidget);
  });

  testWidgets("a 事工's page lists its events ahead; 新增活動 makes one of it", (tester) async {
    final b = seededChurch(
      extra: [
        staffHao.withIdentities(const [MinistryLead('media')]),
      ],
      as: staffHao,
    );
    b.ministries['grace'] = media;
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      CalendarEvent(
        id: 'train',
        title: '影音訓練',
        start: DateTime(2026, 10, 10, 14),
        end: DateTime(2026, 10, 10, 16),
        group: 'ministry:media',
      ),
      CalendarEvent(id: 'church', title: '全教會禱告會', start: DateTime(2026, 10, 9, 19), end: DateTime(2026, 10, 9, 20)),
    ];
    await pumpApp(tester, b);
    await go(tester, '/me/groups/ministry/media');
    expect(find.text('影音訓練'), findsOneWidget);
    expect(find.text('全教會禱告會'), findsNothing, reason: 'not its');
    expect(findShown('陳志豪可以新增、修改這些活動，排它們的服事'), findsOneWidget);
    await tapText(tester, '新增活動');
    expect(find.text('多媒體'), findsWidgets, reason: 'the new event is its');
  });

  testWidgets('a 事工 made with its 負責人 left for later says what one will do', (tester) async {
    final b = seededChurch();
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await go(tester, '/me');
    await tapText(tester, '聚會與事工');
    await tester.scrollUntilVisible(find.text('新增事工'), 200, scrollable: find.byType(Scrollable).last);
    await tapText(tester, '新增事工');
    await tester.enterText(find.byType(TextField), '關懷事工');
    await tapText(tester, '儲存');
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(find.text('指派負責人'), findsOneWidget, reason: 'on its page, not asked again');
    expect(findShown('指派之後，負責人可以新增、修改這些活動，排它們的服事'), findsOneWidget);
  });

  testWidgets("a duty's 負責人 puts anyone on the list of their duty, who becomes the service's 同工 (#94)", (tester) async {
    final b = seededChurch(
      as: staffHao,
      extra: [
        staffHao.withIdentities(const [DutyLead('sunday', '司琴')]),
      ],
    );
    await pumpApp(tester, b);
    await go(tester, '/me/groups/duty?service=sunday&name=%E5%8F%B8%E7%90%B4');
    expect(find.text('主日崇拜的同工'), findsOneWidget);
    expect(find.text('其他人'), findsOneWidget);
    expect(find.text('服事項目名稱'), findsNothing, reason: "the duty's name is the admin's");
    expect(find.text('刪除'), findsNothing);
    expect(findShown('陳志豪可以排主日崇拜的司琴，也可以改這一項的名單'), findsOneWidget);

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

  testWidgets("but only the list of the duty they lead; another's they only read", (tester) async {
    final b = seededChurch(
      as: staffHao,
      extra: [
        staffHao.withIdentities(const [DutyLead('sunday', '司琴')]),
      ],
    );
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
    await tapText(tester, '服事項目');
    await tapText(tester, '招待');
    expect(find.text('服事項目名稱'), findsNothing);
    await tapText(tester, 'John Chen');
    expect(b.members['grace']!['john']!.serves('sunday', '招待'), isTrue);
    await tapText(tester, '陳志豪');
    expect(b.members['grace']!['hao']!.serves('sunday', '招待'), isFalse);
  });

  testWidgets('on its page an admin sees each duty with its list, and who leads it', (tester) async {
    final b = seededChurch(
      extra: [
        staffMei.withIdentities(const [DutyLead('sunday', '司琴')]),
      ],
    );
    await pumpApp(tester, b);
    await go(tester, '/me/groups/service/sunday/duties');
    expect(find.text('2 人'), findsOneWidget, reason: "how many are on 招待's list");
    expect(find.text('李美玉 負責'), findsOneWidget, reason: 'under 司琴');
    await tapText(tester, '司琴');
    expect(find.text('事工'), findsNothing, reason: 'a duty is in no 事工');
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
    // Clear of the tab bar.
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -200));
    await settle(tester);
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

  testWidgets("a service's 負責人 sets what one of its 同工 serves there, and their 小組, from its 同工", (tester) async {
    final b = seededChurch(as: editor);
    b.smallGroups['grace'] = {'joy': const SmallGroupDetails(id: 'joy', name: '喜樂小組', service: 'sunday')};
    await pumpApp(tester, b);
    await go(tester, '/me/groups/service/sunday');
    await tester.scrollUntilVisible(find.text('3 人'), 200, scrollable: find.byType(Scrollable).last);
    await tapText(tester, '3 人');
    await tapText(tester, '李美玉');
    expect(find.text('司琴、招待'), findsWidgets);
    await tapText(tester, '服事項目');
    await tapText(tester, '司會');
    expect(b.members['grace']!['mei']!.serves('sunday', '司會'), isTrue);
    await tapText(tester, '完成');
    await tapText(tester, '小組');
    await tapText(tester, '喜樂小組');
    expect(b.members['grace']!['mei']!.smallGroups, {'joy'});
  });

  testWidgets('加入同工 goes on to what they serve there', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/me/groups/service/sunday');
    await tester.scrollUntilVisible(find.text('3 人'), 200, scrollable: find.byType(Scrollable).last);
    await tapText(tester, '3 人');
    await tapText(tester, '加入同工');
    await tapText(tester, 'John Chen');
    expect(b.members['grace']!['john']!.zoneTypes, ['sunday']);
    await tapText(tester, '服事項目');
    await tapText(tester, '招待');
    expect(b.members['grace']!['john']!.serves('sunday', '招待'), isTrue);
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
    await go(tester, '/me/groups/service/sunday/duties');
    expect(find.text('5 人'), findsOneWidget);
  });

  testWidgets('in 聚會與事工 a service shows only that it opens its page; held, it moves', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me/groups');
    final row = find.ancestor(of: find.text('主日崇拜'), matching: find.byType(ListRow)).first;
    expect(find.descendant(of: row, matching: find.byIcon(Symbols.chevron_right_rounded)), findsOneWidget);
    expect(find.byIcon(Symbols.drag_handle_rounded), findsNothing);
    await dragRow(tester, '主日崇拜', 1);
    expect([for (final s in b.services['grace']!.services) s.id], ['youth', 'sunday']);
  });

  testWidgets("a service's page says its duties are held to move and swiped to delete, with no handles", (
    tester,
  ) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me/groups/service/sunday/duties');
    expect(find.byIcon(Symbols.drag_handle_rounded), findsNothing);
    expect(findShown('按住拖曳排序，左滑刪除'), findsWidgets);
    await dragRow(tester, '司會', 1);
    expect(b.services['grace']!.byId('sunday')!.duties, ['司琴', '司會', '招待']);
  });

  testWidgets('with one duty there is nothing to put in order: the note only says to swipe', (tester) async {
    await pumpApp(tester, seededChurch());
    await go(tester, '/me/groups/service/youth/duties');
    expect(findShown('左滑刪除'), findsWidgets);
    expect(find.textContaining('按住拖曳排序'), findsNothing);
  });

  testWidgets("行政 moves a service's 同工 on their page; a search with no one says so", (tester) async {
    await pumpApp(tester, seededChurch(as: office, extra: [office]));
    await go(tester, '/me/groups/service/sunday');
    await tester.scrollUntilVisible(find.text('3 人'), 200, scrollable: find.byType(Scrollable).last);
    await tapText(tester, '3 人');
    expect(find.text('李美玉'), findsOneWidget);
    expect(find.text('移出'), findsNWidgets(3));
    expect(find.text('加入同工'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '沒有這個人');
    await settle(tester);
    expect(find.text('找不到這位同工'), findsOneWidget);
  });

  testWidgets("a service's page keeps to a screen: each of its lists a row saying how many, opening its own page", (
    tester,
  ) async {
    final b = seededChurch();
    b.smallGroups['grace'] = {'joy': const SmallGroupDetails(id: 'joy', name: '喜樂小組', service: 'sunday')};
    await pumpApp(tester, b);
    await go(tester, '/me/groups/service/sunday');
    Finder inRow(String title, String text) => find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(ListRow)),
      matching: find.text(text),
    );
    expect(inRow('服事項目', '3 項'), findsOneWidget);
    expect(inRow('常用特別活動', '1 個'), findsOneWidget);
    expect(inRow('小組', '1 個'), findsOneWidget);
    expect(inRow('同工', '3 人'), findsOneWidget);
    expect(find.text('司琴'), findsNothing, reason: 'on its own page');
    expect(find.text('喜樂小組'), findsNothing);
    expect(tester.getBottomLeft(find.text('刪除聚會')).dy, lessThan(852 - 83), reason: 'above the tab bar, unscrolled');

    await tapText(tester, '服事項目');
    expect(find.text('司琴'), findsOneWidget);
    expect(find.text('2 人'), findsOneWidget, reason: "how many are on 招待's list");
    await tapText(tester, '新增服事項目');
    await tester.enterText(find.byType(TextField), '音控');
    await tapText(tester, '儲存');
    expect(b.services['grace']!.byId('sunday')!.duties, ['司會', '司琴', '招待', '音控']);
    await tester.tap(find.byType(BackButton).last);
    await settle(tester);
    expect(inRow('服事項目', '4 項'), findsOneWidget);

    await tapText(tester, '常用特別活動');
    expect(find.text('聖餐'), findsOneWidget);
    await tester.tap(find.byType(BackButton).last);
    await settle(tester);
    await tapText(tester, '小組');
    expect(find.text('喜樂小組'), findsOneWidget);
  });

  testWidgets("an admin assigns a duty's 負責人 on its page, and 復原", (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me/groups/duty?service=sunday&name=%E6%8B%9B%E5%BE%85');
    expect(findShown('指派之後，負責人可以排主日崇拜的招待，也可以改這一項的名單'), findsOneWidget);
    await tapText(tester, '指派負責人');
    await tapText(tester, '陳志豪');
    expect(b.members['grace']!['hao']!.identities, const [DutyLead('sunday', '招待')]);
    expect(b.members['grace']!['hao']!.leadTypes, isEmpty, reason: 'not the service’s 負責人');
    expect(b.ministries['grace']?.ministries ?? const [], isEmpty, reason: 'no 事工 made for it');
    expect(findShown('陳志豪可以排主日崇拜的招待，也可以改這一項的名單'), findsOneWidget);
    expect(find.text('已加上「主日崇拜招待 負責人」'), findsOneWidget);
    await tapText(tester, '復原');
    expect(b.members['grace']!['hao']!.identities, isEmpty);
  });

  testWidgets('someone with no account is not offered as a 負責人: a 身分 is held by who signs in', (tester) async {
    final b = seededChurch();
    b.pendingMembers['grace'] = {
      'old-ting': const PendingMember(
        id: 'old-ting',
        name: '林婷',
        zones: [Zone(serviceType: 'sunday')],
      ),
    };
    await pumpApp(tester, b);
    await go(tester, '/me/groups/duty?service=sunday&name=%E6%8B%9B%E5%BE%85');
    final onPage = find.text('林婷').evaluate().length;
    final haoOnPage = find.text('陳志豪').evaluate().length;
    await tapText(tester, '指派負責人');
    expect(find.text('陳志豪').evaluate().length, haoOnPage + 1);
    expect(find.text('林婷').evaluate().length, onPage, reason: 'on the page, not in the 負責人 to pick');
  });

  testWidgets("a duty's page shows its 負責人; one more added leads it too", (tester) async {
    final b = seededChurch(
      extra: [
        staffMei.withIdentities(const [DutyLead('sunday', '司琴')]),
      ],
    );
    await pumpApp(tester, b);
    await go(tester, '/me/groups/duty?service=sunday&name=%E5%8F%B8%E7%90%B4');
    expect(findShown('李美玉可以排主日崇拜的司琴，也可以改這一項的名單'), findsOneWidget);
    expect(find.text('移出'), findsOneWidget);
    await tapText(tester, '再加一位負責人');
    await tapText(tester, '陳志豪');
    expect(b.members['grace']!['hao']!.identities, const [DutyLead('sunday', '司琴')]);
    expect(findShown('李美玉、陳志豪都可以排主日崇拜的司琴，也可以改這一項的名單'), findsOneWidget);
  });

  testWidgets("a service's 負責人 assigns no duty's 負責人", (tester) async {
    await pumpApp(tester, seededChurch(as: editor));
    await go(tester, '/me/groups/duty?service=sunday&name=%E6%8B%9B%E5%BE%85');
    expect(find.text('指派負責人'), findsNothing);
    expect(find.text('負責人'), findsNothing, reason: 'it has none to read');
  });

  testWidgets('a 小組 has as many 小組長 as lead it together: 再加一位, and 移出 with 復原', (tester) async {
    final b = seededChurch(
      extra: [
        staffMei.withIdentities(const [SmallGroupLead('joy')]),
      ],
    );
    b.smallGroups['grace'] = {'joy': const SmallGroupDetails(id: 'joy', name: '喜樂小組', service: 'sunday')};
    await pumpApp(tester, b);
    await go(tester, '/me/groups/small/joy');
    expect(find.text('小組長'), findsOneWidget);
    expect(find.text('李美玉'), findsOneWidget);
    await tapText(tester, '再加一位小組長');
    await tapText(tester, '陳志豪');
    expect(b.members['grace']!['hao']!.leadSmallGroups, ['joy']);
    expect(b.members['grace']!['mei']!.leadSmallGroups, ['joy'], reason: 'both lead it');
    await tester.tap(find.bySemanticsLabel('移除「喜樂小組 小組長」').first);
    await settle(tester);
    expect(b.members['grace']!['mei']!.leadSmallGroups, isEmpty);
    await tapText(tester, '復原');
    expect(b.members['grace']!['mei']!.leadSmallGroups, ['joy']);
  });

  testWidgets("a 小組's name and 小組長 are under the service it is part of, with no row for it", (tester) async {
    final b = seededChurch();
    b.smallGroups['grace'] = {'joy': const SmallGroupDetails(id: 'joy', name: '喜樂小組', service: 'sunday')};
    await pumpApp(tester, b);
    await go(tester, '/me/groups/small/joy');
    expect(find.text('主日崇拜的小組'), findsOneWidget);
    expect(find.text('屬於'), findsNothing);
  });
}
