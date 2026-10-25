import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/languages.dart';
import 'package:martha/data/backend.dart' show WarmUp;
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

/// 申請加入 (#88): someone with a church URL but no invite asks to join,
/// and an admin lets them in or not.
void main() {
  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(findShown(text).last);
    await settle(tester);
  }

  Future<void> go(WidgetTester tester, String location) async {
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
    await settle(tester);
  }

  /// Someone new, in no church, signed in.
  MemoryBackend newcomer() {
    final b = MemoryBackend(clock: testClock);
    b.addChurch('希望堂', id: 'hope');
    b.addMember('hope', pastor);
    b.auth.signInAs('new@example.com', uid: 'new', name: '新朋友');
    b.users['new'] = const UserProfile(uid: 'new', name: '新朋友', email: 'new@example.com');
    return b;
  }

  JoinRequest request({String uid = 'new', String name = '新朋友', String note = '', DateTime? rejectedAt}) => JoinRequest(
    uid: uid,
    name: name,
    email: '$uid@example.com',
    note: note,
    createdAt: testNow,
    rejectedAt: rejectedAt,
  );

  testWidgets('from the church URL, someone asks to join with a note, and can take it back', (tester) async {
    final b = newcomer();
    await pumpApp(tester, b);
    await go(tester, '/c/hope');
    expect(findShown('你還不是這間教會的同工。可以申請加入，管理員允許後就會加入；有邀請碼的話直接輸入。'), findsOneWidget);
    expect(findShown('輸入邀請碼'), findsOneWidget);
    expect(b.warmedUp, contains(WarmUp.askToJoin));

    await tapText(tester, '申請加入');
    expect(find.text('申請加入〈希望堂〉'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  我是敬拜團的小明 ');
    await tapText(tester, '送出申請');
    final sent = b.joinRequests['hope']!['new']!;
    expect(sent.note, '我是敬拜團的小明');
    expect(sent.name, '新朋友');
    expect(findShown('已送出申請，等管理員允許。允許後就會加入。'), findsOneWidget);
    expect(findShown('申請加入'), findsNothing);

    await tapText(tester, '取消申請');
    expect(b.joinRequests['hope']!.containsKey('new'), isFalse);
    expect(findShown('申請加入'), findsOneWidget);
  });

  testWidgets('let in while waiting on the church URL, they are taken into the church', (tester) async {
    final b = newcomer();
    b.joinRequests['hope'] = {'new': request()};
    await pumpApp(tester, b);
    await go(tester, '/c/hope');
    expect(findShown('已送出申請，等管理員允許。允許後就會加入。'), findsOneWidget);

    b.addMember('hope', const Member(uid: 'new', name: '新朋友'));
    await settle(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(findShown('希望堂'), findsWidgets);
  });

  testWidgets('someone in another church, let in, goes into this one', (tester) async {
    final b = seededChurch(as: staffMei);
    b.addChurch('希望堂', id: 'hope');
    b.addMember('hope', pastor);
    b.joinRequests['hope'] = {'mei': request(uid: 'mei', name: '李美玉')};
    await pumpApp(tester, b);
    await go(tester, '/c/hope');
    expect(findShown('已送出申請，等管理員允許。允許後就會加入。'), findsOneWidget);
    expect(findShown('回首頁'), findsOneWidget);

    b.addMember('hope', staffMei);
    await settle(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(findShown('希望堂'), findsWidgets);
  });

  testWidgets('turned down, they are told so and may ask again', (tester) async {
    final b = newcomer();
    b.joinRequests['hope'] = {'new': request(rejectedAt: testNow)};
    await pumpApp(tester, b);
    await go(tester, '/c/hope');
    expect(findShown('這次申請沒有通過，請直接聯絡教會。'), findsOneWidget);

    await tapText(tester, '再申請一次');
    await tapText(tester, '送出申請');
    expect(b.joinRequests['hope']!['new']!.rejectedAt, isNull);
    expect(findShown('已送出申請，等管理員允許。允許後就會加入。'), findsOneWidget);
  });

  testWidgets('a church that takes no requests asks for an invite instead', (tester) async {
    final b = newcomer();
    b.churches['hope'] = b.churches['hope']!.copyWith(takesJoinRequests: false);
    await pumpApp(tester, b);
    await go(tester, '/c/hope');
    expect(findShown('你還不是這間教會的同工。請向管理員要邀請連結來加入。'), findsOneWidget);
    expect(findShown('申請加入'), findsNothing);
  });

  testWidgets('an admin sees who asked on top of 同工, and lets one in and turns one down', (tester) async {
    final b = seededChurch();
    b.joinRequests['grace'] = {
      'new': request(note: '我是敬拜團的小明'),
      'other': request(uid: 'other', name: '陌生人'),
    };
    await pumpApp(tester, b);
    await go(tester, '/me/members');
    expect(findShown('2 位申請加入'), findsOneWidget);
    expect(findShownContaining('我是敬拜團的小明new@example.com · 10'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('允許新朋友加入'));
    await settle(tester);
    expect(b.members['grace']!['new']!.name, '新朋友');
    expect(b.joinRequests['grace']!.containsKey('new'), isFalse);
    expect(find.text('新朋友加入了'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('拒絕陌生人的申請'));
    await settle(tester);
    expect(b.members['grace']!['other'], isNull);
    expect(b.joinRequests['grace']!['other']!.rejectedAt, testNow);
    expect(findShown('申請加入'), findsNothing, reason: 'nobody waiting');
  });

  testWidgets('requests a month old are gone', (tester) async {
    final b = seededChurch();
    b.joinRequests['grace'] = {
      'new': JoinRequest(
        uid: 'new',
        name: '新朋友',
        createdAt: testNow.subtract(const Duration(days: JoinRequest.days)),
      ),
    };
    await pumpApp(tester, b);
    await go(tester, '/me/members');
    expect(findShown('新朋友'), findsNothing);
  });

  testWidgets('an admin stops taking requests in 教會資訊; only admins see the switch', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me/church');
    await tapText(tester, '開放申請加入');
    expect(b.churches['grace']!.takesJoinRequests, isFalse);
    await tapText(tester, '開放申請加入');
    expect(b.churches['grace']!.takesJoinRequests, isTrue);

    await pumpApp(tester, seededChurch(as: staffMei));
    await go(tester, '/me/church');
    expect(findShown('開放申請加入'), findsNothing);
  });

  testWidgets('a church taking no requests cannot let one in', (tester) async {
    final b = seededChurch();
    b.joinRequests['grace'] = {'new': request()};
    b.churches['grace'] = b.churches['grace']!.copyWith(takesJoinRequests: false);
    await pumpApp(tester, b);
    await go(tester, '/me/members');
    await tester.tap(find.bySemanticsLabel('允許新朋友加入'));
    await settle(tester);
    expect(find.text('這間教會沒有開放申請加入'), findsOneWidget);
    expect(b.members['grace']!['new'], isNull);
  });

  testWidgets('cancelling the note sends nothing', (tester) async {
    final b = newcomer();
    await pumpApp(tester, b);
    await go(tester, '/c/hope');
    await tapText(tester, '申請加入');
    await tapText(tester, '取消');
    expect(b.joinRequests['hope'], isNull);
    expect(findShown('申請加入'), findsOneWidget);
  });

  testWidgets('an email not yet verified is asked to verify first, and nothing is sent', (tester) async {
    final b = MemoryBackend(clock: testClock);
    b.addChurch('希望堂', id: 'hope');
    b.addMember('hope', pastor);
    await b.auth.registerWithEmail('新朋友', 'new@example.com', 'secret123', AppLanguage.zhHant);
    await pumpApp(tester, b);
    await go(tester, '/c/hope');
    expect(findShown('驗證你的 email'), findsOneWidget, reason: 'the banner, as on the welcome page');

    await tapText(tester, '申請加入');
    await tapText(tester, '送出申請');
    expect(find.text('驗證 email 後才能申請加入'), findsOneWidget);
    expect(b.joinRequests['hope'], isNull);
  });

  testWidgets('turned down by a church that since stopped taking requests: no asking again', (tester) async {
    final b = newcomer();
    b.joinRequests['hope'] = {'new': request(rejectedAt: testNow)};
    b.churches['hope'] = b.churches['hope']!.copyWith(takesJoinRequests: false);
    await pumpApp(tester, b);
    await go(tester, '/c/hope');
    expect(findShown('這次申請沒有通過，請直接聯絡教會。'), findsOneWidget);
    expect(findShown('再申請一次'), findsNothing);
    await tapText(tester, '輸入邀請碼');
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('the admins, and only they, can mute being told of requests', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me/notifications');
    expect(find.text('有人申請加入教會時（只通知管理員）'), findsOneWidget);
    await tester.tap(find.text('申請加入'));
    await settle(tester);
    expect(b.members['grace']!['pastor']!.mutedNotifications, {NotificationKind.joinRequest});

    await pumpApp(tester, seededChurch(as: staffMei));
    await go(tester, '/me/notifications');
    expect(find.text('申請加入'), findsNothing);
  });

  testWidgets('one already in the church is not listed; one taken back meanwhile cannot be let in', (tester) async {
    final b = seededChurch();
    b.joinRequests['grace'] = {
      'mei': request(uid: 'mei', name: '李美玉'),
      'new': request(),
    };
    await pumpApp(tester, b);
    await go(tester, '/me/members');
    expect(findShown('1 位申請加入'), findsOneWidget);

    b.joinRequests['grace']!.remove('new');
    await tester.tap(find.bySemanticsLabel('允許新朋友加入'));
    await settle(tester);
    expect(find.text('這個申請已經取消或過期了'), findsOneWidget);
    expect(b.members['grace']!['new'], isNull);
  });
}
