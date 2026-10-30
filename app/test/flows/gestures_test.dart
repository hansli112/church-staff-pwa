import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

// How the phone's own ways out work: back, swiping a sheet down, tapping
// outside it, a swipe from the edge. As Apple's and Android's guidelines
// have them.

Future<void> go(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await settle(tester);
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

String path(WidgetTester tester) => GoRouter.of(tester.element(find.byType(Scaffold).last)).state.uri.path;

/// Android's back, as the system sends it.
Future<void> back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await settle(tester);
}

const calendarEditor = Member(uid: 'cal', name: '行事曆同工', groups: {Group.calendarEditors});

/// 喜樂小組, led by 陳志豪, meeting on Fridays, with 回報人數 on.
MemoryBackend joyChurch() {
  final b = seededChurch(
    clock: () => ChurchTimeZone.taipei.instantOf(DateTime.utc(2026, 10, 9, 21, 30)),
  );
  b.churches['grace'] = b.churches['grace']!.copyWith(attendanceSince: () => Day(2026, 10, 1));
  b.smallGroups['grace'] = {
    'joy': const SmallGroupDetails(id: 'joy', name: '喜樂小組', service: 'sunday', weekday: DateTime.friday),
  };
  b.members['grace']!['hao'] = staffHao.withIdentities(const [SmallGroupLead('joy')]);
  return b;
}

