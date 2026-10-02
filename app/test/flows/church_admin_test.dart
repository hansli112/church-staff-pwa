import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/domain/models.dart';

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
  group('members', () {
    testWidgets('an admin changes a role and a group', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/members');
      expect(find.text('5 位同工'), findsOneWidget);
      await tapText(tester, '李美玉');
      await tapText(tester, '小組長');
      await tapText(tester, '安排服事表');
      final mei = b.members['grace']!['mei']!;
      expect(mei.role, Role.leader);
      expect(mei.groups, {Group.rosterEditors});
    });

    testWidgets('zones write the flattened zoneTypes', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/members/john');
      await tester.tap(find.text('負責這個聚會').last);
      await settle(tester);
      expect(b.members['grace']!['john']!.zoneTypes, ['youth']);
    });

    testWidgets('removing uses undo, and commits after the window', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/members');
      await tapText(tester, '陳志豪');
      await tester.scrollUntilVisible(find.text('移除同工'), 300);
      await tapText(tester, '移除同工');
      expect(find.text('已移除陳志豪'), findsOneWidget);
      expect(find.text('陳志豪'), findsNothing, reason: 'hidden at once');
      await tapText(tester, '復原');
      expect(find.text('陳志豪'), findsOneWidget);
      expect(b.members['grace']!.containsKey('hao'), isTrue);

      await tapText(tester, '陳志豪');
      await tester.scrollUntilVisible(find.text('移除同工'), 300);
      await tapText(tester, '移除同工');
      await tester.pump(const Duration(seconds: 6));
      await settle(tester);
      expect(b.members['grace']!.containsKey('hao'), isFalse);
    });

    testWidgets('an admin sees no demote or remove on their own page', (tester) async {
      await pumpApp(tester, seededChurch());
      await go(tester, '/me/members/pastor');
      expect(find.text('角色'), findsNothing);
      expect(find.text('移除同工'), findsNothing);
    });

    testWidgets('150 members scroll and search', (tester) async {
      final many = [for (var i = 0; i < 145; i++) Member(uid: 'x$i', name: '同工${i.toString().padLeft(3, '0')}')];
      await pumpApp(tester, seededChurch(extra: many));
      await go(tester, '/me/members');
      expect(find.text('150 位同工'), findsOneWidget);
      await tester.fling(find.byType(ListView).last, const Offset(0, -5000), 3000);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), '１４４');
      await settle(tester);
      expect(find.text('同工144'), findsOneWidget);
    });
  });

  group('leaving', () {
    testWidgets('staff leave from church info after confirming', (tester) async {
      final b = seededChurch(as: staffMei);
      await pumpApp(tester, b);
      await go(tester, '/me/church');
      await tester.scrollUntilVisible(find.text('退出教會'), 300);
      await tapText(tester, '退出教會');
      expect(find.text('退出〈恩典堂〉？'), findsOneWidget);
      expect(find.text('需要重新邀請才能回來'), findsOneWidget);
      await tapText(tester, '退出');
      expect(b.members['grace']!.containsKey('mei'), isFalse);
      expect(find.text('加入你的教會'), findsOneWidget);
    });

    testWidgets('an admin has no leave entry and is told to hand over', (tester) async {
      await pumpApp(tester, seededChurch());
      await go(tester, '/me/church');
      expect(find.text('退出教會'), findsNothing);
      expect(find.text('管理員要先把管理員交給別人，才能退出'), findsOneWidget);
    });

    testWidgets('a removed member loses the church at once', (tester) async {
      final b = seededChurch(as: staffMei);
      await pumpApp(tester, b);
      expect(find.byType(NavigationBar), findsOneWidget);
      b.members['grace']!.remove('mei');
      b.notify();
      await settle(tester);
      expect(find.text('加入你的教會'), findsOneWidget);
    });
  });

  group('account', () {
    testWidgets('the only admin cannot delete the account and is told where to go', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/account');
      await tester.tap(find.widgetWithText(TextButton, '刪除帳號'));
      await settle(tester);
      expect(find.text('刪除你的帳號？'), findsOneWidget);
      await tester.tap(find.text('刪除帳號').last);
      await settle(tester);
      expect(find.textContaining('你是〈恩典堂〉唯一的管理員'), findsOneWidget);
      expect(b.auth.currentUser, isNotNull);
    });

    testWidgets('staff delete their account and are signed out', (tester) async {
      final b = seededChurch(as: staffHao);
      await pumpApp(tester, b);
      await go(tester, '/account');
      await tester.tap(find.widgetWithText(TextButton, '刪除帳號'));
      await settle(tester);
      await tester.tap(find.text('刪除帳號').last);
      await settle(tester);
      expect(b.members['grace']!.containsKey('hao'), isFalse);
      expect(find.text('使用 Google 登入'), findsOneWidget);
    });
  });

  group('invites and settings', () {
    testWidgets('create a 7-day invite and revoke it', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/invites');
      await tapText(tester, '7 天');
      expect(b.invites.length, 1);
      final code = b.invites.keys.single;
      await go(tester, '/me');
      await go(tester, '/me/invites');
      await tapText(tester, code);
      await tapText(tester, '撤回');
      expect(b.invites[code]!.revoked, isTrue);
    });

    testWidgets('disabling a service hides it from the roster tab but keeps its rosters', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/services/youth');
      await tapText(tester, '舉行中');
      expect(b.services['grace']!.byId('youth')!.enabled, isFalse);
      expect(b.services['grace']!.ids, containsAll(['sunday', 'youth']));
      await go(tester, '/rosters');
      expect(find.text('青年崇拜'), findsNothing);
    });

    testWidgets('renaming a common event renames it on upcoming days', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/services/sunday');
      await tester.scrollUntilVisible(find.text('聖餐'), 300);
      await tapText(tester, '聖餐');
      await tester.enterText(find.byType(TextField).last, '主餐');
      await tapText(tester, '儲存');
      expect(savedDay(b, 4).events.single.name, '主餐');
    });

    testWidgets('renaming a duty moves members\' zones and the staff order with it', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/services/sunday');
      await tapText(tester, '招待');
      await tester.enterText(find.byType(TextField).last, '接待');
      await tapText(tester, '儲存');
      expect(b.services['grace']!.byId('sunday')!.duties, ['司會', '司琴', '接待']);
      expect(b.members['grace']!['hao']!.serves('sunday', '接待'), isTrue);
      expect(b.staffOrders['grace']!['sunday']!.rankingOf('接待'), ['陳志豪', '李美玉']);
      expect(savedDay(b, 4).duties.map((d) => d.role), contains('招待'), reason: 'arranged days keep their wording');
    });

    testWidgets('changing the template does not touch arranged rosters', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/services/sunday');
      await tester.drag(find.text('司琴').first, const Offset(-500, 0));
      await settle(tester);
      expect(b.services['grace']!.byId('sunday')!.duties, ['司會', '招待']);
      expect(savedDay(b, 4).duties.map((d) => d.role), ['司會', '司琴', '招待']);
    });
  });

  group('operator', () {
    testWidgets('is hidden without the claim', (tester) async {
      await pumpApp(tester, seededChurch());
      await go(tester, '/me');
      expect(find.text('平台後台'), findsNothing);
    });

    testWidgets('suspends a church; its members see the closed page', (tester) async {
      final b = seededChurch();
      b.auth.operators.add('pastor');
      await pumpApp(tester, b);
      await go(tester, '/admin');
      await tapText(tester, '恩典堂');
      await tester.scrollUntilVisible(find.text('停用教會'), 300);
      await tapText(tester, '停用教會');
      await tester.tap(find.text('停用教會').last);
      await settle(tester);
      expect(b.churches['grace']!.status, ChurchStatus.suspended);
    });
  });
}
