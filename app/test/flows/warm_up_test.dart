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
    await pumpApp(tester, b);
    for (final (path, what) in [
      ('/me/services/sunday', WarmUp.serviceEdit),
      ('/me/timezone', WarmUp.timeZone),
      ('/rosters/import/sunday', WarmUp.photoImport),
    ]) {
      await go(tester, path);
      expect(b.warmedUp, contains(what), reason: path);
    }
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
