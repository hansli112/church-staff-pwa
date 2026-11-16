import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/web_page.dart';

import '../support/harness.dart';
import '../support/seed.dart';
import 'add_to_home_test.dart' show android, iphone, mac;

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(findShown(text).last);
  await settle(tester);
}

/// 恩典堂, taking requests to join, with the invite WELCOME26.
MemoryBackend graceInviting() {
  final b = MemoryBackend(clock: testClock)..auth.googleAccount = 'new@gmail.com';
  b.addChurch('恩典堂', id: 'grace');
  b.addMember('grace', const Member(uid: 'admin', name: '牧師', role: Role.admin));
  b.invites['WELCOME26'] = Invite(
    code: 'WELCOME26',
    churchId: 'grace',
    churchName: '恩典堂',
    expiresAt: testNow.add(const Duration(days: 7)),
  );
  return b;
}

/// Opens [location] on [userAgent], signed out.
Future<void> open(
  WidgetTester tester,
  MemoryBackend b,
  String userAgent,
  String location, {
  List<Override> overrides = const [],
}) async {
  await pumpApp(tester, b, overrides: [userAgentProvider.overrideWithValue(userAgent), ...overrides]);
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

void main() {
  testWidgets('an invite link on an iPhone’s browser offers the app first', (tester) async {
    final launches = captureLaunches();
    await open(tester, graceInviting(), iphone, '/c/grace/join/WELCOME26?openExternalBrowser=1');
    expect(findShown('邀請你加入〈恩典堂〉'), findsOneWidget);
    expect(findShown('裝好後，再點一次邀請連結'), findsOneWidget);
    expect(find.text('使用 Google 登入'), findsNothing, reason: 'the app first');

    await tapText(tester, '從 App Store 下載');
    expect(launches.opened.single, 'https://apps.apple.com/app/id6823826952');
  });

  testWidgets('用網頁版 goes on to join here, and is not asked again', (tester) async {
    final b = graceInviting();
    await open(tester, b, iphone, '/c/grace/join/WELCOME26');
    await tapText(tester, '用網頁版');
    expect(findShown('受邀加入〈恩典堂〉'), findsOneWidget);
    await tapText(tester, '使用 Google 登入');
    expect(find.text('從 App Store 下載'), findsNothing, reason: 'chosen already, on this phone');
    expect(findShown('加入'), findsWidgets);
  });

  testWidgets('a church URL on an Android phone offers Google Play', (tester) async {
    final launches = captureLaunches();
    await open(tester, graceInviting(), android, '/c/grace');
    expect(findShown('恩典堂'), findsOneWidget);
    expect(findShown('裝好後，再點一次教會網址'), findsOneWidget);
    await tapText(tester, '從 Google Play 下載');
    expect(launches.opened.single, 'https://play.google.com/store/apps/details?id=app.marthasit');
  });

  for (final (where, ua, overrides) in [
    ('a computer', mac, <Override>[]),
    ('the app itself', '', <Override>[]),
    ('the page on the home screen', iphone, [standaloneProvider.overrideWithValue(true)]),
  ]) {
    testWidgets('on $where, an invite link goes straight to signing in', (tester) async {
      await open(tester, graceInviting(), ua, '/c/grace/join/WELCOME26', overrides: overrides);
      expect(find.text('使用 Google 登入'), findsOneWidget);
    });
  }

  testWidgets('signed in on a phone’s browser, an invite to another church still offers the app', (tester) async {
    final b = seededChurch();
    b.addChurch('希望堂', id: 'hope');
    b.invites['HOPE2026'] = Invite(
      code: 'HOPE2026',
      churchId: 'hope',
      churchName: '希望堂',
      expiresAt: testNow.add(const Duration(days: 7)),
    );
    await open(tester, b, android, '/c/hope/join/HOPE2026');
    expect(findShown('邀請你加入〈希望堂〉'), findsOneWidget);
    await tapText(tester, '用網頁版');
    expect(findShown('加入'), findsWidgets);
    expect(find.text('從 Google Play 下載'), findsNothing);
  });
}
