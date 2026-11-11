import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/session.dart';

import '../support/harness.dart';
import '../support/seed.dart';
import '../support/telemetry.dart';

// 開始使用 for a 身分: 青年崇拜 has nobody in it and nothing arranged yet,
// and 陳志豪 was just made its 負責人.
final youthLead = staffHao.withIdentities(const [ServiceLead('youth')]);

MemoryBackend youthChurch() => seededChurch(extra: [youthLead], as: youthLead);

// 活水堂, just made: its admin alone, its services as they came.
MemoryBackend newChurch() {
  final b = MemoryBackend(clock: testClock);
  final cid = b.addChurch('活水堂', id: 'living');
  b.setServices(cid, const [sundayService]);
  b.addMember(cid, pastor);
  b.auth.signInAs('pastor@example.com', uid: pastor.uid, name: pastor.name);
  b.users[pastor.uid] = const UserProfile(uid: 'pastor', name: '王牧師', email: 'pastor@example.com');
  return b;
}

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
    expect(find.text('青年崇拜的同工'), findsOneWidget, reason: 'its 同工, where they are added');
    expect(find.text('加入同工'), findsOneWidget);
    await back(tester);

    await tapText(tester, '排青年崇拜的服事');
    expect(find.text('安排司會'), findsOneWidget, reason: '安排服事, for the one duty it has');
  });

  testWidgets('a step done is checked, and the list gone once every step is', (tester) async {
    final b = youthChurch();
    final telemetry = RecordingTelemetry();
    await pumpApp(tester, b, overrides: [telemetryProvider.overrideWithValue(telemetry)]);
    expect(telemetry.named('tutorial_step'), isEmpty, reason: 'nothing done yet');

    b.members['grace']!['john'] = johnOnSunday.copyWith(zones: const [Zone(serviceType: 'youth')]);
    b.notify();
    await settle(tester);
    expect(find.text('加入青年崇拜的同工'), findsOneWidget, reason: 'still listed, in its place');
    expect(find.bySemanticsLabel(RegExp('已完成')), findsOneWidget);
    expect(find.text('排青年崇拜的服事'), findsOneWidget);
    expect(telemetry.named('tutorial_step'), [
      {'step': 'addStaff'},
    ]);

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
    expect(telemetry.named('tutorial_step'), [
      {'step': 'addStaff'},
      {'step': 'planWeeks'},
    ]);
    expect(telemetry.named('tutorial_complete'), [null]);
  });

  testWidgets('不再顯示 puts it away on this device', (tester) async {
    final telemetry = RecordingTelemetry();
    await pumpApp(tester, youthChurch(), overrides: [telemetryProvider.overrideWithValue(telemetry)]);

    await tapText(tester, '不再顯示');
    expect(find.text('開始使用 · 青年崇拜 負責人'), findsNothing);

    await tapText(tester, '服事表');
    await tapText(tester, '首頁');
    expect(find.text('開始使用 · 青年崇拜 負責人'), findsNothing);
    expect(telemetry.events.where((e) => e.$1.startsWith('tutorial_')), isEmpty, reason: 'put away, not done');
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
    final telemetry = RecordingTelemetry();
    await pumpApp(tester, b, overrides: [telemetryProvider.overrideWithValue(telemetry)]);
    expect(find.text('開始使用 · 青年崇拜 負責人'), findsNothing);
    expect(telemetry.events.where((e) => e.$1.startsWith('tutorial_')), isEmpty, reason: 'done before, not now');
  });

  testWidgets('a church long in use shows its people nothing to start', (tester) async {
    await pumpApp(tester, seededChurch(as: editor));
    expect(findShown('開始使用'), findsNothing);
  });

  testWidgets('a church just moved from self-host: its admin is shown to invite the 同工 and may add a logo', (
    tester,
  ) async {
    final b = newChurch();
    b.addPending('living', const PendingMember(id: 'old-mei', name: '李美玉', email: 'mei@example.com'));
    b.rosters['living']![Roster.idFor('sunday', Day(2026, 10, 4))] = Roster(
      type: 'sunday',
      day: Day(2026, 10, 4),
      duties: const [
        Duty(role: '司會', people: ['李美玉'], uids: {'李美玉': 'old-mei'}),
      ],
    );
    await pumpApp(tester, b);
    expect(find.text('開始使用'), findsOneWidget);
    expect(find.text('建立邀請連結，傳給同工'), findsOneWidget, reason: 'nobody moved has signed in yet');
    expect(find.text('選用 · 邀請頁和首頁會顯示'), findsOneWidget);
    await tapText(tester, '上傳 logo');
    expect(find.text('教會資訊'), findsWidgets);
    await back(tester);
    await tapText(tester, '邀請同工');
    expect(find.text('邀請'), findsWidgets);
  });

  testWidgets('a 小組長 signing in after a move is shown nothing to start: their 小組 is there, not signed in yet', (
    tester,
  ) async {
    final b = seededChurch(as: staffHao);
    b.smallGroups['grace'] = {'joy': const SmallGroupDetails(id: 'joy', name: '喜樂小組', service: 'sunday')};
    b.members['grace']!['hao'] = staffHao.withIdentities(const [SmallGroupLead('joy')]);
    b.addPending(
      'grace',
      const PendingMember(
        id: 'old-ming',
        name: '王小明',
        zones: [
          Zone(serviceType: 'sunday', smallGroups: ['喜樂小組']),
        ],
      ),
    );
    await pumpApp(tester, b);
    expect(findShown('開始使用 · 喜樂小組 小組長'), findsNothing);

    b.pendingMembers['grace']!.clear();
    b.notify();
    await settle(tester);
    expect(findShown('開始使用 · 喜樂小組 小組長'), findsOneWidget, reason: 'nobody in it at all: add them');
  });

  testWidgets("a new church's admin is shown where to start, all under 開始使用", (tester) async {
    await pumpApp(tester, newChurch());

    expect(find.text('開始使用'), findsOneWidget);
    await tapText(tester, '安排服事表');
    expect(find.text('還沒有安排任何人'), findsOneWidget);
  });

  testWidgets("a new church's admin goes step by step: a step's page offers the next once it is done", (tester) async {
    final b = newChurch();
    await pumpApp(tester, b);
    expect(find.text('同工加入後就能做'), findsOneWidget, reason: 'nobody to put in a service yet');
    await tester.tap(find.text('加入主日崇拜的同工'));
    await settle(tester);
    expect(find.text('開始使用'), findsOneWidget, reason: 'not open before anyone joins');

    await tapText(tester, '設定聚會');
    expect(find.text('聚會與事工'), findsWidgets);
    await tapText(tester, '下一步：邀請同工');
    expect(find.text('建立邀請連結'), findsOneWidget);
    expect(findShown('下一步：安排服事表'), findsNothing, reason: 'nobody invited yet');

    await b.church('living').createInvite(validFor: const Duration(days: 7));
    b.notify();
    await settle(tester);
    expect(find.text('下一步：安排服事表'), findsOneWidget, reason: 'waiting on them; 小組 is optional');
    await back(tester);
    expect(find.text('開始使用'), findsOneWidget, reason: 'the services page gave way to the invites');
    expect(find.text('已發出邀請，等同工加入'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('已完成')), findsOneWidget, reason: 'the services, looked at');

    b.addMember('living', const Member(uid: 'john', name: 'John Chen'));
    b.notify();
    await settle(tester);
    expect(find.text('1 位同工還沒加入任何聚會'), findsNothing, reason: 'the step says it');
    await tapText(tester, '加入主日崇拜的同工');
    expect(find.text('主日崇拜的同工'), findsOneWidget);
    expect(findShown('下一步：安排服事表'), findsNothing);
    b.members['living']!['john'] = const Member(
      uid: 'john',
      name: 'John Chen',
      zones: [Zone(serviceType: 'sunday')],
    );
    b.notify();
    await settle(tester);
    await tapText(tester, '下一步：安排服事表');
    expect(find.text('還沒有安排任何人'), findsOneWidget);
  });
}
