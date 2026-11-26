import 'dart:async';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAnimatedOpacity, RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/staff_order.dart';
import 'package:martha/state/providers.dart';
import 'package:martha/features/rosters/roster_image.dart';
import 'package:martha/state/export.dart';
import 'package:martha/state/session.dart';

import 'package:martha/features/rosters/people_picker.dart';
import 'package:martha/features/rosters/plan_weeks_screen.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../support/harness.dart';
import '../support/seed.dart';
import '../support/telemetry.dart';

// 安排服事 (#90). The tests start on Thursday 1 October 2026: 10/4 has
// everyone, 10/11 nobody on 司琴 yet.

Future<void> go(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await settle(tester);
}

String path(WidgetTester tester) => GoRouter.of(tester.element(find.byType(Scaffold).last)).state.uri.path;

/// The table's rows, scrolled up and down.
final rows = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).last;

/// The cell of [role] on October [date].
Finder cell(String role, int date) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == '$role, 10月$date日 週日',
);

/// The date at the start of October [day]'s row.
Finder date(int day) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == '打開 10月$day日 週日',
);

/// Picks [name] for [role] on October [day] in the table.
Future<void> pick(WidgetTester tester, String role, int day, String name) async {
  await tester.tap(cell(role, day));
  await settle(tester);
  await tester.tap(find.text(name).last);
  await settle(tester);
}

/// 完成 tells with [notice], or fails with [error].
class NotifyingBackend extends MemoryBackend {
  NotifyingBackend() : super(clock: testClock);

  PlannedNotice notice = (people: 1, later: false);
  Object? error;

  /// Saving the days fails with this.
  Object? saveError;

  /// Holds 完成's telling until completed.
  Completer<void>? held;

  @override
  ChurchData church(String churchId) => _NotifyingData(this, churchId);
}

class _NotifyingData extends MemoryChurchData {
  _NotifyingData(this.backend, String churchId) : super(backend, churchId);

  final NotifyingBackend backend;

  @override
  Future<void> compareAndSetRosters(RosterChange change) async {
    if (backend.saveError case final e?) throw e;
    return super.compareAndSetRosters(change);
  }

  @override
  Future<PlannedNotice> notifyPlanned(String serviceType) async {
    await backend.held?.future;
    final error = backend.error;
    if (error != null) throw error;
    await super.notifyPlanned(serviceType);
    return backend.notice;
  }
}

/// Who waits for 完成 to be told, on 主日崇拜's days.
Set<String> waiting(MemoryBackend b) => {
  for (final MapEntry(:key, :value)
      in b.planned['grace']?.entries ?? const <MapEntry<String, ({String service, List<String> roles})>>[])
    if (value.service == 'sunday') key.split('/').last,
};

/// 完成: what was changed saved, and the page gone.
Future<void> finish(WidgetTester tester) async {
  await tester.tap(find.text('完成'));
  await settle(tester);
}

/// Who is on [role] on October [day] in the table.
Finder shownOn(String role, int day, String name) => find.descendant(of: cell(role, day), matching: find.text(name));

/// Holds [from] until it lifts, then drags it onto [to] and lets go.
Future<void> drag(WidgetTester tester, Finder from, Finder to) async {
  final gesture = await tester.startGesture(tester.getCenter(from));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  await gesture.moveTo(tester.getCenter(to));
  await tester.pump();
  await gesture.up();
  await settle(tester);
}

class _Saver implements FileSaver {
  final files = <(String, Uint8List, String)>[];

  @override
  Future<bool> save(String name, Uint8List bytes, String mimeType) async {
    files.add((name, bytes, mimeType));
    return true;
  }
}

