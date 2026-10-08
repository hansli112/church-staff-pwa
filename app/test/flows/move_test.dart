import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/core/design/components.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/features/church/move_screen.dart';

import '../support/harness.dart';

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

/// What reading the move file gives: scripted, the backend reads it.
const preview = MovePreview(
  members: 3,
  rosters: 2,
  services: ['主日崇拜', '青年崇拜'],
  people: [
    MovePerson(id: 'old-pastor', name: '王牧師', email: 'pastor@grace.org'),
    MovePerson(id: 'old-mei', name: '李美玉', email: 'mei@example.com'),
    MovePerson(id: 'old-hao', name: '陳志豪'),
  ],
);

/// Signed in, no church yet, with a file picked that reads as [answer].
Future<MemoryBackend> start(WidgetTester tester, Object answer, {String email = 'pastor@grace.org'}) async {
  final b = MemoryBackend(clock: testClock)..moveAnswer = answer;
  b.auth.signInAs(email, uid: 'me', name: '新帳號');
  await pumpApp(tester, b, overrides: [moveFilePickerProvider.overrideWithValue(() async => utf8.encode('{}'))]);
  await tapText(tester, '建立新教會');
  await tester.ensureVisible(find.text('從舊版搬過來'));
  await tapText(tester, '從舊版搬過來');
  return b;
}

void main() {
  testWidgets('upload, preview, pick who I am, and the church is made', (tester) async {
    final b = await start(tester, preview);
    await tapText(tester, '選擇搬家檔');
    expect(find.text('3 位'), findsOneWidget);
    expect(find.text('2 天'), findsOneWidget);
    expect(find.text('主日崇拜、青年崇拜'), findsOneWidget);
    expect(
      tester.widget<ListRow>(find.widgetWithText(ListRow, '王牧師')).selected,
      isTrue,
      reason: 'same email as the signed-in account',
    );

    await tester.enterText(find.widgetWithText(TextField, '教會名稱'), '恩典堂');
    await tester.pump();
    await tester.ensureVisible(find.text('建立教會並搬過來'));
    await tapText(tester, '建立教會並搬過來');

    final cid = b.churches.keys.single;
    expect(b.churches[cid]!.name, '恩典堂');
    expect(b.members[cid]!['me']!.role, Role.admin);
    expect(b.members[cid]!['me']!.name, '王牧師');
    expect(b.pendingMembers[cid]!.keys, unorderedEquals(['old-mei', 'old-hao']));
    expect(b.moveFiles, isEmpty);
    expect(find.byType(NavigationBar), findsOneWidget);

    await go(tester, '/me/members');
    expect(find.text('2 位還沒登入'), findsOneWidget);
    expect(find.text('還沒登入・mei@example.com'), findsOneWidget);
    expect(find.text('還沒登入'), findsOneWidget, reason: '陳志豪 has no email');
  });

  testWidgets('I can be nobody in the file, with any account', (tester) async {
    final b = await start(tester, preview, email: 'brand.new@gmail.com');
    await tapText(tester, '選擇搬家檔');
    expect(tester.widgetList<ListRow>(find.byType(ListRow)).where((r) => r.selected == true), isEmpty);
    await tester.enterText(find.widgetWithText(TextField, '教會名稱'), '恩典堂');
    await tester.pump();
    await tester.ensureVisible(find.text('建立教會並搬過來'));
    await tapText(tester, '建立教會並搬過來');
    final cid = b.churches.keys.single;
    expect(b.members[cid]!['me']!.role, Role.admin);
    expect(b.pendingMembers[cid]!.length, 3);
  });

  testWidgets('a wrong file or one too large says so', (tester) async {
    await start(tester, const CloudException(CloudErrorCode.moveInvalid));
    await tapText(tester, '選擇搬家檔');
    expect(find.text('這不是搬家檔，請確認選對了檔案'), findsOneWidget);
  });

  testWidgets('over 2,000 members is refused with the reason', (tester) async {
    await start(tester, const CloudException(CloudErrorCode.moveTooLarge));
    await tapText(tester, '選擇搬家檔');
    expect(find.text('同工超過 2,000 位或服事表超過 20,000 天，沒辦法自動搬，請聯絡我們'), findsOneWidget);
  });
}
