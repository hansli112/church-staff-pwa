import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/design/components.dart';
import 'package:martha/core/languages.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import 'claim_test.dart' show movedChurch;

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(findShown(text).last);
  await settle(tester);
}

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

/// Signed up with email and password under [email], verified.
Future<String> registered(MemoryBackend b, String email) async {
  await b.auth.registerWithEmail('美玉', email, 'secret123', AppLanguage.zhHant);
  b.auth.verify(email);
  await b.auth.reload();
  return b.auth.currentUser!.uid;
}

Finder rowWith(String text) => find.ancestor(of: find.text(text), matching: find.byType(ListRow)).first;

void main() {
  testWidgets('a password account links a Google account under another email, and either signs in to it', (
    tester,
  ) async {
    final b = MemoryBackend(clock: testClock);
    final uid = await registered(b, 'mei.old@yahoo.com');
    await pumpApp(tester, b);
    await go(tester, '/account/sign-in');
    expect(find.text('Email 與密碼'), findsOneWidget);
    expect(find.text('解除連結'), findsNothing, reason: 'never the last way in');

    b.auth.googleAccount = 'mei@gmail.com';
    await tapText(tester, '連結 Google 帳號');
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('mei@gmail.com'), findsOneWidget);
    expect(find.text('連結 Google 帳號'), findsNothing, reason: 'one Google account at a time');
    expect(find.text('解除連結'), findsNWidgets(2));

    await b.auth.signOut();
    await b.auth.signInWithGoogle();
    expect(b.auth.currentUser!.uid, uid);
    expect(b.auth.currentUser!.email, 'mei.old@yahoo.com', reason: 'the account’s own email stays');
  });

  testWidgets('a Google account that is an account of its own is not linked, and says why', (tester) async {
    final b = MemoryBackend(clock: testClock);
    b.auth.signInAs('mei@gmail.com', uid: 'gmail-mei');
    await b.auth.signOut();
    await registered(b, 'mei.old@yahoo.com');
    await pumpApp(tester, b);
    await go(tester, '/account/sign-in');

    b.auth.googleAccount = 'mei@gmail.com';
    await tapText(tester, '連結 Google 帳號');
    expect(findShownContaining('你選的帳號已經是另一個馬大別忙帳號'), findsOneWidget);
    expect(b.auth.currentUser!.signIns.map((s) => s.method), [SignInMethod.password]);
  });

  testWidgets('closing Google’s sheet links nothing and says nothing', (tester) async {
    final b = MemoryBackend(clock: testClock);
    await registered(b, 'mei.old@yahoo.com');
    await pumpApp(tester, b);
    await go(tester, '/account/sign-in');
    b.auth.googleAccount = null;
    await tapText(tester, '連結 Google 帳號');
    expect(find.text('連結 Google 帳號'), findsOneWidget);
    expect(b.auth.currentUser!.signIns, hasLength(1));
  });

  testWidgets('unlinking asks first, and leaves the last way in', (tester) async {
    final b = MemoryBackend(clock: testClock);
    await registered(b, 'mei.old@yahoo.com');
    b.auth.googleAccount = 'mei@gmail.com';
    await b.auth.linkGoogle();
    await pumpApp(tester, b);
    await go(tester, '/account/sign-in');

    await tester.tap(find.descendant(of: rowWith('Google'), matching: find.text('解除連結')));
    await settle(tester);
    expect(findShown('之後就不能用 mei@gmail.com 登入這個帳號'), findsOneWidget);
    await tapText(tester, '解除連結');
    expect(find.text('Google'), findsNothing);
    expect(find.text('解除連結'), findsNothing);
    expect(find.text('連結 Google 帳號'), findsOneWidget);
  });

  testWidgets('a linked Google email on the moved list is asked, and joining brings back roles and rosters', (
    tester,
  ) async {
    final b = movedChurch(signIn: false);
    final uid = await registered(b, 'mei.old@yahoo.com');
    await pumpApp(tester, b);
    expect(find.textContaining('已經搬過來了'), findsNothing);

    await go(tester, '/account/sign-in');
    b.auth.googleAccount = 'mei@example.com';
    await tapText(tester, '連結 Google 帳號');
    await go(tester, '/welcome');
    expect(findShown('〈恩典堂〉的同工資料已經搬過來了，要加入嗎？'), findsOneWidget);
    await tapText(tester, '加入');

    final m = b.members['grace']![uid]!;
    expect(m.role, Role.leader);
    // Self-host's roster editing was their 牧區's: its 負責人 now (#82).
    expect(m.groups, isEmpty);
    expect(m.leadTypes, ['sunday']);
    expect(m.email, 'mei.old@yahoo.com');
    expect(b.rosters['grace']!.values.single.duties.single.uids, {'李美玉': uid});
  });

  group('Apple', () {
    testWidgets('where Apple signs in, a password account links an Apple ID under another email, and it signs in', (
      tester,
    ) async {
      final b = MemoryBackend(clock: testClock)..auth.offersApple = true;
      final uid = await registered(b, 'mei.old@yahoo.com');
      await pumpApp(tester, b);
      await go(tester, '/account/sign-in');

      b.auth.appleAccount = 'x7f9d2@privaterelay.appleid.com';
      await tapText(tester, '連結 Apple 帳號');
      expect(findShown('已連結 Apple 帳號'), findsOneWidget);
      expect(find.text('Apple'), findsOneWidget);
      expect(find.text('x7f9d2@privaterelay.appleid.com'), findsOneWidget);
      expect(find.text('連結 Apple 帳號'), findsNothing, reason: 'one Apple ID at a time');
      expect(find.text('連結 Google 帳號'), findsOneWidget);

      await b.auth.signOut();
      await b.auth.signInWithApple();
      expect(b.auth.currentUser!.uid, uid);
      expect(b.auth.currentUser!.email, 'mei.old@yahoo.com', reason: 'the account’s own email stays');
    });

    testWidgets('an Apple ID that is an account of its own is not linked, and says why', (tester) async {
      final b = MemoryBackend(clock: testClock)..auth.offersApple = true;
      b.auth.appleAccount = 'mei@icloud.com';
      await b.auth.signInWithApple();
      await b.auth.signOut();
      await registered(b, 'mei.old@yahoo.com');
      await pumpApp(tester, b);
      await go(tester, '/account/sign-in');

      await tapText(tester, '連結 Apple 帳號');
      expect(findShownContaining('你選的帳號已經是另一個馬大別忙帳號'), findsOneWidget);
      expect(b.auth.currentUser!.signIns.map((s) => s.method), [SignInMethod.password]);
    });

    testWidgets('a linked Apple ID can be unlinked, while another way in is left', (tester) async {
      final b = MemoryBackend(clock: testClock)..auth.offersApple = true;
      await registered(b, 'mei.old@yahoo.com');
      b.auth.appleAccount = 'mei@icloud.com';
      await b.auth.linkApple();
      await pumpApp(tester, b);
      await go(tester, '/account/sign-in');

      await tester.tap(find.descendant(of: rowWith('Apple'), matching: find.text('解除連結')));
      await settle(tester);
      await tapText(tester, '解除連結');
      expect(find.text('Apple'), findsNothing);
      expect(find.text('連結 Apple 帳號'), findsOneWidget);
    });

    testWidgets('a linked Apple email on the moved list is asked too', (tester) async {
      final b = movedChurch(signIn: false)..auth.offersApple = true;
      final uid = await registered(b, 'mei.old@yahoo.com');
      await pumpApp(tester, b);
      await go(tester, '/account/sign-in');
      b.auth.appleAccount = 'mei@example.com';
      await tapText(tester, '連結 Apple 帳號');
      await go(tester, '/welcome');
      expect(findShown('〈恩典堂〉的同工資料已經搬過來了，要加入嗎？'), findsOneWidget);
      await tapText(tester, '加入');
      expect(b.members['grace']![uid]!.leadTypes, ['sunday']);
    });

    testWidgets('where Apple does not sign in, there is no Apple to link', (tester) async {
      final b = MemoryBackend(clock: testClock);
      await registered(b, 'mei.old@yahoo.com');
      await pumpApp(tester, b);
      await go(tester, '/account/sign-in');
      expect(find.text('連結 Google 帳號'), findsOneWidget);
      expect(find.text('連結 Apple 帳號'), findsNothing);
    });
  });

  testWidgets('a password account with another email’s Google linked still verifies its own', (tester) async {
    final b = MemoryBackend(clock: testClock);
    await b.auth.registerWithEmail('美玉', 'mei.old@yahoo.com', 'secret123', AppLanguage.zhHant);
    b.auth.googleAccount = 'mei@gmail.com';
    await b.auth.linkGoogle();
    final user = b.auth.currentUser!;
    expect(user.verified, isFalse, reason: 'Google vouches for its own email, not this one');
    expect(user.claimEmails, ['mei@gmail.com']);
  });

  testWidgets('my name at the top of 設定 leads to 登入方式, which 設定 itself no longer lists', (tester) async {
    final b = movedChurch(signIn: false);
    b.auth.signInAs('pastor@grace.org', uid: 'pastor');
    await pumpApp(tester, b);
    await go(tester, '/me');
    for (final moved in ['登入方式', '登出', '刪除帳號', '隱私權政策', '服務條款', '目前版本']) {
      expect(find.text(moved, skipOffstage: false), findsNothing, reason: moved);
    }
    await tapText(tester, 'pastor@grace.org');
    expect(find.text('登出'), findsOneWidget);
    expect(find.text('刪除帳號'), findsOneWidget);
    await tapText(tester, '登入方式');
    expect(find.text('pastor@grace.org'), findsOneWidget);
  });
}