/// Runs [body] as on an iPhone.
Future<void> onIPhone(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  testWidgets('a new event closes with 取消 untouched; once named, every way out asks first', (tester) async {
    final b = seededChurch(as: calendarEditor, extra: const [calendarEditor]);
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tester.tap(find.byTooltip('新增活動'));
    await settle(tester);
    await tapText(tester, '取消');
    expect(find.text('新增活動'), findsNothing, reason: 'closed, nothing to lose');

    await tester.tap(find.byTooltip('新增活動'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '禱告會');
    await tester.pump();
    await back(tester);
    expect(find.text('放棄變更？'), findsOneWidget);
    await tapText(tester, '繼續編輯');
    expect(find.text('禱告會'), findsOneWidget, reason: 'still there');
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    expect(find.text('放棄變更？'), findsOneWidget);
    await tapText(tester, '繼續編輯');
    await tapText(tester, '取消');
    await tapText(tester, '放棄變更');
    expect(find.text('新增活動'), findsNothing);
    expect((b.calendarEvents['grace'] ?? const []).map((e) => e.title), isNot(contains('禱告會')));
  });

  testWidgets('a sheet with nothing changed just closes: 聚會時間, 填寫人數, 特別活動', (tester) async {
    await pumpApp(tester, joyChurch());
    await go(tester, '/me/groups/small/joy');
    await tapText(tester, '聚會時間');
    await back(tester);
    expect(find.text('放棄變更？'), findsNothing);
    expect(find.text('隔週'), findsNothing, reason: 'closed');

    await tester.scrollUntilVisible(find.text('未填').first, 200, scrollable: find.byType(Scrollable).last);
    await tapText(tester, '未填');
    await back(tester);
    expect(find.text('放棄變更？'), findsNothing);
    expect(find.text('這次沒聚會'), findsNothing, reason: 'closed');

    await go(tester, '/rosters/sunday/2026-10-11');
    await tester.tap(find.byTooltip('編輯'));
    await settle(tester);
    await tapText(tester, '特別活動');
    await back(tester);
    expect(find.text('放棄變更？'), findsNothing);
    expect(find.text('加入常用選項'), findsNothing, reason: 'closed');
  });

  testWidgets('a sheet with a change asks before going: 聚會時間, 填寫人數, 特別活動', (tester) async {
    final b = joyChurch();
    await pumpApp(tester, b);
    await go(tester, '/me/groups/small/joy');
    await tapText(tester, '聚會時間');
    await tapText(tester, '隔週');
    await back(tester);
    await tapText(tester, '放棄變更');
    expect(b.smallGroups['grace']!['joy']!.every, 1);

    await tester.scrollUntilVisible(find.text('未填').first, 200, scrollable: find.byType(Scrollable).last);
    await tapText(tester, '未填');
    await tester.enterText(find.widgetWithText(TextField, '人數'), '8');
    await back(tester);
    expect(find.text('放棄變更？'), findsOneWidget);
    await tapText(tester, '繼續編輯');
    await tapText(tester, '儲存');
    expect(b.attendance['grace']!['small:joy']!.days.values, contains(const AttendanceDay.count(8)));

    await go(tester, '/rosters/sunday/2026-10-11');
    await tester.tap(find.byTooltip('編輯'));
    await settle(tester);
    await tapText(tester, '特別活動');
    await tapText(tester, '聖餐');
    await back(tester);
    expect(find.text('放棄變更？'), findsOneWidget);
    await tapText(tester, '放棄變更');

    Future<void> addDuty() async {
      await tester.tap(find.byTooltip('編輯'));
      await settle(tester);
      await tapText(tester, '新增服事項目');
    }

    await addDuty();
    await back(tester);
    expect(find.text('放棄變更？'), findsNothing, reason: 'nothing typed');
    await addDuty();
    await tester.enterText(find.byType(TextField), '燈光');
    await tester.pump();
    await back(tester);
    expect(find.text('放棄變更？'), findsOneWidget);
    await tapText(tester, '繼續編輯');
    await tapText(tester, '新增');
    expect(b.rosters['grace']!.values.any((r) => r.duties.any((d) => d.role == '燈光')), isTrue);
  });

  testWidgets("屬於 opens its choices in the event's own sheet, not a sheet over it", (tester) async {
    final b = seededChurch(
      as: staffHao,
      extra: [
        staffHao.withIdentities(const [MinistryLead('worship'), MinistryLead('sound')]),
      ],
    );
    b.ministries['grace'] = const MinistrySettings(
      ministries: [
        Ministry(id: 'worship', name: '敬拜團'),
        Ministry(id: 'sound', name: '音控組'),
      ],
      ids: ['worship', 'sound'],
    );
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpApp(tester, b);
    await go(tester, '/calendar');
    await tester.tap(find.byTooltip('新增活動'));
    await settle(tester);
    await tapText(tester, '屬於');
    expect(find.byType(BottomSheet), findsOneWidget, reason: 'one sheet');
    await tapText(tester, '音控組');
    expect(find.text('敬拜團'), findsNothing, reason: 'the choices close once one is picked');
    expect(find.text('音控組'), findsOneWidget, reason: "the row's value");
  });

  testWidgets('a tall sheet stops short of the top, the page behind still showing', (tester) async {
    await pumpApp(tester, joyChurch(), textScale: 3);
    await go(tester, '/me/groups/small/joy');
    await tester.tap(findShown('聚會時間'));
    await settle(tester);
    final top = tester.getTopLeft(find.byType(BottomSheet)).dy;
    expect(top, greaterThan(852 * 0.07));
  });

  testWidgets("Android's back on another tab goes to 首頁 first, and from there leaves", (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpApp(tester, seededChurch());
    await go(tester, '/me');
    await back(tester);
    expect(path(tester), '/home');
    expect(calls, isNot(contains('SystemNavigator.pop')));
    await back(tester);
    expect(calls, contains('SystemNavigator.pop'));
  });

  testWidgets('on an iPhone a changed sheet asks from below, as an action sheet', (tester) async {
    await onIPhone(() async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tapText(tester, '招待');
      await tapText(tester, '陳志豪');
      await tapText(tester, '取消');
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      await tapText(tester, '放棄變更');
      expect(find.text('排過招待的人'), findsNothing, reason: 'closed');
      expect(peopleOn(b, 11, '招待'), ['李美玉']);
    });
  });

  testWidgets("on an iPhone a name is asked for in Apple's alert, with its text field", (tester) async {
    await onIPhone(() async {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/me');
      await tapText(tester, '聚會與事工');
      await tapText(tester, '新增事工');
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      await tester.enterText(find.byType(CupertinoTextField), '敬拜團');
      await tapText(tester, '儲存');
      await tapText(tester, '取消');
      expect(b.ministries['grace']!.ministries.single.name, '敬拜團');
    });
  });
}
