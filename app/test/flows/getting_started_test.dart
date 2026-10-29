import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

// 開始使用 for a 身分: 青年崇拜 has nobody in it and nothing arranged yet,
// and 陳志豪 was just made its 負責人.
final youthLead = staffHao.withIdentities(const [ServiceLead('youth')]);

MemoryBackend youthChurch() => seededChurch(extra: [youthLead], as: youthLead);

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(findShown(text).last);
  await settle(tester);
}

Future<void> back(WidgetTester tester) async {
  GoRouter.of(tester.element(find.byType(Scaffold).last)).pop();
  await settle(tester);
}

void main() {
  testWidgets('a new 負責人 sees what to do first, what they can do, and each step opens its page', (tester) async {
    await pumpApp(tester, youthChurch());

    expect(find.text('開始使用 · 青年崇拜 負責人'), findsOneWidget);
    expect(find.text('排青年崇拜的服事表、加入和移出它的同工'), findsOneWidget);

    await tapText(tester, '加入青年崇拜的同工');
    expect(find.text('加入同工'), findsOneWidget, reason: "the service's page, where 同工 are added");
    await back(tester);

    await tapText(tester, '排青年崇拜的服事');
    expect(find.text('排好幾週'), findsOneWidget);
  });

  testWidgets('a step done is gone, and the list once every step is', (tester) async {
    final b = youthChurch();
    await pumpApp(tester, b);

    b.members['grace']!['john'] = johnOnSunday.copyWith(zones: const [Zone(serviceType: 'youth')]);
    b.notify();
    await settle(tester);
    expect(find.text('加入青年崇拜的同工'), findsNothing);
    expect(find.text('排青年崇拜的服事'), findsOneWidget);

    b.rosters['grace']![Roster.idFor('youth', Day(2026, 10, 3))] = Roster(
      type: 'youth',
      day: Day(2026, 10, 3),
      duties: const [
        Duty(role: '司會', people: ['John Chen'], uids: {'John Chen': 'john'}),
      ],
    );
    b.notify();
    await settle(tester);
    expect(find.text('開始使用 · 青年崇拜 負責人'), findsNothing);
  });

  testWidgets('不再顯示 puts it away on this device', (tester) async {
    await pumpApp(tester, youthChurch());

    await tapText(tester, '不再顯示');
    expect(find.text('開始使用 · 青年崇拜 負責人'), findsNothing);

    await tapText(tester, '服事表');
    await tapText(tester, '首頁');
    expect(find.text('開始使用 · 青年崇拜 負責人'), findsNothing);
  });

  testWidgets('a church between seasons, with nothing arranged ahead yet, is not new again', (tester) async {
    final b = youthChurch();
    b.members['grace']!['john'] = johnOnSunday.copyWith(zones: const [Zone(serviceType: 'youth')]);
    b.rosters['grace']![Roster.idFor('youth', Day(2026, 9, 26))] = Roster(
      type: 'youth',
      day: Day(2026, 9, 26),
      duties: const [
        Duty(role: '司會', people: ['John Chen'], uids: {'John Chen': 'john'}),
      ],
    );
    await pumpApp(tester, b);
    expect(find.text('開始使用 · 青年崇拜 負責人'), findsNothing);
  });

  testWidgets('a church long in use shows its people nothing to start', (tester) async {
    await pumpApp(tester, seededChurch(as: editor));
    expect(findShown('開始使用'), findsNothing);
  });

  testWidgets("a new church's admin is shown where to start, all under 開始使用", (tester) async {
    final b = MemoryBackend(clock: testClock);
    final cid = b.addChurch('活水堂', id: 'living');
    b.setServices(cid, const [sundayService]);
    b.addMember(cid, pastor);
    b.auth.signInAs('pastor@example.com', uid: pastor.uid, name: pastor.name);
    b.users[pastor.uid] = const UserProfile(uid: 'pastor', name: '王牧師', email: 'pastor@example.com');
    await pumpApp(tester, b);

    expect(find.text('開始使用'), findsOneWidget);
    await tapText(tester, '安排服事表');
    expect(find.text('還沒有安排任何人'), findsOneWidget);
  });
}
