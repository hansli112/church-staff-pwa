import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/design/components.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/session.dart';

import '../support/harness.dart';
import '../support/seed.dart';
import '../support/telemetry.dart';

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(findShown(text).last);
  await settle(tester);
}

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

/// Scrolls the page down until [text] is on it.
Future<void> scrollTo(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(findShown(text), 300, scrollable: find.byType(Scrollable).first);
  await settle(tester);
}

void main() {
  group('members', () {
    testWidgets('an admin gives a 身分 and takes it back (#82): 管理員, 牧者 then 行政, by name alone', (tester) async {
      final b = seededChurch(
        extra: [
          staffMei.withIdentities(const [ServiceLead('sunday')]),
        ],
      );
      await pumpApp(tester, b);
      await go(tester, '/me/members');
      expect(find.text('5 位同工'), findsOneWidget);
      await tapText(tester, '李美玉');
      expect(find.text('主日崇拜 負責人'), findsOneWidget, reason: 'a 負責人 given on its page is listed here too');
      await tapText(tester, '新增身分');
      double at(String text) => tester.getTopLeft(find.text(text).last).dy;
      expect(at('管理員'), lessThan(at('牧者')));
      expect(at('牧者'), lessThan(at('行政')), reason: '牧者 before 行政, out of respect (2026-11-23)');
      for (final lead in ['聚會負責人', '事工負責人', '小組長']) {
        expect(find.text(lead), findsNothing, reason: 'given on its own page (2026-11-23)');
      }
      expect(find.textContaining('排所有服事表'), findsNothing, reason: 'the names alone, as 牧者 has (2026-11-23)');
      expect(find.textContaining('頁面指派'), findsNothing);
      await tapText(tester, '行政');
      expect(b.members['grace']!['mei']!.groups, {Group.rosterEditors, Group.calendarEditors});

      await tester.tap(find.bySemanticsLabel('移除「主日崇拜 負責人」'));
      await settle(tester);
      expect(b.members['grace']!['mei']!.identities, const [OfficeIdentity()]);
      expect(find.text('已移除「主日崇拜 負責人」'), findsOneWidget);
      await tapText(tester, '復原');
      expect(b.members['grace']!['mei']!.identities, const [ServiceLead('sunday'), OfficeIdentity()]);
    });

    testWidgets("a pastor of some services leads them; a whole church's is an admin", (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/members/mei');
      await tapText(tester, '新增身分');
      await tapText(tester, '牧者');
      await tapText(tester, '青年崇拜');
      expect(b.members['grace']!['mei']!.leadTypes, ['youth']);
      expect(find.text('青年崇拜 牧者'), findsOneWidget);
      await tapText(tester, '新增身分');
      await tapText(tester, '牧者');
      expect(find.text('什麼都能管'), findsNothing, reason: '全教會 says it (2026-11-23)');
      await tapText(tester, '全教會');
      final mei = b.members['grace']!['mei']!;
      expect(mei.identities, const [PastorIdentity(null)]);
      expect(mei.role, Role.admin, reason: 'what the rules and older apps read');
    });

    testWidgets('加入聚會 adds a service, and writes the flattened zoneTypes', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/members/john');
      expect(find.text('主日崇拜'), findsNothing, reason: 'in no service yet');
      await tapText(tester, '加入聚會');
      expect(find.text('加入聚會'), findsNWidgets(2), reason: 'a sheet headed by the row it opened from');
      await tapText(tester, '青年崇拜');
      expect(b.members['grace']!['john']!.zoneTypes, ['youth']);
      expect(find.text('加入聚會'), findsOneWidget, reason: 'picking one closes the sheet');
      expect(find.text('移出青年崇拜'), findsOneWidget);
    });

    testWidgets("a member's page has only their services, what they serve there ticked in a list", (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/members/mei');
      expect(find.text('青年崇拜'), findsNothing, reason: 'not one of hers');
      expect(findShown('司琴、招待'), findsOneWidget);
      expect(
        tester.getTopLeft(findShown('司琴、招待')).dx,
        tester.getTopLeft(find.text('服事項目')).dx,
        reason: 'under 服事項目, short or long, never beside it',
      );
      await tapText(tester, '服事項目');
      await tapText(tester, '司會');
      expect(b.members['grace']!['mei']!.zones.single.duties, ['司琴', '招待', '司會']);
      await tapText(tester, '司琴');
      expect(b.members['grace']!['mei']!.zones.single.duties, ['招待', '司會'], reason: 'the list stays open');
      await tapText(tester, '完成');
      expect(find.text('完成'), findsNothing);
      expect(findShownContaining('招待'), findsOneWidget, reason: 'the row says what is ticked now');
    });

    testWidgets('leaving a 牧區 clears its duties, and undo brings both back', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/members/mei');
      await tapText(tester, '移出主日崇拜');
      expect(b.members['grace']!['mei']!.zones, isEmpty);
      expect(find.text('不再是主日崇拜的同工'), findsOneWidget);
      await tapText(tester, '復原');
      expect(b.members['grace']!['mei']!.zones, const [
        Zone(serviceType: 'sunday', duties: ['司琴', '招待']),
      ]);
    });

    testWidgets('members in no 牧區 are marked, and admins are told on the home page', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await tapText(tester, '1 位同工還沒加入任何聚會');
      expect(find.textContaining('還沒加入任何聚會'), findsOneWidget, reason: 'John Chen, in the member list');
      expect(
        tester.getTopLeft(find.text('John Chen')).dy,
        lessThan(tester.getTopLeft(find.textContaining('王牧師')).dy),
        reason: 'above the admins: the next thing to do is putting him in one',
      );
      await tapText(tester, 'John Chen');
      await tapText(tester, '加入聚會');
      await tapText(tester, '主日崇拜');
      await go(tester, '/home');
      expect(find.textContaining('還沒加入任何聚會'), findsNothing, reason: 'everyone is in a 牧區 now');
    });

    testWidgets('an admin renames someone by tapping their name: here only, on the rosters too; 復原 takes it back', (
      tester,
    ) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/members/mei');
      await tapText(tester, '李美玉');
      await tester.enterText(find.byType(TextField).last, '美玉姐');
      await tapText(tester, '儲存');
      expect(b.members['grace']!['mei']!.name, '美玉姐');
      expect(b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, 4))]!.duties[1].people, ['美玉姐']);
      expect(find.text('美玉姐'), findsOneWidget, reason: 'the title');
      await tapText(tester, '復原');
      expect(b.members['grace']!['mei']!.name, '李美玉');
    });

    testWidgets('a name someone has is said as it is typed, and 儲存 waits for another', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/members/mei');
      await tapText(tester, '李美玉');
      await tester.enterText(find.byType(TextField).last, '陳志豪 ');
      await settle(tester);
      expect(find.text('教會裡已經有人叫「陳志豪」'), findsOneWidget, reason: 'before 儲存, not after the backend says so');
      await tapText(tester, '儲存');
      expect(find.byType(TextField), findsWidgets, reason: 'still asking');
      expect(b.members['grace']!['mei']!.name, '李美玉');
    });

    testWidgets('a new name shows at once while the backend renames them, and comes off again if it cannot', (
      tester,
    ) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/members/mei');
      b.renameHeld = Completer();
      await tapText(tester, '李美玉');
      await tester.enterText(find.byType(TextField).last, '美玉姐');
      await tapText(tester, '儲存');
      expect(find.text('美玉姐'), findsOneWidget, reason: 'the title, though the server has not answered');
      b.renameHeld!.complete();
      await settle(tester);
      expect(find.text('已改名'), findsOneWidget);
      expect(b.members['grace']!['mei']!.name, '美玉姐');

      b.renameHeld = Completer();
      await tapText(tester, '美玉姐');
      await tester.enterText(find.byType(TextField).last, '美玉');
      await tapText(tester, '儲存');
      expect(find.text('美玉'), findsOneWidget);
      b.renameHeld!.completeError(const CloudException(CloudErrorCode.unavailable));
      await settle(tester);
      expect(find.text('美玉姐'), findsOneWidget, reason: 'as it is');
      expect(find.text('美玉'), findsNothing);
    });

    testWidgets(
      'an admin giving the name of one without an account is asked whether they are one person, and merges them',
      (
        tester,
      ) async {
        final b = seededChurch();
        b.addPending('grace', const PendingMember(id: 'old-huang', name: '黃鎮台'));
        await pumpApp(tester, b);
        await go(tester, '/me/members/mei');
        await tapText(tester, '李美玉');
        await tester.enterText(find.byType(TextField).last, '黃鎮台');
        await settle(tester);
        expect(find.text('黃鎮台是沒有帳號的同工'), findsOneWidget);
        await tapText(tester, '儲存');
        expect(find.text('黃鎮台和李美玉是同一個人？'), findsOneWidget);
        await tapText(tester, '合併');
        expect(b.pendingMembers['grace']!.containsKey('old-huang'), isFalse);
        expect(b.members['grace']!['mei']!.name, '黃鎮台');
        expect(find.text('已合併'), findsOneWidget);
      },
    );

    testWidgets('行政 open anyone but an admin: their name and services, no 身分, merging or removing', (tester) async {
      final b = seededChurch(as: office, extra: [office]);
      b.addPending('grace', const PendingMember(id: 'old-huang', name: '黃鎮台'));
      await pumpApp(tester, b);
      await go(tester, '/me/members');
      await tapText(tester, '李美玉');
      expect(find.byIcon(Symbols.edit_rounded), findsOneWidget);
      expect(find.text('移出主日崇拜'), findsOneWidget);
      expect(find.text('身分'), findsNothing);
      expect(find.text('移除同工'), findsNothing);
      expect(find.text('合併沒有帳號的同工'), findsNothing);
      await tapText(tester, '加入聚會');
      await tapText(tester, '青年崇拜');
      expect(b.members['grace']!['mei']!.zoneTypes, ['sunday', 'youth']);

      await tapText(tester, '李美玉');
      await tester.enterText(find.byType(TextField).last, '黃鎮台');
      await settle(tester);
      expect(find.text('教會裡已經有人叫「黃鎮台」'), findsOneWidget, reason: 'merging is an admin\'s');
      await tapText(tester, '取消');

      await go(tester, '/me/members/pastor');
      expect(find.text('加入聚會'), findsNothing, reason: 'an admin is the admins\' to change');
      expect(find.byIcon(Symbols.edit_rounded), findsNothing);
    });

    testWidgets('removing uses undo, and commits after the window', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/members');
      await tapText(tester, '陳志豪');
      await tester.scrollUntilVisible(find.text('移除同工'), 300);
      await tapText(tester, '移除同工');
      expect(find.text('已移除「陳志豪」'), findsOneWidget);
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
      expect(find.text('管理員'), findsOneWidget);
      expect(find.text('移除'), findsNothing);
      expect(find.text('移除同工'), findsNothing);
    });

    testWidgets('an admin alone in the church is offered to invite people', (tester) async {
      final b = MemoryBackend(clock: testClock);
      final cid = b.addChurch('恩典堂', id: 'grace');
      b.addMember(cid, pastor);
      b.auth.signInAs('pastor@example.com', uid: 'pastor', name: pastor.name);
      b.users['pastor'] = UserProfile(uid: 'pastor', name: pastor.name, email: 'pastor@example.com');
      b.notify();
      await pumpApp(tester, b);
      await go(tester, '/me/members');
      expect(find.text('還沒有其他同工'), findsOneWidget);
      await tapText(tester, '邀請同工');
      expect(find.text('建立邀請連結'), findsOneWidget);

      await pumpApp(tester, seededChurch());
      await go(tester, '/me/members');
      expect(find.text('邀請同工'), findsNothing);
    });

    testWidgets('the profile name keeps its label once filled', (tester) async {
      await pumpApp(tester, seededChurch());
      await go(tester, '/me/profile/name');
      expect(find.text('王牧師'), findsOneWidget);
      expect(find.text('名字'), findsWidgets);
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
      await tapText(tester, '退出教會');
      expect(b.members['grace']!.containsKey('mei'), isFalse);
      expect(find.text('加入你的教會'), findsOneWidget);
    });

    testWidgets('leaving goes to 首頁 at once, the church gone when the backend says', (tester) async {
      final b = seededChurch(as: staffMei);
      await pumpApp(tester, b);
      await go(tester, '/me/church');
      await tester.scrollUntilVisible(find.text('退出教會'), 300);
      b.writeHeld = Completer();
      await tapText(tester, '退出教會');
      await tapText(tester, '退出教會');
      expect(find.text('退出教會'), findsNothing, reason: 'not a blank page, nor tapped again');
      expect(find.byType(NavigationBar), findsOneWidget);
      b.writeHeld!.complete();
      b.writeHeld = null;
      await settle(tester);
      expect(find.text('加入你的教會'), findsOneWidget);
      expect(findShown('已退出〈恩典堂〉'), findsOneWidget);
    });

    testWidgets('leaving that fails says so on 首頁, still in the church', (tester) async {
      final b = seededChurch(as: staffMei);
      await pumpApp(tester, b);
      await go(tester, '/me/church');
      await tester.scrollUntilVisible(find.text('退出教會'), 300);
      b.failNextWrite = const CloudException(CloudErrorCode.unavailable);
      await tapText(tester, '退出教會');
      await tapText(tester, '退出教會');
      expect(b.members['grace']!.containsKey('mei'), isTrue);
      expect(findShown('連不上網路，請檢查後再試一次'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('an admin has no leave entry and is told to hand over', (tester) async {
      await pumpApp(tester, seededChurch());
      await go(tester, '/me/church');
      await tester.scrollUntilVisible(findShown('要退出教會，先把管理員交給別人'), 300);
      expect(findShown('退出教會'), findsNothing);
      expect(findShown('要退出教會，先把管理員交給別人'), findsOneWidget);
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
    testWidgets('the only admin is told at once why, and where to go; deleting is off', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/account');
      expect(findShownContaining('你是〈恩典堂〉唯一的管理員'), findsOneWidget);
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '刪除帳號')).onPressed, isNull);
      await tapText(tester, '前往同工');
      expect(findShown('5 位同工'), findsOneWidget);
      expect(b.auth.currentUser, isNotNull);
    });

    testWidgets('a church no one else is in is named, and goes with the account', (tester) async {
      final b = seededChurch();
      final alone = b.addChurch('小羊團契', id: 'lamb');
      b.addMember(alone, pastor);
      b.members['grace']!.removeWhere((uid, _) => uid != pastor.uid);
      await pumpApp(tester, b);
      await go(tester, '/account');
      expect(findShownContaining('〈恩典堂〉〈小羊團契〉只有你一個人，會跟帳號一起刪除'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '刪除帳號'));
      await settle(tester);
      await tester.tap(find.text('刪除帳號').last);
      await settle(tester);
      expect(b.churches['grace']!.status, ChurchStatus.deleted);
      expect(b.churches['lamb']!.status, ChurchStatus.deleted);
      expect(b.auth.currentUser, isNull);
    });

    testWidgets('an admin with another admin may delete the account', (tester) async {
      final b = seededChurch(
        extra: const [Member(uid: 'admin2', name: '張長老', role: Role.admin)],
      );
      await pumpApp(tester, b);
      await go(tester, '/account');
      expect(find.textContaining('唯一的管理員'), findsNothing);
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '刪除帳號')).onPressed, isNotNull);
    });

    testWidgets('staff delete their account and are signed out', (tester) async {
      final b = seededChurch(as: staffHao);
      await pumpApp(tester, b);
      await go(tester, '/account');
      await tester.tap(find.widgetWithText(TextButton, '刪除帳號'));
      await settle(tester);
      expect(find.text('刪除你的帳號？'), findsOneWidget);
      expect(
        findShownContaining('帳號與個人資料會刪除且無法復原'),
        findsOneWidget,
        reason: 'said once on the page, not again in the dialog',
      );
      await tester.tap(find.text('刪除帳號').last);
      await settle(tester);
      expect(b.members['grace']!.containsKey('hao'), isFalse);
      expect(find.text('使用 Google 登入'), findsOneWidget);
    });
  });

  group('invites and settings', () {
    testWidgets('create an invite and revoke it', (tester) async {
      final b = seededChurch();
      final telemetry = RecordingTelemetry();
      await pumpApp(tester, b, overrides: [telemetryProvider.overrideWithValue(telemetry)]);
      await go(tester, '/me/invites');
      await tapText(tester, '建立邀請連結');
      expect(b.invites.length, 1);
      expect(telemetry.named('share'), [
        {'content_type': 'invite', 'method': 'share'},
      ]);
      final code = b.invites.keys.single;
      await go(tester, '/me');
      await go(tester, '/me/invites');
      await tapText(tester, '10月31日 到期');
      await tapText(tester, '停用');
      expect(b.invites[code]!.revoked, isTrue);
      expect(find.text('已停用，這個連結不能再用來加入'), findsOneWidget);
      expect(find.text('10月31日 到期'), findsNothing);
    });

    testWidgets('停用 takes the link off the list at once; failing, it comes back and says so', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      captureOutbox(tester);
      await go(tester, '/me/invites');
      await tapText(tester, '建立邀請連結');
      final code = b.invites.keys.single;
      await tester.pump(const Duration(seconds: 5));
      b.writeHeld = Completer();
      await tapText(tester, '10月31日 到期');
      await tapText(tester, '停用');
      expect(find.text('10月31日 到期'), findsNothing, reason: 'not to be 停用 twice');
      b.writeHeld!.completeError(const CloudException(CloudErrorCode.unavailable));
      b.writeHeld = null;
      await settle(tester);
      expect(b.invites[code]!.revoked, isFalse);
      expect(findShown('連不上網路，請檢查後再試一次'), findsOneWidget);
      expect(find.text('10月31日 到期'), findsOneWidget);
    });

    testWidgets('an invite works for 30 days, with no length to choose', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      captureOutbox(tester);
      await go(tester, '/me/invites');
      expect(find.byType(SegmentedButton<int>), findsNothing);
      await tapText(tester, '建立邀請連結');
      final invite = b.invites.values.single;
      expect(invite.expiresAt.difference(testNow).inDays, 30);
    });

    testWidgets('the same 聚會 again shares the link there is, its 30 days counted again', (tester) async {
      var now = testNow;
      final b = seededChurch(clock: () => now);
      await pumpApp(tester, b);
      final out = captureOutbox(tester);
      await go(tester, '/me/invites');
      await tapText(tester, '青年崇拜');
      await tapText(tester, '建立邀請連結');
      final code = b.invites.keys.single;

      now = testNow.add(const Duration(days: 5));
      await tester.pump(const Duration(days: 5));
      await settle(tester);
      await tester.tap(find.text('青年崇拜').first);
      await settle(tester);
      await tapText(tester, '建立邀請連結');
      expect(b.invites.keys, [code]);
      expect(b.invites[code]!.expiresAt, now.add(const Duration(days: 30)));
      expect(out.sharedTexts, hasLength(2));
      expect(out.sharedTexts.last, out.sharedTexts.first, reason: 'the same link');
      expect(find.text('11月5日 到期'), findsOneWidget);

      // Another set of 聚會 is another link.
      for (final service in ['主日崇拜', '青年崇拜']) {
        await tester.tap(find.text(service).first);
        await settle(tester);
      }
      await tapText(tester, '建立邀請連結');
      expect(b.invites, hasLength(2));
      expect(
        b.invites.values.map((i) => {...i.zoneTypes}),
        containsAll([
          {'youth'},
          {'sunday', 'youth'},
        ]),
      );
    });

    testWidgets('the 牧區 an invite joins look like boxes to tick', (tester) async {
      await pumpApp(tester, seededChurch());
      await go(tester, '/me/invites');
      expect(find.byIcon(Symbols.circle_rounded), findsNWidgets(2));
      await tapText(tester, '青年崇拜');
      expect(find.byIcon(Symbols.check_circle_rounded), findsOneWidget);
    });

    testWidgets('an invite can put those who join in some 牧區, named on it', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      captureOutbox(tester);
      await go(tester, '/me/invites');
      await tapText(tester, '青年崇拜');
      await tapText(tester, '建立邀請連結');
      final invite = b.invites.values.single;
      expect(invite.zoneTypes, ['youth']);
      expect(find.text('青年崇拜'), findsNWidgets(2), reason: 'the picker, and the invite');
    });

    testWidgets('an invite in the list is what it joins and when it ends, not its code', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      captureOutbox(tester);
      await go(tester, '/me/invites');
      await tapText(tester, '青年崇拜');
      await tapText(tester, '建立邀請連結');
      await tapText(tester, '建立邀請連結');
      expect(b.invites, hasLength(2), reason: 'each invite picks its own: none, this time');
      for (final code in b.invites.keys) {
        expect(find.text(code), findsNothing);
      }
      expect(findShown('邀請連結'), findsOneWidget);
      for (final joins in ['青年崇拜', '只加入教會']) {
        final row = find.ancestor(of: find.text(joins).last, matching: find.byType(ListRow));
        expect(
          find.descendant(of: row, matching: find.text('10月31日 到期')),
          findsOneWidget,
          reason: joins,
        );
      }
    });

    testWidgets('ticking no service is allowed; the screen says they see no rosters until put in one', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      captureOutbox(tester);
      await go(tester, '/me/invites');
      expect(find.text('加入後成為這些聚會的同工'), findsOneWidget);
      expect(findShown('沒選的話，對方加入後看不到服事表，要等你把他加進聚會。'), findsOneWidget);
      await tapText(tester, '建立邀請連結');
      expect(b.invites.values.single.zoneTypes, isEmpty);
    });

    testWidgets('with one service, the invite has it ticked already; it can be unticked', (tester) async {
      final b = seededChurch();
      b.setServices('grace', const [sundayService]);
      await pumpApp(tester, b);
      captureOutbox(tester);
      await go(tester, '/me/invites');
      expect(find.byIcon(Symbols.check_circle_rounded), findsOneWidget);
      await tapText(tester, '建立邀請連結');
      expect(b.invites.values.single.zoneTypes, ['sunday']);
      expect(find.byIcon(Symbols.check_circle_rounded), findsOneWidget, reason: 'ticked again for the next');

      // The first 主日崇拜 is the picker's; the other names the invite made.
      await tester.tap(find.text('主日崇拜').first);
      await settle(tester);
      expect(find.byIcon(Symbols.check_circle_rounded), findsNothing);
      await tapText(tester, '建立邀請連結');
      expect(
        b.invites.values.map((i) => i.zoneTypes),
        containsAll([
          ['sunday'],
          isEmpty,
        ]),
      );
    });

    testWidgets('an invite leaves the list when it expires, and stops working', (tester) async {
      var now = testNow;
      final b = seededChurch(clock: () => now);
      await pumpApp(tester, b);
      captureOutbox(tester);
      await go(tester, '/me/invites');
      await tapText(tester, '建立邀請連結');
      final code = b.invites.keys.single;
      expect(find.text('10月31日 到期'), findsOneWidget);

      now = testNow.add(const Duration(days: 29, hours: 23));
      await tester.pump(const Duration(days: 29, hours: 23));
      await settle(tester);
      expect(find.text('10月31日 到期'), findsOneWidget, reason: 'an hour left');
      expect((await b.cloud.previewInvite(code)).code, code);

      now = testNow.add(const Duration(days: 30));
      await tester.pump(const Duration(hours: 1));
      await settle(tester);
      expect(find.text('10月31日 到期'), findsNothing);
      await expectLater(
        b.cloud.previewInvite(code),
        throwsA(isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.inviteExpired)),
      );
    });

    testWidgets('the shared invite link is under the church URL', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      final out = captureOutbox(tester);
      await go(tester, '/me/invites');
      await tapText(tester, '建立邀請連結');
      final code = b.invites.keys.single;
      final church = b.churches.values.single.name;
      expect(
        out.sharedTexts.single,
        '邀請你加入〈$church〉\nhttps://marthasit-dev.web.app/c/grace/join/$code?openExternalBrowser=1',
      );
      await tapText(tester, '10月31日 到期');
      await tapText(tester, '複製連結');
      expect(out.copied.single, 'https://marthasit-dev.web.app/c/grace/join/$code?openExternalBrowser=1');
    });

    testWidgets('a new invite that cannot be shared or copied is shown to copy by hand', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      captureOutbox(tester, blocked: true);
      await go(tester, '/me/invites');
      await tapText(tester, '建立邀請連結');
      final code = b.invites.keys.single;
      expect(find.text('沒有儲存成功，請檢查網路後再試一次'), findsNothing, reason: 'the invite was saved');
      expect(find.text('沒辦法自動複製，請選取下面的文字自己複製'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is SelectableText && w.data!.contains('/c/grace/join/$code')),
        findsOneWidget,
      );
    });

    testWidgets('a service with no day arranged is deleted at once; 復原 brings it back', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/groups/service/youth');
      expect(find.text('啟用'), findsNothing, reason: 'deleted, not turned off');
      await scrollTo(tester, '刪除聚會');
      await tapText(tester, '刪除聚會');
      expect(find.text('刪除「青年崇拜」？'), findsNothing, reason: 'nothing arranged to lose');
      expect(b.services['grace']!.byId('youth'), isNull);
      expect(b.services['grace']!.ids, containsAll(['sunday', 'youth']), reason: 'an ID is never reused');
      expect(find.text('聚會與事工'), findsOneWidget, reason: 'back on the list');
      expect(find.text('青年崇拜'), findsNothing);
      await tapText(tester, '復原');
      expect(b.services['grace']!.services, const [sundayService, youthService]);
    });

    testWidgets('deleting a service with days arranged asks first; it leaves 服事表 and 首頁', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/groups/service/sunday');
      await scrollTo(tester, '刪除聚會');
      await tapText(tester, '刪除聚會');
      expect(find.text('刪除「主日崇拜」？'), findsOneWidget);
      expect(findShown('已經排好的 2 天服事表會一起刪除'), findsOneWidget);
      await tapText(tester, '取消');
      expect(b.services['grace']!.byId('sunday'), isNotNull);
      await tapText(tester, '刪除聚會');
      await tapText(tester, '刪除');
      expect(b.services['grace']!.byId('sunday'), isNull);
      expect(find.text('已刪除「主日崇拜」'), findsOneWidget);
      expect(b.rosters['grace']!.keys, contains(Roster.idFor('sunday', Day(2026, 10, 11))), reason: 'kept, for 復原');
      await tester.pump(const Duration(seconds: 10));
      await go(tester, '/rosters');
      expect(find.textContaining('主日崇拜'), findsNothing);
      await go(tester, '/');
      expect(find.textContaining('主日崇拜'), findsNothing, reason: "王牧師's 司會 on 10/11 went with it");
    });

    testWidgets("a deleted service's 負責人 is not shown as one, by name or by its ID", (tester) async {
      final b = seededChurch(
        extra: const [
          Member(uid: 'lead', name: '張青年', identities: [ServiceLead('youth')]),
        ],
      );
      b.setServices('grace', const [sundayService]);
      await pumpApp(tester, b);
      await go(tester, '/me/members');
      expect(find.textContaining('youth'), findsNothing);
      await go(tester, '/me/members/lead');
      expect(find.textContaining('youth'), findsNothing);
      expect(find.textContaining('負責人'), findsNothing);
    });

    testWidgets('a service meets on several weekdays, each with its own roster; at least one stays ticked', (
      tester,
    ) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/groups/service/youth');
      await tapText(tester, '聚會時間');
      for (final day in ['週一', '週二', '週三', '週四', '週五']) {
        await tapText(tester, day);
      }
      await tapText(tester, '週六');
      await tapText(tester, '完成');
      expect(b.services['grace']!.byId('youth')!.weekdays, [1, 2, 3, 4, 5]);
      expect(find.text('週一到週五'), findsOneWidget);
      await go(tester, '/rosters');
      await tapText(tester, '青年崇拜');
      expect(find.text('週一'), findsWidgets, reason: 'a roster each day');
      expect(find.text('週二'), findsWidgets);

      await go(tester, '/me/groups/service/youth');
      await tapText(tester, '聚會時間');
      for (final day in ['週一', '週二', '週三', '週四', '週五']) {
        await tapText(tester, day);
      }
      await tapText(tester, '完成');
      expect(b.services['grace']!.byId('youth')!.weekdays, [5], reason: 'the last one stays');

      await go(tester, '/me/groups');
      expect(find.text('週五'), findsOneWidget);
    });

    testWidgets('a service every other week, from this week or the next, has rosters on its weeks only', (
      tester,
    ) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/groups/service/youth');
      await tapText(tester, '聚會時間');
      await tapText(tester, '隔週');
      expect(find.text('從哪一週開始'), findsOneWidget);
      expect(find.text('這週'), findsOneWidget, reason: 'Saturday 10/3');
      await tapText(tester, '下週');
      await tapText(tester, '完成');
      final youth = b.services['grace']!.byId('youth')!;
      expect((youth.every, youth.startsOn), (2, Day(2026, 10, 10)));
      expect(find.text('隔週六'), findsOneWidget);

      await go(tester, '/rosters');
      await tapText(tester, '青年崇拜');
      // Its days: 10月 10, 24; 11月 7, 21.
      expect(find.text('10'), findsOneWidget);
      expect(find.text('24'), findsOneWidget);
      expect(find.text('3'), findsNothing, reason: 'the week it is off');
      expect(find.text('17'), findsNothing);

      await go(tester, '/me/groups/service/youth');
      await tapText(tester, '聚會時間');
      await tapText(tester, '每月');
      expect(find.text('第 1 個週六'), findsOneWidget);
      await tapText(tester, '第 3 個週六');
      await tapText(tester, '完成');
      expect(b.services['grace']!.byId('youth')!.monthWeeks, [1, 3]);
      expect(find.text('每月第 1、3 個週六'), findsOneWidget);

      await go(tester, '/me/groups/service/youth');
      await tapText(tester, '聚會時間');
      await tapText(tester, '每週');
      await tapText(tester, '完成');
      expect(b.services['grace']!.byId('youth'), youthService);
    });

    testWidgets('renaming a duty moves members\' zones and the staff order with it', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/groups/service/sunday/duties');
      await tapText(tester, '招待');
      await tapText(tester, '服事項目名稱');
      await tester.enterText(find.byType(TextField).last, '接待');
      await tapText(tester, '儲存');
      expect(b.services['grace']!.byId('sunday')!.duties, ['司會', '司琴', '接待']);
      expect(b.members['grace']!['hao']!.serves('sunday', '接待'), isTrue);
      expect(b.staffOrders['grace']!['sunday']!.rankingOf('接待'), ['陳志豪', '李美玉']);
      expect(savedDay(b, 4).duties.map((d) => d.role), contains('招待'), reason: 'arranged days keep their wording');
    });

    testWidgets('a duty can be deleted from its page, not only by swiping', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/groups/service/sunday/duties');
      await tapText(tester, '司琴');
      await tapText(tester, '刪除');
      expect(b.services['grace']!.byId('sunday')!.duties, ['司會', '招待']);
      await tapText(tester, '復原');
      expect(b.services['grace']!.byId('sunday')!.duties, ['司會', '司琴', '招待']);
    });

    testWidgets('changing the template does not touch arranged rosters', (tester) async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me/groups/service/sunday/duties');
      expect(find.textContaining('左滑刪除'), findsWidgets, reason: 'the swipe is not seen otherwise');
      await tester.drag(find.text('司琴').first, const Offset(-500, 0));
      await settle(tester);
      expect(b.services['grace']!.byId('sunday')!.duties, ['司會', '招待']);
      expect(savedDay(b, 4).duties.map((d) => d.role), ['司會', '司琴', '招待']);
    });
  });

  testWidgets('a short swipe stops with 刪除 showing, deleted only once it is tapped; a tap on the row shuts it', (
    tester,
  ) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me/groups/service/sunday/duties');
    await tester.drag(find.text('司琴').first, const Offset(-100, 0));
    await settle(tester);
    expect(find.text('刪除'), findsOneWidget, reason: 'it stays open');
    expect(b.services['grace']!.byId('sunday')!.duties, ['司會', '司琴', '招待'], reason: 'nothing deleted yet');
    // Red only where the row moved off: the row is clear, and red under
    // all of it turned the whole row red.
    final row = tester.getSize(find.ancestor(of: find.text('司琴').first, matching: find.byType(SwipeAction)));
    final red = find.ancestor(of: find.text('刪除'), matching: find.byType(ColoredBox)).first;
    expect(tester.getSize(red).width, lessThan(row.width / 2));

    // Its name is slid off the screen's edge: the rest of the row.
    await tester.tapAt(Offset(200, tester.getCenter(find.text('司琴').first).dy));
    await settle(tester);
    expect(find.text('刪除'), findsNothing, reason: 'shut, not opened');
    expect(find.text('司琴'), findsOneWidget);

    await tester.drag(find.text('司琴').first, const Offset(-100, 0));
    await settle(tester);
    await tester.drag(find.text('招待').first, const Offset(-100, 0));
    await settle(tester);
    expect(find.text('刪除'), findsOneWidget, reason: 'one open at a time');
    await tapText(tester, '刪除');
    expect(b.services['grace']!.byId('sunday')!.duties, ['司會', '司琴']);
    expect(find.text('已刪除「招待」'), findsOneWidget);
  });

  group('operator', () {
    testWidgets('is hidden without the claim', (tester) async {
      await pumpApp(tester, seededChurch());
      await go(tester, '/me');
      expect(find.text('平台後台'), findsNothing);
    });

    testWidgets('keeps the cost list and shows the target the backend works out', (tester) async {
      // Scripted: the backend's target for NT\$ costs, a yearly one a twelfth.
      Funding published(List<CostItem> costs) => Funding(
        month: '2026-10',
        target: costs.fold<num>(0, (t, c) => t + (c.per == CostPeriod.year ? c.amount / 12 : c.amount)).round(),
        received: 0,
        carried: 0,
        monthsLeft: 0,
      );
      final b = seededChurch()..publishFunding = published;
      b.auth.operators.add('pastor');
      b.fundingCosts = const [CostItem(name: '雲端', amount: 300, currency: Currency.twd, per: CostPeriod.month)];
      b.funding = published(b.fundingCosts);
      await pumpApp(tester, b);
      await go(tester, '/admin/funding');
      expect(find.text('每月目標 NT\$300'), findsOneWidget);

      await tapText(tester, '新增項目');
      await tester.enterText(find.byKey(const Key('costName')), '網域');
      await tester.enterText(find.byKey(const Key('costAmount')), '600');
      await tapText(tester, '每年');
      await tapText(tester, '儲存');
      expect(
        b.fundingCosts.last,
        const CostItem(name: '網域', amount: 600, currency: Currency.twd, per: CostPeriod.year),
      );
      expect(find.text('每月目標 NT\$350'), findsOneWidget);

      await tapText(tester, '雲端');
      await tester.enterText(find.byKey(const Key('costAmount')), '400');
      await tapText(tester, '儲存');
      expect(find.text('每月目標 NT\$450'), findsOneWidget);

      await tapText(tester, '網域');
      await tapText(tester, '刪除');
      expect(b.fundingCosts, const [CostItem(name: '雲端', amount: 400, currency: Currency.twd, per: CostPeriod.month)]);
      await tapText(tester, '復原');
      expect(b.fundingCosts.map((c) => c.name), ['雲端', '網域']);
    });

    testWidgets('finds the back office at the top of 我的: churches, stats and costs, one tap each', (tester) async {
      final b = seededChurch();
      b.auth.operators.add('pastor');
      await pumpApp(tester, b);
      await go(tester, '/me');
      for (final row in ['教會', '統計', '雲端費用']) {
        expect(find.text(row).hitTestable(), findsOneWidget, reason: '$row without scrolling');
      }
      await tapText(tester, '雲端費用');
      expect(GoRouter.of(tester.element(find.byType(Scaffold).last)).state.uri.path, '/admin/funding');
    });

    testWidgets('a saved cost shows at once; the target says it is updating until the backend has it', (
      tester,
    ) async {
      Funding published(List<CostItem> costs) => Funding(
        month: '2026-10',
        target: costs.fold<num>(0, (t, c) => t + c.amount).round(),
        received: 0,
        carried: 0,
        monthsLeft: 0,
      );
      final b = seededChurch()..publishFunding = published;
      b.auth.operators.add('pastor');
      b.fundingCosts = const [CostItem(name: '雲端', amount: 300, currency: Currency.twd, per: CostPeriod.month)];
      b.funding = published(b.fundingCosts);
      await pumpApp(tester, b);
      await go(tester, '/admin/funding');
      b.writeDelay = const Duration(seconds: 3);

      await tapText(tester, '雲端');
      await tester.enterText(find.byKey(const Key('costAmount')), '400');
      await tapText(tester, '儲存');
      expect(find.text('NT\$400 · 每月'), findsOneWidget, reason: 'the new amount, before the backend answers');
      expect(find.text('每月目標 NT\$300'), findsNothing, reason: 'no stale target while it updates');
      expect(find.text('每月目標更新中…'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(find.text('每月目標 NT\$400'), findsOneWidget);
      expect(find.text('每月目標更新中…'), findsNothing);
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

  testWidgets('deleting a service, a duty or a 事工 goes back at once, off the list while the backend has it', (
    tester,
  ) async {
    final b = seededChurch();
    b.ministries['grace'] = const MinistrySettings(
      ministries: [
        Ministry(id: 'worship', name: '敬拜團', duties: [MinistryDuty('sunday', '司琴')]),
      ],
      ids: ['worship'],
    );
    await pumpApp(tester, b);

    await go(tester, '/me/groups/service/youth');
    b.writeHeld = Completer();
    await scrollTo(tester, '刪除聚會');
    await tapText(tester, '刪除聚會');
    expect(find.text('聚會與事工'), findsOneWidget, reason: 'back on the list at once');
    expect(find.text('青年崇拜'), findsNothing);
    b.writeHeld!.complete();
    await settle(tester);
    expect(b.services['grace']!.byId('youth'), isNull);

    await go(tester, '/me/groups/ministry/worship');
    b.writeHeld = Completer();
    await scrollTo(tester, '刪除事工');
    await tapText(tester, '刪除事工');
    expect(find.text('刪除事工'), findsNothing, reason: 'back at once');
    expect(find.text('敬拜團'), findsNothing);
    b.writeHeld!.complete();
    await settle(tester);
    expect(b.ministries['grace']!.ministries, isEmpty);

    await go(tester, '/me/groups/service/sunday/duties');
    await go(tester, '/me/groups/duty?service=sunday&name=招待');
    b.writeHeld = Completer();
    await scrollTo(tester, '刪除');
    await tapText(tester, '刪除');
    expect(find.text('刪除'), findsNothing, reason: 'back at once');
    b.writeHeld!.complete();
    await settle(tester);
    expect(b.services['grace']!.byId('sunday')!.duties, isNot(contains('招待')));
  });

  testWidgets('my name saved closes at once, the new name shown while it is saved', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me/profile');
    await tapText(tester, '名字');
    await tester.enterText(find.byType(TextField), '王大衛');
    await tester.pump();
    b.writeHeld = Completer();
    await tapText(tester, '儲存');
    expect(find.byType(TextField), findsNothing, reason: 'closed at once');
    expect(find.text('王大衛'), findsOneWidget, reason: 'shown, though the server has not answered');
    b.writeHeld!.complete();
    await settle(tester);
    expect(find.text('王大衛'), findsOneWidget);
    expect(find.text('已更新名字'), findsOneWidget);
  });
}