void main() {
  testWidgets('a day with no meeting is 沒有聚會 across its row, nothing to pick, and left out of the picture', (
    tester,
  ) async {
    final saver = _Saver();
    final b = seededChurch();
    b.rosters['grace']!['2026-10-11_sunday'] = Roster(
      type: 'sunday',
      day: Day(2026, 10, 11),
      duties: const [Duty(role: '司琴')],
      noService: true,
    );
    await pumpApp(tester, b, overrides: [fileSaverProvider.overrideWithValue(saver)]);
    await go(tester, '/rosters/plan/sunday');
    expect(find.text('沒有聚會'), findsOneWidget);
    // Its own line, level with its date; not the row's height with the
    // words at its top.
    final (words, date) = (
      tester.getRect(find.text('沒有聚會')),
      tester.getRect(find.bySemanticsLabel(RegExp('^打開.*10月11日'))),
    );
    expect(words.height, lessThan(date.height / 2));
    expect(words.center.dy, moreOrLessEquals(date.center.dy, epsilon: 1));
    await tester.tap(find.text('沒有聚會'));
    await settle(tester);
    expect(find.text('恢復聚會'), findsOneWidget, reason: 'its day opens, where it is undone');
    Navigator.of(tester.element(find.text('恢復聚會'))).pop();
    await settle(tester);
    await tester.tap(find.byIcon(Symbols.more_horiz_rounded));
    await settle(tester);
    await tester.tap(find.text('分享成圖片'));
    await settle(tester);
    final picture = find.byType(RosterImage);
    expect(find.descendant(of: picture, matching: find.text('10月11日')), findsNothing);
    expect(find.descendant(of: picture, matching: find.text('10月4日')), findsOneWidget);
  });

  testWidgets('⋯ 分享成圖片: a month of the roster as a picture, the months around it a tap away', (tester) async {
    final saver = _Saver();
    await pumpApp(tester, seededChurch(), overrides: [fileSaverProvider.overrideWithValue(saver)]);
    await go(tester, '/rosters/plan/sunday');
    await tester.tap(find.byIcon(Symbols.more_horiz_rounded));
    await settle(tester);
    await tester.tap(find.text('分享成圖片'));
    await settle(tester);
    final picture = find.byType(RosterImage);
    expect(find.descendant(of: picture, matching: find.text('主日崇拜 2026年10月')), findsOneWidget);
    expect(find.descendant(of: picture, matching: find.text('恩典堂')), findsOneWidget);
    expect(
      find.descendant(of: picture, matching: find.text('聖餐')),
      findsOneWidget,
      reason: "the day's 特別活動",
    );
    expect(
      find.descendant(of: picture, matching: find.text('待定')),
      findsNothing,
      reason: 'only who is arranged',
    );
    // A duty a row, a day a column: tall like a phone however many duties.
    final day11 = find.descendant(of: picture, matching: find.text('10月11日'));
    final day18 = find.descendant(of: picture, matching: find.text('10月18日'));
    expect(tester.getTopLeft(day11).dy, tester.getTopLeft(day18).dy);
    expect(tester.getTopLeft(day11).dx, lessThan(tester.getTopLeft(day18).dx));
    final duty = find.descendant(of: picture, matching: find.text('司會'));
    final person = find.descendant(of: picture, matching: find.text('王牧師')).first;
    expect(tester.getTopLeft(duty).dy, tester.getTopLeft(person).dy);
    expect(tester.getTopLeft(duty).dx, lessThan(tester.getTopLeft(person).dx));
    expect(tester.getCenter(person).dx, closeTo(tester.getCenter(day11).dx, 60));

    await tester.tap(find.byTooltip('下個月'));
    await settle(tester);
    expect(find.descendant(of: picture, matching: find.text('主日崇拜 2026年11月')), findsOneWidget);

    await tester.tap(find.text('分享'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(tester);
    final (name, bytes, mime) = saver.files.single;
    expect(name, '主日崇拜 2026年11月.png');
    expect(mime, 'image/png');
    expect(bytes.take(4), [0x89, 0x50, 0x4E, 0x47]);
  });

  testWidgets('分享成圖片 of a month half gone: its arranged days gone by are in it, the empty ones not', (tester) async {
    await pumpApp(tester, seededChurch(clock: () => ChurchTimeZone.taipei.instantOf(DateTime.utc(2026, 10, 20, 1))));
    await go(tester, '/rosters/plan/sunday');
    await tester.tap(find.byIcon(Symbols.more_horiz_rounded));
    await settle(tester);
    await tester.tap(find.text('分享成圖片'));
    await settle(tester);
    final picture = find.byType(RosterImage);
    expect(find.descendant(of: picture, matching: find.text('主日崇拜 2026年10月')), findsOneWidget);
    expect(
      find.descendant(of: picture, matching: find.text('林同工')),
      findsOneWidget,
      reason: 'the 4th, arranged',
    );
    expect(
      find.descendant(of: picture, matching: find.text('王牧師')),
      findsOneWidget,
      reason: 'the 11th, arranged',
    );
    expect(
      find.descendant(of: picture, matching: find.text('10月18日')),
      findsNothing,
      reason: 'gone by, nobody on it',
    );
    expect(
      find.descendant(of: picture, matching: find.text('10月25日')),
      findsOneWidget,
      reason: 'still to come',
    );
  });

  testWidgets('a cell picks its people on screen; 完成 saves them all and tells each once, going back', (tester) async {
    final b = seededChurch();
    final telemetry = RecordingTelemetry();
    await pumpApp(tester, b, overrides: [telemetryProvider.overrideWithValue(telemetry)]);
    await go(tester, '/rosters/plan/sunday');
    expect(find.text('2026年10月'), findsOneWidget);
    expect(find.text('2026年11月'), findsOneWidget);

    await tester.tap(cell('司琴', 11));
    await settle(tester);
    await tester.tap(find.text('李美玉').last);
    await settle(tester);
    expect(find.descendant(of: cell('司琴', 11), matching: find.text('李美玉')), findsOneWidget);
    expect(peopleOn(b, 11, '司琴'), isEmpty, reason: 'not saved until 完成');
    expect(waiting(b), isEmpty);
    await pick(tester, '司琴', 18, '李美玉');
    expect(telemetry.named('roster_edit'), isEmpty);

    await tester.tap(find.text('完成'));
    await settle(tester);
    expect(peopleOn(b, 11, '司琴'), ['李美玉']);
    expect(peopleOn(b, 18, '司琴'), ['李美玉']);
    expect(telemetry.named('roster_edit'), [
      {'via': 'plan'},
    ], reason: 'saved at once, together');
    expect(find.text('已通知 1 位同工'), findsOneWidget);
    expect(telemetry.named('roster_notify'), [
      {'people': 1},
    ], reason: 'once, at 完成');
    expect(waiting(b), isEmpty);
    expect(path(tester), '/rosters');
  });

  testWidgets('a picker left open after 安排服事 is gone still lays out (prod error 2026-11-07)', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await tester.tap(cell('司琴', 11));
    await settle(tester);
    expect(find.text('李美玉'), findsWidgets);

    // The page that opened the sheet goes (a back, a link), the sheet stays.
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/rosters');
    await settle(tester);
    expect(find.byType(PlanWeeksScreen, skipOffstage: false), findsNothing);
    expect(find.byType(PeoplePicker), findsOneWidget);
    // The sheet lays out again: the window turns, or the keyboard comes up.
    tester.view.physicalSize = tester.view.physicalSize.flipped;
    addTearDown(tester.view.resetPhysicalSize);
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('李美玉'), findsWidgets);
  });

  testWidgets('what it reads fails: says so with 重試, not an empty table', (tester) async {
    final b = seededChurch();
    var fail = true;
    await pumpApp(
      tester,
      b,
      overrides: [
        staffOrderProvider.overrideWith(
          (ref, type) => fail
              ? Stream.error(const CloudException(CloudErrorCode.unavailable))
              : Stream.value(b.staffOrders['grace']?[type] ?? StaffOrder()),
        ),
      ],
    );
    await go(tester, '/rosters/plan/sunday');
    expect(find.text('載入失敗，請檢查網路後再試一次'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('重試'));
    await settle(tester);
    expect(find.text('2026年10月'), findsOneWidget);
  });

  testWidgets('完成 with nobody to tell just goes back', (tester) async {
    await pumpApp(tester, seededChurch());
    await go(tester, '/rosters/plan/sunday');
    await tester.tap(find.text('完成'));
    await settle(tester);
    expect(path(tester), '/rosters');
    expect(find.textContaining('已通知'), findsNothing);
  });

  testWidgets('leaving with changes not saved asks first: 放棄變更 drops them, 繼續編輯 stays', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await pick(tester, '司琴', 11, '李美玉');
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(find.text('放棄變更？'), findsOneWidget);
    await tester.tap(find.text('繼續編輯'));
    await settle(tester);
    expect(path(tester), '/rosters/plan/sunday');
    expect(find.descendant(of: cell('司琴', 11), matching: find.text('李美玉')), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.tap(find.text('放棄變更').last);
    await settle(tester);
    expect(path(tester), '/rosters');
    expect(peopleOn(b, 11, '司琴'), isEmpty);
    expect(waiting(b), isEmpty, reason: 'nothing saved, nobody to tell');

    await go(tester, '/rosters/plan/sunday');
    expect(
      find.descendant(of: cell('司琴', 11), matching: find.text('李美玉')),
      findsNothing,
      reason: 'dropped',
    );
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(path(tester), '/rosters', reason: 'nothing changed: gone at once');
  });

  testWidgets('people saved here before and not yet told: leaving offers 通知 on the page behind', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await pick(tester, '司琴', 11, '李美玉');
    // A date saves what was changed, and tells nobody yet.
    await tester.tap(date(11));
    await settle(tester);
    expect(peopleOn(b, 11, '司琴'), ['李美玉']);
    expect(waiting(b), {'mei'});
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(path(tester), '/rosters');
    expect(find.text('在這裡排進或移出的人還沒收到通知'), findsOneWidget);
    await tester.tap(find.text('通知'));
    await settle(tester);
    expect(find.text('已通知 1 位同工'), findsOneWidget);
    expect(waiting(b), isEmpty);
  });

  testWidgets('on an iPhone a swipe from the edge leaves at once with nothing changed, and asks first with', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final b = seededChurch();
      await pumpApp(tester, b);
      await go(tester, '/rosters/plan/sunday');
      await tester.dragFrom(const Offset(2, 300), const Offset(500, 0));
      await settle(tester);
      expect(path(tester), '/rosters');

      await go(tester, '/rosters/plan/sunday');
      await pick(tester, '司琴', 11, '李美玉');
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expect(find.text('放棄變更？'), findsOneWidget, reason: 'from below, as iPhone asks');
      await tester.tap(find.text('放棄變更').last);
      await settle(tester);
      expect(path(tester), '/rosters');
      expect(peopleOn(b, 11, '司琴'), isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('more duties than fit: the next shows in part, so the table says it goes on', (tester) async {
    final b = seededChurch();
    b.setServices('grace', [
      sundayService.copyWith(duties: ['司會', '司琴', '招待', '音控', '投影', '燈光', '直播', '接待']),
    ]);
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final cut = [
      for (final role in ['司會', '司琴', '招待', '音控', '投影', '燈光', '直播', '接待'])
        // Columns well past the edge are not there yet.
        if (cell(role, 11).evaluate().isNotEmpty)
          if (tester.getRect(cell(role, 11)) case final r when r.left < width && r.right > width) role,
    ];
    expect(cut, hasLength(1));
    final shown = tester.getRect(cell(cut.single, 11));
    expect((width - shown.left) / shown.width, inInclusiveRange(0.25, 0.6));
  });

  testWidgets('a column is as wide as its names: short ones fit more duties, a long one widens them', (tester) async {
    final b = seededChurch();
    b.setServices('grace', [
      sundayService.copyWith(duties: ['司會', '司琴', '招待', '音控', '投影']),
    ]);
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final whole = [
      for (final role in ['司會', '司琴', '招待', '音控', '投影'])
        if (cell(role, 11).evaluate().isNotEmpty && tester.getRect(cell(role, 11)).right <= width) role,
    ];
    expect(whole.length, greaterThanOrEqualTo(4), reason: 'names of three characters need no 100pt column');
    final narrow = tester.getRect(cell('司會', 11)).width;

    final id = Roster.idFor('sunday', Day(2026, 10, 11));
    final day = b.rosters['grace']![id]!;
    b.rosters['grace']![id] = day.copyWith(
      duties: [
        for (final d in day.duties) d.role == '司琴' ? const Duty(role: '司琴', people: ['Christopher Lee']) : d,
      ],
    );
    b.notify();
    await settle(tester);
    expect(tester.getRect(cell('司會', 11)).width, greaterThan(narrow), reason: 'every column as wide as the widest');
  });

  testWidgets('a column is as wide as most names: a long one now and then is cut short, not every column widened', (
    tester,
  ) async {
    final b = seededChurch();
    Roster sunday(int day, String pianist) => Roster(
      type: 'sunday',
      day: Day(2026, 10, day),
      duties: [
        const Duty(role: '司會', people: ['王牧師']),
        Duty(role: '司琴', people: [pianist]),
        const Duty(role: '招待', people: ['陳志豪', '李美玉']),
      ],
    );
    for (final day in [18, 25]) {
      b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, day))] = sunday(day, '李美玉');
    }
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    final narrow = tester.getRect(cell('司會', 11)).width;

    final eleventh = Roster.idFor('sunday', Day(2026, 10, 11));
    b.rosters['grace']![eleventh] = b.rosters['grace']![eleventh]!.copyWith(
      duties: [
        for (final d in b.rosters['grace']![eleventh]!.duties)
          d.role == '司琴' ? const Duty(role: '司琴', people: ['Christopher Lee']) : d,
      ],
    );
    b.notify();
    await settle(tester);
    expect(tester.getRect(cell('司會', 11)).width, narrow, reason: 'one name in nineteen');
    expect(
      tester.renderObject<RenderParagraph>(find.text('Christopher Lee')).didExceedMaxLines,
      isTrue,
      reason: 'cut short',
    );

    for (final day in [18, 25]) {
      b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, day))] = sunday(day, 'Christopher Lee');
    }
    b.notify();
    await settle(tester);
    expect(tester.getRect(cell('司會', 11)).width, greaterThan(narrow), reason: 'three in nineteen');
  });

  testWidgets('each duty’s name starts where the names and ＋ under it do, the cut column’s too', (tester) async {
    await pumpApp(tester, seededChurch());
    await go(tester, '/rosters/plan/sunday');
    expect(find.text('安排服事'), findsOneWidget);
    for (final role in ['司會', '司琴', '招待']) {
      final name = tester.getRect(find.text(role)).left;
      for (final day in [4, 11]) {
        final inside = find.descendant(of: cell(role, day), matching: find.byType(Text));
        final what = inside.evaluate().isEmpty
            ? find.descendant(of: cell(role, day), matching: find.byType(CustomPaint))
            : inside;
        expect(tester.getRect(what.first).left, moreOrLessEquals(name, epsilon: 1), reason: '$role 10/$day');
      }
    }
  });

  testWidgets('two people on a duty, a line each: a long name is cut short, not wrapped onto the next', (tester) async {
    final b = seededChurch();
    final id = Roster.idFor('sunday', Day(2026, 10, 11));
    final day = b.rosters['grace']![id]!;
    b.rosters['grace']![id] = day.copyWith(
      duties: [
        for (final d in day.duties) d.role == '司琴' ? const Duty(role: '司琴', people: ['Christopher Lee', '李美玉']) : d,
      ],
    );
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    Rect line(int date, String name) =>
        tester.getRect(find.descendant(of: cell(date == 4 ? '招待' : '司琴', date), matching: find.text(name)));
    expect(line(4, '李美玉').top, greaterThan(line(4, '陳志豪').top), reason: 'one under the other');
    final cut = line(11, 'Christopher Lee');
    expect(cut.height, lessThan(line(11, '李美玉').height * 1.5), reason: 'one line, however long');
    expect(
      line(11, '李美玉').bottom,
      lessThanOrEqualTo(tester.getRect(cell('司琴', 11)).bottom),
      reason: 'the second still shows',
    );
  });

  testWidgets('three or more: the first and how many more under it; a reader hears them all', (tester) async {
    final b = seededChurch();
    final id = Roster.idFor('sunday', Day(2026, 10, 4));
    final day = b.rosters['grace']![id]!;
    b.rosters['grace']![id] = day.copyWith(
      duties: [
        for (final d in day.duties) d.role == '招待' ? const Duty(role: '招待', people: ['陳志豪', '李美玉', '王牧師']) : d,
      ],
    );
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    String said() => tester
        .widgetList<Text>(find.descendant(of: cell('招待', 4), matching: find.byType(Text)))
        .map((t) => t.data)
        .join('|');
    expect(said(), '陳志豪|+2', reason: 'a second name and a count do not fit one line of a narrow column');
    expect(tester.widget<Semantics>(cell('招待', 4)).properties.value, '陳志豪、李美玉、王牧師');
  });

  testWidgets('a name that three or more hide behind their count widens nothing', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    final narrow = tester.getRect(cell('司會', 11)).width;

    final id = Roster.idFor('sunday', Day(2026, 10, 4));
    final day = b.rosters['grace']![id]!;
    b.rosters['grace']![id] = day.copyWith(
      duties: [
        for (final d in day.duties)
          d.role == '招待' ? const Duty(role: '招待', people: ['陳志豪', 'Christopher Lee', '王牧師']) : d,
      ],
    );
    b.notify();
    await settle(tester);
    expect(tester.getRect(cell('司會', 11)).width, narrow);
  });

  testWidgets('nobody yet is a ＋ to fill, not 待定 down the table; a reader still hears 待定', (tester) async {
    await pumpApp(tester, seededChurch());
    await go(tester, '/rosters/plan/sunday');
    expect(find.descendant(of: cell('司琴', 11), matching: find.byIcon(Symbols.add_rounded)), findsOneWidget);
    expect(find.descendant(of: cell('司琴', 11), matching: find.text('待定')), findsNothing);
    expect(tester.widget<Semantics>(cell('司琴', 11)).properties.value, '待定');
  });

  testWidgets('a 事工’s 負責人 sees only the duties it leads', (tester) async {
    const worship = Ministry(id: 'worship', name: '敬拜團', duties: [MinistryDuty('sunday', '司琴')]);
    final b = seededChurch(
      extra: [
        staffMei.withIdentities(const [MinistryLead('worship')]),
      ],
      as: staffMei,
    );
    b.ministries['grace'] = const MinistrySettings(ministries: [worship], ids: ['worship']);
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    expect(cell('司琴', 11), findsOneWidget);
    expect(cell('司會', 11), findsNothing);
    expect(cell('招待', 11), findsNothing);
    expect(find.text('安排司琴'), findsOneWidget, reason: 'the one duty named in the title');
    expect(find.text('司琴'), findsNothing, reason: 'no row of duty names over one column');
    final slot = tester.getRect(find.descendant(of: cell('司琴', 11), matching: find.byType(CustomPaint)).first);
    expect(slot.width, greaterThan(tester.getRect(cell('司琴', 11)).width * 0.8), reason: 'a row-wide place to fill');
  });

  testWidgets('switching services shows the other table at once, not a blank page first', (tester) async {
    await pumpApp(tester, seededChurch());
    await go(tester, '/rosters/plan/sunday');
    await tester.tap(find.descendant(of: find.byType(SegmentedButton<String>), matching: find.text('青年崇拜')));
    await tester.pump();
    expect(find.byType(TableView), findsOneWidget, reason: 'its days were read while the page was open');
  });

  testWidgets('switching between a service whose duties fit and one whose do not keeps the table whole', (
    tester,
  ) async {
    final b = seededChurch();
    b.setServices('grace', [
      sundayService.copyWith(duties: ['司會', '司琴', '招待', '音控', '投影', '燈光', '直播', '接待']),
      youthService,
    ]);
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    for (final name in ['青年崇拜', '主日崇拜', '青年崇拜']) {
      await tester.tap(find.descendant(of: find.byType(SegmentedButton<String>), matching: find.text(name)));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'to $name: one table, never two at once');
      final edge = find.byWidgetPredicate((w) => w is AnimatedOpacity && w.child is DecoratedBox);
      double fade() => tester.renderObject<RenderAnimatedOpacity>(edge).opacity.value;
      if (name == '青年崇拜') expect(fade(), 0, reason: 'its one duty fits: no fade, not even fading out');
      await settle(tester);
      if (name == '主日崇拜') expect(fade(), 1, reason: 'its duties go on past the edge');
    }
  });

  testWidgets('a long name months ahead widens the columns from the start, not once scrolled to', (tester) async {
    final b = seededChurch();
    b.setServices('grace', [
      sundayService.copyWith(duties: ['司會', '司琴', '招待', '音控', '投影']),
    ]);
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    final narrow = tester.getRect(cell('司會', 11)).width;
    await go(tester, '/rosters');

    final later = Day(2027, 3, 7);
    b.rosters['grace']![Roster.idFor('sunday', later)] = Roster(
      type: 'sunday',
      day: later,
      duties: const [
        Duty(role: '司琴', people: ['Christopher Lee']),
      ],
    );
    b.notify();
    await go(tester, '/rosters/plan/sunday');
    expect(tester.getRect(cell('司會', 11)).width, greaterThan(narrow));
  });

  testWidgets('a long duty name takes two whole lines, not cut short', (tester) async {
    final b = seededChurch();
    b.setServices('grace', [
      sundayService.copyWith(duties: ['司會', '兒童主日學老師', '招待']),
    ]);
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    final head = tester.renderObject<RenderParagraph>(find.text('兒童主日學老師'));
    expect(head.didExceedMaxLines, isFalse);
  });

  testWidgets('opens at this month even when it is all arranged; the months after follow below', (tester) async {
    final b = seededChurch();
    for (final date in [11, 18, 25]) {
      b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, date))] = savedDay(
        b,
        4,
      ).copyWith(day: Day(2026, 10, date));
    }
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    expect(find.text('2026年10月'), findsOneWidget, reason: 'what is arranged now is where they look first');
    for (var i = 0; i < 10 && find.text('2026年11月').evaluate().isEmpty; i++) {
      await tester.drag(rows, const Offset(0, -200));
      await settle(tester);
    }
    expect(find.text('2026年11月'), findsOneWidget);
  });

  testWidgets('the picker says what else someone serves there, how often that month, and what else that day', (
    tester,
  ) async {
    final b = seededChurch();
    b.rosters['grace']![Roster.idFor('youth', Day(2026, 10, 11))] = Roster(
      type: 'youth',
      day: Day(2026, 10, 11),
      duties: const [
        Duty(role: '司會', people: ['李美玉'], uids: {'李美玉': 'mei'}),
      ],
    );
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tester.tap(find.text('司琴'));
    await settle(tester);
    // 10/4 主日 and 10/11 青年; not the day being arranged.
    // 招待 at this 主日 too: said, and the 主日 not counted again.
    expect(findShown('同一場：招待 · 這個月另有 2 次服事 · 同一天：青年崇拜 司會'), findsOneWidget);
  });

  testWidgets(
    'the picker suggests who serves nothing else there first, who does after, and says it searches everyone',
    (
      tester,
    ) async {
      final b = seededChurch();
      b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, 11))] = Roster(
        type: 'sunday',
        day: Day(2026, 10, 11),
        duties: const [
          Duty(role: '司會', people: ['陳志豪'], uids: {'陳志豪': 'hao'}),
          Duty(role: '招待', people: []),
        ],
      );
      await pumpApp(tester, b);
      await go(tester, '/rosters/sunday/2026-10-11');
      await tester.tap(find.text('招待'));
      await settle(tester);
      expect(find.text('建議'), findsOneWidget);
      expect(find.widgetWithText(TextField, '搜尋所有同工'), findsOneWidget);
      // 陳志豪 comes first in 招待's order, but is 司會 at this 主日.
      final mei = tester.getTopLeft(find.text('李美玉').last).dy;
      final hao = tester.getTopLeft(find.text('陳志豪').last).dy;
      expect(mei, lessThan(hao));
      expect(findShown('同一場：司會 · 這個月另有 1 次服事'), findsOneWidget);
    },
  );

  testWidgets('復原 here takes back what waits for 完成; the day’s own page saves and tells at once', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await pick(tester, '司琴', 11, '李美玉');
    await tester.tap(find.text('復原'));
    await settle(tester);
    expect(find.descendant(of: cell('司琴', 11), matching: find.text('李美玉')), findsNothing);
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(path(tester), '/rosters', reason: 'on and off again: nothing to save');
    expect(peopleOn(b, 11, '司琴'), isEmpty);

    await go(tester, '/rosters/sunday/2026-10-11');
    await tester.tap(find.text('司琴'));
    await settle(tester);
    await tester.tap(find.text('李美玉').last);
    await settle(tester);
    expect(peopleOn(b, 11, '司琴'), ['李美玉']);
    expect(waiting(b), isEmpty);
  });

  testWidgets('a duty taken off a day shows a dash, centered; tapped, it opens the picker and comes back', (
    tester,
  ) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await tester.tap(cell('司琴', 11));
    await settle(tester);
    await tester.tap(find.text('這一天沒有這項服事'));
    await settle(tester);
    final dash = find.descendant(of: cell('司琴', 11), matching: find.text('—'));
    expect(dash, findsOneWidget);
    expect(
      tester.getCenter(dash).dx,
      moreOrLessEquals(tester.getCenter(cell('司琴', 11)).dx, epsilon: 1),
      reason: 'in the middle, where ＋ is',
    );
    await tester.tap(cell('司琴', 11));
    await settle(tester);
    expect(find.text('這一天沒有這項服事'), findsNothing, reason: 'already off');
    await tester.tap(find.text('李美玉').last);
    await settle(tester);
    expect(find.descendant(of: cell('司琴', 11), matching: find.text('李美玉')), findsOneWidget);
    await finish(tester);
    expect(peopleOn(b, 11, '司琴'), ['李美玉']);
  });

  testWidgets('先空著 on a dash puts the duty back with nobody yet', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await tester.tap(cell('司琴', 11));
    await settle(tester);
    await tester.tap(find.text('這一天沒有這項服事'));
    await settle(tester);
    await tester.tap(cell('司琴', 11));
    await settle(tester);
    await tester.tap(find.text('先空著'));
    await settle(tester);
    await finish(tester);
    expect(savedDay(b, 11).duties.map((d) => d.role), contains('司琴'));
  });

  testWidgets('a date is its day’s number over its weekday or its 特別活動, each a line, in a column as narrow as can be', (
    tester,
  ) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    final narrow = tester.getRect(date(11)).width;

    for (final (on, events) in [
      (Day(2026, 10, 18), const [EventTag(name: 'Thanksgiving Service', color: 1)]),
      (Day(2026, 10, 25), const [EventTag(name: '聖餐', color: 0), EventTag(name: '洗禮', color: 3)]),
      (
        Day(2026, 11, 1),
        const [EventTag(name: '聖餐', color: 0), EventTag(name: '洗禮', color: 3), EventTag(name: '感恩', color: 2)],
      ),
    ]) {
      b.rosters['grace']![Roster.idFor('sunday', on)] = Roster(
        type: 'sunday',
        day: on,
        events: events,
        duties: const [
          Duty(role: '司會'),
          Duty(role: '司琴'),
          Duty(role: '招待'),
        ],
      );
    }
    b.notify();
    await settle(tester);
    final november = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '打開 11月1日 週日');
    String said(Finder date) =>
        tester.widgetList<Text>(find.descendant(of: date, matching: find.byType(Text))).map((t) => t.data).join('|');
    expect(said(date(4)), '4|聖餐');
    expect(said(date(11)), '11|週日');
    expect(said(date(18)), '18|Thanksgiving Service', reason: 'one, on two lines if it needs them');
    expect(said(date(25)), '25|聖餐|洗禮', reason: 'each a line of its own');
    expect(said(november), '1|聖餐|+2', reason: 'past two, the first and how many more');
    expect(tester.getRect(date(18)).width, narrow, reason: 'a long one is cut short, the column not widened');
    final long = tester.renderObject<RenderParagraph>(
      find.descendant(of: date(18), matching: find.text('Thanksgiving Service')),
    );
    expect(long.size.height, greaterThan(12 * 1.3 * 1.5), reason: 'on two lines');
  });

  testWidgets('a date opens its day', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await tester.tap(date(11));
    await settle(tester);
    expect(GoRouterState.of(tester.element(find.byType(Scaffold).last)).uri.path, '/rosters/sunday/2026-10-11');
  });

  testWidgets('more months join on as the table nears its end, through next December: all of next year', (
    tester,
  ) async {
    await pumpApp(tester, seededChurch());
    await go(tester, '/rosters/plan/sunday');
    expect(find.text('顯示更多'), findsNothing);
    var last = '';
    for (var i = 0; i < 40; i++) {
      await tester.drag(rows, const Offset(0, -2000));
      await settle(tester);
      final titles = [
        for (final e in find.textContaining(RegExp(r'^\d{4}年\d+月$')).evaluate()) (e.widget as Text).data!,
      ];
      if (titles.isNotEmpty && titles.last == last) break;
      if (titles.isNotEmpty) last = titles.last;
    }
    expect(last, '2027年12月');
  });

  testWidgets('another service, from this month', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await tester.drag(rows, const Offset(0, -2000));
    await settle(tester);

    await tester.tap(find.text('青年崇拜'));
    await settle(tester);
    expect(
      find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '司會, 10月3日 週六'),
      findsOneWidget,
    );
    expect(cell('司琴', 11), findsNothing);
  });

  testWidgets('pressed at night: says when they will hear', (tester) async {
    final b = seededChurch(into: NotifyingBackend()..notice = (people: 2, later: true));
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await pick(tester, '司琴', 11, '李美玉');
    await tester.tap(find.text('完成'));
    await settle(tester);
    expect(find.text('早上 7 點會通知 2 位同工'), findsOneWidget);
  });

  testWidgets('完成 goes back at once, telling them behind it; told, it says so', (tester) async {
    final backend = NotifyingBackend()..held = Completer();
    final b = seededChurch(into: backend);
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await pick(tester, '司琴', 11, '李美玉');
    await tester.tap(find.text('完成'));
    await settle(tester);
    expect(path(tester), '/rosters', reason: 'not waiting for the backend to start');
    expect(find.textContaining('還沒收到通知'), findsNothing, reason: 'they are being told');
    expect(waiting(b), {'mei'});
    backend.held!.complete();
    await settle(tester);
    expect(find.text('已通知 1 位同工'), findsOneWidget);
    expect(waiting(b), isEmpty);
  });

  testWidgets('saving: 完成 greys until it is done; a date waits for it; back then leaves once saved, unasked', (
    tester,
  ) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await pick(tester, '司琴', 11, '李美玉');
    b.writeHeld = Completer<void>();
    await tester.tap(find.text('完成'));
    await settle(tester);
    expect(path(tester), '/rosters/plan/sunday', reason: 'still saving');
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '完成')).onPressed, isNull);
    await tester.tap(date(11));
    await settle(tester);
    expect(path(tester), '/rosters/plan/sunday', reason: 'a date waits for the save');
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(find.text('放棄變更？'), findsNothing, reason: 'nothing to drop: it is being saved');

    b.writeHeld!.complete();
    b.writeHeld = null;
    await settle(tester);
    expect(peopleOn(b, 11, '司琴'), ['李美玉']);
    expect(path(tester), '/rosters');
  });

  testWidgets('a date tapped while saving, then back: leaves once saved, and opens no day', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await pick(tester, '司琴', 11, '李美玉');
    b.writeHeld = Completer<void>();
    await tester.tap(date(11));
    await settle(tester);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '完成')).onPressed, isNull);
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(find.text('放棄變更？'), findsNothing);
    b.writeHeld!.complete();
    b.writeHeld = null;
    await settle(tester);
    expect(peopleOn(b, 11, '司琴'), ['李美玉']);
    expect(path(tester), '/rosters');
  });

  testWidgets('完成 not saved stays, everything still on it, and says why; pressed again, it saves', (tester) async {
    final backend = NotifyingBackend()..saveError = const CloudException(CloudErrorCode.unavailable);
    final b = seededChurch(into: backend);
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await pick(tester, '司琴', 11, '李美玉');
    await finish(tester);
    expect(path(tester), '/rosters/plan/sunday');
    expect(shownOn('司琴', 11, '李美玉'), findsOneWidget);
    expect(find.textContaining('網路'), findsOneWidget, reason: 'says why');
    backend.saveError = null;
    await finish(tester);
    expect(path(tester), '/rosters');
    expect(peopleOn(b, 11, '司琴'), ['李美玉']);
  });

  testWidgets('a failed 完成 says so on the page behind; 重試 tells them', (tester) async {
    final backend = NotifyingBackend()..error = const CloudException(CloudErrorCode.unavailable);
    final b = seededChurch(into: backend);
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await pick(tester, '司琴', 11, '李美玉');
    await tester.tap(find.text('完成'));
    await settle(tester);
    expect(waiting(b), {'mei'}, reason: 'nobody told');
    expect(path(tester), '/rosters');
    backend.error = null;
    await tester.tap(find.text('重試'));
    await settle(tester);
    expect(find.text('已通知 1 位同工'), findsOneWidget);
    expect(waiting(b), isEmpty);
  });

  testWidgets('fits with text at twice its size', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b, textScale: 2);
    await go(tester, '/rosters/plan/sunday');
    expect(tester.takeException(), isNull);
    await pick(tester, '司琴', 11, '李美玉');
    expect(tester.takeException(), isNull);
  });
  testWidgets('和別週交換 in the picker: to a day nobody is on, moves them; nobody told yet', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await tester.tap(cell('司琴', 4));
    await settle(tester);
    await tester.tap(find.text('和別週交換'));
    await settle(tester);
    expect(find.text('和誰交換司琴？'), findsOneWidget);
    await tester.tap(find.text('10月11日 週日').last);
    await settle(tester);
    expect(shownOn('司琴', 4, '李美玉'), findsNothing);
    expect(shownOn('司琴', 11, '李美玉'), findsOneWidget);
    expect(findShown('已把「李美玉」移到 10月11日 週日'), findsOneWidget);
    expect(waiting(b), isEmpty, reason: 'not saved yet');

    await tester.tap(find.text('復原'));
    await settle(tester);
    expect(shownOn('司琴', 4, '李美玉'), findsOneWidget);
    expect(shownOn('司琴', 11, '李美玉'), findsNothing);

    await tester.tap(cell('司琴', 4));
    await settle(tester);
    await tester.tap(find.text('和別週交換'));
    await settle(tester);
    await tester.tap(find.text('10月11日 週日').last);
    await settle(tester);
    await finish(tester);
    expect(peopleOn(b, 4, '司琴'), isEmpty);
    expect(peopleOn(b, 11, '司琴'), ['李美玉']);
  });

  testWidgets('dragging a cell onto another day of the duty trades them', (tester) async {
    final backend = NotifyingBackend()..held = Completer();
    final b = seededChurch(into: backend);
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await drag(tester, cell('招待', 4), cell('招待', 11));
    expect(findShown('已交換「陳志豪、李美玉」和「李美玉」'), findsOneWidget);
    await finish(tester);
    expect(peopleOn(b, 4, '招待'), ['李美玉']);
    expect(peopleOn(b, 11, '招待'), ['陳志豪', '李美玉']);
    // 李美玉 招待 both days, as before: only 陳志豪 has news.
    expect(waiting(b), {'hao'});
    backend.held!.complete();
  });

  testWidgets('a cell dropped on another duty, or let go of where it was, changes nothing', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await drag(tester, cell('司琴', 4), cell('招待', 11));
    await drag(tester, cell('司琴', 4), cell('司琴', 4));
    expect(peopleOn(b, 4, '司琴'), ['李美玉']);
    expect(peopleOn(b, 11, '司琴'), isEmpty);
    expect(peopleOn(b, 11, '招待'), ['李美玉']);
    expect(waiting(b), isEmpty);
  });
  testWidgets('held at the bottom, the table scrolls on; let go, it lands under the finger', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    final table = tester.getRect(rows);
    final edge = Offset(tester.getCenter(cell('司琴', 4)).dx, table.bottom - 4);
    final gesture = await tester.startGesture(tester.getCenter(cell('司琴', 4)));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(edge);
    final under = find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          (w.properties.label?.startsWith('司琴, ') ?? false) &&
          tester.getRect(find.byWidget(w)).contains(edge),
    );
    // The day under the finger, if a day (not a month's name).
    Day? there() {
      if (under.evaluate().length != 1) return null;
      final label = tester.widget<Semantics>(under).properties.label!;
      final [month, date] = [for (final m in RegExp(r'\d+').allMatches(label)) int.parse(m[0]!)];
      return Day(2026, month, date);
    }

    // The finger stays put; the table scrolls under it till a later day
    // is there.
    final first = there();
    bool scrolledOn() => there() != null && (first == null || there()!.isAfter(first));
    for (var i = 0; i < 40 && !scrolledOn(); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(scrolledOn(), isTrue);
    final day = there()!;
    await gesture.up();
    await settle(tester);
    await finish(tester);
    final landed = b.rosters['grace']![Roster.idFor('sunday', day)]!;
    expect(landed.duties.firstWhere((d) => d.role == '司琴').people, ['李美玉']);
    expect(peopleOn(b, 4, '司琴'), isEmpty);
  });
  testWidgets('a 事工’s 負責人 moves a duty onto a day not saved yet, and 復原 puts it back', (tester) async {
    const worship = Ministry(id: 'worship', name: '敬拜團', duties: [MinistryDuty('sunday', '司琴')]);
    final b = seededChurch(
      extra: [
        staffMei.withIdentities(const [MinistryLead('worship')]),
      ],
      as: staffMei,
    );
    b.ministries['grace'] = const MinistrySettings(ministries: [worship], ids: ['worship']);
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await drag(tester, cell('司琴', 4), cell('司琴', 18));
    expect(shownOn('司琴', 18, '李美玉'), findsOneWidget);
    await tester.tap(find.text('復原'));
    await settle(tester);
    expect(find.textContaining('權限'), findsNothing);
    expect(shownOn('司琴', 4, '李美玉'), findsOneWidget);
    expect(shownOn('司琴', 18, '李美玉'), findsNothing);

    await drag(tester, cell('司琴', 4), cell('司琴', 18));
    await finish(tester);
    expect(find.textContaining('權限'), findsNothing, reason: 'saved as only the duty it leads');
    expect(peopleOn(b, 4, '司琴'), isEmpty);
    expect(peopleOn(b, 18, '司琴'), ['李美玉']);
  });
  testWidgets('a cell emptied elsewhere while held still lets go', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    final gesture = await tester.startGesture(tester.getCenter(cell('司琴', 4)));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(tester.getCenter(cell('司琴', 11)));
    await tester.pump();
    b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, 4))] = savedDay(b, 4).copyWith(
      duties: const [
        Duty(role: '司會'),
        Duty(role: '司琴'),
        Duty(role: '招待'),
      ],
    );
    b.notify();
    await tester.pump();
    await gesture.up();
    await settle(tester);
    expect(
      tester
          .widgetList<AnimatedOpacity>(
            find.descendant(of: find.byType(TableView), matching: find.byType(AnimatedOpacity)),
          )
          .map((o) => o.opacity),
      everyElement(1),
      reason: 'nothing left held',
    );
  });
  testWidgets('和別週交換 goes once someone is picked or unpicked: a swap would not keep it', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/plan/sunday');
    await tester.tap(cell('招待', 4));
    await settle(tester);
    expect(find.text('和別週交換'), findsOneWidget);
    await tester.tap(find.text('李美玉').last);
    await settle(tester);
    expect(find.text('和別週交換'), findsNothing);
  });
}
