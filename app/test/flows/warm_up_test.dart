import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

void main() {
  testWidgets('opening the event editor warms up saving, before anything is saved', (tester) async {
    const calendarEditor = Member(uid: 'cal', name: '行事曆同工', groups: {Group.calendarEditors});
    final b = seededChurch(as: calendarEditor, extra: const [calendarEditor]);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    expect(b.warmedUp, isNot(contains(WarmUp.calendarWrite)));
    await tester.tap(find.byTooltip('新增活動'));
    await settle(tester);
    expect(b.warmedUp, contains(WarmUp.calendarWrite));
  });

  testWidgets('the pages that end in a slow call warm it up as they open', (tester) async {
    final b = seededChurch();
    b.smallGroups['grace'] = {'joy': const SmallGroupDetails(id: 'joy', name: '喜樂小組', service: 'sunday')};
    await pumpApp(tester, b);
    for (final (path, what) in [
      ('/me/groups/service/sunday', WarmUp.serviceEdit),
      ('/me/groups/small/joy', WarmUp.smallGroupEdit),
      ('/me/groups/duty?service=sunday&name=%E5%8F%B8%E7%90%B4', WarmUp.dutyList),
      ('/me/timezone', WarmUp.timeZone),
      ('/rosters/import/sunday', WarmUp.photoImport),
      ('/rosters/plan/sunday', WarmUp.planWeeks),
      ('/rosters/request/r1', WarmUp.swapAnswer),
      ('/me/attendance', WarmUp.attendanceRemind),
      ('/me/groups/service/sunday/staff', WarmUp.groupStaff),
    ]) {
      await go(tester, path);
      expect(b.warmedUp, contains(what), reason: path);
    }
  });

  testWidgets("a 事工's 負責人, whose changes the backend checks, warms that up where they arrange; an admin does not", (
    tester,
  ) async {
    final b = seededChurch(
      extra: [
        staffMei.withIdentities(const [MinistryLead('worship')]),
      ],
      as: staffMei,
    );
    b.ministries['grace'] = const MinistrySettings(
      ministries: [
        Ministry(id: 'worship', name: '敬拜團', duties: [MinistryDuty('sunday', '司琴')]),
      ],
      ids: ['worship'],
    );
    await pumpApp(tester, b);
    for (final path in ['/rosters/plan/sunday', '/rosters/sunday/2026-10-04', '/rosters/event/e1']) {
      b.warmedUp.clear();
      await go(tester, path);
      expect(b.warmedUp, contains(WarmUp.ledDuties), reason: path);
    }

    final admin = seededChurch();
    await pumpApp(tester, admin);
    await go(tester, '/rosters/plan/sunday');
    await go(tester, '/rosters/sunday/2026-10-04');
    expect(admin.warmedUp, isNot(contains(WarmUp.ledDuties)), reason: 'saved without it');
  });

  testWidgets('whoever arranges, tapping their own name on the day, warms up 請人代', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-04');
    expect(b.warmedUp, isNot(contains(WarmUp.swapAsk)));
    await tester.tap(find.text('林同工').last);
    await settle(tester);
    expect(find.text('我不行'), findsOneWidget);
    expect(b.warmedUp, contains(WarmUp.swapAsk));
  });

  testWidgets('同工 warms up answering a request to join, only while someone asks', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me/members');
    expect(b.warmedUp, isNot(contains(WarmUp.joinAnswer)));
    await go(tester, '/me');
    b.joinRequests['grace'] = {
      'new': JoinRequest(uid: 'new', name: '新朋友', email: 'new@example.com', note: '', createdAt: testNow),
    };
    b.notify();
    await go(tester, '/me/members');
    expect(b.warmedUp, contains(WarmUp.joinAnswer));
  });

  testWidgets('joining or starting a church warms it up as its page opens', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/welcome/join');
    expect(b.warmedUp, contains(WarmUp.joinChurch));
    await go(tester, '/welcome/create');
    expect(b.warmedUp, contains(WarmUp.createChurch));
  });
}
