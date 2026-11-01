import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/swap.dart';

import '../support/harness.dart';
import '../support/seed.dart';

// 找人代／交換 (#92). The tests start on Thursday 1 October 2026: 李美玉
// plays on 10/4, 張雅雨 on 10/18; both are on 司琴's list.

const yu = Member(
  uid: 'yu',
  name: '張雅雨',
  zones: [
    Zone(serviceType: 'sunday', duties: ['司琴']),
  ],
);

MemoryBackend church({Member as = staffMei}) {
  final b = seededChurch(as: as, extra: const [yu]);
  b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, 18))] = Roster(
    type: 'sunday',
    day: Day(2026, 10, 18),
    duties: const [
      Duty(role: '司琴', people: ['張雅雨'], uids: {'張雅雨': 'yu'}),
    ],
  );
  b.notify();
  return b;
}

Future<void> go(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await settle(tester);
}

String path(WidgetTester tester) => GoRouter.of(tester.element(find.byType(Scaffold).last)).state.uri.path;

List<SwapRequest> requests(MemoryBackend b) => [...?b.swapRequests['grace']?.values];

/// My row of [duty] on the day's page, tapped.
Future<void> myRow(WidgetTester tester, String duty) async {
  await tester.tap(find.text(duty).first);
  await settle(tester);
}

void main() {
  testWidgets('my own duty: 請人代 asks those free on the list, and 收回 takes it back', (tester) async {
    final b = church();
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-04');
    await myRow(tester, '司琴');
    expect(find.text('請人代'), findsOneWidget);
    await tester.tap(find.text('請人代'));
    await settle(tester);
    expect(find.text('已請 1 位同工代，有人接手會通知你'), findsOneWidget);
    final r = requests(b).single;
    expect((r.kind, r.from, r.duty), (SwapKind.cover, 'mei', '司琴'));
    expect(r.asked, ['yu']);

    await myRow(tester, '司琴');
    expect(find.text('已請人代，還沒有人接手'), findsOneWidget);
    await tester.tap(find.text('收回'));
    await settle(tester);
    expect(find.text('已收回'), findsOneWidget);
    expect(requests(b).single.status, SwapStatus.withdrawn);
  });

  testWidgets('nobody free on the list: says to ask the lead, and asks nobody', (tester) async {
    final b = church();
    b.unavailable['grace'] = {'yu': const UnavailableDays().add(Day(2026, 10, 4), Day(2026, 10, 4))};
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-04');
    await myRow(tester, '司琴');
    await tester.tap(find.text('請人代'));
    await settle(tester);
    expect(find.text('名單上那天沒有其他有空的同工，請找負責人'), findsOneWidget);
    expect(requests(b), isEmpty);
  });

  testWidgets('和別週交換 lists who is on it on later days, and asks the one picked', (tester) async {
    final b = church();
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-04');
    await myRow(tester, '司琴');
    await tester.tap(find.text('和別週交換'));
    await settle(tester);
    expect(find.text('和誰交換司琴？'), findsOneWidget);
    await tester.tap(find.text('張雅雨'));
    await settle(tester);
    expect(find.text('已請張雅雨交換，對方接受才換'), findsOneWidget);
    final r = requests(b).single;
    expect((r.kind, r.to, r.toDay), (SwapKind.swap, 'yu', Day(2026, 10, 18)));
  });

  testWidgets('asked to cover: 我來 takes it, goes to the day, and 復原 gives it back', (tester) async {
    final b = church(as: yu);
    b.swapRequests['grace'] = {
      'r1': SwapRequest(
        id: 'r1',
        kind: SwapKind.cover,
        serviceId: 'sunday',
        day: Day(2026, 10, 4),
        duty: '司琴',
        from: 'mei',
        fromName: '李美玉',
        asked: const ['yu'],
      ),
    };
    await pumpApp(tester, b);
    await go(tester, '/rosters/request/r1');
    expect(find.text('李美玉想請你代'), findsOneWidget);
    await tester.tap(find.text('我來'));
    await settle(tester);
    expect(peopleOn(b, 4, '司琴'), ['張雅雨']);
    expect(path(tester), '/rosters/sunday/2026-10-04');
    expect(find.text('已接手'), findsOneWidget);
    await tester.tap(find.text('復原'));
    await settle(tester);
    expect(peopleOn(b, 4, '司琴'), ['李美玉']);
    expect(requests(b).single.isOpen, isTrue);
  });

  testWidgets('asked to swap: 不方便 closes it, and the page says so', (tester) async {
    final b = church(as: yu);
    b.swapRequests['grace'] = {
      'r1': SwapRequest(
        id: 'r1',
        kind: SwapKind.swap,
        serviceId: 'sunday',
        day: Day(2026, 10, 4),
        duty: '司琴',
        from: 'mei',
        fromName: '李美玉',
        to: 'yu',
        toName: '張雅雨',
        toDay: Day(2026, 10, 18),
      ),
    };
    await pumpApp(tester, b);
    await go(tester, '/rosters/request/r1');
    expect(find.text('李美玉想和你交換'), findsOneWidget);
    expect(find.text('李美玉改成'), findsOneWidget);
    await tester.tap(find.text('不方便'));
    await settle(tester);
    expect(requests(b).single.status, SwapStatus.declined);
    expect(find.text('你說了不方便'), findsOneWidget);
    expect(find.text('接受'), findsNothing);
  });

  testWidgets('a request the roster no longer bears is void', (tester) async {
    final b = church(as: yu);
    b.swapRequests['grace'] = {
      'r1': SwapRequest(
        id: 'r1',
        kind: SwapKind.cover,
        serviceId: 'sunday',
        day: Day(2026, 10, 11),
        duty: '司琴',
        from: 'mei',
        fromName: '李美玉',
        asked: const ['yu'],
      ),
    };
    await pumpApp(tester, b);
    await go(tester, '/rosters/request/r1');
    expect(find.text('這個請求已經不算了：服事表改過，或日子已經過了'), findsOneWidget);
    expect(find.text('我來'), findsNothing);
  });

  testWidgets('whoever arranges finds it on their own name, beside changing it outright', (tester) async {
    final b = church(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-04');
    await tester.tap(find.text('林同工'));
    await settle(tester);
    expect(find.text('找人代／交換'), findsOneWidget);
    expect(find.text('交換'), findsOneWidget);
  });
}
